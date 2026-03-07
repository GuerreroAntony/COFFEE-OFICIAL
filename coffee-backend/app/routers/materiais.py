from __future__ import annotations

import asyncio
import sys
from datetime import datetime, timedelta, timezone
from uuid import UUID

from fastapi import APIRouter, BackgroundTasks, Depends, HTTPException, status

from app.database import execute_query, fetch_all, fetch_one
from app.dependencies import get_current_user
from app.schemas.materiais import (
    MaterialListResponse,
    MaterialResponse,
    SyncStatusResponse,
    ToggleAIResponse,
)

router = APIRouter(prefix="/api/v1/materiais", tags=["materiais"])


# ── GET /disciplina/{id} ─────────────────────────────────────────────────────

@router.get("/disciplina/{disciplina_id}", response_model=MaterialListResponse)
async def listar_materiais(
    disciplina_id: UUID,
    user_id: UUID = Depends(get_current_user),
):
    """Lista materiais de uma disciplina em que o aluno está matriculado."""
    enrolled = await fetch_one(
        "SELECT 1 FROM user_disciplinas WHERE user_id = $1 AND disciplina_id = $2",
        user_id, disciplina_id,
    )
    if not enrolled:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Acesso negado")

    rows = await fetch_all(
        """
        SELECT id, disciplina_id, tipo, nome, url_storage, fonte, ai_enabled, created_at
        FROM materiais
        WHERE disciplina_id = $1
        ORDER BY created_at DESC
        """,
        disciplina_id,
    )
    return MaterialListResponse(
        materiais=[MaterialResponse(**dict(r)) for r in rows]
    )


# ── GET /{id} ─────────────────────────────────────────────────────────────────

@router.get("/{material_id}", response_model=MaterialResponse)
async def get_material(
    material_id: UUID,
    user_id: UUID = Depends(get_current_user),
):
    """Retorna detalhe de um material (com verificação de matrícula)."""
    row = await fetch_one(
        """
        SELECT m.id, m.disciplina_id, m.tipo, m.nome, m.url_storage,
               m.fonte, m.ai_enabled, m.created_at
        FROM materiais m
        JOIN user_disciplinas ud ON ud.disciplina_id = m.disciplina_id AND ud.user_id = $2
        WHERE m.id = $1
        """,
        material_id, user_id,
    )
    if not row:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Material não encontrado")
    return MaterialResponse(**dict(row))


# ── PATCH /{id}/toggle-ai ────────────────────────────────────────────────────

@router.patch("/{material_id}/toggle-ai", response_model=ToggleAIResponse)
async def toggle_ai(
    material_id: UUID,
    user_id: UUID = Depends(get_current_user),
):
    """Inverte o flag ai_enabled de um material."""
    row = await fetch_one(
        """
        UPDATE materiais m
        SET ai_enabled = NOT m.ai_enabled
        FROM user_disciplinas ud
        WHERE m.id = $1
          AND ud.disciplina_id = m.disciplina_id
          AND ud.user_id = $2
        RETURNING m.id, m.ai_enabled
        """,
        material_id, user_id,
    )
    if not row:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Material não encontrado")
    return ToggleAIResponse(id=row["id"], ai_enabled=row["ai_enabled"])


# ── POST /disciplina/{id}/sync ────────────────────────────────────────────────

@router.post("/disciplina/{disciplina_id}/sync", response_model=SyncStatusResponse)
async def trigger_sync(
    disciplina_id: UUID,
    background_tasks: BackgroundTasks,
    user_id: UUID = Depends(get_current_user),
):
    """Dispara scraping em background para uma disciplina."""
    enrolled = await fetch_one(
        "SELECT 1 FROM user_disciplinas WHERE user_id = $1 AND disciplina_id = $2",
        user_id, disciplina_id,
    )
    if not enrolled:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Acesso negado")

    disc = await fetch_one(
        "SELECT last_scraped_at FROM disciplinas WHERE id = $1",
        disciplina_id,
    )
    last_scraped = disc["last_scraped_at"] if disc else None

    if last_scraped and (datetime.now(timezone.utc) - last_scraped) < timedelta(hours=1):
        return SyncStatusResponse(status="fresh", last_scraped_at=last_scraped)

    background_tasks.add_task(_run_scraper_subprocess, str(disciplina_id))
    return SyncStatusResponse(status="triggered", last_scraped_at=last_scraped)


async def _run_scraper_subprocess(disciplina_id: str) -> None:
    """Executa o scraper como subprocesso. Não bloqueia a API."""
    import logging
    logger = logging.getLogger("materiais.sync")

    proc = await asyncio.create_subprocess_exec(
        sys.executable, "-m", "scraper.main", "--disciplina", disciplina_id,
        stdout=asyncio.subprocess.PIPE,
        stderr=asyncio.subprocess.PIPE,
    )
    stdout, stderr = await proc.communicate()

    if proc.returncode == 0:
        logger.info("Scraper OK for %s: %s", disciplina_id, stdout.decode()[-200:])
    else:
        logger.error("Scraper FAIL for %s: %s", disciplina_id, stderr.decode()[-500:])
