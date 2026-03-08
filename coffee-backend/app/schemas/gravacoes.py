from datetime import date as DateType, datetime
from typing import Optional
from uuid import UUID
from pydantic import BaseModel, Field


class CriarGravacaoRequest(BaseModel):
    source_type: str = Field(pattern="^(disciplina|repositorio)$")
    source_id: UUID
    transcription: str = Field(min_length=10)
    duration_seconds: int = Field(gt=0)
    date: Optional[DateType] = None  # default: today


class MoverGravacaoRequest(BaseModel):
    source_type: str = Field(pattern="^(disciplina|repositorio)$")
    source_id: UUID


class MediaUploadResponse(BaseModel):
    id: UUID
    type: str
    label: Optional[str]
    timestamp_seconds: int
    timestamp_label: str
    url: str
    created_at: datetime


class GravacaoSummarySection(BaseModel):
    title: str
    bullets: list[str]


class GravacaoMediaItem(BaseModel):
    id: UUID
    type: str
    label: Optional[str]
    timestamp_seconds: int
    timestamp_label: str
    url: str


class GravacaoMaterialItem(BaseModel):
    id: UUID
    nome: str
    tipo: str
    size_label: str
    url: Optional[str]


class GravacaoListItem(BaseModel):
    id: UUID
    source_type: str
    source_id: UUID
    date: DateType
    date_label: str
    duration_seconds: int
    duration_label: str
    status: str
    short_summary: Optional[str]
    media_count: int
    materials_count: int


class GravacaoDetail(BaseModel):
    id: UUID
    source_type: str
    source_id: UUID
    date: DateType
    date_label: str
    duration_seconds: int
    duration_label: str
    status: str
    short_summary: Optional[str]
    full_summary: Optional[list[GravacaoSummarySection]]
    transcription: Optional[str]
    media: list[GravacaoMediaItem]
    materials: list[GravacaoMaterialItem]
    created_at: datetime


class GravacaoCreatedResponse(BaseModel):
    id: UUID
    source_type: str
    source_id: UUID
    date: DateType
    date_label: str
    duration_seconds: int
    duration_label: str
    status: str
    created_at: datetime
