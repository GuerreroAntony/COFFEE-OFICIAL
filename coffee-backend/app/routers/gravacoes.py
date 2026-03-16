from datetime import date, datetime, timedelta, timezone
from typing import Optional
from uuid import UUID

import httpx
from fastapi import APIRouter, BackgroundTasks, Depends, File, Form, HTTPException, UploadFile, status
from fastapi.responses import StreamingResponse as PDFStreamingResponse

from app.config import settings
from app.database import execute_query, fetch_all, fetch_one
from app.dependencies import get_current_user, get_current_user_with_plan
from app.schemas.gravacoes import (
    CriarGravacaoRequest,
    GravacaoCreatedResponse,
    GravacaoDetail,
    GravacaoListItem,
    GravacaoMediaItem,
    GravacaoMaterialItem,
    GravacaoSummarySection,
    MediaUploadResponse,
    MoverGravacaoRequest,
)
from app.schemas.base import error_response, success_response
from app.services.embedding_service import generate_transcription_embeddings, remove_embeddings
from app.services.summary_service import generate_summary_for_gravacao

router = APIRouter(prefix="/api/v1/gravacoes", tags=["gravacoes"])


# ── Helpers ──────────────────────────────────────────────────

_DAYS = {"Monday": "Segunda", "Tuesday": "Terça", "Wednesday": "Quarta", "Thursday": "Quinta", "Friday": "Sexta", "Saturday": "Sábado", "Sunday": "Domingo"}
_MONTHS = {"January": "janeiro", "February": "fevereiro", "March": "março", "April": "abril", "May": "maio", "June": "junho", "July": "julho", "August": "agosto", "September": "setembro", "October": "outubro", "November": "novembro", "December": "dezembro"}


def _format_date_label(d: date) -> str:
    """'2026-02-25' → 'Terça, 25 de fevereiro'"""
    day_name = _DAYS.get(d.strftime("%A"), d.strftime("%A"))
    month_name = _MONTHS.get(d.strftime("%B"), d.strftime("%B"))
    return f"{day_name}, {d.day} de {month_name}"


def _format_duration(seconds: int) -> str:
    """4800 → '1h 20min'"""
    h = seconds // 3600
    m = (seconds % 3600) // 60
    if h > 0:
        return f"{h}h {m}min" if m > 0 else f"{h}h"
    return f"{m}min"


def _format_timestamp(seconds: int) -> str:
    """872 → '14:32'"""
    m = seconds // 60
    s = seconds % 60
    return f"{m}:{s:02d}"


def _format_size(size_bytes: Optional[int]) -> str:
    """2516582 → '2.4 MB'"""
    if not size_bytes:
        return "0 KB"
    if size_bytes >= 1_000_000:
        return f"{size_bytes / 1_000_000:.1f} MB"
    return f"{size_bytes / 1_000:.0f} KB"


# ── Ownership validation ─────────────────────────────────────

async def _validate_source_ownership(user_id: UUID, source_type: str, source_id: UUID):
    """Validate that the user owns the source (disciplina or repositorio)."""
    if source_type == "disciplina":
        row = await fetch_one(
            "SELECT 1 FROM user_disciplinas WHERE user_id = $1 AND disciplina_id = $2",
            user_id, source_id,
        )
    else:
        row = await fetch_one(
            "SELECT 1 FROM repositorios WHERE id = $1 AND user_id = $2",
            source_id, user_id,
        )
    if not row:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail=error_response("ACCESS_DENIED", "Acesso negado à fonte"))


# ── POST /gravacoes ──────────────────────────────────────────

@router.post("")
async def criar_gravacao(
    body: CriarGravacaoRequest,
    background_tasks: BackgroundTasks,
    user_plan: tuple = Depends(get_current_user_with_plan),
):
    """Salvar nova gravação com transcrição (texto)."""
    user_id, plano = user_plan

    if plano == "expired":
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail=error_response("SUBSCRIPTION_REQUIRED", "Assinatura necessária para gravar aulas"),
        )

    await _validate_source_ownership(user_id, body.source_type, body.source_id)

    # Parse date: accepts "YYYY-MM-DD" or full ISO8601 datetime string
    gravacao_date = date.today()
    if body.date:
        try:
            # Try "YYYY-MM-DD" first
            gravacao_date = date.fromisoformat(body.date[:10])
        except (ValueError, TypeError):
            gravacao_date = date.today()

    row = await fetch_one(
        """INSERT INTO gravacoes (user_id, source_type, source_id, date, duration_seconds, status, transcription)
           VALUES ($1, $2, $3, $4, $5, 'processing', $6)
           RETURNING id, source_type, source_id, date, duration_seconds, status, created_at""",
        user_id, body.source_type, body.source_id, gravacao_date,
        body.duration_seconds, body.transcription,
    )

    gravacao_id = row["id"]

    # disciplina_id para embeddings: disciplina → source_id, repositório → None
    disciplina_id = body.source_id if body.source_type == "disciplina" else None

    # Background tasks: embeddings + summary
    background_tasks.add_task(
        generate_transcription_embeddings,
        body.transcription, gravacao_id, disciplina_id,
    )
    background_tasks.add_task(generate_summary_for_gravacao, gravacao_id)

    resp = GravacaoCreatedResponse(
        id=row["id"],
        source_type=row["source_type"],
        source_id=row["source_id"],
        date=row["date"],
        date_label=_format_date_label(row["date"]),
        duration_seconds=row["duration_seconds"],
        duration_label=_format_duration(row["duration_seconds"]),
        status=row["status"],
        created_at=row["created_at"],
    )
    return success_response(resp.model_dump(mode="json"))


