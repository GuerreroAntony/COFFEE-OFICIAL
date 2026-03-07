"""
Coffee Canvas Scraper — Main Orchestrator
==========================================
Usage:
    python -m scraper.main              # intelligent multi-user scrape (default)
    python -m scraper.main --test       # dry-run: scrape but don't save
    python -m scraper.main --legacy     # single-credential mode (old behavior)
    python -m scraper.main --disciplina UUID  # single disciplina
"""

from __future__ import annotations

import argparse
import asyncio
import json
import logging
import re
import sys
import unicodedata
from uuid import UUID

from cryptography.fernet import Fernet

from scraper.config import settings
from scraper.canvas_scraper import CanvasESPMScraper, CourseInfo
from scraper import db
from scraper.file_processor import extract_text, compute_file_hash
from scraper.storage import upload_to_supabase
from scraper.embedding_pipeline import process_material
from scraper.push import send_fcm_push

logger = logging.getLogger(__name__)


# ── Helpers ──────────────────────────────────────────────────────────────────


def _normalize(text: str) -> str:
    """Lowercase, strip accents, collapse whitespace."""
    text = unicodedata.normalize("NFKD", text)
    text = "".join(c for c in text if not unicodedata.combining(c))
    return " ".join(text.lower().split())


def _classify_file_type(ext: str | None) -> str:
    """Map file extension to materiais.tipo enum."""
    if not ext:
        return "outro"
    ext = ext.lower()
    if ext == "pdf":
        return "pdf"
    elif ext in ("pptx", "ppt"):
        return "slide"
    return "outro"


async def _match_courses_to_disciplinas(
    courses: list[CourseInfo],
    disciplinas: list,
) -> dict[int, UUID]:
    """Match Canvas courses to Coffee disciplinas.

    Returns {canvas_course_id: disciplina_id}.
    Priority:
      1. Exact match on disciplinas.canvas_course_id (previously linked)
      2. Normalized name containment
    """
    mapping: dict[int, UUID] = {}

    for course in courses:
        # Priority 1: already linked
        row = await db.find_disciplina_by_canvas_course_id(course.canvas_course_id)
        if row:
            mapping[course.canvas_course_id] = row["id"]
            continue

        # Priority 2: fuzzy name match
        norm_course = _normalize(course.name)
        best_match = None
        for disc in disciplinas:
            norm_disc = _normalize(disc["nome"])
            if norm_disc in norm_course or norm_course in norm_disc:
                best_match = disc
                break

        if best_match:
            mapping[course.canvas_course_id] = best_match["id"]
            await db.update_disciplina_canvas_id(
                best_match["id"], course.canvas_course_id
            )
            logger.info("Matched: '%s' → '%s'", course.name, best_match["nome"])
        else:
            logger.warning(
                "No match for Canvas course: '%s' (ID=%d)",
                course.name,
                course.canvas_course_id,
            )

    return mapping


async def _process_material(mat, disc_id: UUID, stats: dict, test_mode: bool) -> None:
    """Process a single MaterialInfo: dedup, extract, upload, save, embed."""
    if await db.material_exists(mat.canvas_file_id):
        stats["materials_skipped"] += 1
        return

    if test_mode:
        logger.info("[TEST] Would process: %s (file_id=%d)", mat.file_name, mat.canvas_file_id)
        stats["materials_new"] += 1
        return

    # Extract text
    texto = extract_text(mat.file_url, mat.file_type)
    file_hash = compute_file_hash(mat.file_url)

    # Upload to Supabase Storage
    try:
        public_url = await upload_to_supabase(
            mat.file_url, str(disc_id), mat.file_name
        )
    except Exception as e:
        logger.error("Upload failed for %s: %s", mat.file_name, e)
        public_url = None

    # Save material record
    tipo = _classify_file_type(mat.file_type)
    ai_enabled = bool(re.search(r'Aula\s*\d+', mat.file_name, re.IGNORECASE))
    material_id = await db.save_material(
        disciplina_id=disc_id,
        tipo=tipo,
        nome=mat.file_name,
        url_storage=public_url,
        texto_extraido=texto if texto else None,
        canvas_file_id=mat.canvas_file_id,
        hash_arquivo=file_hash,
        ai_enabled=ai_enabled,
    )
    stats["materials_new"] += 1
    logger.info("Saved material: %s (id=%s)", mat.file_name, material_id)

    # Generate embeddings
    if texto:
        try:
            n_chunks = await process_material(texto, disc_id, material_id)
            stats["embeddings_created"] += n_chunks
        except Exception as e:
            logger.error("Embedding failed for %s: %s", mat.file_name, e)

    # Notification trigger + push delivery
    try:
        await db.save_notification_trigger(disc_id, mat.file_name)
        await _send_push_notifications(disc_id, mat.file_name)
    except Exception as e:
        logger.error("Notification/push failed for %s: %s", mat.file_name, e)


