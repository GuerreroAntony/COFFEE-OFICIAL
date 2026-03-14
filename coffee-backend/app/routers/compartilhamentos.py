"""
Compartilhamentos (Sharing) — share gravações with other Coffee users.
Contract v3.1 compliant.
"""
from __future__ import annotations

import json
import logging
from uuid import UUID

from fastapi import APIRouter, BackgroundTasks, Depends, HTTPException, status

from app.database import execute_query, fetch_all, fetch_one
from app.dependencies import get_current_user
from app.schemas.base import error_response, success_response
from app.schemas.compartilhamentos import (
    AcceptShareRequest,
    CreateShareRequest,
    ReceivedShareGravacao,
    ReceivedShareItem,
    ReceivedShareSender,
    ShareResultItem,
)

router = APIRouter(prefix="/api/v1/compartilhamentos", tags=["compartilhamentos"])
logger = logging.getLogger(__name__)


def _make_initials(nome: str) -> str:
    """Generate initials from name (e.g. 'Ana Beatriz' → 'AB')."""
    parts = nome.strip().split()
    if len(parts) >= 2:
        return (parts[0][0] + parts[-1][0]).upper()
    elif parts:
        return parts[0][:2].upper()
    return "?"


def _duration_label(seconds: int | None) -> str | None:
    """Format seconds as 'Xh Ymin'."""
    if not seconds:
        return None
    hours = seconds // 3600
    minutes = (seconds % 3600) // 60
    if hours > 0:
        return f"{hours}h {minutes}min"
    return f"{minutes}min"


def _date_label(date_str: str | None) -> str | None:
    """Format date as 'Terça, 25 de fevereiro'."""
    if not date_str:
        return None
    try:
        from datetime import datetime
        dt = datetime.strptime(str(date_str)[:10], "%Y-%m-%d")
        dias = ["Segunda", "Terça", "Quarta", "Quinta", "Sexta", "Sábado", "Domingo"]
        meses = ["janeiro", "fevereiro", "março", "abril", "maio", "junho",
                 "julho", "agosto", "setembro", "outubro", "novembro", "dezembro"]
        return f"{dias[dt.weekday()]}, {dt.day} de {meses[dt.month - 1]}"
    except Exception:
        return date_str


# ── POST /compartilhamentos ──────────────────────────────────

@router.post("")
async def share_gravacao(
    body: CreateShareRequest,
    background_tasks: BackgroundTasks,
    user_id: UUID = Depends(get_current_user),
):
    """Compartilhar gravação com outros usuários por email."""
    # Verify ownership
    grav = await fetch_one(
        "SELECT id, short_summary, date FROM gravacoes WHERE id = $1 AND user_id = $2",
        body.gravacao_id, user_id,
    )
    if not grav:
        raise HTTPException(status_code=404, detail=error_response("NOT_FOUND", "Gravação não encontrada"))

    sender = await fetch_one("SELECT nome, email FROM users WHERE id = $1", user_id)
    sender_name = sender["nome"] if sender else "Aluno"

    results: list[dict] = []
    shared_count = 0
    not_found_emails: list[str] = []

    for email in body.recipient_emails:
        # Find recipient by email or espm_login
        recipient = await fetch_one(
            "SELECT id, nome FROM users WHERE email = $1 OR espm_login = $1",
            email,
        )

        if not recipient:
            not_found_emails.append(email)
            results.append(ShareResultItem(
                email=email, status="not_found",
            ).model_dump(mode="json"))
            continue

        if recipient["id"] == user_id:
            results.append(ShareResultItem(
                email=email, status="not_found", recipient_name=recipient["nome"],
            ).model_dump(mode="json"))
            continue

        # Create compartilhamento
        comp_row = await fetch_one(
            """INSERT INTO compartilhamentos
               (sender_id, recipient_id, gravacao_id, shared_content, message, status)
               VALUES ($1, $2, $3, $4::jsonb, $5, 'pending')
               RETURNING id""",
            user_id, recipient["id"], body.gravacao_id,
            json.dumps(body.shared_content),
            body.message,
        )
        comp_id = comp_row["id"] if comp_row else None
        shared_count += 1

        results.append(ShareResultItem(
            email=email, status="sent", recipient_name=recipient["nome"],
        ).model_dump(mode="json"))

        # Create notification for recipient (with deep_link per contract v3.1)
        deep_link = f"coffee://compartilhamentos/{comp_id}" if comp_id else "coffee://compartilhamentos"
        data_payload = json.dumps({
            "compartilhamento_id": str(comp_id) if comp_id else None,
            "deep_link": deep_link,
            "type": "compartilhamento",
        })
        await execute_query(
            """INSERT INTO notificacoes (user_id, tipo, titulo, corpo, data_payload)
               VALUES ($1, 'compartilhamento', $2, $3, $4::jsonb)""",
            recipient["id"],
            f"{sender_name} compartilhou uma gravação",
            body.message or "Você recebeu uma gravação compartilhada.",
            data_payload,
        )

        # Push notification in background
        background_tasks.add_task(
            _send_share_push, recipient["id"], sender_name, str(comp_id) if comp_id else None,
        )

    # Contract: 404 RECIPIENT_NOT_FOUND only if ALL emails not found
    if shared_count == 0 and not_found_emails:
        raise HTTPException(status_code=404, detail=error_response(
            "RECIPIENT_NOT_FOUND", "Nenhum destinatário encontrado no Coffee."))

    return success_response({
        "shared_count": shared_count,
        "not_found_emails": not_found_emails,
        "results": results,
    })


