from __future__ import annotations

from datetime import datetime
from typing import Optional
from uuid import UUID

from app.schemas.base import BaseSchema


class MaterialResponse(BaseSchema):
    id: UUID
    disciplina_id: UUID
    tipo: str
    nome: str
    url_storage: Optional[str] = None
    fonte: str
    ai_enabled: bool
    created_at: datetime


class MaterialListResponse(BaseSchema):
    materiais: list[MaterialResponse]


class ToggleAIResponse(BaseSchema):
    id: UUID
    ai_enabled: bool


class SyncStatusResponse(BaseSchema):
    status: str  # "triggered" | "fresh"
    last_scraped_at: Optional[datetime] = None
