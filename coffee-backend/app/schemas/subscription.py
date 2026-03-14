from datetime import datetime
from typing import Optional

from pydantic import BaseModel


class VerifyReceiptRequest(BaseModel):
    receipt_data: str
    transaction_id: str


class GiftCodeBrief(BaseModel):
    code: str
    redeemed: bool


class SubscriptionStatusResponse(BaseModel):
    plano: str
    subscription_active: bool
    expires_at: Optional[datetime] = None
    gift_codes: list[GiftCodeBrief] = []
