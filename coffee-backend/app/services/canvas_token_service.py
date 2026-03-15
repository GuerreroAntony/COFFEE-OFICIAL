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

# Realistic Chrome user-agent — Microsoft SSO blocks obvious headless bots
_USER_AGENT = (
    "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 "
    "(KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36"
)

# Docker-safe Chromium launch args (NO --single-process — causes hangs)
_CHROMIUM_ARGS = [
    "--no-sandbox",
    "--disable-setuid-sandbox",
    "--disable-dev-shm-usage",
    "--disable-gpu",
    "--disable-background-networking",
    "--disable-default-apps",
    "--disable-extensions",
    "--disable-sync",
    "--disable-translate",
    "--no-first-run",
    "--mute-audio",
]


# ═══════════════════════════════════════════════════════════════════════════════
# 1. MICROSOFT POST-LOGIN HANDLER
# ═══════════════════════════════════════════════════════════════════════════════

async def _handle_microsoft_post_login(page) -> None:
    """
    After clicking Sign In, Microsoft may show intermediate pages before
    redirecting back to Canvas. This function handles all known cases:

    1. "Stay signed in?" (KMSI) → click Yes
    2. MFA registration (mysignins.microsoft.com) → click Skip/Cancel
    3. ProofUp redirect → click skip button
    4. Already on Canvas → return immediately

    Polls for up to 30s with 2s intervals.
    """
    for attempt in range(15):  # 15 × 2s = 30s max
        await asyncio.sleep(2)
        current_url = page.url

        # Already on Canvas — done!
        if CANVAS_BASE_URL in current_url:
            logger.info("[canvas] post_login: already on Canvas")
            return

        logger.info("[canvas] post_login attempt=%d url=%s", attempt, current_url[:80])

        # Case 1: "Stay signed in?" (KMSI) — same button #idSIButton9
        if "login.microsoftonline.com" in current_url:
            try:
                kmsi_btn = page.locator("#idSIButton9")
                if await kmsi_btn.is_visible():
                    await kmsi_btn.click()
                    logger.info("[canvas] post_login: clicked 'Stay signed in'")
                    continue
            except Exception:
                pass

            # Also check for ProofUp redirect button
            try:
                proof_btn = page.locator("#idSubmit_ProofUp_Redirect")
                if await proof_btn.is_visible():
                    await proof_btn.click()
                    logger.info("[canvas] post_login: clicked ProofUp redirect")
                    continue
            except Exception:
                pass

        # Case 2: MFA registration page (mysignins.microsoft.com)
        if "mysignins.microsoft.com" in current_url:
            skip_result = await page.evaluate("""() => {
                const all = document.querySelectorAll('a, button, span[role="button"]');
                for (const el of all) {
                    const text = (el.innerText || el.textContent || '').trim().toLowerCase();
                    if (text.includes('skip') || text.includes('cancel') || text.includes('ignorar')
                        || text.includes('cancelar') || text.includes('pular')
                        || text.includes('ask later') || text.includes('perguntar depois')
                        || text.includes('não, obrigado') || text.includes('no thanks')) {
                        el.click();
                        return 'clicked: ' + text.substring(0, 40);
                    }
                }
                const close = document.querySelector(
                    '[aria-label="Close"], [aria-label="Fechar"], .ms-Dialog-button--close'
                );
                if (close) { close.click(); return 'clicked-close'; }
                return 'no-skip-found';
            }""")
            logger.info("[canvas] post_login: MFA page → %s", skip_result)
            if "clicked" in skip_result:
                continue
            # No skip button — try navigating back
            await page.go_back()
            continue

        # Case 3: Any other Microsoft page — look for generic skip/next buttons
        if "microsoft" in current_url:
            try:
                generic_result = await page.evaluate("""() => {
                    const all = document.querySelectorAll('button, input[type=submit], a');
                    for (const el of all) {
                        const text = (el.innerText || el.value || '').trim().toLowerCase();
                        if (text.includes('skip') || text.includes('next') || text.includes('yes')
                            || text.includes('continue') || text.includes('pular')
                            || text.includes('continuar') || text.includes('sim')) {
                            el.click();
                            return 'clicked: ' + text.substring(0, 40);
                        }
                    }
                    return 'no-action';
                }""")
                logger.info("[canvas] post_login: generic Microsoft page → %s", generic_result)
                if "clicked" in generic_result:
                    continue
            except Exception:
                pass

    # If we get here and we're still not on Canvas, let the caller's
    # wait_for_url handle the final timeout
    logger.warning("[canvas] post_login: exhausted attempts, current URL: %s", page.url)


