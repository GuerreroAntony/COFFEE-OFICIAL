"""
ESPMAuthenticator — autenticação headless no Portal ESPM via Playwright.
Fluxo: portal.espm.br → #ESPMExchange → Microsoft login (2 etapas) → sso_reload → portal.

Adaptado para arquitetura Coffee (asyncpg, sem SQLAlchemy).
"""
from __future__ import annotations

import asyncio
import json
import os
import structlog
from typing import Dict, List, Tuple

from cryptography.fernet import Fernet
from playwright.async_api import async_playwright, TimeoutError as PlaywrightTimeoutError

_HEADLESS = os.getenv("PLAYWRIGHT_HEADED", "false").lower() != "true"

logger = structlog.get_logger(__name__)

# Flags do Chromium headless — Railway container + iframe cross-origin (sso_reload)
_CHROMIUM_ARGS = [
    "--no-sandbox",
    "--disable-dev-shm-usage",
    "--disable-blink-features=AutomationControlled",
    "--disable-infobars",
    "--disable-web-security",
    "--disable-features=SameSiteByDefaultCookies,CookiesWithoutSameSiteMustBeSecure",
    "--allow-running-insecure-content",
]

_USER_AGENT = (
    "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) "
    "AppleWebKit/537.36 (KHTML, like Gecko) "
    "Chrome/131.0.0.0 Safari/537.36"
)

_BROWSER_HEADERS = {
    "Accept-Language": "pt-BR,pt;q=0.9,en-US;q=0.8",
    "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
}


class AuthenticationError(Exception):
    """Falha de autenticação."""


