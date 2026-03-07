from __future__ import annotations

import json
from typing import Any, Optional
from uuid import UUID

from pydantic import field_validator

from app.schemas.base import BaseSchema


class DisciplinaResponse(BaseSchema):
    id: UUID
    nome: str
    professor: Optional[str] = None
    horario: Optional[str] = None
    sala: Optional[str] = None
    semestre: Optional[str] = None
    gravacoes_count: int = 0
    materiais_count: int = 0
    ai_active: bool = False
    horarios: Optional[list[Any]] = None

    @field_validator("horarios", mode="before")
    @classmethod
    def parse_horarios(cls, v):
        if isinstance(v, str):
            return json.loads(v)
        return v


class DisciplinaListResponse(BaseSchema):
    disciplinas: list[DisciplinaResponse]


class DisciplinaDetailResponse(BaseSchema):
    disciplina: DisciplinaResponse
    gravacoes_count: int = 0
    materiais_count: int = 0