# ── GET /gravacoes ───────────────────────────────────────────

@router.get("")
async def listar_gravacoes(
    source_type: str,
    source_id: UUID,
    page: int = 1,
    per_page: int = 20,
    user_id: UUID = Depends(get_current_user),
):
    """Listar gravações por fonte."""
    await _validate_source_ownership(user_id, source_type, source_id)

    offset = (page - 1) * per_page

    rows = await fetch_all(
        """SELECT g.id, g.source_type, g.source_id, g.date, g.duration_seconds,
                  g.status, g.short_summary, g.received_from,
                  (g.mind_map IS NOT NULL) AS has_mind_map,
                  (SELECT COUNT(*) FROM gravacao_media gm WHERE gm.gravacao_id = g.id) AS media_count,
                  CASE WHEN g.source_type = 'disciplina'
                       THEN (SELECT COUNT(*) FROM materiais m WHERE m.disciplina_id = g.source_id)
                       ELSE 0
                  END AS materials_count
           FROM gravacoes g
           WHERE g.user_id = $1 AND g.source_type = $2 AND g.source_id = $3
           ORDER BY g.date DESC, g.created_at DESC
           LIMIT $4 OFFSET $5""",
        user_id, source_type, source_id, per_page, offset,
    )

    count_row = await fetch_one(
        "SELECT COUNT(*) AS cnt FROM gravacoes WHERE user_id = $1 AND source_type = $2 AND source_id = $3",
        user_id, source_type, source_id,
    )
    total = count_row["cnt"] if count_row else 0

    items = [
        GravacaoListItem(
            id=r["id"],
            source_type=r["source_type"],
            source_id=r["source_id"],
            date=r["date"],
            date_label=_format_date_label(r["date"]),
            duration_seconds=r["duration_seconds"],
            duration_label=_format_duration(r["duration_seconds"]),
            status=r["status"],
            short_summary=r["short_summary"],
            has_mind_map=r["has_mind_map"],
            received_from=r["received_from"],
            media_count=r["media_count"],
            materials_count=r["materials_count"],
        ).model_dump(mode="json")
        for r in rows
    ]
    from app.schemas.base import paginated_response
    return paginated_response(items, total, page, per_page)


# ── GET /gravacoes/{id} ──────────────────────────────────────

