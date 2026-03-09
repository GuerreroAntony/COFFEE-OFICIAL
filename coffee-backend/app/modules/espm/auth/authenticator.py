"""
ESPMAuthenticator — autenticação headless no Portal ESPM via Playwright.
Fluxo: portal.espm.br → #ESPMExchange → Microsoft login (2 etapas) → sso_reload → portal.

Adaptado para arquitetura Coffee (asyncpg, sem SQLAlchemy).
"""
from __future__ import annotations

import asyncio
import base64
import hashlib
import json
import os
import secrets
import structlog
import uuid
from typing import Dict, List, Tuple
from urllib.parse import quote

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
                await self._apply_stealth(context)
                page = await context.new_page()
                try:
                    await self._run_login_steps(page, context, login, password, logs)
                except AuthenticationError as exc:
                    logger.error("auth.login_failed", logs=logs)
                    # Return partial result with logs for debugging (don't lose logs)
                    return {"state": {}, "logs": logs, "disciplines": [], "auth_error": str(exc)}
                storage_state = await context.storage_state()
                logger.info("auth.login.success", login=login)
                try:
                    disciplines = await extractor.extract_with_context(context, logs, page=page)
                except Exception as exc:
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
                await self._apply_stealth(context)
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
                await self._apply_stealth(context)
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

    @staticmethod
    def _generate_pkce() -> Dict:
        """Generate PKCE code_verifier and code_challenge for B2C OIDC flow."""
        # code_verifier: 43-128 chars, base64url-safe
        verifier_bytes = secrets.token_bytes(32)
        code_verifier = base64.urlsafe_b64encode(verifier_bytes).rstrip(b"=").decode("ascii")
        # code_challenge: SHA256(code_verifier), base64url-encoded
        digest = hashlib.sha256(code_verifier.encode("ascii")).digest()
        code_challenge = base64.urlsafe_b64encode(digest).rstrip(b"=").decode("ascii")
        return {"code_verifier": code_verifier, "code_challenge": code_challenge}

    @staticmethod
    def _build_b2c_authorize_url(code_challenge: str) -> str:
        """Build the full B2C authorize URL with proper PKCE params."""
        client_request_id = str(uuid.uuid4())
        nonce = str(uuid.uuid4())
        state_data = json.dumps({
            "id": str(uuid.uuid4()),
            "meta": {"interactionType": "redirect"}
        })
        state_b64 = base64.b64encode(state_data.encode()).decode()

        params = (
            f"client_id=9051a4d6-a66b-45b3-87bd-373c03911eda"
            f"&scope=openid%20profile%20offline_access"
            f"&redirect_uri={quote('https://portal.espm.br/', safe='')}"
            f"&client-request-id={client_request_id}"
            f"&response_mode=fragment"
            f"&response_type=code"
            f"&x-client-SKU=msal.js.browser"
            f"&x-client-VER=3.20.0"
            f"&x-app-name=lifeApp"
            f"&x-app-ver=2.0.0"
            f"&client_info=1"
            f"&code_challenge={code_challenge}"
            f"&code_challenge_method=S256"
            f"&nonce={nonce}"
            f"&state={quote(state_b64, safe='')}"
        )
        return (
            "https://acadespmb2c.b2clogin.com/acadespmb2c.onmicrosoft.com"
            f"/b2c_1a_signup_signin/oauth2/v2.0/authorize?{params}"
        )

    async def _run_login_steps(
        self, page, context, login: str, password: str, logs: List[str]
    ) -> None:
        """Executa login via B2C direto (bypassa portal.espm.br/Vercel)."""
        # 1. Gerar PKCE e navegar direto para B2C authorize
        pkce = self._generate_pkce()
        b2c_url = self._build_b2c_authorize_url(pkce["code_challenge"])
        logs.append("Navegando direto para B2C (bypass Vercel)...")
        await page.goto(b2c_url, wait_until="domcontentloaded", timeout=30000)
        await page.wait_for_timeout(3000)
        logs.append(f"URL B2C: {page.url[:80]}")

        # 2. B2C custom page: clicar "Conectar com sua conta ESPM"
        if "b2clogin.com" in page.url:
            try:
                clicked = await page.evaluate("""() => {
                    // Search all element types for "Conectar"
                    const selectors = ['button', 'a', 'div[role="button"]', 'span'];
                    for (const sel of selectors) {
                        for (const el of document.querySelectorAll(sel)) {
                            const text = (el.innerText || el.textContent || '').trim();
                            if (text.includes('Conectar')) {
                                el.click();
                                return 'clicked: ' + text.substring(0, 50);
                            }
                        }
                    }
                    return 'not-found';
                }""")
                logs.append(f"B2C Conectar: {clicked}")
                if "clicked" in clicked:
                    await page.wait_for_timeout(5000)
            except Exception as e:
                logs.append(f"WARN: Erro botão Conectar: {str(e)[:100]}")

        # 3. Aguardar campo de email Microsoft B2C
        try:
            await page.wait_for_selector(
                self.MS_EMAIL_SEL, state="visible", timeout=20000
            )
        except Exception:
            debug_text = await page.evaluate(
                "() => document.body?.innerText?.substring(0, 500) || ''"
            )
            logs.append(f"DEBUG page text: {debug_text[:200]}")
            logs.append(f"DEBUG URL: {page.url}")
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

        # 6. Aguardar B2C processar login + handle Microsoft federation redirect
        await page.wait_for_timeout(5000)
        logs.append(f"URL pós-senha: {page.url[:80]}")

        # B2C may redirect to login.microsoftonline.com for federated auth.
        # Handle the full redirect chain: B2C → Microsoft → KMSi → portal
        for attempt in range(8):
            cur = page.url
            if self._is_espm_portal(cur):
                logs.append("Redirecionado para portal.")
                break

            # Debug: log page state on first iteration and when URL changes
            if attempt == 0 or (attempt <= 3):
                try:
                    debug_info = await page.evaluate("""() => {
                        const inputs = Array.from(document.querySelectorAll('input')).map(i =>
                            `${i.type}:${i.id||i.name}:vis=${i.offsetParent!==null}`
                        );
                        const buttons = Array.from(document.querySelectorAll('button, input[type=submit]')).map(b =>
                            `${b.tagName}:${b.id||''}:${(b.innerText||b.value||'').substring(0,30)}`
                        );
                        const text = (document.body?.innerText || '').substring(0, 300);
                        return JSON.stringify({inputs, buttons, text: text.substring(0, 200)});
                    }""")
                    logs.append(f"DEBUG[{attempt}] {cur[:50]}: {debug_info[:200]}")
                except Exception:
                    pass

            # Try to find and interact with Microsoft forms
            try:
                # Check for email field first (Microsoft may show email form)
                email_field = await page.query_selector(self.MS_EMAIL_SEL)
                if email_field and await email_field.is_visible():
                    logs.append(f"Microsoft login: preenchendo email (attempt {attempt+1})...")
                    await page.fill(self.MS_EMAIL_SEL, login)
                    btn = await page.query_selector(self.MS_SUBMIT_ID)
                    if btn:
                        await btn.click()
                    await page.wait_for_timeout(3000)
                    continue

                # Check for password field
                pwd_field = await page.query_selector(self.MS_PASSWORD_SEL)
                if pwd_field and await pwd_field.is_visible():
                    logs.append(f"Microsoft login: preenchendo senha (attempt {attempt+1})...")
                    await page.fill(self.MS_PASSWORD_SEL, password)
                    btn = await page.query_selector(self.MS_SUBMIT_ID)
                    if btn:
                        await btn.click()
                    await page.wait_for_timeout(5000)
                    continue

                # Check for MFA/ProofUp redirect ("Avançar" / "Next")
                proofup_btn = await page.query_selector("#idSubmit_ProofUp_Redirect")
                if proofup_btn and await proofup_btn.is_visible():
                    logs.append("MFA/ProofUp page — clicando 'Avançar'...")
                    await proofup_btn.click()
                    await page.wait_for_timeout(5000)
                    continue

                # Check for KMSi / any submit button
                btn = await page.query_selector(self.MS_SUBMIT_ID)
                if btn and await btn.is_visible():
                    page_text = await page.evaluate(
                        "() => document.body?.innerText?.substring(0, 500) || ''"
                    )
                    text_lower = page_text.lower()
                    if "stay signed in" in text_lower or "manter" in text_lower:
                        logs.append("Confirmando 'Stay signed in'...")
                        await btn.click()
                        await page.wait_for_timeout(5000)
                        continue
                    logs.append(f"Botão encontrado, clicando (attempt {attempt+1})...")
                    await btn.click()
                    await page.wait_for_timeout(3000)
                    continue

                # Generic: click any visible submit/button we find
                any_submit = await page.query_selector("input[type=submit]:visible, button[type=submit]:visible")
                if any_submit:
                    btn_text = await any_submit.get_attribute("value") or await any_submit.text_content() or ""
                    logs.append(f"Botão genérico encontrado: '{btn_text[:30]}'. Clicando...")
                    await any_submit.click()
                    await page.wait_for_timeout(3000)
                    continue
            except Exception as e:
                logs.append(f"WARN loop[{attempt}]: {str(e)[:80]}")

            await page.wait_for_timeout(3000)

        # 8. Aguardar redirect para portal (até 25s)
        if not self._is_espm_portal(page.url):
            logs.append(f"Aguardando redirect para portal... URL: {page.url[:80]}")
            try:
                await page.wait_for_url("**/portal.espm.br/**", timeout=25000)
                logs.append("Redirect para portal detectado.")
            except Exception:
                logs.append(f"WARN: Redirect não aconteceu. URL: {page.url[:80]}")

        # 9. Se chegou no portal, aguardar MSAL processar o auth code
        if self._is_espm_portal(page.url):
            logs.append("No portal — aguardando MSAL processar...")
            await page.wait_for_timeout(8000)
            await self._wait_idle(page, 5000)

            # Check for Vercel blocking on the redirect landing
            try:
                is_vercel = await page.evaluate("""() => {
                    const text = (document.body?.innerText || '').toLowerCase();
                    return text.includes('failed to verify') || text.includes('falha ao verificar');
                }""")
                if is_vercel:
                    logs.append("Vercel bloqueou redirect. Recarregando...")
                    for retry in range(3):
                        await page.reload(wait_until="domcontentloaded", timeout=30000)
                        await page.wait_for_timeout(5000)
                        still_blocked = await page.evaluate("""() => {
                            const text = (document.body?.innerText || '').toLowerCase();
                            return text.includes('failed to verify') || text.includes('falha ao verificar');
                        }""")
                        if not still_blocked:
                            logs.append(f"Vercel resolvido após reload {retry+1}.")
                            break
                        logs.append(f"Vercel persistente (reload {retry+1}/3).")
            except Exception:
                pass

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
    async def _apply_stealth(context) -> None:
        """Hide automation markers to bypass Vercel/Cloudflare bot detection."""
        await context.add_init_script("""
            // Hide navigator.webdriver
            Object.defineProperty(navigator, 'webdriver', {
                get: () => undefined
            });

            // Add chrome runtime object
            window.chrome = {
                runtime: {},
                loadTimes: function() {},
                csi: function() {},
                app: {}
            };

            // Override permissions query
            const originalQuery = window.navigator.permissions.query;
            window.navigator.permissions.query = (parameters) =>
                parameters.name === 'notifications'
                    ? Promise.resolve({ state: Notification.permission })
                    : originalQuery(parameters);

            // Override plugins to look real
            Object.defineProperty(navigator, 'plugins', {
                get: () => [1, 2, 3, 4, 5]
            });

            // Override languages
            Object.defineProperty(navigator, 'languages', {
                get: () => ['pt-BR', 'pt', 'en-US', 'en']
            });

            // Hide automation in WebGL renderer
            const getParameter = WebGLRenderingContext.prototype.getParameter;
            WebGLRenderingContext.prototype.getParameter = function(parameter) {
                if (parameter === 37445) return 'Intel Inc.';
                if (parameter === 37446) return 'Intel Iris OpenGL Engine';
                return getParameter.apply(this, arguments);
            };
        """)

    @staticmethod
    def _is_espm_portal(url: str) -> bool:
        """Check if URL is the real portal (not B2C or Vercel checkpoint)."""
        url_lower = url.lower()
        if "portal.espm.br" not in url_lower:
            return False
        # Vercel security checkpoint has portal.espm.br URL but isn't the real portal
        if "security-checkpoint" in url_lower or "vercel" in url_lower:
            return False
        return True
