"""
Canvas ESPM Scraper — Self-Contained
=====================================

Extracts courses and lesson materials (PDFs) from Canvas ESPM (canvas.espm.br).
Authenticates via Microsoft B2C SSO.

Dependencies:
    pip install playwright python-dotenv
    playwright install chromium

Usage:
    See run_extraction.py for usage example.
"""

from __future__ import annotations

import asyncio
import logging
import os
import pathlib
import re
from dataclasses import dataclass, field
from typing import Any

from playwright.async_api import Browser, BrowserContext, Page, async_playwright

logger = logging.getLogger(__name__)

# ── URLs ─────────────────────────────────────────────────────────────────────
CANVAS_URL = "https://canvas.espm.br"


# ── Data Classes ─────────────────────────────────────────────────────────────

@dataclass
class CourseInfo:
    """A Canvas course."""
    canvas_course_id: int
    name: str
    course_code: str | None = None
    term: str | None = None


@dataclass
class MaterialInfo:
    """A downloaded file from Canvas."""
    canvas_file_id: int
    file_name: str
    file_url: str           # Local path to the saved file
    file_type: str | None = None  # Extension: pdf, pptx, etc.
    course_id: int | None = None


@dataclass
class ExtractionResult:
    """Full result of a Canvas extraction."""
    success: bool
    courses: list[CourseInfo] = field(default_factory=list)
    materials: dict[str, list[MaterialInfo]] = field(default_factory=dict)
    error: str | None = None


# ── Scraper ──────────────────────────────────────────────────────────────────