@router.get("/{gravacao_id}")
async def get_gravacao(
    gravacao_id: UUID,
    background_tasks: BackgroundTasks,
    user_id: UUID = Depends(get_current_user),
):
    """Detalhe completo de uma gravação."""
    row = await fetch_one(
        """SELECT id, source_type, source_id, date, duration_seconds, status,
                  short_summary, full_summary, mind_map, received_from,
                  transcription, created_at
           FROM gravacoes
           WHERE id = $1 AND user_id = $2""",
        gravacao_id, user_id,
    )
    if not row:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail=error_response("NOT_FOUND", "Gravação não encontrada"))

    # Reprocess stuck gravações (processing > 5 min)
    if row["status"] == "processing" and row["created_at"]:
        age = datetime.now(timezone.utc) - row["created_at"]
        if age > timedelta(minutes=5):
            background_tasks.add_task(generate_summary_for_gravacao, row["id"])

    # Parse full_summary JSONB → list[GravacaoSummarySection]
    full_summary = None
    if row["full_summary"]:
        import json
        raw = row["full_summary"]
        if isinstance(raw, str):
            raw = json.loads(raw)
        if isinstance(raw, list):
            full_summary = [
                GravacaoSummarySection(
                    title=item.get("titulo", item.get("title", "")),
                    bullets=[item.get("conteudo", "")] if isinstance(item.get("conteudo"), str)
                            else item.get("bullets", []),
                )
                for item in raw
            ]

    # Fetch media
    media_rows = await fetch_all(
        """SELECT id, type, label, timestamp_seconds, url_storage
           FROM gravacao_media WHERE gravacao_id = $1
           ORDER BY timestamp_seconds""",
        gravacao_id,
    )
    media = [
        GravacaoMediaItem(
            id=m["id"],
            type=m["type"],
            label=m["label"],
            timestamp_seconds=m["timestamp_seconds"],
            timestamp_label=_format_timestamp(m["timestamp_seconds"]),
            url=m["url_storage"],
        )
        for m in media_rows
    ]

    # Fetch materials (only if source_type='disciplina')
    materials = []
    if row["source_type"] == "disciplina":
        mat_rows = await fetch_all(
            """SELECT id, nome, tipo, size_bytes, url_storage
               FROM materiais WHERE disciplina_id = $1
               ORDER BY created_at DESC""",
            row["source_id"],
        )
        materials = [
            GravacaoMaterialItem(
                id=m["id"],
                nome=m["nome"],
                tipo=m["tipo"] or "outro",
                size_label=_format_size(m["size_bytes"]),
                url=m["url_storage"],
            )
            for m in mat_rows
        ]

    # Parse mind_map JSONB
    mind_map = None
    if row["mind_map"]:
        import json as json_mod
        raw_mm = row["mind_map"]
        if isinstance(raw_mm, str):
            mind_map = json_mod.loads(raw_mm)
        else:
            mind_map = raw_mm

    detail = GravacaoDetail(
        id=row["id"],
        source_type=row["source_type"],
        source_id=row["source_id"],
        date=row["date"],
        date_label=_format_date_label(row["date"]),
        duration_seconds=row["duration_seconds"],
        duration_label=_format_duration(row["duration_seconds"]),
        status=row["status"],
        short_summary=row["short_summary"],
        full_summary=full_summary,
        mind_map=mind_map,
        received_from=row["received_from"],
        transcription=row["transcription"],
        media=media,
        materials=materials,
        created_at=row["created_at"],
    )
    return success_response(detail.model_dump(mode="json"))


# ── POST /gravacoes/{id}/media ───────────────────────────────

@router.post("/{gravacao_id}/media")
async def upload_media(
    gravacao_id: UUID,
    file: UploadFile = File(...),
    timestamp_seconds: int = Form(...),
    label: Optional[str] = Form(None),
    user_id: UUID = Depends(get_current_user),
):
    """Upload foto para uma gravação."""
    # Validate ownership
    grav = await fetch_one(
        "SELECT id FROM gravacoes WHERE id = $1 AND user_id = $2",
        gravacao_id, user_id,
    )
    if not grav:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail=error_response("NOT_FOUND", "Gravação não encontrada"))

    # Read file
    content = await file.read()
    filename = file.filename or "photo.jpg"
    content_type = file.content_type or "image/jpeg"

    # Upload to Supabase Storage
    storage_path = f"{gravacao_id}/{filename}"
    upload_url = (
        f"{settings.SUPABASE_URL}/storage/v1/object/"
        f"{settings.SUPABASE_MEDIA_BUCKET}/{storage_path}"
    )

    async with httpx.AsyncClient(timeout=30.0) as client:
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

    public_url = (
        f"{settings.SUPABASE_URL}/storage/v1/object/public/"
        f"{settings.SUPABASE_MEDIA_BUCKET}/{storage_path}"
    )

    # Save to DB
    row = await fetch_one(
        """INSERT INTO gravacao_media (gravacao_id, type, label, timestamp_seconds, url_storage)
           VALUES ($1, 'photo', $2, $3, $4)
           RETURNING id, type, label, timestamp_seconds, url_storage, created_at""",
        gravacao_id, label, timestamp_seconds, public_url,
    )

    media_resp = MediaUploadResponse(
        id=row["id"],
        type=row["type"],
        label=row["label"],
        timestamp_seconds=row["timestamp_seconds"],
        timestamp_label=_format_timestamp(row["timestamp_seconds"]),
        url=row["url_storage"],
        created_at=row["created_at"],
    )
    return success_response(media_resp.model_dump(mode="json"))


# ── PATCH /gravacoes/{id} ────────────────────────────────────

