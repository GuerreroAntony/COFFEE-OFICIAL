from __future__ import annotations

from datetime import datetime
from typing import Any, Optional
from uuid import UUID

from pydantic import BaseModel, Field


class CreateShareRequest(BaseModel):
    gravacao_id: UUID
    recipient_emails: list[str] = Field(min_length=1)
    shared_content: list[str] = Field(default=["transcription", "summary", "mind_map"])
    message: Optional[str] = None


class AcceptShareRequest(BaseModel):
    destination_type: str = Field(pattern="^(disciplina|repositorio)$")
    destination_id: UUID


class ShareResultItem(BaseModel):
    email: str
    status: str  # "sent" or "not_found"
    recipient_name: Optional[str] = None


class ReceivedShareSender(BaseModel):
    nome: str
    initials: str


class ReceivedShareGravacao(BaseModel):
    date: Optional[str] = None
    date_label: Optional[str] = None
    duration_label: Optional[str] = None
    short_summary: Optional[str] = None
    has_mind_map: bool = False


class ReceivedShareItem(BaseModel):
    id: UUID
    sender: ReceivedShareSender
    gravacao: ReceivedShareGravacao
    source_discipline: Optional[str] = None
    shared_content: list[str]
    message: Optional[str] = None
    status: str  # "pending", "accepted", "rejected"
    is_new: bool = True
    created_at: datetime
