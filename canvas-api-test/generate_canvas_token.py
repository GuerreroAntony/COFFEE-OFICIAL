"""
generate_canvas_token.py — Gera um access token no Canvas ESPM via UI.
Usa canvas_login.py para autenticação, depois navega até /profile/settings.
"""

import asyncio
import json
import os
import re
from datetime import datetime, timedelta

from canvas_login import canvas_login

MONTHS_TO_ADVANCE = 4
DAYS_AHEAD = 120


async def generate_token(
    email: str,
    password: str,
    purpose: str = "scrapper-auto",
    base_url: str = "https://canvas.espm.br",
    output_file: str = "canvas_token.json",
    headless: bool = True,
) -> dict:
    """Gera um access token no Canvas e retorna dict com os dados."""

    target_date = datetime.now() + timedelta(days=DAYS_AHEAD)
    target_day = target_date.day

    print("=" * 58)
    print("  Canvas ESPM — Gerador Automático de Access Token")
    print("=" * 58)
    print(f"   Data alvo de expiração: {target_date.strftime('%d/%m/%Y')} (dia {target_day})")
    print(f"   Objetivo: {purpose}")

    # 1. Login (já vai direto para /profile/settings)
    pw, browser, page = await canvas_login(
        email, password, base_url, target_path="/profile/settings", headless=headless
    )

    try:

        # 3. Clicar "+ Novo token de acesso"
        print("   Clicando em '+ Novo token de acesso'...")
        new_token_link = page.get_by_text("Novo token de acesso")
        await new_token_link.click(timeout=10_000)
        print("   ✅ Modal aberto")

        # 4. Preencher objetivo
        print(f"   Preenchendo objetivo: '{purpose}'")
        await page.fill("input[name='purpose']", purpose, timeout=5_000)

        # 5. Abrir calendário (clicar no campo de data)
        print("   Abrindo calendário...")
        date_input = page.locator("input[id^='Selectable']")
        await date_input.click(timeout=5_000)

        # 6. Avançar meses
        print(f"   Avançando {MONTHS_TO_ADVANCE} meses no calendário...")
        for i in range(MONTHS_TO_ADVANCE):
            next_btn = page.locator("button:has-text('Próximo mês')")
            await next_btn.click(timeout=5_000)
            await asyncio.sleep(0.15)
            print(f"      Mês avançado ({i + 1}/{MONTHS_TO_ADVANCE})")

        # 7. Selecionar dia (dia de hoje - 3)
        safe_day = max(datetime.now().day - 3, 1)
        print(f"   Selecionando dia {safe_day}...")
        day_buttons = page.locator("button[role='option']")
        count = await day_buttons.count()
        clicked = False
        for idx in range(count):
            btn = day_buttons.nth(idx)
            text = await btn.inner_text()
            # Texto é tipo "9 julho 2026\n09" — checar se começa com "N "
            if text.startswith(f"{safe_day} "):
                await btn.click()
                clicked = True
                print(f"   ✅ Dia {safe_day} selecionado")
                break

        if not clicked:
            print(f"   ⚠️  Dia {safe_day} não encontrado, tentando sem data...")

        # 8. Gerar token
        print("   Gerando token...")
        submit_btn = page.locator("button[type='submit']:has-text('Gerar token')")
        await submit_btn.click(timeout=10_000)

        # 9. Aguardar modal com token
        # 9-10. Aguardar e extrair token direto pelo data-testid
        token_el = page.locator('[data-testid="visible_token"]')
        await token_el.wait_for(state="visible", timeout=15_000)
        token = (await token_el.inner_text()).strip()

        if not token or "~" not in token:
            raise RuntimeError(f"Token inválido extraído: {token}")
        print("   ✅ Token extraído")

        # Resultado
        now = datetime.now()
        result = {
            "token": token,
            "purpose": purpose,
            "created_at": now.isoformat(timespec="seconds"),
            "expires_at": target_date.isoformat(timespec="seconds"),
            "canvas_url": base_url,
        }

        # Salvar arquivo
        with open(output_file, "w", encoding="utf-8") as f:
            json.dump(result, f, indent=2, ensure_ascii=False)

        print(f"\n🎉 Token gerado com sucesso!")
        print(f"   Token: {token[:20]}...{token[-6:]}")
        print(f"   Expira em: {target_date.strftime('%d/%m/%Y')}")
        print(f"   Salvo em: {output_file}")

        return result

    finally:
        await browser.close()
        await pw.stop()


# ── Main ──────────────────────────────────────────────────────
if __name__ == "__main__":
    email = os.environ.get("CANVAS_EMAIL", "")
    password = os.environ.get("CANVAS_PASSWORD", "")
    purpose = os.environ.get("TOKEN_PURPOSE", "scrapper-auto")
    base_url = os.environ.get("CANVAS_BASE_URL", "https://canvas.espm.br")
    output_file = os.environ.get("TOKEN_OUTPUT_FILE", "canvas_token.json")
    headless = os.environ.get("HEADLESS", "true").lower() == "true"

    if not email or not password:
        print("Defina CANVAS_EMAIL e CANVAS_PASSWORD")
        exit(1)

    data = asyncio.run(generate_token(
        email=email,
        password=password,
        purpose=purpose,
        base_url=base_url,
        output_file=output_file,
        headless=headless,
    ))
