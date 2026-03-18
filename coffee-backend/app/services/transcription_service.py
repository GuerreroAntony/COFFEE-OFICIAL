"""
Transcription service — GPT-4o Transcribe cloud transcription.
Downloads audio from Supabase Storage, transcribes via OpenAI API,
and handles cleanup.  Includes cross-validation against secondary
recordings to detect and fill transcription gaps.
"""
import io
import logging
import random
from typing import Optional

import httpx

from app.config import settings
from app.services.openai_service import OpenAIService

logger = logging.getLogger("transcription_service")
_openai = OpenAIService()


async def transcribe_audio(
    audio_bytes: bytes,
    language: str = "pt",
    model: str = "gpt-4o-transcribe",
    max_retries: int = 3,
) -> str:
    """Transcribe audio bytes using GPT-4o Transcribe API.

    Retries up to max_retries times with exponential backoff.
    Returns plain text transcription.
    """
    import asyncio

    last_error = None
    for attempt in range(max_retries):
        try:
            audio_file = io.BytesIO(audio_bytes)
            audio_file.name = "recording.m4a"

            result = await _openai.client.audio.transcriptions.create(
                model=model,
                file=audio_file,
                language=language,
                response_format="text",
            )

            text = result.strip() if isinstance(result, str) else str(result).strip()
            logger.info("Transcription completed: %d chars (attempt %d)", len(text), attempt + 1)
            return text
        except Exception as e:
            last_error = e
            wait = 2 ** attempt * 5  # 5s, 10s, 20s
            logger.warning(
                "Transcription attempt %d failed: %s. Retrying in %ds...",
                attempt + 1, e, wait,
            )
            await asyncio.sleep(wait)

    raise RuntimeError(f"Transcription failed after {max_retries} attempts: {last_error}")


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


# ---------------------------------------------------------------------------
# Cross-validation against secondary recordings
# ---------------------------------------------------------------------------

def _word_set(text: str) -> set[str]:
    """Lowercase word set for overlap comparison."""
    return set(text.lower().split())


def _word_overlap_ratio(text_a: str, text_b: str) -> float:
    """Fraction of words in text_b that also appear in text_a."""
    words_a = _word_set(text_a)
    words_b = _word_set(text_b)
    if not words_b:
        return 1.0
    return len(words_a & words_b) / len(words_b)


async def cross_validate(primary_text: str, secondary_audio_bytes: bytes) -> str:
    """Compare a primary transcription against clips from a secondary recording.

    1. Split the secondary audio into 3-5 random 30-second clips (pydub).
    2. Transcribe each clip with gpt-4o-mini-transcribe ($0.003/min).
    3. Find the corresponding segment in the primary text by rough position.
    4. If word overlap < 60 %, treat it as a gap and append missing content.
    5. Return the corrected transcript (or original if no gaps found).

    On any error the original *primary_text* is returned unchanged.
    """
    try:
        from pydub import AudioSegment
    except ImportError:
        logger.warning("pydub not installed — skipping cross-validation")
        return primary_text

    try:
        # --- load secondary audio ---
        audio = AudioSegment.from_file(io.BytesIO(secondary_audio_bytes), format="m4a")
        total_ms = len(audio)
        clip_duration_ms = 30_000  # 30 seconds per clip

        if total_ms < clip_duration_ms:
            logger.info("Secondary audio too short (%.1fs) for cross-validation", total_ms / 1000)
            return primary_text

        # Decide number of clips (3-5 depending on audio length)
        num_clips = min(5, max(3, total_ms // (5 * 60 * 1000) + 3))

        # Pick random start positions (non-overlapping when possible)
        max_start = total_ms - clip_duration_ms
        starts: list[int] = sorted(random.sample(
            range(0, max_start, clip_duration_ms // 2),  # step = 15s grid
            min(num_clips, max(1, max_start // (clip_duration_ms // 2))),
        ))
        logger.info(
            "Cross-validation: %d clips from %.1fs secondary audio",
            len(starts), total_ms / 1000,
        )

        # --- split primary text into proportional segments for comparison ---
        primary_words = primary_text.split()
        total_words = len(primary_words)
        if total_words == 0:
            return primary_text

        gaps: list[tuple[int, str]] = []  # (word_position, missing_text)

        for clip_start_ms in starts:
            clip_end_ms = min(clip_start_ms + clip_duration_ms, total_ms)
            clip = audio[clip_start_ms:clip_end_ms]

            # Export clip to bytes
            buf = io.BytesIO()
            clip.export(buf, format="mp4", codec="aac")
            clip_bytes = buf.getvalue()

            # Transcribe clip with the cheaper model
            clip_file = io.BytesIO(clip_bytes)
            clip_file.name = "clip.m4a"
            try:
                clip_text_result = await _openai.client.audio.transcriptions.create(
                    model="gpt-4o-mini-transcribe",
                    file=clip_file,
                    language="pt",
                    response_format="text",
                )
                clip_text = (
                    clip_text_result.strip()
                    if isinstance(clip_text_result, str)
                    else str(clip_text_result).strip()
                )
            except Exception as e:
                logger.warning("Clip transcription failed at %dms: %s", clip_start_ms, e)
                continue

            if not clip_text or len(clip_text.split()) < 3:
                continue

            # Map clip time-position to approximate word position in primary
            ratio = clip_start_ms / total_ms
            word_pos = int(ratio * total_words)
            # Take a window of ±200 words around that position
            window_start = max(0, word_pos - 200)
            window_end = min(total_words, word_pos + 200)
            segment_text = " ".join(primary_words[window_start:window_end])

            overlap = _word_overlap_ratio(segment_text, clip_text)
            logger.info(
                "Clip @%ds: %d words, overlap=%.0f%%",
                clip_start_ms // 1000, len(clip_text.split()), overlap * 100,
            )

            if overlap < 0.60:
                gaps.append((word_pos, clip_text))
                logger.info("Gap detected at word position %d (overlap %.0f%%)", word_pos, overlap * 100)

        # Release audio memory
        del audio

        # --- patch gaps into the primary text ---
        if not gaps:
            logger.info("Cross-validation complete: no gaps found")
            return primary_text

        logger.info("Cross-validation: patching %d gap(s) into primary text", len(gaps))

        # Sort gaps by position (descending) so inserts don't shift indices
        result_words = list(primary_words)
        for word_pos, missing_text in sorted(gaps, key=lambda g: g[0], reverse=True):
            insert_idx = min(word_pos, len(result_words))
            missing_words = missing_text.split()
            result_words[insert_idx:insert_idx] = ["[...]"] + missing_words + ["[...]"]

        corrected = " ".join(result_words)
        logger.info(
            "Cross-validation done: %d → %d words (+%d)",
            total_words, len(result_words), len(result_words) - total_words,
        )
        return corrected

    except Exception as e:
        logger.error("Cross-validation failed, returning original: %s", e, exc_info=True)
        return primary_text
