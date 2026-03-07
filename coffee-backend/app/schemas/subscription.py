from datetime import datetime
from typing import Optional
from uuid import UUID
from pydantic import BaseModel


class VerifyReceiptRequest(BaseModel):
    receipt_data: str
    transaction_id: str


class SubscriptionStatusResponse(BaseModel):
    plano: str
    subscription_active: bool
    expires_at: Optional[datetime] = None
