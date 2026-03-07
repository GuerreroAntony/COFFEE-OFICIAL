from datetime import datetime
from typing import Optional
from uuid import UUID
from pydantic import BaseModel


class MaterialResponse(BaseModel):
    id: UUID
    disciplina_id: UUID
    tipo: Optional[str] = None
    nome: str
    url_storage: Optional[str] = None
    fonte: str
    ai_enabled: bool
    size_bytes: Optional[int] = None
    size_label: Optional[str] = None
    created_at: datetime


class MaterialListResponse(BaseModel):
    materiais: list[MaterialResponse]


class ToggleAIResponse(BaseModel):
    id: UUID
    ai_enabled: bool


class SyncStatusResponse(BaseModel):
    status: str  # "triggered" | "fresh"
    last_scraped_at: Optional[datetime] = None
