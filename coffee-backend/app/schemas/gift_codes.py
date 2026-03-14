from datetime import datetime
from typing import Optional

from pydantic import BaseModel, Field


class ValidateGiftCodeRequest(BaseModel):
    code: str = Field(min_length=1, max_length=20)


class RedeemGiftCodeRequest(BaseModel):
    code: str = Field(min_length=1, max_length=20)


class GiftCodeItem(BaseModel):
    code: str
    redeemed: bool
    redeemed_by: Optional[str] = None
    redeemed_at: Optional[datetime] = None
    created_at: Optional[datetime] = None


class GiftCodesListResponse(BaseModel):
    codes: list[GiftCodeItem]
    share_message: Optional[str] = None


class ValidateResponse(BaseModel):
    valid: bool
    owner_name: Optional[str] = None


class RedeemResponse(BaseModel):
    redeemed: bool
    days_added: int
    new_trial_end: datetime
