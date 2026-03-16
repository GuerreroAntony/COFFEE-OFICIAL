from datetime import datetime
from typing import Optional
from uuid import UUID

from pydantic import BaseModel, Field


class QuestionsRemaining(BaseModel):
    espresso: int = 75
    lungo: int = 30
    cold_brew: int = 15


class UsageStats(BaseModel):
    gravacoes_total: int
    horas_gravadas: float
    questions_remaining: QuestionsRemaining
    questions_reset_at: datetime


class GiftCodeProfile(BaseModel):
    code: str
    redeemed: bool
    redeemed_by: Optional[str] = None
    redeemed_at: Optional[datetime] = None


class ProfileResponse(BaseModel):
    id: UUID
    nome: str
    email: str
    plano: str
    trial_end: Optional[datetime] = None
    subscription_active: bool
    espm_connected: bool
    espm_login: Optional[str] = None
    usage: UsageStats
    gift_codes: list[GiftCodeProfile] = []
    created_at: datetime


class UpdateProfileRequest(BaseModel):
    nome: str = Field(min_length=2, max_length=255)
