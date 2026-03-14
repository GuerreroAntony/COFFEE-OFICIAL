from uuid import UUID
from datetime import datetime
from typing import Optional
from pydantic import BaseModel, Field


class CreateChatRequest(BaseModel):
    source_type: str = Field(pattern="^(disciplina|repositorio)$")
    source_id: UUID


class SendMessageRequest(BaseModel):
    text: str = Field(min_length=1, max_length=5000)
    mode: str = Field(pattern="^(espresso|lungo|cold_brew)$")
    gravacao_id: Optional[UUID] = None


class SourceReference(BaseModel):
    type: str  # "transcription" ou "material"
    gravacao_id: Optional[UUID] = None
    material_id: Optional[UUID] = None
    title: str
    date: Optional[str] = None
    excerpt: str
    similarity: float


class MessageResponse(BaseModel):
    id: UUID
    sender: str  # "user" ou "ai"
    text: str
    mode: Optional[str] = None
    label: Optional[str] = None
    sources: Optional[list[SourceReference]] = None
    created_at: datetime


class ChatSummary(BaseModel):
    id: UUID
    source_type: str
    source_id: UUID
    source_name: str
    source_icon: Optional[str] = None
    last_message: Optional[str] = None
    message_count: int
    updated_at: datetime
