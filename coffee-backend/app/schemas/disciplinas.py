from __future__ import annotations

from typing import Optional
from uuid import UUID

from app.schemas.base import BaseSchema


class DisciplinaResponse(BaseSchema):
    id: UUID
    nome: str
    turma: Optional[str] = None
    semestre: Optional[str] = None
    sala: Optional[str] = None
    canvas_course_id: Optional[int] = None
    last_synced_at: Optional[str] = None
    gravacoes_count: int = 0
    materiais_count: int = 0
    ai_active: bool = False


class DisciplinaListResponse(BaseSchema):
    disciplinas: list[DisciplinaResponse]


class DisciplinaDetailResponse(BaseSchema):
    disciplina: DisciplinaResponse
    gravacoes_count: int = 0
    materiais_count: int = 0
