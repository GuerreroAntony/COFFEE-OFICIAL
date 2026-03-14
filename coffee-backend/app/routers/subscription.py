from uuid import UUID

from fastapi import APIRouter, Depends, status

from app.database import execute_query, fetch_all, fetch_one
from app.dependencies import get_current_user
from app.routers.gift_codes import create_gift_codes_for_user
from app.schemas.base import success_response
from app.schemas.subscription import GiftCodeBrief, SubscriptionStatusResponse, VerifyReceiptRequest

router = APIRouter(prefix="/api/v1/subscription", tags=["subscription"])


async def _get_user_gift_codes(user_id: UUID) -> list[dict]:
    """Fetch gift codes owned by user."""
    rows = await fetch_all(
        """SELECT code, redeemed_by IS NOT NULL AS redeemed
           FROM gift_codes WHERE owner_id = $1
           ORDER BY created_at""",
        user_id,
    )
    return [{"code": r["code"], "redeemed": r["redeemed"]} for r in rows]


@router.post("/verify", status_code=status.HTTP_201_CREATED)
async def verify_receipt(
    body: VerifyReceiptRequest,
    user_id: UUID = Depends(get_current_user),
):
    """Verificar recibo Apple e ativar subscription."""
    row = await fetch_one(
        """INSERT INTO subscriptions (user_id, plano, status, apple_transaction_id)
           VALUES ($1, 'premium', 'active', $2)
           RETURNING id, plano, status, expires_at""",
        user_id, body.transaction_id,
    )

    await execute_query(
        "UPDATE users SET plano = 'premium' WHERE id = $1",
        user_id,
    )

    # Auto-generate 2 gift codes for the new subscriber
    existing_codes = await fetch_one(
        "SELECT COUNT(*) AS cnt FROM gift_codes WHERE owner_id = $1", user_id
    )
    gift_codes = []
    if not existing_codes or existing_codes["cnt"] == 0:
        gift_codes = await create_gift_codes_for_user(user_id, count=2)
    else:
        gift_codes = await _get_user_gift_codes(user_id)

    resp = SubscriptionStatusResponse(
        plano="premium",
        subscription_active=True,
        expires_at=row.get("expires_at"),
        gift_codes=[GiftCodeBrief(**gc) for gc in gift_codes],
    )
    return success_response(resp.model_dump(mode="json"))


@router.get("/status")
async def get_status(user_id: UUID = Depends(get_current_user)):
    """Status da subscription."""
    user = await fetch_one(
        "SELECT plano FROM users WHERE id = $1", user_id
    )
    sub = await fetch_one(
        """SELECT status, expires_at FROM subscriptions
           WHERE user_id = $1 AND status = 'active'
           ORDER BY created_at DESC LIMIT 1""",
        user_id,
    )

    plano = user["plano"] if user else "trial"
    subscription_active = sub is not None and plano == "premium"
    expires_at = sub["expires_at"] if sub else None

    gift_codes = []
    if plano == "premium":
        gift_codes = await _get_user_gift_codes(user_id)

    resp = SubscriptionStatusResponse(
        plano=plano,
        subscription_active=subscription_active,
        expires_at=expires_at,
        gift_codes=[GiftCodeBrief(**gc) for gc in gift_codes],
    )
    return success_response(resp.model_dump(mode="json"))
