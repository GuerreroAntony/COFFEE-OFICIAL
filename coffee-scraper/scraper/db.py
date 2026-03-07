from __future__ import annotations

import json
import logging
from typing import Any, Optional
from uuid import UUID

import asyncpg

from scraper.config import settings

logger = logging.getLogger(__name__)

_pool: Optional[asyncpg.Pool] = None


async def get_pool() -> asyncpg.Pool:
    global _pool
    if _pool is None:
        _pool = await asyncpg.create_pool(
            settings.DATABASE_URL,
            min_size=1,
            max_size=5,
        )
    return _pool


async def close_pool() -> None:
    global _pool
    if _pool is not None:
        await _pool.close()
        _pool = None


async def _fetch_one(query: str, *args: Any) -> Optional[asyncpg.Record]:
    pool = await get_pool()
    async with pool.acquire() as conn:
        return await conn.fetchrow(query, *args)


async def _fetch_all(query: str, *args: Any) -> list[asyncpg.Record]:
    pool = await get_pool()
    async with pool.acquire() as conn:
        return await conn.fetch(query, *args)


async def _execute(query: str, *args: Any) -> str:
    pool = await get_pool()
    async with pool.acquire() as conn:
        return await conn.execute(query, *args)


# ── Disciplina queries ───────────────────────────────────────────────────────


async def get_all_disciplinas() -> list[asyncpg.Record]:
    """All disciplinas that could be matched to Canvas courses."""
    return await _fetch_all(
        """SELECT id, nome, codigo_espm, canvas_course_id, semestre
           FROM disciplinas
           ORDER BY semestre DESC NULLS LAST"""
    )


async def get_disciplina(disciplina_id: UUID) -> Optional[asyncpg.Record]:
    return await _fetch_one(
        "SELECT id, nome, codigo_espm, canvas_course_id FROM disciplinas WHERE id = $1",
        disciplina_id,
    )


async def find_disciplina_by_canvas_course_id(
    canvas_course_id: int,
) -> Optional[asyncpg.Record]:
    return await _fetch_one(
        "SELECT id, nome FROM disciplinas WHERE canvas_course_id = $1",
        canvas_course_id,
    )


async def update_disciplina_canvas_id(
    disciplina_id: UUID, canvas_course_id: int
) -> None:
    await _execute(
        "UPDATE disciplinas SET canvas_course_id = $1 WHERE id = $2",
        canvas_course_id,
        disciplina_id,
    )


# ── Material queries ─────────────────────────────────────────────────────────


async def material_exists(canvas_file_id: int) -> bool:
    row = await _fetch_one(
        "SELECT EXISTS(SELECT 1 FROM materiais WHERE canvas_file_id = $1) AS exists",
        canvas_file_id,
    )
    return row["exists"] if row else False


async def save_material(
    *,
    disciplina_id: UUID,
    tipo: str,
    nome: str,
    url_storage: Optional[str],
    texto_extraido: Optional[str],
    canvas_file_id: int,
    hash_arquivo: Optional[str],
    ai_enabled: bool = True,
) -> UUID:
    row = await _fetch_one(
        """INSERT INTO materiais
               (disciplina_id, tipo, nome, url_storage, texto_extraido,
                fonte, canvas_file_id, hash_arquivo, ai_enabled)
           VALUES ($1, $2, $3, $4, $5, 'scraper', $6, $7, $8)
           RETURNING id""",
        disciplina_id,
        tipo,
        nome,
        url_storage,
        texto_extraido,
        canvas_file_id,
        hash_arquivo,
        ai_enabled,
    )
    return row["id"]


# ── Embedding queries ────────────────────────────────────────────────────────


async def save_embeddings_batch(
    rows: list[tuple[UUID, UUID, int, str, list[float], str]],
) -> None:
    """Bulk insert embedding rows.

    Each tuple: (disciplina_id, fonte_id, chunk_index, texto_chunk, embedding, metadata_json)
    """
    pool = await get_pool()
    async with pool.acquire() as conn:
        await conn.executemany(
            """INSERT INTO embeddings
                   (disciplina_id, fonte_tipo, fonte_id, chunk_index,
                    texto_chunk, embedding, metadata)
               VALUES ($1, 'material', $2, $3, $4, $5, $6::jsonb)""",
            rows,
        )


# ── Intelligent scraper queries ───────────────────────────────────────────────


async def get_stale_disciplinas(max_age_hours: int = 24) -> list[asyncpg.Record]:
    """Disciplinas that need scraping (never scraped or older than max_age_hours)."""
    return await _fetch_all(
        """SELECT id, nome, canvas_course_id, last_scraped_at
           FROM disciplinas
           WHERE canvas_course_id IS NOT NULL
             AND (last_scraped_at IS NULL
                  OR last_scraped_at < NOW() - INTERVAL '1 hour' * $1)
           ORDER BY last_scraped_at NULLS FIRST""",
        max_age_hours,
    )


async def get_credential_pool() -> list[asyncpg.Record]:
    """Users who have stored ESPM credentials for scraping."""
    return await _fetch_all(
        """SELECT u.id AS user_id, u.espm_login, u.encrypted_espm_password
           FROM users u
           WHERE u.espm_login IS NOT NULL
             AND u.encrypted_espm_password IS NOT NULL"""
    )


async def get_user_disciplina_ids(user_id: UUID) -> list[UUID]:
    """Disciplina IDs a user is enrolled in (only those with canvas_course_id)."""
    rows = await _fetch_all(
        """SELECT ud.disciplina_id
           FROM user_disciplinas ud
           JOIN disciplinas d ON d.id = ud.disciplina_id
           WHERE ud.user_id = $1
             AND d.canvas_course_id IS NOT NULL""",
        user_id,
    )
    return [r["disciplina_id"] for r in rows]


async def update_last_scraped(disciplina_id: UUID) -> None:
    """Mark a disciplina as freshly scraped."""
    await _execute(
        "UPDATE disciplinas SET last_scraped_at = NOW() WHERE id = $1",
        disciplina_id,
    )


# ── Notification trigger ─────────────────────────────────────────────────────


async def save_notification_trigger(disciplina_id: UUID, material_name: str) -> None:
    """Insert a notification record for users enrolled in this disciplina."""
    await _execute(
        """INSERT INTO notificacoes (user_id, tipo, titulo, corpo, data_payload)
           SELECT ud.user_id, 'novo_material',
                  'Novo material disponível',
                  $2,
                  jsonb_build_object('disciplina_id', $1::text, 'material_nome', $2)
           FROM user_disciplinas ud
           WHERE ud.disciplina_id = $1""",
        disciplina_id,
        material_name,
    )


# ── Push notification queries ────────────────────────────────────────────────


async def get_device_tokens_for_disciplina(
    disciplina_id: UUID,
) -> list[asyncpg.Record]:
    """FCM tokens for all users enrolled in a disciplina."""
    return await _fetch_all(
        """SELECT DISTINCT dt.fcm_token
           FROM device_tokens dt
           JOIN user_disciplinas ud ON ud.user_id = dt.user_id
           WHERE ud.disciplina_id = $1""",
        disciplina_id,
    )
