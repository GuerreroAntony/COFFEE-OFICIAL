from datetime import datetime
from typing import Optional
from uuid import UUID
from pydantic import BaseModel, Field


class UsageStats(BaseModel):
    gravacoes_total: int
    horas_gravadas: float
    perguntas_hoje: int
    perguntas_limite: int  # 10 se trial, -1 se premium


class ProfileResponse(BaseModel):
    id: UUID
    nome: str
    email: str
    plano: str
    trial_end: Optional[datetime] = None
    espm_connected: bool
    referral_code: Optional[str] = None
    referrals_count: int
    usage: UsageStats
    created_at: datetime


class UpdateProfileRequest(BaseModel):
    nome: str = Field(min_length=2, max_length=255)
