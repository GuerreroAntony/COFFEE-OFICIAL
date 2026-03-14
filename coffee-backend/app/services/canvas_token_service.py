"""
Canvas Token Service — Generates Canvas API access tokens and fetches data via REST API.

Adapted from canvas-api-test/generate_canvas_token.py and canvas-api-test/canvas_login.py.

Two main capabilities:
1. generate_canvas_token() — Playwright login + token generation (~19s, once per 120 days)
2. fetch_canvas_courses()  — REST API call to get student's courses (~2s, uses token)
"""
from __future__ import annotations

import asyncio
import logging
from datetime import datetime, timedelta

import httpx
from playwright.async_api import async_playwright
from playwright.async_api import TimeoutError as PlaywrightTimeoutError

logger = logging.getLogger("canvas_token_service")


# ── Custom Exceptions ─────────────────────────────────────────────────────────

class CanvasAuthError(Exception):
    """Raised when Canvas login fails due to invalid credentials."""
    pass

class CanvasTimeoutError(Exception):
    """Raised when Canvas login or token generation times out."""
    pass


CANVAS_BASE_URL = "https://canvas.espm.br"
CANVAS_API_BASE = f"{CANVAS_BASE_URL}/api/v1"
MONTHS_TO_ADVANCE = 4
DAYS_AHEAD = 120


# ═══════════════════════════════════════════════════════════════════════════════
# 1. CANVAS LOGIN (Playwright — Microsoft B2C SSO)
# ═══════════════════════════════════════════════════════════════════════════════

async def _canvas_login(
    email: str,
    password: str,
    target_path: str = "/profile/settings",
    headless: bool = True,
) -> tuple:
    """
    Login to Canvas ESPM via Microsoft B2C SSO.
    Returns (pw, browser, page) — caller is responsible for closing.

    CRITICAL: Do NOT change these selectors or timings without testing against
    the real Microsoft SSO flow. See canvas-api-test/CANVAS_SCRAPER_DOCS.md.
    """
    pw = await async_playwright().start()
    browser = await pw.chromium.launch(headless=headless)
    page = await browser.new_page()

    try:
        target_url = f"{CANVAS_BASE_URL}{target_path}"
        logger.info("Navigating to %s", target_url)
        await page.goto(target_url, wait_until="domcontentloaded", timeout=30_000)

        # Click SSO login button
        sso_btn = page.get_by_text("Conectar com sua conta ESPM")
        await sso_btn.click(timeout=10_000)

        # Fill email
        await page.wait_for_selector("#i0116", timeout=15_000)
        await page.fill("#i0116", email)
        await page.click("#idSIButton9")  # Next

        # Wait for password field — 0.4s animation delay is CRITICAL (do NOT remove)
        passwd_field = page.locator("#i0118")
        await passwd_field.wait_for(state="visible", timeout=15_000)
        await asyncio.sleep(0.4)
        await passwd_field.click()
        await passwd_field.fill(password)

        # Sign In
        await page.locator("#idSIButton9").click()

        # "Stay signed in?" — click Yes if it appears
        try:
            stay_btn = page.locator("#idSIButton9")
            await stay_btn.wait_for(state="visible", timeout=8_000)
            await stay_btn.click()
        except PlaywrightTimeoutError:
            pass

        # Wait for redirect back to Canvas
        await page.wait_for_url(f"{CANVAS_BASE_URL}/**", timeout=45_000)
        await page.wait_for_load_state("domcontentloaded", timeout=15_000)

        # Close NEXUS modal if it appears
        try:
            close_btn = page.locator("button[aria-label='Close']").first
            await close_btn.click(timeout=3_000)
        except Exception:
            pass

        # Verify login
        if CANVAS_BASE_URL not in page.url:
            await browser.close()
            await pw.stop()
            raise CanvasAuthError(f"Canvas login failed. Final URL: {page.url}")

        logger.info("Canvas login successful → %s", page.url)
        return pw, browser, page

    except PlaywrightTimeoutError as e:
        await browser.close()
        await pw.stop()
        raise CanvasTimeoutError(f"Canvas login timed out: {e}") from e
    except CanvasAuthError:
        raise  # Re-raise auth errors as-is


# ═══════════════════════════════════════════════════════════════════════════════
# 2. TOKEN GENERATION (Playwright — navigates Canvas UI)
# ═══════════════════════════════════════════════════════════════════════════════