class ESPMAuthenticator:
    PORTAL_URL     = "https://portal.espm.br/"
    MY_COURSES_URL = "https://portal.espm.br/my-courses"
    TIMEOUT        = 60000  # 60 segundos por etapa

    # Seletores Microsoft (IDs fixos do B2C — mesmos usados no scraper)
    MS_EMAIL_SEL    = "#i0116"
    MS_PASSWORD_SEL = "#i0118"
    MS_SUBMIT_ID    = "#idSIButton9"

    def __init__(self, secret_key: str) -> None:
        self._fernet = Fernet(secret_key.encode() if isinstance(secret_key, str) else secret_key)

    # ── Public ────────────────────────────────────────────────────────────────

    async def login(self, login: str, password: str) -> Dict:
        """
        Autentica no portal ESPM via Microsoft SSO.
        Retorna {"state": storage_state_dict, "logs": [str]}.
        """
        logs: List[str] = []
        try:
            return await self._do_login(login, password, logs)
        except PlaywrightTimeoutError as exc:
            logs.append(f"Timeout: {exc}")
            raise

    async def login_and_extract(self, login: str, password: str, extractor) -> Dict:
        """
        Faz login e extrai a grade numa única janela de browser — sem fechar entre etapas.
        Retorna {"state": ..., "logs": ..., "disciplines": [...]}.
        """
        logs: List[str] = []
        async with async_playwright() as pw:
            browser = await pw.chromium.launch(headless=_HEADLESS, args=_CHROMIUM_ARGS)
            try:
                context = await browser.new_context(
                    user_agent=_USER_AGENT,
                    viewport={"width": 1280, "height": 720},
                    extra_http_headers=_BROWSER_HEADERS,
                )
                page = await context.new_page()
                await self._run_login_steps(page, context, login, password, logs)
                storage_state = await context.storage_state()
                logger.info("auth.login.success", login=login)
                try:
                    disciplines = await extractor.extract_with_context(context, logs, page=page)
                except Exception as exc:
                    # Preserve logs even on extraction failure
                    logs.append(f"EXTRACT ERROR: {str(exc)[:200]}")
                    logger.error("auth.extract_failed", error=str(exc), logs=logs)
                    disciplines = []
                return {"state": storage_state, "logs": logs, "disciplines": disciplines}
            finally:
                await browser.close()

    async def get_or_refresh_session(
        self, encrypted_session: bytes, login: str, password: str
    ) -> Tuple[Dict, List[str]]:
        """
        Tenta reutilizar sessão existente. Se expirada, faz login novo.
        Retorna ({"state": ..., "logs": ...}, logs).
        """
        logs: List[str] = []
        state = self._decrypt_session(encrypted_session)

        async with async_playwright() as pw:
            browser = await pw.chromium.launch(headless=_HEADLESS, args=_CHROMIUM_ARGS)
            try:
                context = await browser.new_context(
                    storage_state=state,
                    user_agent=_USER_AGENT,
                    viewport={"width": 1280, "height": 720},
                    extra_http_headers=_BROWSER_HEADERS,
                )
                page = await context.new_page()
                await page.goto(self.MY_COURSES_URL, timeout=self.TIMEOUT)
                await self._wait_idle(page)

                if self._is_espm_portal(page.url):
                    storage_state = await context.storage_state()
                    return {"state": storage_state, "logs": logs}, logs

                logs.append("Sessão expirada — fazendo novo login…")
            finally:
                await browser.close()

        # Sessão expirada: login novo
        result = await self.login(login, password)
        result["logs"] = logs + result.get("logs", [])
        return result, result["logs"]

    def encrypt_session(self, state: Dict) -> bytes:
        return self._fernet.encrypt(json.dumps(state).encode())

    def _decrypt_session(self, encrypted: bytes) -> Dict:
        return json.loads(self._fernet.decrypt(encrypted).decode())

    # ── Core login flow ───────────────────────────────────────────────────────

    async def _do_login(self, login: str, password: str, logs: List[str]) -> Dict:
        async with async_playwright() as pw:
            browser = await pw.chromium.launch(headless=_HEADLESS, args=_CHROMIUM_ARGS)
            try:
                context = await browser.new_context(
                    user_agent=_USER_AGENT,
                    viewport={"width": 1280, "height": 720},
                    extra_http_headers=_BROWSER_HEADERS,
                )
                page = await context.new_page()
                await self._run_login_steps(page, context, login, password, logs)
                storage_state = await context.storage_state()
                logger.info("auth.login.success", login=login)
                return {"state": storage_state, "logs": logs}
            finally:
                await browser.close()

    @staticmethod
    async def _wait_idle(page, timeout_ms: int = 8_000) -> None:
        """Tenta networkidle por timeout_ms; se não disparar (SPA), continua."""
        try:
            await page.wait_for_load_state("networkidle", timeout=timeout_ms)
        except Exception:
            pass

    async def _run_login_steps(
        self, page, context, login: str, password: str, logs: List[str]
    ) -> None:
        """Executa os passos de login seguindo o fluxo comprovado do scraper."""
        # 1. Abrir portal
        logs.append("Navegando para portal.espm.br...")
        await page.goto(self.PORTAL_URL, wait_until="networkidle", timeout=30000)

        # Se já estiver no portal autenticado, pular
        if self._is_espm_portal(page.url) and "login" not in page.url.lower():
            logs.append("Já autenticado no portal.")
            return

        # 2. Clicar "Conectar com sua conta ESPM" (busca robusta por texto)
        logs.append("Procurando botão 'Conectar com sua conta ESPM'...")
        try:
            buttons = await page.query_selector_all("button")
            for btn in buttons:
                text = await btn.text_content()
                if "Conectar" in (text or "").strip():
                    logs.append("Botão encontrado. Clicando...")
                    await btn.click()
                    break
        except Exception:
            logs.append("WARN: Botão 'Conectar' não encontrado — tentando prosseguir...")

        # 3. Aguardar campo de email Microsoft B2C
        try:
            await page.wait_for_selector(
                self.MS_EMAIL_SEL, state="visible", timeout=20000
            )
        except Exception:
            raise AuthenticationError(
                f"Campo de e-mail B2C ({self.MS_EMAIL_SEL}) não encontrado. URL: {page.url}"
            )

        # 4. Preencher email e clicar Next
        logs.append("Preenchendo email Microsoft...")
        await page.fill(self.MS_EMAIL_SEL, login)
        submit_btn = await page.query_selector(self.MS_SUBMIT_ID)
        if submit_btn:
            await submit_btn.click()
            await page.wait_for_timeout(2000)

        # 5. Preencher senha e clicar Sign In
        logs.append("Preenchendo senha...")
        await page.fill(self.MS_PASSWORD_SEL, password)
        sign_in_btn = await page.query_selector(self.MS_SUBMIT_ID)
        if sign_in_btn:
            await sign_in_btn.click()

        # 6. Aguardar B2C processar login — esperar KMSi prompt ou redirect
        await page.wait_for_timeout(3000)

        # 7. Handle "Stay signed in?" (KMSi) — poll for up to 15s
        for attempt in range(3):
            # Se já chegou no portal, pronto
            if self._is_espm_portal(page.url):
                logs.append("Redirecionado para portal após Sign In.")
                break

            try:
                stay_btn = await page.wait_for_selector(
                    self.MS_SUBMIT_ID, state="visible", timeout=5000
                )
                if stay_btn:
                    # Verificar se é o KMSi prompt (não o form de senha)
                    page_text = await page.evaluate(
                        "() => document.body?.innerText?.substring(0, 500) || ''"
                    )
                    if "stay signed in" in page_text.lower() or "manter" in page_text.lower():
                        logs.append("Confirmando 'Stay signed in'...")
                        await stay_btn.click()
                        await page.wait_for_timeout(5000)
                        break
                    else:
                        logs.append(f"Botão encontrado mas não é KMSi (attempt {attempt+1})")
                        await page.wait_for_timeout(3000)
            except Exception:
                await page.wait_for_timeout(2000)

        # 8. Aguardar redirect para portal (até 20s)
        if not self._is_espm_portal(page.url):
            logs.append(f"Aguardando redirect para portal... URL atual: {page.url[:80]}")
            try:
                await page.wait_for_url("**/portal.espm.br/**", timeout=20000)
                logs.append("Redirect para portal detectado.")
            except Exception:
                logs.append(f"WARN: Redirect não aconteceu. URL: {page.url[:80]}")

        # 9. Se chegou no portal, aguardar MSAL processar o auth code
        if self._is_espm_portal(page.url):
            logs.append("No portal — aguardando MSAL processar...")
            await page.wait_for_timeout(8000)
            await self._wait_idle(page, 5000)

            # Verificar se MSAL não redirecionou de volta para B2C
            if not self._is_espm_portal(page.url):
                logs.append(f"WARN: MSAL redirecionou para B2C. URL: {page.url[:80]}")

        # 10. Check final
        if not self._is_espm_portal(page.url):
            raise AuthenticationError(
                f"Autenticação falhou — não redirecionou ao portal. URL: {page.url}"
            )

        logs.append("Login concluído com sucesso.")

    # ── Helpers ───────────────────────────────────────────────────────────────

    @staticmethod
    def _is_espm_portal(url: str) -> bool:
        return "portal.espm.br" in url.lower()
