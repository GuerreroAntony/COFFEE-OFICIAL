import asyncio
from datetime import datetime, timedelta, timezone
from math import floor
from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, status

from app.config import settings
from app.database import execute_query, fetch_all, fetch_one
from app.dependencies import get_current_user
from app.schemas.base import error_response, success_response
from app.schemas.profile import (
    BaristaUsage,
    GiftCodeProfile,
    ProfileResponse,
    QuestionsRemaining,
    UpdateProfileRequest,
    UsageStats,
)

router = APIRouter(prefix="/api/v1/profile", tags=["profile"])


def _get_current_cycle(created_at: datetime) -> tuple[datetime, datetime]:
    """Calculate the current 30-day billing cycle from user creation date."""
    now = datetime.now(timezone.utc)
    if created_at.tzinfo is None:
        created_at = created_at.replace(tzinfo=timezone.utc)
    elapsed = (now - created_at).total_seconds()
    cycle_number = floor(elapsed / (30 * 86400))
    cycle_start = created_at + timedelta(days=cycle_number * 30)
    cycle_end = cycle_start + timedelta(days=30)
    return cycle_start, cycle_end


async def _build_profile(user_id: UUID) -> dict:
    user = await fetch_one(
        """SELECT id, nome, email, plano, trial_end, espm_login, created_at
           FROM users WHERE id = $1""",
        user_id,
    )
    if not user:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail=error_response("NOT_FOUND", "Usuário não encontrado"))

    # Subscription active check
    sub = await fetch_one(
        "SELECT 1 FROM subscriptions WHERE user_id = $1 AND status = 'active'",
        user_id,
    )
    trial_end = user.get("trial_end")
    trial_valid = (
        user["plano"] == "trial"
        and trial_end is not None
        and (trial_end if trial_end.tzinfo else trial_end.replace(tzinfo=timezone.utc)) > datetime.now(timezone.utc)
    )
    from app.plan_limits import is_paid_plan
    subscription_active = (sub is not None and is_paid_plan(user["plano"])) or trial_valid

    # Usage stats: gravacoes
    grav_row = await fetch_one(
        """SELECT COUNT(*) AS total, COALESCE(SUM(duration_seconds), 0) AS total_seconds
           FROM gravacoes WHERE user_id = $1""",
        user_id,
    )
    gravacoes_total = grav_row["total"] if grav_row else 0
    horas_gravadas = round((grav_row["total_seconds"] if grav_row else 0) / 3600.0, 1)

    # Billing cycle
    cycle_start, cycle_end = _get_current_cycle(user["created_at"])

    # Barista v2: budget-based usage
    from app.plan_limits import get_plan_budget
    budget_usd = get_plan_budget(user["plano"])

    budget_row = await fetch_one(
        "SELECT used_usd FROM usage_budget WHERE user_id = $1 AND cycle_start = $2",
        user_id, cycle_start.date() if hasattr(cycle_start, 'date') else cycle_start,
    )
    used_usd = budget_row["used_usd"] if budget_row else 0.0
    remaining_usd = max(0.0, budget_usd - used_usd)
    usage_percent = min(100.0, round((used_usd / budget_usd) * 100, 1)) if budget_usd > 0 else 0.0

    barista_usage = BaristaUsage(
        usage_percent=usage_percent,
        budget_usd=budget_usd,
        used_usd=round(used_usd, 4),
        remaining_usd=round(remaining_usd, 4),
        cycle_reset_at=cycle_end,
    )

    # Legacy questions_remaining (all -1 = unlimited, for old iOS)
    questions = QuestionsRemaining(espresso=-1, lungo=-1, cold_brew=-1)

    usage = UsageStats(
        gravacoes_total=gravacoes_total,
        horas_gravadas=horas_gravadas,
        questions_remaining=questions,
        barista_usage=barista_usage,
        questions_reset_at=cycle_end,
    )

    # Gift codes (for paid plans)
    gift_codes = []
    if is_paid_plan(user["plano"]):
        gc_rows = await fetch_all(
            """SELECT gc.code, gc.redeemed_by IS NOT NULL AS redeemed,
                      u.nome AS redeemed_by_name, gc.redeemed_at
               FROM gift_codes gc
               LEFT JOIN users u ON gc.redeemed_by = u.id
               WHERE gc.owner_id = $1
               ORDER BY gc.created_at""",
            user_id,
        )
        gift_codes = [
            GiftCodeProfile(
                code=r["code"],
                redeemed=r["redeemed"],
                redeemed_by=r["redeemed_by_name"],
                redeemed_at=r["redeemed_at"],
            ).model_dump(mode="json")
            for r in gc_rows
        ]

    return ProfileResponse(
        id=user["id"],
        nome=user["nome"],
        email=user["email"],
        plano=user["plano"],
        trial_end=user.get("trial_end"),
        subscription_active=subscription_active,
        espm_connected=user.get("espm_login") is not None,
        espm_login=user.get("espm_login"),
        usage=usage,
        gift_codes=gift_codes,
        created_at=user["created_at"],
    ).model_dump(mode="json")


@router.get("")
async def get_profile(user_id: UUID = Depends(get_current_user)):
    """Dados completos do perfil com usage stats."""
    return success_response(await _build_profile(user_id))


@router.patch("")
async def update_profile(
    body: UpdateProfileRequest,
    user_id: UUID = Depends(get_current_user),
):
    """Atualizar nome."""
    await execute_query(
        "UPDATE users SET nome = $1, updated_at = NOW() WHERE id = $2",
        body.nome, user_id,
    )
    return success_response(await _build_profile(user_id))