async def _send_push_notifications(disc_id: UUID, material_name: str) -> None:
    """Send FCM push to all users enrolled in a disciplina."""
    if not settings.FIREBASE_PROJECT_ID:
        return

    tokens = await db.get_device_tokens_for_disciplina(disc_id)
    if not tokens:
        return

    sent = 0
    for row in tokens:
        try:
            ok = await send_fcm_push(
                token=row["fcm_token"],
                title="Novo material disponivel",
                body=material_name,
                data={"disciplina_id": str(disc_id), "material_nome": material_name},
            )
            if ok:
                sent += 1
        except Exception as e:
            logger.error("FCM push failed for token: %s", e)

    if sent:
        logger.info("Sent %d push notification(s) for '%s'", sent, material_name)


# ── Main pipelines ───────────────────────────────────────────────────────────


async def scrape_all(test_mode: bool = False) -> dict:
    """Full pipeline: scrape all Canvas courses and process materials."""
    await db.get_pool()
    stats = {
        "courses_found": 0,
        "matched": 0,
        "materials_new": 0,
        "materials_skipped": 0,
        "embeddings_created": 0,
    }

    # Step 1: Get all disciplinas from DB
    disciplinas = await db.get_all_disciplinas()
    if not disciplinas:
        logger.warning("No disciplinas found in DB. Run ESPM sync first.")
        await db.close_pool()
        return stats

    # Step 2: Run Canvas scraper
    logger.info("Starting Canvas scrape for %s...", settings.ESPM_USERNAME)
    async with CanvasESPMScraper(
        email=settings.ESPM_USERNAME,
        password=settings.ESPM_PASSWORD,
        download_dir=settings.DOWNLOAD_DIR,
        headless=settings.HEADLESS,
    ) as scraper:
        result = await scraper.run()

    if not result.success:
        logger.error("Canvas scrape failed: %s", result.error)
        await db.close_pool()
        return stats

    stats["courses_found"] = len(result.courses)
    logger.info("Found %d courses on Canvas", len(result.courses))

    # Step 3: Match courses to disciplinas
    course_disc_map = await _match_courses_to_disciplinas(
        result.courses, disciplinas
    )
    stats["matched"] = len(course_disc_map)
    logger.info("Matched %d/%d courses to disciplinas", len(course_disc_map), len(result.courses))

    # Step 4: Process materials
    for course in result.courses:
        disc_id = course_disc_map.get(course.canvas_course_id)
        if not disc_id:
            continue

        materials = result.materials.get(course.name, [])
        logger.info("Processing %d materials for '%s'", len(materials), course.name)

        for mat in materials:
            await _process_material(mat, disc_id, stats, test_mode)

    await db.close_pool()
    return stats


async def scrape_disciplina(
    disciplina_id: str, test_mode: bool = False
) -> dict:
    """Scrape materials for a single disciplina."""
    await db.get_pool()
    stats = {
        "materials_new": 0,
        "materials_skipped": 0,
        "embeddings_created": 0,
    }

    disc_uuid = UUID(disciplina_id)
    disc = await db.get_disciplina(disc_uuid)
    if not disc:
        logger.error("Disciplina %s not found", disciplina_id)
        await db.close_pool()
        return stats

    canvas_course_id = disc["canvas_course_id"]
    if not canvas_course_id:
        # Try matching by codigo_espm as fallback
        if disc["codigo_espm"] and disc["codigo_espm"].isdigit():
            canvas_course_id = int(disc["codigo_espm"])
        else:
            logger.error(
                "Disciplina '%s' has no canvas_course_id. Run scrape_all first to match.",
                disc["nome"],
            )
            await db.close_pool()
            return stats

    logger.info("Scraping course %d for disciplina '%s'", canvas_course_id, disc["nome"])

    async with CanvasESPMScraper(
        email=settings.ESPM_USERNAME,
        password=settings.ESPM_PASSWORD,
        download_dir=settings.DOWNLOAD_DIR,
        headless=settings.HEADLESS,
    ) as scraper:
        await scraper.login_via_sso()
        materials = await scraper.scrape_course_materials(canvas_course_id)

    logger.info("Found %d materials for course %d", len(materials), canvas_course_id)

    for mat in materials:
        await _process_material(mat, disc_uuid, stats, test_mode)

    await db.close_pool()
    return stats


# ── Intelligent multi-user scraping ──────────────────────────────────────────


def _decrypt_password(encrypted: bytes) -> str:
    """Decrypt a user's ESPM password using Fernet + SECRET_KEY."""
    f = Fernet(
        settings.SECRET_KEY.encode()
        if isinstance(settings.SECRET_KEY, str)
        else settings.SECRET_KEY
    )
    data = json.loads(f.decrypt(encrypted).decode())
    return data["p"]


