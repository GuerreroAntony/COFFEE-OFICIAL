from uuid import UUID

from fastapi import APIRouter, Depends

from app.config import settings
from app.database import fetch_all, fetch_one
from app.dependencies import get_current_user
from app.schemas.base import success_response
from app.schemas.referral import (
    ReferralItem,
    ReferralResponse,
    ValidateCodeRequest,
    ValidateCodeResponse,
)

router = APIRouter(prefix="/api/v1/referral", tags=["referral"])


@router.get("")
async def get_referral(user_id: UUID = Depends(get_current_user)):
    """Dados do programa de referral."""
    user = await fetch_one(
        "SELECT referral_code FROM users WHERE id = $1", user_id
    )
    code = user["referral_code"] if user else None

    rows = await fetch_all(
        """SELECT u.nome, r.created_at
           FROM referrals r
           JOIN users u ON r.referred_id = u.id
           WHERE r.referrer_id = $1
           ORDER BY r.created_at DESC""",
        user_id,
    )

    referrals = [
        ReferralItem(referred_name=r["nome"], created_at=r["created_at"])
        for r in rows
    ]
    total = len(referrals)
    days_earned = total * settings.REFERRAL_BONUS_DAYS

    share_message = (
        f"Estudo com o Coffee e tá me ajudando demais! "
        f"Usa meu código {code} pra ganhar {settings.REFERRAL_BONUS_DAYS} dias grátis: https://coffeeapp.com.br/r/{code}"
    )

    resp = ReferralResponse(
        code=code,
        total_referrals=total,
        days_earned=days_earned,
        share_message=share_message,
        referrals=[r.model_dump(mode="json") for r in referrals],
    )
    return success_response(resp.model_dump(mode="json"))


@router.post("/validate")
async def validate_code(body: ValidateCodeRequest):
    """Validar código de referral."""
    user = await fetch_one(
        "SELECT nome FROM users WHERE referral_code = $1", body.code
    )
    if user:
        resp = ValidateCodeResponse(valid=True, referrer_name=user["nome"])
    else:
        resp = ValidateCodeResponse(valid=False)
    return success_response(resp.model_dump(mode="json"))
