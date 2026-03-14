from datetime import datetime
from typing import Optional
from uuid import UUID
from pydantic import BaseModel, Field


class CriarRepositorioRequest(BaseModel):
    nome: str = Field(min_length=1, max_length=50)
    icone: str = Field(default="folder", max_length=50)


class RenameRepositorioRequest(BaseModel):
    nome: str = Field(min_length=1, max_length=50)


class RepositorioResponse(BaseModel):
    id: UUID
    nome: str
    icone: str
    gravacoes_count: int
    ai_active: bool
    created_at: datetime
