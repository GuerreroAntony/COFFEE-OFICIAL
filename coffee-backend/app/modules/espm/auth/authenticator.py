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
                disciplines = await extractor.extract_with_context(context, logs)
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
        """Executa os passos de login numa page/context já abertos."""
        # 1. Abrir portal
        logs.append("Navegando para portal.espm.br...")
        await page.goto(self.PORTAL_URL, timeout=self.TIMEOUT)
        await self._wait_idle(page)

        # 2. Clicar em "Conectar com sua conta ESPM"
        await self._click_espm_provider(page, logs)
        await page.wait_for_load_state("networkidle", timeout=self.TIMEOUT)

        # 3. Preencher e-mail Microsoft
        logs.append("Preenchendo email Microsoft...")
        await self._ms_fill_email(page, login, logs)

        # 4. Clicar Next
        await self._ms_click_submit(page, logs, label="Next")
        await page.wait_for_load_state("networkidle", timeout=self.TIMEOUT)

        # 5. Aguardar campo de senha visível e preencher
        await page.wait_for_selector(self.MS_PASSWORD_SEL, state="visible", timeout=self.TIMEOUT)
        await asyncio.sleep(1)  # aguarda animação Microsoft
        await page.fill(self.MS_PASSWORD_SEL, password)
        logs.append("Senha preenchida, submetendo...")

        # 6. Clicar Sign in
        await asyncio.sleep(1)  # aguarda antes de submeter
        await self._ms_click_submit(page, logs, label="Sign in")

        # 7. Aguardar portal.espm.br
        logs.append("Aguardando redirecionamento ao portal...")
        reached = await self._wait_for_portal(page, logs)

        if not reached:
            raise AuthenticationError(
                f"Autenticação falhou — não redirecionou ao portal. URL: {page.url}"
            )

        # 8. Aguardar MSAL.js processar tokens
        await self._wait_idle(page)
        logs.append("Login concluído com sucesso.")

    # ── Wait for portal ───────────────────────────────────────────────────────

    async def _wait_for_portal(self, page, logs: List[str]) -> bool:
        """
        Aguarda até portal.espm.br — loop com timeout de 120s.
        Dispensa "Stay signed in?" automaticamente se aparecer.
        """
        last_url = ""
        max_attempts = 60  # 60 * 2s = 120s max

        for _ in range(max_attempts):
            await asyncio.sleep(2)
            url = page.url

            if url != last_url:
                last_url = url

            if self._is_espm_portal(url):
                return True

            # Dispensar "Stay signed in?" se aparecer
            for sel in [
                self.MS_SUBMIT_ID,
                'button:has-text("Yes")',
                'button:has-text("Sim")',
            ]:
                try:
                    btn = page.locator(sel).first
                    if await btn.is_visible(timeout=2000):
                        await btn.click()
                        logs.append("Dispensou popup 'Stay signed in?'")
                        await asyncio.sleep(3)
                        break
                except Exception:
                    pass

        # Fallback: se SSO completou mas não redirecionou, navegar explicitamente
        if not self._is_espm_portal(page.url):
            logs.append("Fallback: navegando explicitamente para portal.espm.br...")
            try:
                await page.goto(self.PORTAL_URL, wait_until="domcontentloaded", timeout=30000)
                await asyncio.sleep(5)
            except Exception:
                pass

        return self._is_espm_portal(page.url)

    # ── Helpers ───────────────────────────────────────────────────────────────

    async def _click_espm_provider(self, page, logs: List[str]) -> None:
        for sel in [
            "#ESPMExchange",
            "button.accountButton.firstButton",
            "button:has-text('Conectar com sua conta ESPM')",
        ]:
            try:
                btn = await page.wait_for_selector(sel, timeout=5000, state="visible")
                await btn.click()
                logs.append("Clicou no provedor ESPM (SSO).")
                return
            except Exception:
                continue
        logs.append("WARN: Nenhum seletor ESPM encontrado, tentando prosseguir...")

    async def _ms_fill_email(self, page, email: str, logs: List[str]) -> None:
        try:
            await page.wait_for_selector(
                self.MS_EMAIL_SEL, state="visible", timeout=60000
            )
            await page.fill(self.MS_EMAIL_SEL, email)
        except Exception:
            raise AuthenticationError("Campo de e-mail Microsoft não encontrado.")

    async def _ms_click_submit(self, page, logs: List[str], label: str = "") -> None:
        """Clica no botão submit Microsoft pelo id #idSIButton9."""
        for sel in [self.MS_SUBMIT_ID, 'input[type="submit"]']:
            try:
                btn = await page.wait_for_selector(sel, state="visible", timeout=5000)
                await btn.click()
                return
            except Exception:
                continue
        await page.keyboard.press("Enter")

    @staticmethod
    def _is_espm_portal(url: str) -> bool:
        return "portal.espm.br" in url.lower()
