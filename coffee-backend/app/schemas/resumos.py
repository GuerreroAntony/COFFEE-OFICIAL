from datetime import datetime
from typing import List, Optional
from uuid import UUID

from pydantic import BaseModel


class ConceitoChave(BaseModel):
    termo: str
    definicao: str


class Topico(BaseModel):
    titulo: str
    conteudo: str


class GerarResumoRequest(BaseModel):
    transcricao_id: UUID


class AtualizarTituloRequest(BaseModel):
    titulo: str


class ResumoResponse(BaseModel):
    id: UUID
    transcricao_id: UUID
    titulo: str
    topicos: List[Topico]
    conceitos_chave: List[ConceitoChave]
    resumo_geral: str
    modelo_usado: str
    tokens_usados: int
    created_at: datetime


class ResumoListResponse(BaseModel):
    resumos: List[ResumoResponse]