async def generate_canvas_token(
    email: str,
    password: str,
    purpose: str = "coffee-auto",
    headless: bool = True,
) -> dict:
    """
    Generate a Canvas API access token via UI automation.

    Returns dict: {token, purpose, created_at, expires_at}

    IMPORTANT: The token only appears ONCE in the modal right after creation.
    If you navigate away, Canvas shows it truncated.

    Performance: ~19s (login SSO + navigate + create token)
    """
    target_date = datetime.now() + timedelta(days=DAYS_AHEAD)
    safe_day = max(datetime.now().day - 3, 1)

    logger.info("Generating Canvas token, target expiry: %s", target_date.strftime("%d/%m/%Y"))

    pw, browser, page = await _canvas_login(
        email, password, target_path="/profile/settings", headless=headless
    )

    try:
        # Click "+ Novo token de acesso"
        new_token_link = page.get_by_text("Novo token de acesso")
        await new_token_link.click(timeout=10_000)

        # Fill purpose (10s — Canvas settings page may load slowly after SSO redirect)
        await page.fill("input[name='purpose']", purpose, timeout=10_000)

        # Open calendar
        date_input = page.locator("input[id^='Selectable']")
        await date_input.click(timeout=5_000)

        # Advance months
        for i in range(MONTHS_TO_ADVANCE):
            next_btn = page.locator("button:has-text('Próximo mês')")
            await next_btn.click(timeout=5_000)
            await asyncio.sleep(0.15)

        # Select day — text format is "9 julho 2026\n09" so use startswith
        day_buttons = page.locator("button[role='option']")
        count = await day_buttons.count()
        for idx in range(count):
            btn = day_buttons.nth(idx)
            text = await btn.inner_text()
            if text.startswith(f"{safe_day} "):
                await btn.click()
                break

        # Generate token
        submit_btn = page.locator("button[type='submit']:has-text('Gerar token')")
        await submit_btn.click(timeout=10_000)

        # Extract token — visible_token only appears ONCE in creation modal
        token_el = page.locator('[data-testid="visible_token"]')
        await token_el.wait_for(state="visible", timeout=15_000)
        token = (await token_el.inner_text()).strip()

        if not token or "~" not in token:
            raise RuntimeError(f"Invalid token extracted: {token}")

        now = datetime.now()
        result = {
            "token": token,
            "purpose": purpose,
            "created_at": now.isoformat(timespec="seconds"),
            "expires_at": target_date.isoformat(timespec="seconds"),
        }

        logger.info("Canvas token generated: %s...%s (expires %s)",
                     token[:15], token[-4:], target_date.strftime("%d/%m/%Y"))
        return result

    except PlaywrightTimeoutError as e:
        raise CanvasTimeoutError(f"Canvas token generation timed out: {e}") from e
    finally:
        await browser.close()
        await pw.stop()


# ═══════════════════════════════════════════════════════════════════════════════
# 3. CANVAS REST API (uses token — no Playwright needed)
# ═══════════════════════════════════════════════════════════════════════════════

async def fetch_canvas_courses(canvas_token: str) -> list[dict]:
    """
    Fetch student's courses from Canvas REST API.

    Returns list of dicts with: nome, turma, semestre, canvas_course_id

    Uses paginated GET /api/v1/courses with Bearer token.
    Performance: ~2s (vs ~30-60s with Playwright).
    """
    headers = {"Authorization": f"Bearer {canvas_token}"}

    async with httpx.AsyncClient(timeout=30.0) as client:
        courses = []
        url = f"{CANVAS_API_BASE}/courses"
        params: dict = {"include[]": "term", "per_page": "100"}

        while url:
            r = await client.get(url, headers=headers, params=params)
            r.raise_for_status()
            data = r.json()
            if isinstance(data, list):
                courses.extend(data)
            else:
                courses.append(data)

            # Follow Link pagination
            url = None
            params = {}
            link_header = r.headers.get("Link", "")
            for part in link_header.split(","):
                if 'rel="next"' in part:
                    url = part.split(";")[0].strip().strip("<>")
                    break

    # Convert Canvas courses → Coffee disciplinas format
    disciplines = []
    for course in courses:
        if not isinstance(course, dict) or not course.get("name"):
            continue

        nome_completo = course["name"]

        # Parse "TURMA - Disciplina" format
        if " - " in nome_completo:
            turma, nome = nome_completo.split(" - ", 1)
        elif "-" in nome_completo:
            turma, nome = nome_completo.split("-", 1)
        else:
            turma, nome = "", nome_completo

        term = course.get("term", {})
        semestre = term.get("name", None) if term else None

        disciplines.append({
            "nome": nome.strip(),
            "turma": turma.strip() or None,
            "semestre": semestre,
            "canvas_course_id": course.get("id"),
        })

    logger.info("Canvas API: %d courses fetched", len(disciplines))
    return disciplines
