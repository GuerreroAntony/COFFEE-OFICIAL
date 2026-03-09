"""
ScheduleExtractor — extrai grade horária do Portal ESPM via Playwright.
Usa storage_state já autenticado; seletores resilientes com correspondência parcial.

Adaptado para arquitetura Coffee:
- Output mapeado para tabela `disciplinas` (nome, professor, horario, semestre, codigo_espm)
- Sem dependência de SQLAlchemy
"""
from __future__ import annotations

import os
import re
import structlog
from datetime import date
from typing import Dict, List, Optional, Tuple

from playwright.async_api import async_playwright

from app.modules.espm.auth.authenticator import _USER_AGENT, _BROWSER_HEADERS, _CHROMIUM_ARGS

_HEADLESS = os.getenv("PLAYWRIGHT_HEADED", "false").lower() != "true"

logger = structlog.get_logger(__name__)

MY_COURSES_URL = "https://portal.espm.br/my-courses"


class ScheduleExtractor:
    # ── Seletores resilientes (parciais, não dependem de hash CSS) ────────────
    COURSE_CARD_SEL = 'a[href*="my-courses/student-"]'
    GRID_SVG_SEL    = "svg.lucide-layout-grid"
    COLLAPSE_BOX    = 'div[class*="collapseBox"]'

    # ── Públicos ──────────────────────────────────────────────────────────────

    async def extract(self, storage_state: Dict, logs: List[str]) -> List[Dict]:
        """Cria um novo browser a partir do storage_state e extrai a grade."""
        async with async_playwright() as pw:
            browser = await pw.chromium.launch(headless=_HEADLESS, args=_CHROMIUM_ARGS)
            try:
                context = await browser.new_context(
                    storage_state=storage_state,
                    user_agent=_USER_AGENT,
                    viewport={"width": 1280, "height": 720},
                    extra_http_headers=_BROWSER_HEADERS,
                )
                return await self._do_extract(context, logs)
            finally:
                await browser.close()

    async def extract_with_context(self, context, logs: List[str], page=None) -> List[Dict]:
        """Extrai a grade reutilizando um contexto já autenticado (mesma janela do login)."""
        return await self._do_extract(context, logs, page=page)

    # ── Core ──────────────────────────────────────────────────────────────────

    async def _do_extract(self, context, logs: List[str], page=None) -> List[Dict]:
        if page is None:
            page = await context.new_page()

        await page.goto(MY_COURSES_URL, wait_until="domcontentloaded", timeout=60000)
        await self._wait_idle(page)

        # Remove modal NEXUS/MUI do DOM via JS
        await self._remove_nexus_modal(page, logs)

        # Entrar no curso ativo — tenta múltiplos seletores
        CARD_SELECTORS = [
            'a[href*="my-courses/student-"]',
            'a[href*="my-courses/"]',
            'a[href*="/student-"]',
            'div[class*="courseCard"] a',
            'div[class*="CourseCard"] a',
        ]

        card = None
        for sel in CARD_SELECTORS:
            try:
                card = await page.wait_for_selector(sel, timeout=5000)
                if card:
                    logs.append(f"Course card encontrado via: {sel}")
                    break
            except Exception:
                continue

        if not card:
            html_snippet = await page.evaluate("() => document.body.innerHTML.substring(0, 3000)")
            logs.append(f"DEBUG HTML (primeiros 500 chars): {html_snippet[:500]}")
            logger.error("schedule.extract.no_card", url=page.url, html_snippet=html_snippet[:1000])
            raise RuntimeError("Nenhum course card encontrado no portal.")

        href = await card.get_attribute("href")
        if not href:
            raise RuntimeError("Link do curso não encontrado no card.")
        course_url = href if href.startswith("http") else f"https://portal.espm.br{href}"
        logs.append(f"Navegando para curso: {course_url}")
        await page.goto(course_url, wait_until="domcontentloaded", timeout=60000)
        await self._wait_idle(page, 15000)
        await page.wait_for_timeout(4000)  # aguarda React hidratar

        # Log do título da página para confirmar que carregou
        title = await page.title()
        logs.append(f"Página carregada: {title}")

        # Remover modais novamente (podem reaparecer na página do curso)
        await self._remove_nexus_modal(page, logs)
        await page.wait_for_timeout(500)

        # Ativar list view (collapseBox só existe em list view, não em grid view)
        await self._activate_list_view(page, logs)

        await page.wait_for_timeout(3000)  # render dos cards

        # Expandir todos os collapseBox
        await page.evaluate("""
            () => {
                document.querySelectorAll('button[class*="expand"]').forEach(btn => btn.click());
            }
        """)
        await page.wait_for_timeout(1000)

        # Extrair dados brutos do DOM
        raw_list = await page.evaluate("""
            () => {
                const boxes = document.querySelectorAll('div[class*="collapseBox"], div[class*="MuiCollapse-root"]');
                const results = [];
                Array.from(boxes).forEach(box => {
                    function getTextNodes(node) {
                        let all = [];
                        for (node = node.firstChild; node; node = node.nextSibling) {
                            if (node.nodeType == 3) {
                                if (node.textContent.trim().length > 0) all.push(node.textContent.trim());
                            } else {
                                all = all.concat(getTextNodes(node));
                            }
                        }
                        return all;
                    }
                    
                    const texts = getTextNodes(box);
                    if (texts.length < 3) return;
                    
                    results.push({
                        name:  box.querySelector('h2, div[class*="Typography"]')?.innerText?.trim() ?? texts[0],
                        texts: texts
                    });
                });
                return results;
            }
        """)


        disciplines: List[Dict] = []
        for raw in raw_list:
            if 'texts' in raw:
                texts = raw["texts"]
                raw["name"] = raw.get("name") or texts[0]
                raw["labels"] = []
                raw["timeChips"] = []
                raw["professor"] = None

                for i, text in enumerate(texts):
                    if "Carga horária:" in text:
                        val = text
                        if not re.search(r'\d', text) and i + 1 < len(texts):
                            val += " " + texts[i + 1]
                        raw["labels"].append(val)
                    elif "Período:" in text:
                        val = text
                        if not re.search(r'\d', text) and i + 1 < len(texts):
                            val += " " + texts[i + 1]
                        raw["labels"].append(val)

                    if "das " in text.lower() and "às " in text.lower():
                        time_str = text.replace("Dias de aula:", "").strip()
                        if time_str and time_str not in raw["timeChips"]:
                            raw["timeChips"].append(time_str)

                    if (len(text) > 4
                        and "Falta" not in text
                        and "Aula a aula" not in text
                        and "Carga" not in text
                        and "Período" not in text):
                        if (not re.search(r'\d', text)
                            and "das " not in text.lower()
                            and "às " not in text.lower()):
                            if len(text) > 3 and not (text.isupper() and len(text) <= 4):
                                if text != raw["name"] and "2026" not in text:
                                    if not raw["professor"]:
                                        raw["professor"] = text

            disc = self._parse_raw(raw)
            if disc and disc.get("nome"):
                # Filtrar falsos positivos: só aceita entradas com turma (padrão "CÓDIGO - Nome")
                if not disc.get("turma"):
                    continue
                # Excluir entradas onde o "professor" é na verdade um label do DOM
                professor = disc.get("professor") or ""
                if professor.rstrip(":").strip().lower() in ("dias de aula", "carga horária", "período"):
                    continue
                if not any(d["nome"] == disc["nome"] for d in disciplines):
                    disciplines.append(disc)

        logger.info("schedule.extract.done", count=len(disciplines))
        logs.append(f"Extraídas {len(disciplines)} disciplinas.")
        return disciplines

    # ── Grid view ─────────────────────────────────────────────────────────────

    async def _activate_list_view(self, page, logs: List[str]) -> None:
        """Ativa list view clicando no botão gridFiltersButton sem classe 'active'.
        Grid view é o padrão da página — collapseBox só existe em list view."""
        # Remove modais MUI que podem bloquear cliques
        await page.evaluate("""() => {
            ['.MuiDialog-container', '.MuiBackdrop-root', '.MuiModal-root',
             '[role="dialog"]'].forEach(sel => {
                document.querySelectorAll(sel).forEach(el => el.remove());
            });
        }""")
        await page.wait_for_timeout(300)

        # Clica no botão SEM a classe "active" (= list view button)
        clicked = await page.evaluate("""() => {
            const buttons = document.querySelectorAll('div[class*="gridFiltersButton"]');
            for (const btn of buttons) {
                if (!btn.className.includes('active')) {
                    btn.click();
                    return 'ok: ' + btn.className.substring(0, 60);
                }
            }
            return 'nenhum botão inativo encontrado';
        }""")
        logs.append(f"List view click: {clicked}")
        await self._wait_idle(page, 3000)

    # ── Helpers de página ─────────────────────────────────────────────────────

    @staticmethod
    async def _wait_idle(page, timeout_ms: int = 8_000) -> None:
        try:
            await page.wait_for_load_state("networkidle", timeout=timeout_ms)
        except Exception:
            pass

    async def _remove_nexus_modal(self, page, logs: List[str]) -> None:
        try:
            await page.wait_for_timeout(2_000)
            removed = await page.evaluate("""
                () => {
                    const els = document.querySelectorAll(
                        '.MuiDialog-container, .MuiBackdrop-root, .MuiModal-root'
                    );
                    els.forEach(el => el.remove());
                    return els.length;
                }
            """)
            if removed:
                logs.append(f"Removido {removed} modal(is) NEXUS.")
        except Exception as exc:
            logger.warning("schedule.remove_nexus_modal.error", error=str(exc))

    # ── Parsers ───────────────────────────────────────────────────────────────
    # Output mapeado para schema Coffee `disciplinas`:
    #   turma, nome, professor, horario, horarios, semestre,
    #   days, time_start, time_end, period_start, period_end

    def _parse_raw(self, raw: dict) -> Optional[Dict]:
        """Converte dict bruto do JS → dict no formato Coffee `disciplinas`."""
        name = raw.get("name")
        if not name:
            return None

        # ── Extrair turma e nome real ──────────────────────────────────────────
        # Portal ESPM: "AD1N - Business Lab 1" → turma="AD1N", nome="Business Lab 1"
        if " - " in name:
            turma, nome = name.split(" - ", 1)
            turma = turma.strip()
            nome  = nome.strip()
        else:
            turma = None
            nome  = name.strip()

        professor  = raw.get("professor")
        time_chips = raw.get("timeChips", [])
        labels     = raw.get("labels", [])

        # ── Coletar TODOS os slots de horário ──────────────────────────────────
        horarios: List[Dict] = []
        seen_slots: set = set()
        for chip_text in time_chips:
            parsed = self._parse_chip(chip_text)
            if parsed:
                day, ts, te = parsed
                slot_key = (day, ts, te)
                if slot_key not in seen_slots:
                    seen_slots.add(slot_key)
                    horarios.append({
                        "day":        day.capitalize(),
                        "time_start": ts,
                        "time_end":   te,
                    })

        # dias únicos (preservando ordem de aparição)
        days: List[str] = list(dict.fromkeys(h["day"] for h in horarios))

        # primeiro slot para colunas legadas
        time_start: Optional[str] = horarios[0]["time_start"] if horarios else None
        time_end:   Optional[str] = horarios[0]["time_end"]   if horarios else None

        # string legível: "Sexta 19:30-21:10 / Sexta 21:20-23:00"
        horario: Optional[str] = None
        if horarios:
            parts = [f"{h['day']} {h['time_start']}-{h['time_end']}" for h in horarios]
            horario = " / ".join(parts)

        # ── Período ────────────────────────────────────────────────────────────
        period_start: Optional[date] = None
        period_end:   Optional[date] = None

        for text in labels:
            if period_start is None and re.search(r"\d{2}/\d{2}/\d{4}", text):
                period_start, period_end = self._parse_period(text)

        semester = self._infer_semester(period_start)

        return {
            # ── Campos da tabela Coffee `disciplinas` ──
            "turma":       turma,
            "nome":        nome,
            "professor":   professor,
            "horario":     horario,
            "semestre":    semester,
            "codigo_espm": None,

            # ── Campos de horário detalhados ──
            "horarios":    horarios,        # lista de {day, time_start, time_end}
            "days":        days or None,
            "time_start":  time_start,
            "time_end":    time_end,

            # ── Período (objetos date — asyncpg converte para DATE) ──
            "period_start": period_start,
            "period_end":   period_end,
        }

    @staticmethod
    def _parse_chip(text: str) -> Optional[Tuple[str, str, str]]:
        """'Quinta, das 21:20 às 23:00' → ('quinta', '21:20', '23:00')"""
        m = re.search(
            r"(\w+),\s*das\s+(\d{2}:\d{2})\s+às\s+(\d{2}:\d{2})",
            text,
            re.IGNORECASE | re.UNICODE,
        )
        if not m:
            return None
        return m.group(1).lower(), m.group(2), m.group(3)

    @staticmethod
    def _parse_period(text: str) -> Tuple[Optional[date], Optional[date]]:
        """'Iniciou em 05/02/2026 e termina em 25/06/2026.' → (date, date)"""
        from datetime import datetime
        dates = re.findall(r"\d{2}/\d{2}/\d{4}", text)
        parsed = []
        for d in dates:
            try:
                parsed.append(datetime.strptime(d, "%d/%m/%Y").date())
            except ValueError:
                pass
        return (parsed[0] if parsed else None, parsed[1] if len(parsed) > 1 else None)

    @staticmethod
    def _infer_semester(period_start: Optional[date]) -> str:
        """month <= 6 → 'YYYY.1', month > 6 → 'YYYY.2'. Fallback: ano atual."""
        if period_start is None:
            from datetime import date as _date
            today = _date.today()
            return f"{today.year}.{'1' if today.month <= 6 else '2'}"
        return f"{period_start.year}.{'1' if period_start.month <= 6 else '2'}"
