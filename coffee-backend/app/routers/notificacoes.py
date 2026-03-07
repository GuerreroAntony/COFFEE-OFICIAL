"""
Notification list and management endpoints.
"""
from __future__ import annotations

from datetime import datetime
from typing import Any, Optional
from uuid import UUID

from fastapi import APIRouter, Depends
from pydantic import BaseModel

from app.database import execute_query, fetch_all
from app.dependencies import get_current_user
from app.schemas.base import success_response

router = APIRouter(prefix="/api/v1/notificacoes", tags=["notificacoes"])


class NotificacaoOut(BaseModel):
    id: UUID
    tipo: str
    titulo: str
    corpo: Optional[str]
    lida: bool
    created_at: datetime
    data_payload: Optional[Any] = None


@router.get("")
async def list_notificacoes(
    user_id: UUID = Depends(get_current_user),
):
    """List user's notifications (newest first, limit 50)."""
    rows = await fetch_all(
        """SELECT id, tipo, titulo, corpo, lida, created_at, data_payload
           FROM notificacoes
           WHERE user_id = $1
           ORDER BY created_at DESC
           LIMIT 50""",
        user_id,
    )
    items = [NotificacaoOut(**dict(r)).model_dump(mode="json") for r in rows]
    return success_response(items)


@router.patch("/{notificacao_id}/read")
async def mark_read(
    notificacao_id: UUID,
    user_id: UUID = Depends(get_current_user),
):
    """Mark a notification as read."""
    await execute_query(
        "UPDATE notificacoes SET lida = TRUE WHERE id = $1 AND user_id = $2",
        notificacao_id,
        user_id,
    )
    return success_response(None, "Notificação marcada como lida")
