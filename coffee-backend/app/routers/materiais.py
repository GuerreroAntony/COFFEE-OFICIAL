from __future__ import annotations

import asyncio
import io
import sys
from datetime import datetime, timedelta, timezone
from typing import Optional
from uuid import UUID

import httpx
from fastapi import APIRouter, BackgroundTasks, Depends, File, Form, HTTPException, UploadFile, status

from app.config import settings
from app.database import execute_query, fetch_all, fetch_one
from app.dependencies import get_current_user
from app.schemas.materiais import (
    MaterialResponse,
    SyncStatusResponse,
    ToggleAIResponse,
)
from app.schemas.base import error_response, success_response
from app.services.embedding_service import generate_material_embeddings, remove_embeddings

router = APIRouter(prefix="/api/v1/materiais", tags=["materiais"])
disc_router = APIRouter(prefix="/api/v1/disciplinas", tags=["materiais"])


# ── Helpers ──────────────────────────────────────────────────

def _format_size(size_bytes: Optional[int]) -> Optional[str]:
    if not size_bytes:
        return None
    if size_bytes >= 1_000_000:
        return f"{size_bytes / 1_000_000:.1f} MB"
    return f"{size_bytes / 1_000:.0f} KB"


def _material_response(r) -> dict:
    return MaterialResponse(
        id=r["id"],
        disciplina_id=r["disciplina_id"],
        tipo=r["tipo"],
        nome=r["nome"],
        url_storage=r.get("url_storage"),
        fonte=r["fonte"],
        ai_enabled=r["ai_enabled"],
        size_bytes=r.get("size_bytes"),
        size_label=_format_size(r.get("size_bytes")),
        created_at=r["created_at"],
    ).model_dump(mode="json")


def _detect_tipo(filename: str) -> str:
    ext = filename.rsplit(".", 1)[-1].lower() if "." in filename else ""
    mapping = {"pdf": "pdf", "pptx": "slide", "ppt": "slide", "jpg": "foto", "jpeg": "foto", "png": "foto"}
    return mapping.get(ext, "outro")


def _extract_content_type(filename: str) -> str:
    ext = filename.rsplit(".", 1)[-1].lower() if "." in filename else ""
    mapping = {
        "pdf": "application/pdf",
        "pptx": "application/vnd.openxmlformats-officedocument.presentationml.presentation",
        "ppt": "application/vnd.ms-powerpoint",
        "jpg": "image/jpeg",
        "jpeg": "image/jpeg",
        "png": "image/png",
    }
    return mapping.get(ext, "application/octet-stream")


async def _extract_text(content: bytes, filename: str) -> str:
    """Extract text from PDF or PPTX files."""
    ext = filename.rsplit(".", 1)[-1].lower() if "." in filename else ""
    text = ""

    if ext == "pdf":
        try:
            from PyPDF2 import PdfReader
            reader = PdfReader(io.BytesIO(content))
            text = "\n".join(page.extract_text() or "" for page in reader.pages)
        except Exception:
            text = ""
    elif ext in ("pptx",):
        try:
            from pptx import Presentation
            prs = Presentation(io.BytesIO(content))
            parts = []
            for slide in prs.slides:
                for shape in slide.shapes:
                    if hasattr(shape, "text"):
                        parts.append(shape.text)
            text = "\n".join(parts)
        except Exception:
            text = ""

    return text.strip()


# ── GET /disciplina/{id} ─────────────────────────────────────

@disc_router.get("/{disciplina_id}/materiais")
async def listar_materiais(
    disciplina_id: UUID,
    user_id: UUID = Depends(get_current_user),
):
    """Lista materiais de uma disciplina."""
    enrolled = await fetch_one(
        "SELECT 1 FROM user_disciplinas WHERE user_id = $1 AND disciplina_id = $2",
        user_id, disciplina_id,
    )
    if not enrolled:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail=error_response("ACCESS_DENIED", "Acesso negado"))

    rows = await fetch_all(
        """SELECT id, disciplina_id, tipo, nome, url_storage, fonte, ai_enabled, size_bytes, created_at
           FROM materiais WHERE disciplina_id = $1
           ORDER BY created_at DESC""",
        disciplina_id,
    )
    items = [_material_response(r) for r in rows]
    return success_response(items)


# ── GET /{id} ────────────────────────────────────────────────

@router.get("/{material_id}")
async def get_material(
    material_id: UUID,
    user_id: UUID = Depends(get_current_user),
):
    """Detalhe de um material."""
    row = await fetch_one(
        """SELECT m.id, m.disciplina_id, m.tipo, m.nome, m.url_storage,
                  m.fonte, m.ai_enabled, m.size_bytes, m.created_at
           FROM materiais m
           JOIN user_disciplinas ud ON ud.disciplina_id = m.disciplina_id AND ud.user_id = $2
           WHERE m.id = $1""",
        material_id, user_id,
    )
    if not row:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail=error_response("NOT_FOUND", "Material não encontrado"))
    return success_response(_material_response(row))