async def _send_share_push(recipient_id: UUID, sender_name: str, comp_id: str | None = None):
    """Send push notification for a new share."""
    try:
        from app.services.push_service import send_push_to_user
        deep_link = f"coffee://compartilhamentos/{comp_id}" if comp_id else "coffee://compartilhamentos"
        data = {
            "type": "compartilhamento",
            "deep_link": deep_link,
        }
        await send_push_to_user(
            recipient_id,
            f"{sender_name} compartilhou uma gravação",
            "Abra o Coffee para ver a gravação recebida.",
            data,
        )
    except Exception as e:
        logger.warning("Push notification failed for share: %s", e)


# ── GET /compartilhamentos/received ──────────────────────────

@router.get("/received")
async def list_received_shares(
    status_filter: str = "all",
    user_id: UUID = Depends(get_current_user),
):
    """Listar compartilhamentos recebidos (inbox). Contract v3.1 shape."""
    query = """
        SELECT c.id, c.shared_content, c.message, c.status, c.created_at,
               u.nome AS sender_name, u.email AS sender_email,
               g.date::text AS gravacao_date,
               g.duration_seconds,
               g.short_summary,
               g.mind_map IS NOT NULL AS has_mind_map,
               d.nome AS source_discipline
        FROM compartilhamentos c
        JOIN users u ON c.sender_id = u.id
        LEFT JOIN gravacoes g ON c.gravacao_id = g.id
        LEFT JOIN disciplinas d ON g.source_type = 'disciplina' AND g.source_id = d.id
        WHERE c.recipient_id = $1
    """
    params = [user_id]

    if status_filter != "all":
        query += " AND c.status = $2"
        params.append(status_filter)

    query += " ORDER BY c.created_at DESC"

    rows = await fetch_all(query, *params)

    items = []
    for r in rows:
        shared_content = r["shared_content"]
        if isinstance(shared_content, str):
            shared_content = json.loads(shared_content)
        elif shared_content is None:
            shared_content = []

        sender_name = r["sender_name"] or "Aluno"
        item = ReceivedShareItem(
            id=r["id"],
            sender=ReceivedShareSender(
                nome=sender_name,
                initials=_make_initials(sender_name),
            ),
            gravacao=ReceivedShareGravacao(
                date=r["gravacao_date"],
                date_label=_date_label(r["gravacao_date"]),
                duration_label=_duration_label(r["duration_seconds"]),
                short_summary=r["short_summary"],
                has_mind_map=r["has_mind_map"] or False,
            ),
            source_discipline=r["source_discipline"],
            shared_content=shared_content,
            message=r["message"],
            status=r["status"],
            is_new=(r["status"] == "pending"),
            created_at=r["created_at"],
        )
        items.append(item.model_dump(mode="json"))

    return success_response(items)


# ── POST /compartilhamentos/{id}/accept ──────────────────────