class CanvasESPMScraper:
    """
    Playwright-based scraper for Canvas ESPM.

    Authenticates via Microsoft B2C SSO, then scrapes courses
    and downloads lesson materials (PDFs matching "Aula \\d+").

    Usage:
        async with CanvasESPMScraper(email, password) as scraper:
            result = await scraper.run()
    """

    def __init__(
        self,
        email: str,
        password: str,
        download_dir: str = "./downloads",
        headless: bool = True,
    ) -> None:
        self._email = email
        self._password = password
        self._download_dir = pathlib.Path(download_dir)
        self._headless = headless
        self._browser: Browser | None = None
        self._context: BrowserContext | None = None
        self._page: Page | None = None

    # ── Context Manager ──────────────────────────────────────────────────

    async def __aenter__(self) -> CanvasESPMScraper:
        """Launch browser and create page."""
        self._playwright = await async_playwright().start()
        self._browser = await self._playwright.chromium.launch(
            headless=self._headless,
            args=[
                "--no-sandbox",
                "--disable-dev-shm-usage",
                "--disable-blink-features=AutomationControlled",
                "--disable-infobars",
            ],
        )
        self._context = await self._browser.new_context(
            user_agent=(
                "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) "
                "AppleWebKit/537.36 (KHTML, like Gecko) "
                "Chrome/131.0.0.0 Safari/537.36"
            ),
            viewport={"width": 1280, "height": 720},
            extra_http_headers={
                "Accept-Language": "pt-BR,pt;q=0.9,en-US;q=0.8",
                "Accept": (
                    "text/html,application/xhtml+xml,"
                    "application/xml;q=0.9,*/*;q=0.8"
                ),
            },
        )
        self._page = await self._context.new_page()
        return self

    async def __aexit__(self, *args: Any) -> None:
        """Close browser — no state persisted."""
        if self._context:
            await self._context.close()
        if self._browser:
            await self._browser.close()
        if self._playwright:
            await self._playwright.stop()

    # ── Public API ───────────────────────────────────────────────────────

    async def run(self, max_retries: int = 3) -> ExtractionResult:
        """
        Full extraction: login → list courses → download materials.

        Args:
            max_retries: Max login attempts.

        Returns:
            ExtractionResult with courses and materials per course.
        """
        last_error: str | None = None

        for attempt in range(1, max_retries + 1):
            try:
                if attempt > 1:
                    logger.info(
                        "Tentativa %d/%d...", attempt, max_retries
                    )
                    await self.__aexit__(None, None, None)
                    await self.__aenter__()

                # Step 1: Login
                await self.login_via_sso()

                # Step 2: Get courses
                courses = await self.scrape_courses()

                # Step 3: Get materials per course
                all_materials: dict[str, list[MaterialInfo]] = {}
                for course in courses:
                    try:
                        materials = await self.scrape_course_materials(
                            course.canvas_course_id
                        )
                        all_materials[course.name] = materials
                    except Exception as exc:
                        logger.warning(
                            "Falha ao buscar materiais de '%s': %s",
                            course.name, str(exc)[:80],
                        )
                        all_materials[course.name] = []

                return ExtractionResult(
                    success=True,
                    courses=courses,
                    materials=all_materials,
                )

            except Exception as exc:
                last_error = f"{type(exc).__name__}: {exc}"
                logger.warning(
                    "Tentativa %d/%d falhou: %s",
                    attempt, max_retries, last_error,
                )
                if attempt == max_retries:
                    return ExtractionResult(
                        success=False, error=last_error
                    )
                await asyncio.sleep(3)

        return ExtractionResult(success=False, error=last_error)

    # ── SSO Login ────────────────────────────────────────────────────────

    async def login_via_sso(self) -> None:
        """
        Authenticate to Canvas via ESPM Microsoft B2C SSO.

        Flow:
        1. Navigate to Canvas → redirects to ESPM login page
        2. Click "Conectar com sua conta ESPM" button
        3. Fill Microsoft B2C form (email → password)
        4. Handle "Stay signed in?" prompt
        5. Dismiss NEXUS modal if present
        6. Verify Canvas is accessible
        """
        page = self._page
        if not page:
            raise RuntimeError("Browser not initialized. Use 'async with'.")

        logger.info("Iniciando autenticação no Canvas via SSO...")

        # Navigate to Canvas → redireciona para login ESPM
        await page.goto(CANVAS_URL, wait_until="networkidle", timeout=30000)

        # Check if already authenticated
        if self._is_canvas_url(page.url):
            logger.info("Já autenticado no Canvas (sessão válida).")
            return

        # Click "Conectar com sua conta ESPM" button
        logger.info("Procurando botão 'Conectar com sua conta ESPM'...")
        try:
            buttons = await page.query_selector_all("button")
            for btn in buttons:
                text = await btn.text_content()
                if "Conectar" in (text or "").strip():
                    logger.info("Botão encontrado. Clicando...")
                    await btn.click()
                    break
        except Exception:
            logger.warning("Botão 'Conectar' não encontrado — tentando B2C direto.")

        # Wait for Microsoft B2C email field
        try:
            await page.wait_for_selector(
                "#i0116", state="visible", timeout=20000
            )
        except Exception:
            raise RuntimeError(
                "Campo de email B2C (#i0116) não encontrado. "
                "A página de SSO pode ter mudado."
            )

        # Fill email and click Next
        logger.info("Preenchendo email...")
        await page.fill("#i0116", self._email)
        submit_btn = await page.query_selector("#idSIButton9")
        if submit_btn:
            await submit_btn.click()
            await page.wait_for_timeout(2000)

        # Fill password and click Sign In
        logger.info("Preenchendo senha...")
        await page.fill("#i0118", self._password)
        sign_in_btn = await page.query_selector("#idSIButton9")
        if sign_in_btn:
            await sign_in_btn.click()

        # Wait for redirect
        try:
            await page.wait_for_load_state(
                "domcontentloaded", timeout=30000
            )
        except Exception:
            pass
        await page.wait_for_timeout(5000)

        # Handle "Stay signed in?" dialog
        try:
            stay_btn = await page.query_selector("#idSIButton9")
            if stay_btn:
                logger.info("Confirmando 'Stay signed in'...")
                await stay_btn.click()
                await page.wait_for_timeout(3000)
                try:
                    await page.wait_for_load_state(
                        "domcontentloaded", timeout=15000
                    )
                except Exception:
                    pass
                await page.wait_for_timeout(3000)
        except Exception:
            pass

        # Dismiss NEXUS modal (Portal popup that may block the page)
        try:
            await page.evaluate("""
                () => {
                    const backdrop = document.querySelector('.MuiDialog-container');
                    if (backdrop) backdrop.click();
                    document.querySelectorAll('.MuiDialog-root').forEach(
                        el => el.remove()
                    );
                }
            """)
            await page.wait_for_timeout(2000)
        except Exception:
            pass

        # If not on Canvas yet, navigate explicitly
        if not self._is_canvas_url(page.url):
            logger.info("Redirecionando para Canvas...")
            await page.goto(
                CANVAS_URL, wait_until="domcontentloaded", timeout=30000
            )
            await page.wait_for_timeout(5000)

        # Final check
        if not self._is_canvas_url(page.url):
            raise RuntimeError(
                f"SSO falhou. URL atual: {page.url}. "
                "Verifique as credenciais."
            )

        logger.info("✅ Login no Canvas realizado com sucesso.")

    # ── Course Scraping ──────────────────────────────────────────────────

    async def scrape_courses(self) -> list[CourseInfo]:
        """
        Scrape all enrolled courses from Canvas.

        Returns list of CourseInfo with course ID and name.
        """
        page = self._page
        if not page:
            raise RuntimeError("Browser not initialized.")

        logger.info("Buscando cursos no Canvas...")

        await page.goto(
            f"{CANVAS_URL}/courses",
            wait_until="networkidle",
            timeout=15000,
        )

        # Extract courses via JavaScript
        courses_data = await page.evaluate("""
            () => {
                const courses = [];
                const rows = document.querySelectorAll(
                    'tr.course-list-table-row, ' +
                    '.course-list-course-title-column a, ' +
                    '.ic-DashboardCard, ' +
                    '[data-course-id]'
                );
                rows.forEach(row => {
                    const nameEl = row.querySelector(
                        '.course-list-course-title-column a, ' +
                        '.ic-DashboardCard__header_title, ' +
                        'a[href*="/courses/"], h3, span.name'
                    ) || row;
                    const name = nameEl?.textContent?.trim();
                    const href = (
                        nameEl?.getAttribute('href') ||
                        row.getAttribute('href') || ''
                    );
                    const match = href.match(/\\/courses\\/(\\d+)/);
                    const courseId = match ? parseInt(match[1]) : null;
                    const codeEl = row.querySelector(
                        '.course-list-course-code, ' +
                        '.ic-DashboardCard__header_subtitle'
                    );
                    const code = codeEl?.textContent?.trim();
                    const termEl = row.querySelector(
                        '.course-list-term, .term'
                    );
                    const term = termEl?.textContent?.trim();

                    if (name && courseId) {
                        courses.push({
                            canvas_course_id: courseId,
                            name: name,
                            course_code: code || null,
                            term: term || null,
                        });
                    }
                });
                return courses;
            }
        """)

        # Deduplicate by course ID
        seen: set[int] = set()
        courses: list[CourseInfo] = []
        for c in courses_data:
            cid = c["canvas_course_id"]
            if cid not in seen:
                seen.add(cid)
                courses.append(
                    CourseInfo(
                        canvas_course_id=cid,
                        name=c["name"],
                        course_code=c.get("course_code"),
                        term=c.get("term"),
                    )
                )

        logger.info("Encontrados %d cursos.", len(courses))
        return courses

    # ── Material Scraping ────────────────────────────────────────────────

    async def scrape_course_materials(
        self, course_id: int
    ) -> list[MaterialInfo]:
        """
        Scrape and download lesson materials from a Canvas course.

        Navigates to /courses/{id}/modules, finds links matching
        "Aula \\d+" regex, clicks each to open the document page,
        then downloads the file.

        Args:
            course_id: Canvas course numeric ID.

        Returns:
            List of MaterialInfo with local file paths.
        """
        page = self._page
        if not page:
            raise RuntimeError("Browser not initialized.")

        logger.info("Buscando materiais do curso %d...", course_id)

        # Create download dir for this course
        dl_dir = self._download_dir / str(course_id)
        dl_dir.mkdir(parents=True, exist_ok=True)

        materials: list[MaterialInfo] = []

        # Navigate to modules page
        await page.goto(
            f"{CANVAS_URL}/courses/{course_id}/modules",
            wait_until="domcontentloaded",
            timeout=30000,
        )
        await page.wait_for_timeout(3000)

        # Find links matching "Aula \d+" pattern
        aula_links = await page.evaluate("""
            () => {
                const results = [];
                const links = document.querySelectorAll(
                    '.context_module_item .item_name a, ' +
                    '.ig-title a, a.ig-title'
                );
                const pattern = /Aula\\s*\\d+/i;
                links.forEach(a => {
                    const text = a.textContent?.trim();
                    if (text && pattern.test(text)) {
                        results.push({
                            text: text,
                            href: a.getAttribute('href') || '',
                        });
                    }
                });
                return results;
            }
        """)

        logger.info(
            "Encontrados %d links 'Aula' no curso %d.",
            len(aula_links), course_id,
        )

        # Download each material
        for idx, link_info in enumerate(aula_links):
            name = link_info["text"]
            href = link_info["href"]

            logger.info(
                "  [%d/%d] Baixando: %s",
                idx + 1, len(aula_links), name[:60],
            )

            try:
                # Navigate to the document page
                full_url = (
                    href
                    if href.startswith("http")
                    else f"{CANVAS_URL}{href}"
                )
                await page.goto(
                    full_url,
                    wait_until="domcontentloaded",
                    timeout=20000,
                )
                await page.wait_for_timeout(2000)

                # Find download link on the document page
                download_link = await page.query_selector(
                    'a[download], a[href*="/download"], '
                    'a:has-text("Download"), '
                    'a:has-text("download"), a.file-download'
                )

                if download_link:
                    download_href = await download_link.get_attribute("href")
                    if download_href:
                        dl_url = (
                            download_href
                            if download_href.startswith("http")
                            else f"{CANVAS_URL}{download_href}"
                        )

                        # Use Playwright download mechanism
                        async with page.expect_download(
                            timeout=30000
                        ) as download_info:
                            await download_link.click()

                        download = await download_info.value
                        suggested = (
                            download.suggested_filename
                            or f"{name}.pdf"
                        )
                        save_path = dl_dir / suggested
                        await download.save_as(str(save_path))

                        # Extract file ID from URL
                        fid_match = re.search(r"/files/(\d+)", dl_url)
                        file_id = (
                            int(fid_match.group(1))
                            if fid_match
                            else hash(name) % 10**9
                        )

                        ext = save_path.suffix.lstrip(".").lower()
                        materials.append(
                            MaterialInfo(
                                canvas_file_id=file_id,
                                file_name=suggested,
                                file_url=str(save_path),
                                file_type=ext if ext else None,
                                course_id=course_id,
                            )
                        )
                        logger.info("    ✅ Salvo: %s", suggested)
                    else:
                        logger.warning(
                            "    ⚠️  Link sem href: %s", name
                        )
                else:
                    logger.warning(
                        "    ⚠️  Botão download não encontrado: %s", name
                    )

            except Exception as e:
                logger.warning(
                    "    ❌ Falha: '%s': %s",
                    name[:40], str(e)[:80],
                )
                continue

        # Return to modules page
        await page.goto(
            f"{CANVAS_URL}/courses/{course_id}/modules",
            wait_until="domcontentloaded",
            timeout=15000,
        )

        logger.info(
            "Baixados %d materiais do curso %d.",
            len(materials), course_id,
        )
        return materials

    # ── Helpers ───────────────────────────────────────────────────────────

    @staticmethod
    def _is_canvas_url(url: str) -> bool:
        """Check if URL is an authenticated Canvas page (not login)."""
        url_lower = url.lower()
        return "canvas.espm.br" in url_lower and "login" not in url_lower