@router.patch("/{gravacao_id}")
async def mover_gravacao(
    gravacao_id: UUID,
    body: MoverGravacaoRequest,
    user_id: UUID = Depends(get_current_user),
):
    """Mover gravação para outro destino."""
    # Validate gravacao ownership
    grav = await fetch_one(
        "SELECT id FROM gravacoes WHERE id = $1 AND user_id = $2",
        gravacao_id, user_id,
    )
    if not grav:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail=error_response("NOT_FOUND", "Gravação não encontrada"))

    # Validate new destination ownership
    await _validate_source_ownership(user_id, body.source_type, body.source_id)

    await execute_query(
        "UPDATE gravacoes SET source_type = $1, source_id = $2 WHERE id = $3",
        body.source_type, body.source_id, gravacao_id,
    )
    return success_response({"id": str(gravacao_id), "source_type": body.source_type, "source_id": str(body.source_id)})


# ── DELETE /gravacoes/{id} ───────────────────────────────────

@router.delete("/{gravacao_id}", status_code=status.HTTP_204_NO_CONTENT)
async def deletar_gravacao(
    gravacao_id: UUID,
    user_id: UUID = Depends(get_current_user),
):
    """Excluir gravação e embeddings associados."""
    # Check ownership
    grav = await fetch_one(
        "SELECT id FROM gravacoes WHERE id = $1 AND user_id = $2",
        gravacao_id, user_id,
    )
    if not grav:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail=error_response("NOT_FOUND", "Gravação não encontrada"))

    # Remove embeddings first
    await remove_embeddings(gravacao_id)

    # Delete gravação (cascades to gravacao_media)
    await execute_query(
        "DELETE FROM gravacoes WHERE id = $1",
        gravacao_id,
    )


# ── POST /gravacoes/{id}/regenerate ──────────────────────────

@router.post("/{gravacao_id}/regenerate")
async def regenerar_gravacao(
    gravacao_id: UUID,
    background_tasks: BackgroundTasks,
    user_id: UUID = Depends(get_current_user),
):
    """Re-gerar resumo e mapa mental de uma gravação."""
    grav = await fetch_one(
        "SELECT id, transcription FROM gravacoes WHERE id = $1 AND user_id = $2",
        gravacao_id, user_id,
    )
    if not grav:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail=error_response("NOT_FOUND", "Gravação não encontrada"))

    # Reset status
    await execute_query(
        "UPDATE gravacoes SET status = 'processing', short_summary = NULL, full_summary = NULL, mind_map = NULL WHERE id = $1",
        gravacao_id,
    )

    background_tasks.add_task(generate_summary_for_gravacao, gravacao_id)
    return success_response({"id": str(gravacao_id), "status": "processing"})


# ── GET /gravacoes/{id}/pdf/resumo ───────────────────────────

@router.get("/{gravacao_id}/pdf/resumo")
async def download_resumo_pdf(
    gravacao_id: UUID,
    user_id: UUID = Depends(get_current_user),
):
    """Download PDF do resumo da gravação."""
    row = await fetch_one(
        """SELECT id, date, short_summary, full_summary
           FROM gravacoes WHERE id = $1 AND user_id = $2""",
        gravacao_id, user_id,
    )
    if not row:
        raise HTTPException(status_code=404, detail=error_response("NOT_FOUND", "Gravação não encontrada"))
    if not row["full_summary"] and not row["short_summary"]:
        raise HTTPException(status_code=404, detail=error_response("NOT_FOUND", "Resumo ainda não disponível"))

    from app.services.pdf_service import generate_resumo_pdf
    import io
    pdf_bytes = generate_resumo_pdf(dict(row))
    return PDFStreamingResponse(
        io.BytesIO(pdf_bytes),
        media_type="application/pdf",
        headers={"Content-Disposition": f"attachment; filename=resumo_{gravacao_id}.pdf"},
    )


# ── GET /gravacoes/{id}/pdf/mindmap ──────────────────────────

@router.get("/{gravacao_id}/pdf/mindmap")
async def download_mindmap_pdf(
    gravacao_id: UUID,
    user_id: UUID = Depends(get_current_user),
):
    """Download PDF do mapa mental da gravação."""
    row = await fetch_one(
        """SELECT id, date, mind_map
           FROM gravacoes WHERE id = $1 AND user_id = $2""",
        gravacao_id, user_id,
    )
    if not row:
        raise HTTPException(status_code=404, detail=error_response("NOT_FOUND", "Gravação não encontrada"))
    if not row["mind_map"]:
        raise HTTPException(status_code=404, detail=error_response("NOT_FOUND", "Mapa mental ainda não disponível"))

    from app.services.pdf_service import generate_mindmap_pdf
    import io
    pdf_bytes = generate_mindmap_pdf(dict(row))
    return PDFStreamingResponse(
        io.BytesIO(pdf_bytes),
        media_type="application/pdf",
        headers={"Content-Disposition": f"attachment; filename=mindmap_{gravacao_id}.pdf"},
    )
