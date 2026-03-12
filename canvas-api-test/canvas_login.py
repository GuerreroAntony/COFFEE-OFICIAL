"""
canvas_login.py — Login via Microsoft B2C SSO no Canvas ESPM.
Retorna uma Playwright Page autenticada.
"""

import asyncio
from playwright.async_api import async_playwright, Page


async def canvas_login(
    email: str,
    password: str,
    base_url: str = "https://canvas.espm.br",
    target_path: str = "/profile/settings",
    headless: bool = True,
) -> tuple:
    """
    Faz login no Canvas ESPM via Microsoft SSO.
    Navega direto para target_path — o SSO redireciona de volta após login.
    Retorna (pw, browser, page) — o chamador é responsável por fechar.
    """
    pw = await async_playwright().start()
    browser = await pw.chromium.launch(headless=headless)
    page = await browser.new_page()

    target_url = f"{base_url}{target_path}"
    print(f"🔗 Navegando para {target_url} ...")
    await page.goto(target_url, wait_until="domcontentloaded", timeout=30_000)

    # Clicar no botão de login SSO
    sso_btn = page.get_by_text("Conectar com sua conta ESPM")
    await sso_btn.click(timeout=10_000)
    print("   Redirecionando para Microsoft SSO...")

    # Preencher email
    await page.wait_for_selector("#i0116", timeout=15_000)
    await page.fill("#i0116", email)
    await page.click("#idSIButton9")  # Next
    print(f"   Email preenchido: {email}")

    # Esperar campo de senha ficar visível E interagível
    passwd_field = page.locator("#i0118")
    await passwd_field.wait_for(state="visible", timeout=15_000)
    await asyncio.sleep(0.4)  # animação do campo
    await passwd_field.click()
    await passwd_field.fill(password)
    print("   Senha preenchida")

    # Sign In
    await page.locator("#idSIButton9").click()
    print("   Fazendo login...")

    # "Stay signed in?" — clicar Yes se aparecer
    try:
        stay_btn = page.locator("#idSIButton9")
        await stay_btn.wait_for(state="visible", timeout=8_000)
        await stay_btn.click()
        print("   'Stay signed in?' confirmado")
    except Exception:
        pass

    # Aguardar redirecionamento de volta ao Canvas
    await page.wait_for_url(f"{base_url}/**", timeout=45_000)
    await page.wait_for_load_state("domcontentloaded", timeout=15_000)

    # Fechar modal NEXUS se aparecer
    try:
        close_btn = page.locator("button[aria-label='Close']").first
        await close_btn.click(timeout=3_000)
    except Exception:
        pass

    # Verificar se login funcionou
    final_url = page.url
    if base_url in final_url:
        print(f"   ✅ Login realizado com sucesso! → {final_url}")
    else:
        await browser.close()
        await pw.stop()
        raise RuntimeError(f"Login falhou. URL final: {final_url}")

    return pw, browser, page


# ── Teste standalone ──────────────────────────────────────────
if __name__ == "__main__":
    import os

    email = os.environ.get("CANVAS_EMAIL", "")
    password = os.environ.get("CANVAS_PASSWORD", "")
    headless = os.environ.get("HEADLESS", "true").lower() == "true"

    if not email or not password:
        print("Defina CANVAS_EMAIL e CANVAS_PASSWORD")
        exit(1)

    async def _test():
        pw, browser, page = await canvas_login(email, password, headless=headless)
        print(f"   URL final: {page.url}")
        await browser.close()
        await pw.stop()

    asyncio.run(_test())
