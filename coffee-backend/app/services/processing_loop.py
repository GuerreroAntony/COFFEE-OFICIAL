"""
Processing loop — background asyncio task that processes audio uploads.

Runs every 60 seconds. Finds recording_uploads ready for processing
(created_at + WAIT_MINUTES <= now), groups by discipline + time window,
transcribes via GPT-4o Transcribe, generates summaries/embeddings,
notifies users via push, and cleans up audio.
"""
import asyncio
import json
import logging
from datetime import datetime, timezone
from uuid import UUID

from app.config import settings
from app.database import execute_query, fetch_all, fetch_one
from app.services.embedding_service import generate_transcription_embeddings
from app.services.mindmap_service import generate_mindmap_for_gravacao
from app.services.openai_service import OpenAIService
from app.services.push_service import send_push_to_user
from app.services.transcription_service import (
    delete_from_storage,
    download_from_storage,
    transcribe_audio,
)

logger = logging.getLogger("processing_loop")
_openai = OpenAIService()

# Concurrency limit: max 2 groups processed in parallel
_PROCESSING_SEMAPHORE = asyncio.Semaphore(2)


async def start_processing_loop() -> None:
    """Entry point — called from main.py lifespan. Runs forever."""
    logger.info("Processing loop started (wait=%d min)", settings.TRANSCRIPTION_WAIT_MINUTES)
    while True:
        try:
            await _process_pending_uploads()
        except asyncio.CancelledError:
            logger.info("Processing loop cancelled")
            return
        except Exception as e:
            logger.error("Processing loop error: %s", e, exc_info=True)
        await asyncio.sleep(60)


async def _process_pending_uploads() -> None:
    """Find uploads ready for processing and process each group."""
    wait_minutes = settings.TRANSCRIPTION_WAIT_MINUTES

    # Find individual uploads that are ready (old enough + not yet processing)
    ready_uploads = await fetch_all(
        """SELECT id, disciplina_id, start_time, quality_score, duration_seconds, created_at
           FROM recording_uploads
           WHERE status = 'uploaded'
             AND created_at + make_interval(mins := $1) <= NOW()
           ORDER BY disciplina_id, start_time""",
        wait_minutes,
    )

    if not ready_uploads:
        return

    # Group by discipline + time window (±15 min on start_time)
    groups = _group_by_time_window(ready_uploads, window_minutes=15)

    # Process groups with concurrency limit
    tasks = [_process_group_with_semaphore(g) for g in groups]
    await asyncio.gather(*tasks, return_exceptions=True)


def _group_by_time_window(uploads: list[dict], window_minutes: int = 15) -> list[dict]:
    """Group uploads by discipline + time window.

    Two uploads belong to the same group if:
    - Same disciplina_id
    - start_time within ±window_minutes of each other
    """
    if not uploads:
        return []

    groups = []
    current_group = None

    for upload in uploads:
        disc_id = upload["disciplina_id"]
        start = upload["start_time"]

        if (current_group is None
            or current_group["disciplina_id"] != disc_id
            or abs((start - current_group["last_start"]).total_seconds()) > window_minutes * 60):
            # New group
            if current_group:
                groups.append(current_group)
            current_group = {
                "disciplina_id": disc_id,
                "aula_date": start.date() if hasattr(start, 'date') else start,
                "upload_ids": [upload["id"]],
                "last_start": start,
            }
        else:
            current_group["upload_ids"].append(upload["id"])
            current_group["last_start"] = start

    if current_group:
        groups.append(current_group)

    return groups


async def _process_group_with_semaphore(group: dict) -> None:
    """Process a group with concurrency limiting."""
    async with _PROCESSING_SEMAPHORE:
        try:
            await _process_group(
                disciplina_id=group["disciplina_id"],
                aula_date=group["aula_date"],
                upload_ids=group["upload_ids"],
            )
        except Exception as e:
            logger.error(
                "Failed to process group disc=%s date=%s: %s",
                group["disciplina_id"], group["aula_date"], e, exc_info=True,
            )


