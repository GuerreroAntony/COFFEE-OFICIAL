from datetime import datetime, timezone
from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, status

from app.database import execute_query, fetch_all, fetch_one
from app.dependencies import get_current_user
from app.plan_limits import get_gift_code_count, is_paid_plan
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
    # Validate plan name
    if body.plano not in ("cafe_com_leite", "black"):
        raise HTTPException(status_code=400, detail="Plano inválido. Use 'cafe_com_leite' ou 'black'.")

    row = await fetch_one(
        """INSERT INTO subscriptions (user_id, plano, status, apple_transaction_id)
           VALUES ($1, $2, 'active', $3)
           RETURNING id, plano, status, expires_at""",
        user_id, body.plano, body.transaction_id,
    )

    await execute_query(
        "UPDATE users SET plano = $2 WHERE id = $1",
        user_id, body.plano,
    )

    # Auto-generate gift codes based on plan tier
    existing_codes = await fetch_one(
        "SELECT COUNT(*) AS cnt FROM gift_codes WHERE owner_id = $1", user_id
    )
    gift_codes = []
    code_count = get_gift_code_count(body.plano)
    if (not existing_codes or existing_codes["cnt"] == 0) and code_count > 0:
        gift_codes = await create_gift_codes_for_user(user_id, count=code_count)
    else:
        gift_codes = await _get_user_gift_codes(user_id)

    resp = SubscriptionStatusResponse(
        plano=body.plano,
        subscription_active=True,
        expires_at=row.get("expires_at"),
        gift_codes=[GiftCodeBrief(**gc) for gc in gift_codes],
    )
    return success_response(resp.model_dump(mode="json"))


@router.get("/status")
async def get_status(user_id: UUID = Depends(get_current_user)):
    """Status da subscription."""
    user = await fetch_one(
        "SELECT plano, trial_end FROM users WHERE id = $1", user_id
    )
    sub = await fetch_one(
        """SELECT status, expires_at FROM subscriptions
           WHERE user_id = $1 AND status = 'active'
           ORDER BY created_at DESC LIMIT 1""",
        user_id,
    )

    plano = user["plano"] if user else "trial"
    # Active if paid plan with subscription OR trial still valid
    trial_end = user.get("trial_end") if user else None
    trial_valid = (
        plano == "trial"
        and trial_end is not None
        and (trial_end if trial_end.tzinfo else trial_end.replace(tzinfo=timezone.utc)) > datetime.now(timezone.utc)
    )
    subscription_active = (sub is not None and is_paid_plan(plano)) or trial_valid
    expires_at = sub["expires_at"] if sub else None

    gift_codes = []
    if is_paid_plan(plano):
        gift_codes = await _get_user_gift_codes(user_id)

    resp = SubscriptionStatusResponse(
        plano=plano,
        subscription_active=subscription_active,
        expires_at=expires_at,
        gift_codes=[GiftCodeBrief(**gc) for gc in gift_codes],
    )
    return success_response(resp.model_dump(mode="json"))
