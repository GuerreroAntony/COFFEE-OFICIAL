from __future__ import annotations

import logging
import pathlib

import httpx

from scraper.config import settings

logger = logging.getLogger(__name__)


async def upload_to_supabase(
    filepath: str, disciplina_id: str, filename: str
) -> str:
    """Upload file to Supabase Storage. Returns the public URL."""
    storage_path = f"{disciplina_id}/{filename}"
    url = (
        f"{settings.SUPABASE_URL}/storage/v1/object/"
        f"{settings.SUPABASE_STORAGE_BUCKET}/{storage_path}"
    )

    content_type = _guess_content_type(pathlib.Path(filepath).suffix.lower())

    async with httpx.AsyncClient(timeout=60.0) as client:
        with open(filepath, "rb") as f:
            resp = await client.post(
                url,
                content=f.read(),
                headers={
                    "Authorization": f"Bearer {settings.SUPABASE_KEY}",
                    "Content-Type": content_type,
                    "x-upsert": "true",
                },
            )
            resp.raise_for_status()

    public_url = (
        f"{settings.SUPABASE_URL}/storage/v1/object/public/"
        f"{settings.SUPABASE_STORAGE_BUCKET}/{storage_path}"
    )
    logger.info("Uploaded %s → %s", filename, public_url)
    return public_url


def _guess_content_type(ext: str) -> str:
    mapping = {
        ".pdf": "application/pdf",
        ".pptx": "application/vnd.openxmlformats-officedocument.presentationml.presentation",
        ".ppt": "application/vnd.ms-powerpoint",
        ".docx": "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
    }
    return mapping.get(ext, "application/octet-stream")