async def _process_group(
    disciplina_id: UUID,
    aula_date,
    upload_ids: list[UUID],
) -> None:
    """Process a group of uploads for the same discipline+time window.

    Steps:
    1. Acquire lock (mark uploads as 'selected' to prevent double processing)
    2. Select best upload by quality_score > duration > created_at
    3. Transcribe the best audio via GPT-4o Transcribe
    4. Generate summary + mind map + embeddings
    5. Copy output to ALL students' gravacoes in this group
    6. Push notification to each student
    7. Delete all audio files
    """
    # === LOCK: Atomically mark uploads to prevent double processing ===
    lock_result = await execute_query(
        """UPDATE recording_uploads SET status = 'selected'
           WHERE id = ANY($1) AND status = 'uploaded'""",
        upload_ids,
    )
    # If no rows were updated, another loop iteration already grabbed them
    if lock_result and "UPDATE 0" in str(lock_result):
        logger.info("Group disc=%s date=%s already being processed, skipping", disciplina_id, aula_date)
        return

    # Select the best upload (by quality, then duration, then earliest)
    best_upload = await fetch_one(
        """SELECT id, storage_path, user_id, gravacao_id, duration_seconds
           FROM recording_uploads
           WHERE id = ANY($1)
           ORDER BY quality_score DESC, duration_seconds DESC, created_at ASC
           LIMIT 1""",
        upload_ids,
    )
    if not best_upload:
        logger.error("No uploads found for group disc=%s", disciplina_id)
        return

    primary_id = best_upload["id"]
    logger.info(
        "Processing group: disc=%s date=%s uploads=%d primary=%s",
        disciplina_id, aula_date, len(upload_ids), primary_id,
    )

    # Create aula_transcripts entry
    transcript_row = await fetch_one(
        """INSERT INTO aula_transcripts (disciplina_id, selected_upload_id, date, status)
           VALUES ($1, $2, $3, 'transcribing')
           RETURNING id""",
        disciplina_id, primary_id, aula_date,
    )
    transcript_id = transcript_row["id"]

    try:
        # === PHASE 1: Download + Transcribe ===
        logger.info("Downloading audio from storage: %s", best_upload["storage_path"])
        audio_bytes = await download_from_storage(
            settings.SUPABASE_RECORDINGS_BUCKET,
            best_upload["storage_path"],
        )

        audio_size_mb = len(audio_bytes) / (1024 * 1024)
        logger.info("Transcribing %.1f MB with GPT-4o Transcribe...", audio_size_mb)

        # Handle files > 25MB by splitting
        if len(audio_bytes) > 25 * 1024 * 1024:
            transcription = await _transcribe_large_audio(audio_bytes)
        else:
            transcription = await transcribe_audio(audio_bytes)

        # Release audio_bytes from memory immediately
        del audio_bytes

        # Calculate cost: duration_seconds / 60 * $0.006
        duration_min = (best_upload["duration_seconds"] or 60) / 60.0
        cost_usd = round(duration_min * 0.006, 4)

        # Save transcription
        await execute_query(
            """UPDATE aula_transcripts
               SET transcription = $1, status = 'processing', cost_usd = $2
               WHERE id = $3""",
            transcription, cost_usd, transcript_id,
        )

        # === PHASE 2: Generate AI outputs ===
        disc_row = await fetch_one(
            "SELECT nome FROM disciplinas WHERE id = $1", disciplina_id,
        )
        source_name = disc_row["nome"] if disc_row else "Aula"

        word_count = len(transcription.split())
        logger.info("Transcription: %d words. Generating summary for '%s'...", word_count, source_name)

        short_summary = None
        full_summary_json = None

        if word_count >= 10:
            summary = await _openai.generate_summary(transcription, source_name)
            short_summary = (
                summary.get("titulo_curto", "")
                or summary.get("titulo", "")
                or summary.get("resumo_geral", "")[:60]
            )
            full_summary_json = json.dumps(summary.get("topicos", []), ensure_ascii=False)
        else:
            short_summary = "Transcrição muito curta para gerar resumo" if word_count > 0 else None

        # Save summary to aula_transcripts
        await execute_query(
            """UPDATE aula_transcripts
               SET short_summary = $1, full_summary = $2::jsonb
               WHERE id = $3""",
            short_summary, full_summary_json, transcript_id,
        )

        # Generate embeddings
        await generate_transcription_embeddings(transcription, transcript_id, disciplina_id)

        # === PHASE 3: Copy output to ALL students' gravacoes ===
        all_uploads = await fetch_all(
            "SELECT id, user_id, gravacao_id FROM recording_uploads WHERE id = ANY($1)",
            upload_ids,
        )

        for upload in all_uploads:
            if not upload["gravacao_id"]:
                continue
            await execute_query(
                """UPDATE gravacoes
                   SET aula_transcript_id = $1,
                       short_summary = $2,
                       full_summary = $3::jsonb,
                       transcription = $4,
                       status = 'ready'
                   WHERE id = $5""",
                transcript_id, short_summary, full_summary_json,
                transcription, upload["gravacao_id"],
            )
            await execute_query(
                "UPDATE recording_uploads SET aula_transcript_id = $1, status = 'processed' WHERE id = $2",
                transcript_id, upload["id"],
            )

        # === Mark as READY first — everything critical is done ===
        await execute_query(
            "UPDATE aula_transcripts SET status = 'ready' WHERE id = $1",
            transcript_id,
        )
        logger.info(
            "Group processed successfully: disc=%s date=%s uploads=%d cost=$%.4f",
            disciplina_id, aula_date, len(upload_ids), cost_usd,
        )

        # === Non-critical: mind map, push, cleanup (failures don't change status) ===

        # Mind map
        if best_upload["gravacao_id"] and word_count >= 10:
            try:
                await generate_mindmap_for_gravacao(best_upload["gravacao_id"])
                mm_row = await fetch_one(
                    "SELECT mind_map FROM gravacoes WHERE id = $1", best_upload["gravacao_id"],
                )
                if mm_row and mm_row["mind_map"]:
                    mind_map_val = mm_row["mind_map"] if isinstance(mm_row["mind_map"], str) else json.dumps(mm_row["mind_map"], ensure_ascii=False)
                    await execute_query(
                        "UPDATE aula_transcripts SET mind_map = $1::jsonb WHERE id = $2",
                        mind_map_val, transcript_id,
                    )
                    for upload in all_uploads:
                        if upload["gravacao_id"] and upload["gravacao_id"] != best_upload["gravacao_id"]:
                            await execute_query(
                                "UPDATE gravacoes SET mind_map = $1::jsonb WHERE id = $2",
                                mind_map_val, upload["gravacao_id"],
                            )
            except Exception as e:
                logger.warning("Mind map failed (non-critical): %s", e)

        # Push notifications
        for upload in all_uploads:
            try:
                body = f'"{short_summary}" está pronta' if short_summary else "Sua gravação foi processada"
                await send_push_to_user(
                    upload["user_id"],
                    "Aula processada!",
                    body,
                    {"type": "recording_ready", "gravacao_id": str(upload["gravacao_id"] or "")},
                )
            except Exception as e:
                logger.warning("Push failed (non-critical) for user %s: %s", upload["user_id"], e)

        # Cleanup audio files
        for upload in all_uploads:
            try:
                up_row = await fetch_one(
                    "SELECT storage_path FROM recording_uploads WHERE id = $1", upload["id"],
                )
                if up_row and up_row["storage_path"]:
                    await delete_from_storage(
                        settings.SUPABASE_RECORDINGS_BUCKET,
                        up_row["storage_path"],
                    )
                    await execute_query(
                        "UPDATE recording_uploads SET storage_path = NULL WHERE id = $1",
                        upload["id"],
                    )
            except Exception as e:
                logger.warning("Cleanup failed (non-critical): %s", e)

    except Exception as e:
        logger.error("Processing failed for transcript %s: %s", transcript_id, e, exc_info=True)
        await execute_query(
            "UPDATE aula_transcripts SET status = 'error' WHERE id = $1",
            transcript_id,
        )
        # Mark all gravacoes as error so users see it failed
        for uid in upload_ids:
            up = await fetch_one("SELECT gravacao_id FROM recording_uploads WHERE id = $1", uid)
            if up and up["gravacao_id"]:
                await execute_query(
                    "UPDATE gravacoes SET status = 'error' WHERE id = $1",
                    up["gravacao_id"],
                )


