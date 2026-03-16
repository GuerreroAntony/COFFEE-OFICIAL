import random
import string
from datetime import timedelta, datetime, timezone
from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, status

from app.config import settings
from app.database import execute_query, fetch_all, fetch_one
from app.dependencies import get_current_user
from app.schemas.base import error_response, success_response
from app.schemas.gift_codes import (
    GiftCodeItem,
    GiftCodesListResponse,
    RedeemGiftCodeRequest,
    RedeemResponse,
    ValidateGiftCodeRequest,
    ValidateResponse,
)

router = APIRouter(prefix="/api/v1/gift-codes", tags=["gift-codes"])


def generate_gift_code() -> str:
    """Generate random 8-char uppercase alphanumeric code."""
    return "".join(random.choices(string.ascii_uppercase + string.digits, k=8))


async def create_gift_codes_for_user(user_id: UUID, count: int = 2) -> list[dict]:
    """Auto-generate gift codes for a user (called on subscription verify)."""
    codes = []
    for _ in range(count):
        code = generate_gift_code()
        # Ensure uniqueness
        for _retry in range(5):
            conflict = await fetch_one("SELECT 1 FROM gift_codes WHERE code = $1", code)
            if not conflict:
                break
            code = generate_gift_code()

        await execute_query(
            "INSERT INTO gift_codes (owner_id, code) VALUES ($1, $2)",
            user_id, code,
        )
        codes.append({"code": code, "redeemed": False})
    return codes


# ── GET /gift-codes ──────────────────────────────────────────

@router.get("")
async def list_gift_codes(user_id: UUID = Depends(get_current_user)):
    """List gift codes owned by the user."""
    rows = await fetch_all(
        """SELECT gc.code, gc.redeemed_by IS NOT NULL AS redeemed,
                  u.nome AS redeemed_by_name, gc.redeemed_at, gc.created_at
           FROM gift_codes gc
           LEFT JOIN users u ON gc.redeemed_by = u.id
           WHERE gc.owner_id = $1
           ORDER BY gc.created_at""",
        user_id,
    )

    codes = []
    first_available = None
    for r in rows:
        item = GiftCodeItem(
            code=r["code"],
            redeemed=r["redeemed"],
            redeemed_by=r["redeemed_by_name"],
            redeemed_at=r["redeemed_at"],
            created_at=r["created_at"],
        )
        codes.append(item)
        if not r["redeemed"] and first_available is None:
            first_available = r["code"]

    share_message = None
    if first_available:
        share_message = f"Usa meu codigo {first_available} no Coffee e ganha 7 dias gratis!"

    resp = GiftCodesListResponse(codes=codes, share_message=share_message)
    return success_response(resp.model_dump(mode="json"))


# ── POST /gift-codes/validate ────────────────────────────────

@router.post("/validate")
async def validate_gift_code(body: ValidateGiftCodeRequest):
    """Check if a gift code is valid (exists and not yet redeemed)."""
    row = await fetch_one(
        """SELECT gc.id, u.nome AS owner_name
           FROM gift_codes gc
           JOIN users u ON gc.owner_id = u.id
           WHERE gc.code = $1 AND gc.redeemed_by IS NULL""",
        body.code,
    )

    if not row:
        return success_response(ValidateResponse(valid=False).model_dump(mode="json"))

    return success_response(
        ValidateResponse(valid=True, owner_name=row["owner_name"]).model_dump(mode="json")
    )


# ── POST /gift-codes/redeem ─────────────────────────────────

@router.post("/redeem")
async def redeem_gift_code(
    body: RedeemGiftCodeRequest,
    user_id: UUID = Depends(get_current_user),
):
    """Redeem a gift code. Only trial users can redeem. Adds +7 days to trial_end."""
    # Check user plan
    user = await fetch_one(
        "SELECT plano, trial_end FROM users WHERE id = $1", user_id
    )
    if not user:
        raise HTTPException(status_code=404, detail=error_response("NOT_FOUND", "Usuário não encontrado"))

    if user["plano"] in ("cafe_com_leite", "black"):
        raise HTTPException(status_code=403, detail=error_response("SUBSCRIPTION_REQUIRED", "Assinantes não podem resgatar gift codes"))

    # Check if user already redeemed a code
    already = await fetch_one(
        "SELECT 1 FROM gift_codes WHERE redeemed_by = $1", user_id
    )
    if already:
        raise HTTPException(status_code=409, detail=error_response("ALREADY_REDEEMED", "Você já resgatou um gift code"))

    # Validate code
    gc = await fetch_one(
        "SELECT id FROM gift_codes WHERE code = $1 AND redeemed_by IS NULL",
        body.code,
    )
    if not gc:
        # Check if code exists but is already used
        exists = await fetch_one("SELECT 1 FROM gift_codes WHERE code = $1", body.code)
        if exists:
            raise HTTPException(status_code=409, detail=error_response("CODE_ALREADY_USED", "Este código já foi utilizado"))
        raise HTTPException(status_code=404, detail=error_response("INVALID_CODE", "Código não encontrado"))

    # Redeem: mark code and extend trial
    bonus = settings.GIFT_CODE_BONUS_DAYS
    await execute_query(
        "UPDATE gift_codes SET redeemed_by = $1, redeemed_at = NOW() WHERE id = $2",
        user_id, gc["id"],
    )

    new_trial = await fetch_one(
        """UPDATE users
           SET trial_end = COALESCE(trial_end, NOW()) + make_interval(days => $1)
           WHERE id = $2
           RETURNING trial_end""",
        bonus, user_id,
    )

    resp = RedeemResponse(
        redeemed=True,
        days_added=bonus,
        new_trial_end=new_trial["trial_end"],
    )
    return success_response(resp.model_dump(mode="json"))