# ═══════════════════════════════════════════════════════════════════════════════
# 2. CANVAS LOGIN (Playwright — Microsoft B2C SSO)
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
    browser = await pw.chromium.launch(headless=headless, args=_CHROMIUM_ARGS)
    page = await browser.new_page(
        user_agent=_USER_AGENT,
        viewport={"width": 1280, "height": 720},
    )

    step = "init"
    try:
        target_url = f"{CANVAS_BASE_URL}{target_path}"
        step = "navigate"
        logger.info("[canvas] step=navigate url=%s", target_url)
        await page.goto(target_url, wait_until="domcontentloaded", timeout=30_000)

        # Click SSO login button
        step = "sso_button"
        logger.info("[canvas] step=sso_button")
        sso_btn = page.get_by_text("Conectar com sua conta ESPM")
        await sso_btn.click(timeout=10_000)

        # Fill email
        step = "email"
        logger.info("[canvas] step=email")
        await page.wait_for_selector("#i0116", timeout=15_000)
        await page.fill("#i0116", email)
        await page.click("#idSIButton9")  # Next

        # Wait for password field — 0.4s animation delay is CRITICAL (do NOT remove)
        step = "password"
        logger.info("[canvas] step=password")
        passwd_field = page.locator("#i0118")
        await passwd_field.wait_for(state="visible", timeout=15_000)
        await asyncio.sleep(0.4)
        await passwd_field.click()
        await passwd_field.fill(password)

        # Sign In
        step = "sign_in"
        logger.info("[canvas] step=sign_in")
        await page.locator("#idSIButton9").click()

        # Post-login: handle Microsoft intermediate pages
        # Microsoft may show: "Stay signed in?", MFA registration, ProofUp, etc.
        step = "post_login"
        logger.info("[canvas] step=post_login (handling Microsoft pages)")
        await _handle_microsoft_post_login(page)

        # Wait for redirect back to Canvas
        step = "redirect"
        logger.info("[canvas] step=redirect (waiting for Canvas URL)")
        await page.wait_for_url(f"{CANVAS_BASE_URL}/**", timeout=30_000, wait_until="commit")
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

        logger.info("[canvas] login OK → %s", page.url)
        return pw, browser, page

    except PlaywrightTimeoutError as e:
        logger.error("[canvas] TIMEOUT at step=%s: %s", step, e)
        await browser.close()
        await pw.stop()
        raise CanvasTimeoutError(f"Canvas login timed out at step '{step}': {e}") from e
    except CanvasAuthError:
        raise  # Re-raise auth errors as-is
    except Exception as e:
        logger.error("[canvas] ERROR at step=%s: %s", step, e)
        await browser.close()
        await pw.stop()
        raise


# ═══════════════════════════════════════════════════════════════════════════════
# 2. TOKEN GENERATION (Playwright — navigates Canvas UI)
# ═══════════════════════════════════════════════════════════════════════════════

