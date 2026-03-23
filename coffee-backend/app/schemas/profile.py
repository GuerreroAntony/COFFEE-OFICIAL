from datetime import datetime
from typing import Optional
from uuid import UUID

from pydantic import BaseModel, Field


class QuestionsRemaining(BaseModel):
    """Legacy — kept for backward compatibility with old iOS versions."""
    espresso: int = -1
    lungo: int = -1
    cold_brew: int = -1


class BaristaUsage(BaseModel):
    """Barista v2 — budget-based usage tracking."""
    usage_percent: float = 0.0       # 0-100, how much of budget is used
    budget_usd: float = 0.0          # total budget for this cycle
    used_usd: float = 0.0            # how much has been used
    remaining_usd: float = 0.0       # budget - used
    cycle_reset_at: datetime         # when the cycle resets


class UsageStats(BaseModel):
    gravacoes_total: int
    horas_gravadas: float
    questions_remaining: QuestionsRemaining  # legacy
    barista_usage: BaristaUsage              # v2
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
