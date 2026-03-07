from datetime import date, datetime
from typing import Optional
from uuid import UUID

from app.schemas.base import BaseSchema


class CriarGravacaoRequest(BaseSchema):
    disciplina_id: UUID
    data_aula: date


class TranscricaoResponse(BaseSchema):
    id: UUID
    gravacao_id: UUID
    texto: str
    idioma: str
    confianca: float
    created_at: datetime


class GravacaoResponse(BaseSchema):
    id: UUID
    disciplina_id: UUID
    data_aula: date
    duracao_segundos: int
    status: str
    created_at: datetime
    transcricao: Optional[TranscricaoResponse] = None


class GravacaoListResponse(BaseSchema):
    gravacoes: list[GravacaoResponse]