async def _generate_canvas_token_once(
    email: str,
    password: str,
    purpose: str = "coffee-auto",
    headless: bool = True,
) -> dict:
    """
    Single attempt to generate a Canvas API access token via UI automation.
    Returns dict: {token, purpose, created_at, expires_at}
    """
    target_date = datetime.now() + timedelta(days=DAYS_AHEAD)
    safe_day = max(datetime.now().day - 3, 1)

    pw, browser, page = await _canvas_login(
        email, password, target_path="/profile/settings", headless=headless
    )

    step = "token_init"
    try:
        # Click "+ Novo token de acesso"
        step = "new_token_link"
        logger.info("[canvas] step=new_token_link")
        new_token_link = page.get_by_text("Novo token de acesso")
        await new_token_link.click(timeout=10_000)

        # Fill purpose
        step = "fill_purpose"
        logger.info("[canvas] step=fill_purpose")
        await page.fill("input[name='purpose']", purpose, timeout=10_000)

        # Open calendar
        step = "open_calendar"
        date_input = page.locator("input[id^='Selectable']")
        await date_input.click(timeout=5_000)

        # Advance months
        step = "advance_months"
        for i in range(MONTHS_TO_ADVANCE):
            next_btn = page.locator("button:has-text('Próximo mês')")
            await next_btn.click(timeout=5_000)
            await asyncio.sleep(0.15)

        # Select day — text format is "9 julho 2026\n09" so use startswith
        step = "select_day"
        day_buttons = page.locator("button[role='option']")
        count = await day_buttons.count()
        for idx in range(count):
            btn = day_buttons.nth(idx)
            text = await btn.inner_text()
            if text.startswith(f"{safe_day} "):
                await btn.click()
                break

        # Generate token
        step = "submit"
        logger.info("[canvas] step=submit (generating token)")
        submit_btn = page.locator("button[type='submit']:has-text('Gerar token')")
        await submit_btn.click(timeout=10_000)

        # Extract token — visible_token only appears ONCE in creation modal
        step = "extract_token"
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

        logger.info("[canvas] TOKEN OK: %s...%s (expires %s)",
                     token[:15], token[-4:], target_date.strftime("%d/%m/%Y"))
        return result

    except PlaywrightTimeoutError as e:
        logger.error("[canvas] TIMEOUT at step=%s: %s", step, e)
        raise CanvasTimeoutError(f"Token generation timed out at step '{step}': {e}") from e
    finally:
        await browser.close()
        await pw.stop()


async def generate_canvas_token(
    email: str,
    password: str,
    purpose: str = "coffee-auto",
    headless: bool = True,
    max_retries: int = 2,
) -> dict:
    """
    Generate a Canvas API access token with automatic retry.

    Retries up to max_retries times on timeout (CanvasTimeoutError).
    Does NOT retry on auth errors (wrong password).

    Performance: ~19s per attempt (login SSO + navigate + create token).
    Token lasts 120 days — this only runs once every ~4 months.
    """
    last_error = None

    for attempt in range(1, max_retries + 1):
        try:
            logger.info("[canvas] attempt %d/%d", attempt, max_retries)
            result = await _generate_canvas_token_once(email, password, purpose, headless)
            return result
        except CanvasAuthError:
            raise  # Wrong password — don't retry
        except CanvasTimeoutError as e:
            last_error = e
            logger.warning("[canvas] attempt %d failed: %s", attempt, e)
            if attempt < max_retries:
                logger.info("[canvas] retrying in 3s...")
                await asyncio.sleep(3)

    raise last_error  # type: ignore[misc]


# ═══════════════════════════════════════════════════════════════════════════════
# 3. CANVAS REST API (uses token — no Playwright needed)
# ═══════════════════════════════════════════════════════════════════════════════

async def validate_canvas_token(token: str) -> dict:
    """
    Validate a Canvas API token by calling GET /api/v1/users/self.

    Returns the user info dict if valid.
    Raises CanvasAuthError if the token is invalid or expired.
    """
    headers = {"Authorization": f"Bearer {token}"}
    async with httpx.AsyncClient(timeout=15.0) as client:
        r = await client.get(f"{CANVAS_API_BASE}/users/self", headers=headers)
        if r.status_code == 401:
            raise CanvasAuthError("Token Canvas inválido ou expirado")
        r.raise_for_status()
        logger.info("[canvas] Token validated OK via /users/self")
        return r.json()


async def fetch_canvas_courses(canvas_token: str) -> list[dict]:
    """
    Fetch student's courses from Canvas REST API.

    Returns list of dicts with: nome, turma, semestre, sala, canvas_course_id

    Uses paginated GET /api/v1/courses with Bearer token.
    Includes sections to extract sala (classroom) info.
    Performance: ~2s (vs ~30-60s with Playwright).
    """
    headers = {"Authorization": f"Bearer {canvas_token}"}

    async with httpx.AsyncClient(timeout=30.0) as client:
        courses = []
        url = f"{CANVAS_API_BASE}/courses"
        params: dict = {"include[]": ["term", "sections"], "per_page": "100"}

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

    # Debug: log first course's available fields
    if courses:
        first = courses[0]
        logger.info(
            "[canvas] sample course keys: %s",
            sorted(first.keys()) if isinstance(first, dict) else "NOT_DICT",
        )
        logger.info(
            "[canvas] sample course_code=%s, sections=%s, sis_course_id=%s",
            first.get("course_code"),
            first.get("sections"),
            first.get("sis_course_id"),
        )

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

        # Extract sala from Canvas course data
        sala = _extract_sala_from_course(course, turma.strip())

        disciplines.append({
            "nome": nome.strip(),
            "turma": turma.strip() or None,
            "semestre": semestre,
            "sala": sala,
            "canvas_course_id": course.get("id"),
        })

    logger.info("Canvas API: %d courses fetched", len(disciplines))
    return disciplines


