from datetime import datetime
from typing import Optional
from uuid import UUID
from pydantic import BaseModel


class ReferralItem(BaseModel):
    referred_name: str
    created_at: datetime


class ReferralResponse(BaseModel):
    code: Optional[str]
    total_referrals: int
    days_earned: int
    share_message: str
    referrals: list[ReferralItem]


class ValidateCodeRequest(BaseModel):
    code: str


class ValidateCodeResponse(BaseModel):
    valid: bool
    referrer_name: Optional[str] = None