@router.post("/{share_id}/accept")
async def accept_share(
    share_id: UUID,
    body: AcceptShareRequest,
    background_tasks: BackgroundTasks,
    user_id: UUID = Depends(get_current_user),
):
    """Aceitar compartilhamento — cria deep copy da gravação."""
    share = await fetch_one(
        """SELECT c.id, c.gravacao_id, c.sender_id, c.shared_content, c.status
           FROM compartilhamentos c
           WHERE c.id = $1 AND c.recipient_id = $2""",
        share_id, user_id,
    )
    if not share:
        raise HTTPException(status_code=404, detail=error_response("NOT_FOUND", "Compartilhamento não encontrado"))
    if share["status"] != "pending":
        raise HTTPException(status_code=400, detail=error_response("ALREADY_HANDLED", "Compartilhamento já processado"))

    # Get sender name for received_from
    sender = await fetch_one("SELECT nome FROM users WHERE id = $1", share["sender_id"])
    sender_name = sender["nome"] if sender else "Aluno"

    # Get original gravação
    orig = await fetch_one(
        """SELECT transcription, short_summary, full_summary, mind_map,
                  date, duration_seconds
           FROM gravacoes WHERE id = $1""",
        share["gravacao_id"],
    )
    if not orig:
        raise HTTPException(status_code=404, detail=error_response("NOT_FOUND", "Gravação original não encontrada"))

    # Deep copy: create new gravação for recipient
    new_grav = await fetch_one(
        """INSERT INTO gravacoes
           (user_id, source_type, source_id, date, duration_seconds, status,
            transcription, short_summary, full_summary, mind_map, received_from)
           VALUES ($1, $2, $3, $4, $5, 'ready', $6, $7, $8, $9, $10)
           RETURNING id""",
        user_id, body.destination_type, body.destination_id,
        orig["date"], orig["duration_seconds"],
        orig["transcription"], orig["short_summary"],
        orig["full_summary"], orig["mind_map"],
        sender_name,
    )
    new_gravacao_id = new_grav["id"]

    # Copy media (same URL, no file duplication)
    media_rows = await fetch_all(
        "SELECT type, label, timestamp_seconds, url_storage FROM gravacao_media WHERE gravacao_id = $1",
        share["gravacao_id"],
    )
    for m in media_rows:
        await execute_query(
            """INSERT INTO gravacao_media (gravacao_id, type, label, timestamp_seconds, url_storage)
               VALUES ($1, $2, $3, $4, $5)""",
            new_gravacao_id, m["type"], m["label"], m["timestamp_seconds"], m["url_storage"],
        )

    # Update compartilhamento status
    await execute_query(
        "UPDATE compartilhamentos SET status = 'accepted', created_gravacao_id = $1 WHERE id = $2",
        new_gravacao_id, share_id,
    )

    # Generate embeddings for the copy in background
    if orig["transcription"]:
        disciplina_id = body.destination_id if body.destination_type == "disciplina" else None
        background_tasks.add_task(
            _generate_embeddings_for_copy,
            orig["transcription"], new_gravacao_id, disciplina_id,
        )

    # Contract v3.1 response: {gravacao_id, destination_type, destination_id, status}
    return success_response({
        "gravacao_id": str(new_gravacao_id),
        "destination_type": body.destination_type,
        "destination_id": str(body.destination_id),
        "status": "accepted",
    })


async def _generate_embeddings_for_copy(transcription: str, gravacao_id: UUID, disciplina_id):
    """Generate embeddings for a shared gravação copy."""
    try:
        from app.services.embedding_service import generate_transcription_embeddings
        await generate_transcription_embeddings(transcription, gravacao_id, disciplina_id)
    except Exception as e:
        logger.warning("Embedding generation failed for shared copy %s: %s", gravacao_id, e)


# ── POST /compartilhamentos/{id}/reject ──────────────────────

@router.post("/{share_id}/reject")
async def reject_share(
    share_id: UUID,
    user_id: UUID = Depends(get_current_user),
):
    """Rejeitar compartilhamento."""
    share = await fetch_one(
        "SELECT id, status FROM compartilhamentos WHERE id = $1 AND recipient_id = $2",
        share_id, user_id,
    )
    if not share:
        raise HTTPException(status_code=404, detail=error_response("NOT_FOUND", "Compartilhamento não encontrado"))
    if share["status"] != "pending":
        raise HTTPException(status_code=400, detail=error_response("ALREADY_HANDLED", "Compartilhamento já processado"))

    await execute_query(
        "UPDATE compartilhamentos SET status = 'rejected' WHERE id = $1",
        share_id,
    )
    # Contract v3.1: {data: {status: "rejected"}}
    return success_response({"status": "rejected"})