# ── PATCH /{id}/toggle-ai ───────────────────────────────────

@router.patch("/{material_id}/toggle-ai")
async def toggle_ai(
    material_id: UUID,
    background_tasks: BackgroundTasks,
    user_id: UUID = Depends(get_current_user),
):
    """Inverte ai_enabled e gera/remove embeddings."""
    row = await fetch_one(
        """UPDATE materiais m
           SET ai_enabled = NOT m.ai_enabled
           FROM user_disciplinas ud
           WHERE m.id = $1
             AND ud.disciplina_id = m.disciplina_id
             AND ud.user_id = $2
           RETURNING m.id, m.ai_enabled, m.texto_extraido, m.disciplina_id""",
        material_id, user_id,
    )
    if not row:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail=error_response("NOT_FOUND", "Material não encontrado"))

    # Generate or remove embeddings based on new state
    if row["ai_enabled"]:
        # ai_enabled became True → generate embeddings
        if row["texto_extraido"]:
            background_tasks.add_task(
                generate_material_embeddings,
                row["texto_extraido"], row["id"], row["disciplina_id"],
            )
    else:
        # ai_enabled became False → remove embeddings
        background_tasks.add_task(remove_embeddings, row["id"])

    resp = ToggleAIResponse(id=row["id"], ai_enabled=row["ai_enabled"])
    return success_response(resp.model_dump(mode="json"))


# ── POST /disciplina/{id}/materiais (manual upload) ──────────

@disc_router.post("/{disciplina_id}/materiais", status_code=status.HTTP_201_CREATED)
async def upload_material(
    disciplina_id: UUID,
    background_tasks: BackgroundTasks,
    file: UploadFile = File(...),
    ai_enabled: bool = Form(True),
    user_id: UUID = Depends(get_current_user),
):
    """Upload manual de material."""
    enrolled = await fetch_one(
        "SELECT 1 FROM user_disciplinas WHERE user_id = $1 AND disciplina_id = $2",
        user_id, disciplina_id,
    )
    if not enrolled:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail=error_response("ACCESS_DENIED", "Acesso negado"))

    content = await file.read()
    filename = file.filename or "arquivo"
    size_bytes = len(content)
    tipo = _detect_tipo(filename)
    content_type = _extract_content_type(filename)

    # Extract text
    texto_extraido = await _extract_text(content, filename)

    # Upload to Supabase Storage
    storage_path = f"{disciplina_id}/{filename}"
    upload_url = f"{settings.SUPABASE_URL}/storage/v1/object/materiais/{storage_path}"

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
        raise HTTPException(
            status_code=status.HTTP_502_BAD_GATEWAY,
            detail=error_response("AI_ERROR", "Erro no upload do arquivo"),
        )

    public_url = f"{settings.SUPABASE_URL}/storage/v1/object/public/materiais/{storage_path}"

    # Save to DB
    row = await fetch_one(
        """INSERT INTO materiais (disciplina_id, tipo, nome, url_storage, texto_extraido, fonte, ai_enabled, size_bytes)
           VALUES ($1, $2, $3, $4, $5, 'manual', $6, $7)
           RETURNING id, disciplina_id, tipo, nome, url_storage, fonte, ai_enabled, size_bytes, created_at""",
        disciplina_id, tipo, filename, public_url, texto_extraido, ai_enabled, size_bytes,
    )

    # Generate embeddings if ai_enabled and text extracted
    if ai_enabled and texto_extraido:
        background_tasks.add_task(
            generate_material_embeddings,
            texto_extraido, row["id"], disciplina_id,
        )

    return success_response(_material_response(row))


# ── POST /disciplina/{id}/sync ───────────────────────────────

@disc_router.post("/{disciplina_id}/sync")
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
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail=error_response("ACCESS_DENIED", "Acesso negado"))

    disc = await fetch_one(
        "SELECT last_scraped_at FROM disciplinas WHERE id = $1",
        disciplina_id,
    )
    last_scraped = disc["last_scraped_at"] if disc else None

    if last_scraped and (datetime.now(timezone.utc) - last_scraped) < timedelta(hours=settings.SYNC_COOLDOWN_HOURS):
        next_sync = last_scraped + timedelta(hours=settings.SYNC_COOLDOWN_HOURS)
        raise HTTPException(
            status_code=429,
            detail=error_response(
                "SYNC_COOLDOWN",
                "Sincronização em cooldown",
                extra={"next_sync_available_at": next_sync.isoformat()},
            ),
        )

    background_tasks.add_task(_run_scraper_subprocess, str(disciplina_id))
    resp = SyncStatusResponse(status="triggered", last_scraped_at=last_scraped)
    return success_response(resp.model_dump(mode="json"))


async def _run_scraper_subprocess(disciplina_id: str) -> None:
    """Executa o scraper como subprocesso."""
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
