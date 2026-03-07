from uuid import UUID
from datetime import datetime
from typing import Optional
from pydantic import BaseModel, Field


class PersonalityConfig(BaseModel):
    profundidade: int = Field(default=50, ge=0, le=100)
    linguagem: int = Field(default=50, ge=0, le=100)
    exemplos: int = Field(default=50, ge=0, le=100)
    questionamento: int = Field(default=50, ge=0, le=100)
    foco: int = Field(default=50, ge=0, le=100)


class CreateChatRequest(BaseModel):
    source_type: str = Field(pattern="^(disciplina|repositorio)$")
    source_id: UUID


class SendMessageRequest(BaseModel):
    text: str = Field(min_length=1, max_length=5000)
    personality: Optional[PersonalityConfig] = None


class SourceReference(BaseModel):
    type: str  # "transcription" ou "material"
    gravacao_id: Optional[UUID] = None  # se type=transcription
    material_id: Optional[UUID] = None  # se type=material
    title: str
    date: Optional[str] = None
    excerpt: str
    similarity: float


class MessageResponse(BaseModel):
    id: UUID
    sender: str  # "user" ou "ai"
    text: str
    label: Optional[str] = None  # "Barista de Marketing" (só pra ai)
    sources: Optional[list[SourceReference]] = None  # só pra ai
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
