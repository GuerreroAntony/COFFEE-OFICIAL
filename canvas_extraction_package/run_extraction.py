"""
Canvas ESPM — Material Extraction Runner
=========================================

Standalone script to extract all course materials from Canvas ESPM.

Setup:
    1. Copy .env.example to .env and fill in credentials
    2. pip install -r requirements.txt
    3. playwright install chromium
    4. python run_extraction.py

Output:
    - Console: table of courses + materials per discipline
    - Files: PDFs saved to ./downloads/{course_id}/
"""

import asyncio
import json
import logging
import os
import sys

from dotenv import load_dotenv

# Load .env from the same directory as this script
load_dotenv(os.path.join(os.path.dirname(__file__), ".env"))

from canvas_scraper import CanvasESPMScraper

# ── Configuration ────────────────────────────────────────────────────────────

EMAIL = os.getenv("ESPM_PORTAL_LOGIN", "")
PASSWORD = os.getenv("ESPM_PORTAL_PASSWORD", "")
DOWNLOAD_DIR = os.getenv("DOWNLOAD_DIR", "./downloads")
HEADLESS = os.getenv("HEADLESS", "true").lower() == "true"

# ── Logging ──────────────────────────────────────────────────────────────────

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(name)s: %(message)s",
    stream=sys.stdout,
)
logger = logging.getLogger("run_extraction")


async def main():
    if not EMAIL or not PASSWORD:
        logger.error(
            "❌ Credenciais não configuradas!\n"
            "   Copie .env.example para .env e preencha ESPM_PORTAL_LOGIN e ESPM_PORTAL_PASSWORD."
        )
        sys.exit(1)

    logger.info("=" * 60)
    logger.info("EXTRAÇÃO DE MATERIAIS — CANVAS ESPM")
    logger.info("=" * 60)
    logger.info("Usuário: %s", EMAIL)
    logger.info("Headless: %s", HEADLESS)
    logger.info("Downloads: %s", os.path.abspath(DOWNLOAD_DIR))
    logger.info("=" * 60)

    async with CanvasESPMScraper(
        email=EMAIL,
        password=PASSWORD,
        download_dir=DOWNLOAD_DIR,
        headless=HEADLESS,
    ) as scraper:
        result = await scraper.run()

    if not result.success:
        logger.error("❌ Extração falhou: %s", result.error)
        sys.exit(1)

    # ── Print Results ────────────────────────────────────────────────────
    logger.info("\n" + "=" * 60)
    logger.info("RESULTADO FINAL")
    logger.info("=" * 60)

    total_materials = 0
    summary = {}

    for course in result.courses:
        materials = result.materials.get(course.name, [])
        total_materials += len(materials)
        summary[course.name] = {
            "course_id": course.canvas_course_id,
            "materials_count": len(materials),
            "materials": [
                {
                    "file_name": m.file_name,
                    "file_type": m.file_type,
                    "file_url": m.file_url,
                    "canvas_file_id": m.canvas_file_id,
                }
                for m in materials
            ],
        }

        logger.info(f"\n📘 {course.name} (ID={course.canvas_course_id}):")
        if materials:
            for m in materials:
                logger.info(f"   📎 {m.file_name} ({m.file_type or '?'})")
        else:
            logger.info("   (nenhum material extraído)")

    logger.info(
        f"\n🎯 Total: {len(result.courses)} disciplinas, "
        f"{total_materials} materiais extraídos"
    )

    # Save JSON summary
    summary_path = os.path.join(DOWNLOAD_DIR, "extraction_summary.json")
    os.makedirs(DOWNLOAD_DIR, exist_ok=True)
    with open(summary_path, "w", encoding="utf-8") as f:
        json.dump(summary, f, ensure_ascii=False, indent=2)
    logger.info(f"\n📋 Resumo salvo em: {summary_path}")


if __name__ == "__main__":
    asyncio.run(main())