async def _transcribe_large_audio(audio_bytes: bytes) -> str:
    """Split audio > 25MB into chunks and transcribe each, then merge.

    Uses pydub + ffmpeg to split at 20-minute intervals with 30s overlap.
    """
    import io
    import tempfile

    try:
        from pydub import AudioSegment
    except ImportError:
        logger.error("pydub not installed, cannot split large audio")
        # Fallback: try sending as-is (may fail at OpenAI)
        return await transcribe_audio(audio_bytes)

    # Load audio
    audio = AudioSegment.from_file(io.BytesIO(audio_bytes), format="m4a")
    total_ms = len(audio)
    chunk_ms = 20 * 60 * 1000   # 20 minutes per chunk
    overlap_ms = 30 * 1000       # 30 seconds overlap

    chunks_text = []
    pos = 0
    chunk_num = 0

    while pos < total_ms:
        end = min(pos + chunk_ms, total_ms)
        chunk = audio[pos:end]
        chunk_num += 1

        # Export chunk to bytes
        buf = io.BytesIO()
        chunk.export(buf, format="mp4", codec="aac")
        chunk_bytes = buf.getvalue()

        logger.info("Transcribing chunk %d (%.1f MB, %d-%d ms)", chunk_num, len(chunk_bytes) / 1e6, pos, end)
        text = await transcribe_audio(chunk_bytes)
        chunks_text.append(text)

        # Move forward by chunk_ms - overlap_ms (so there's overlap for continuity)
        pos += chunk_ms - overlap_ms

    # Release audio from memory
    del audio

    # Simple merge: join all chunks. Overlap creates duplicate text at boundaries,
    # but this is acceptable — GPT-4o-mini summary will clean it up.
    merged = " ".join(chunks_text)
    logger.info("Merged %d chunks into %d chars", len(chunks_text), len(merged))
    return merged