def _extract_sala_from_course(course: dict, turma: str) -> str | None:
    """
    Try to extract sala (classroom/room) from Canvas course data.

    Checks multiple potential sources:
    1. Section names (sections included via include[]=sections)
    2. course_code (often set by SIS, may contain room info)
    3. sis_course_id (SIS integration identifier)
    """
    # 1. Check sections — section names may contain room/sala info
    sections = course.get("sections", [])
    if isinstance(sections, list):
        for section in sections:
            if not isinstance(section, dict):
                continue
            sec_name = (section.get("name") or "").strip()
            # If section name differs from turma, it might be the sala
            if sec_name and sec_name != turma:
                logger.info("[canvas] sala candidate from section: %s (turma=%s)", sec_name, turma)
                return sec_name

    # 2. Check course_code — SIS may set this to include room info
    course_code = (course.get("course_code") or "").strip()
    if course_code and course_code != turma:
        logger.info("[canvas] sala candidate from course_code: %s (turma=%s)", course_code, turma)
        return course_code

    # 3. Check sis_course_id — some SIS encode room in this field
    sis_id = (course.get("sis_course_id") or "").strip()
    if sis_id and sis_id != turma:
        logger.info("[canvas] sala candidate from sis_course_id: %s (turma=%s)", sis_id, turma)
        return sis_id

    return None


# ═══════════════════════════════════════════════════════════════════════════════
# 4. CANVAS FILES API (fetch course files + download)
# ═══════════════════════════════════════════════════════════════════════════════

_MAX_SYNC_FILE_BYTES = 50 * 1024 * 1024  # 50 MB limit per file


async def fetch_canvas_course_files(canvas_token: str, canvas_course_id: int) -> list[dict]:
    """
    Fetch all files from a Canvas course using REST API with pagination.

    Returns list of dicts with Canvas file metadata:
      id, display_name, filename, content-type, size, url, created_at, updated_at
    """
    headers = {"Authorization": f"Bearer {canvas_token}"}

    async with httpx.AsyncClient(timeout=30.0) as client:
        files: list[dict] = []
        url: str | None = f"{CANVAS_API_BASE}/courses/{canvas_course_id}/files"
        params: dict = {"per_page": "100"}

        while url:
            r = await client.get(url, headers=headers, params=params)
            if r.status_code == 401:
                raise CanvasAuthError("Token Canvas inválido ou expirado")
            if r.status_code == 403:
                logger.warning(
                    "[canvas] course %d: 403 Forbidden for files endpoint (no access)",
                    canvas_course_id,
                )
                return []  # User doesn't have file access for this course
            r.raise_for_status()
            data = r.json()
            if isinstance(data, list):
                files.extend(data)
            else:
                files.append(data)

            # Follow Link pagination
            url = None
            params = {}
            link_header = r.headers.get("Link", "")
            for part in link_header.split(","):
                if 'rel="next"' in part:
                    url = part.split(";")[0].strip().strip("<>")
                    break

    # Filter out oversized files
    valid = [f for f in files if isinstance(f, dict) and f.get("size", 0) <= _MAX_SYNC_FILE_BYTES]
    logger.info(
        "[canvas] course %d: %d files fetched, %d within size limit",
        canvas_course_id, len(files), len(valid),
    )
    return valid


async def download_canvas_file(canvas_token: str, file_url: str) -> bytes:
    """
    Download a file from Canvas.

    Canvas file URLs require authentication and typically redirect.
    Returns file content as bytes.
    """
    headers = {"Authorization": f"Bearer {canvas_token}"}

    async with httpx.AsyncClient(timeout=120.0, follow_redirects=True) as client:
        r = await client.get(file_url, headers=headers)
        r.raise_for_status()
        return r.content
