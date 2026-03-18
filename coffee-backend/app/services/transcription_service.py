"""
Transcription service — GPT-4o Transcribe cloud transcription.
Downloads audio from Supabase Storage, transcribes via OpenAI API,
and handles cleanup.
"""
import logging
from typing import Optional

import httpx

from app.config import settings
from app.services.openai_service import OpenAIService

logger = logging.getLogger("transcription_service")
_openai = OpenAIService()


async def transcribe_audio(audio_bytes: bytes, language: str = "pt") -> str:
    """Transcribe audio bytes using GPT-4o Transcribe API.

    Returns plain text transcription.
    """
    import io

    audio_file = io.BytesIO(audio_bytes)
    audio_file.name = "recording.m4a"

    # AsyncOpenAI client — await directly (no to_thread)
    result = await _openai.client.audio.transcriptions.create(
        model="gpt-4o-transcribe",
        file=audio_file,
        language=language,
        response_format="text",
    )

    text = result.strip() if isinstance(result, str) else str(result).strip()
    logger.info("Transcription completed: %d chars", len(text))
    return text


async def download_from_storage(bucket: str, path: str) -> bytes:
    """Download a file from Supabase Storage."""
    url = f"{settings.SUPABASE_URL}/storage/v1/object/{bucket}/{path}"
    async with httpx.AsyncClient(timeout=120.0) as client:
        resp = await client.get(
            url,
            headers={"Authorization": f"Bearer {settings.SUPABASE_KEY}"},
        )
    if resp.status_code != 200:
        raise RuntimeError(f"Failed to download {bucket}/{path}: {resp.status_code}")
    return resp.content


async def delete_from_storage(bucket: str, path: str) -> bool:
    """Delete a file from Supabase Storage. Returns True on success.

    Uses the batch delete endpoint: DELETE /storage/v1/object/{bucket}
    with JSON body {"prefixes": ["path"]}.
    """
    url = f"{settings.SUPABASE_URL}/storage/v1/object/{bucket}"
    async with httpx.AsyncClient(timeout=30.0) as client:
        resp = await client.request(
            "DELETE",
            url,
            headers={
                "Authorization": f"Bearer {settings.SUPABASE_KEY}",
                "Content-Type": "application/json",
            },
            content=__import__("json").dumps({"prefixes": [path]}),
        )
    if resp.status_code in (200, 204):
        logger.info("Deleted %s/%s from storage", bucket, path)
        return True
    logger.warning("Failed to delete %s/%s: %d %s", bucket, path, resp.status_code, resp.text[:100])
    return False


async def upload_to_storage(
    bucket: str,
    path: str,
    content: bytes,
    content_type: str = "audio/mp4",
) -> str:
    """Upload a file to Supabase Storage. Returns the public URL."""
    upload_url = f"{settings.SUPABASE_URL}/storage/v1/object/{bucket}/{path}"

    async with httpx.AsyncClient(timeout=60.0) as client:
        resp = await client.post(
            upload_url,
            content=content,
            headers={
                "Authorization": f"Bearer {settings.SUPABASE_KEY}",
                "Content-Type": content_type,
                "x-upsert": "true",
            },
        )
    if resp.status_code not in (200, 201):
        raise RuntimeError(f"Storage upload failed ({resp.status_code}): {resp.text[:200]}")

    public_url = (
        f"{settings.SUPABASE_URL}/storage/v1/object/public/{bucket}/{path}"
    )
    return public_url