async def _build_scrape_plan() -> list[dict]:
    """Greedy set cover: pick minimum users to cover all stale disciplinas.

    Returns list of:
      {"email": str, "password": str, "canvas_course_map": {disc_id: canvas_course_id}}
    """
    stale = await db.get_stale_disciplinas()
    if not stale:
        logger.info("All disciplinas are fresh. Nothing to scrape.")
        return []

    stale_ids = {row["id"] for row in stale}
    disc_to_canvas = {row["id"]: row["canvas_course_id"] for row in stale}

    credential_pool = await db.get_credential_pool()
    if not credential_pool:
        logger.warning("No users with stored credentials.")
        return []

    # Build user -> set of stale disciplina_ids they can cover
    user_coverage: dict[UUID, dict] = {}
    for user in credential_pool:
        user_disc_ids = set(await db.get_user_disciplina_ids(user["user_id"]))
        coverable = user_disc_ids & stale_ids
        if coverable:
            user_coverage[user["user_id"]] = {
                "email": user["espm_login"],
                "encrypted_password": user["encrypted_espm_password"],
                "coverable": coverable,
            }

    # Greedy set cover
    plan = []
    uncovered = set(stale_ids)

    while uncovered and user_coverage:
        best_uid = max(
            user_coverage,
            key=lambda uid: len(user_coverage[uid]["coverable"] & uncovered),
        )
        best = user_coverage[best_uid]
        covered_now = best["coverable"] & uncovered

        if not covered_now:
            break

        try:
            password = _decrypt_password(best["encrypted_password"])
        except Exception as e:
            logger.error("Failed to decrypt password for %s: %s", best["email"], e)
            del user_coverage[best_uid]
            continue

        plan.append({
            "email": best["email"],
            "password": password,
            "canvas_course_map": {
                did: disc_to_canvas[did] for did in covered_now
            },
        })

        uncovered -= covered_now
        del user_coverage[best_uid]

    if uncovered:
        logger.warning(
            "%d disciplinas have no user with credentials: %s",
            len(uncovered),
            [str(uid) for uid in uncovered],
        )

    return plan


async def scrape_all_intelligent(test_mode: bool = False) -> dict:
    """Multi-user intelligent scraping pipeline."""
    await db.get_pool()
    stats = {
        "users_used": 0,
        "courses_scraped": 0,
        "materials_new": 0,
        "materials_skipped": 0,
        "embeddings_created": 0,
        "errors": 0,
    }

    plan = await _build_scrape_plan()

    if not plan:
        # Fallback to legacy global credentials if available
        if settings.ESPM_USERNAME and settings.ESPM_PASSWORD:
            logger.info("No multi-user plan. Falling back to global credentials.")
            return await scrape_all(test_mode=test_mode)
        logger.info("Nothing to scrape.")
        await db.close_pool()
        return stats

    logger.info(
        "Scrape plan: %d user(s) covering %d course(s)",
        len(plan),
        sum(len(a["canvas_course_map"]) for a in plan),
    )

    for assignment in plan:
        email = assignment["email"]
        canvas_map = assignment["canvas_course_map"]

        logger.info(
            "Logging in as %s to scrape %d course(s)...",
            email, len(canvas_map),
        )
        stats["users_used"] += 1

        try:
            async with CanvasESPMScraper(
                email=email,
                password=assignment["password"],
                download_dir=settings.DOWNLOAD_DIR,
                headless=settings.HEADLESS,
            ) as scraper:
                await scraper.login_via_sso()

                for disc_id, canvas_course_id in canvas_map.items():
                    try:
                        materials = await scraper.scrape_course_materials(
                            canvas_course_id
                        )
                        logger.info(
                            "Found %d materials for course %d",
                            len(materials), canvas_course_id,
                        )

                        for mat in materials:
                            await _process_material(mat, disc_id, stats, test_mode)

                        if not test_mode:
                            await db.update_last_scraped(disc_id)
                        stats["courses_scraped"] += 1

                    except Exception as e:
                        logger.error(
                            "Failed to scrape course %d: %s",
                            canvas_course_id, e,
                        )
                        stats["errors"] += 1

        except Exception as e:
            logger.error("Login failed for %s: %s", email, e)
            stats["errors"] += 1

    await db.close_pool()
    return stats


# ── CLI ──────────────────────────────────────────────────────────────────────


def main():
    parser = argparse.ArgumentParser(description="Coffee Canvas Scraper")
    parser.add_argument("--test", action="store_true", help="Dry-run mode (no DB writes)")
    parser.add_argument("--disciplina", type=str, help="Scrape single disciplina by UUID")
    parser.add_argument("--legacy", action="store_true", help="Use legacy single-credential mode")
    args = parser.parse_args()

    logging.basicConfig(
        level=getattr(logging, settings.LOG_LEVEL),
        format="%(asctime)s [%(levelname)s] %(name)s: %(message)s",
        stream=sys.stdout,
    )

    if args.disciplina:
        stats = asyncio.run(scrape_disciplina(args.disciplina, test_mode=args.test))
    elif args.legacy:
        stats = asyncio.run(scrape_all(test_mode=args.test))
    else:
        stats = asyncio.run(scrape_all_intelligent(test_mode=args.test))

    logger.info("Scrape complete: %s", stats)


if __name__ == "__main__":
    main()
