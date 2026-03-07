from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, status

from app.config import settings
from app.database import execute_query, fetch_one
from app.dependencies import get_current_user
from app.schemas.base import error_response, success_response
from app.schemas.profile import ProfileResponse, UpdateProfileRequest, UsageStats

router = APIRouter(prefix="/api/v1/profile", tags=["profile"])


async def _build_profile(user_id: UUID) -> dict:
    user = await fetch_one(
        """SELECT id, nome, email, plano, trial_end, espm_login, referral_code, created_at
           FROM users WHERE id = $1""",
        user_id,
    )
    if not user:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail=error_response("NOT_FOUND", "Usuário não encontrado"))

    # Referrals count
    ref_row = await fetch_one(
        "SELECT COUNT(*) AS cnt FROM referrals WHERE referrer_id = $1", user_id
    )
    referrals_count = ref_row["cnt"] if ref_row else 0

    # Usage stats
    grav_row = await fetch_one(
        """SELECT COUNT(*) AS total, COALESCE(SUM(duration_seconds), 0) AS total_seconds
           FROM gravacoes WHERE user_id = $1""",
        user_id,
    )
    gravacoes_total = grav_row["total"] if grav_row else 0
    horas_gravadas = round((grav_row["total_seconds"] if grav_row else 0) / 3600.0, 1)

    perguntas_row = await fetch_one(
        """SELECT COUNT(*) AS cnt FROM mensagens m
           JOIN chats c ON m.chat_id = c.id
           WHERE c.user_id = $1 AND m.role = 'user'
             AND m.created_at >= CURRENT_DATE""",
        user_id,
    )
    perguntas_hoje = perguntas_row["cnt"] if perguntas_row else 0
    perguntas_limite = settings.QUESTION_LIMIT_TRIAL if user["plano"] == "trial" else settings.QUESTION_LIMIT_PREMIUM

    usage = UsageStats(
        gravacoes_total=gravacoes_total,
        horas_gravadas=horas_gravadas,
        perguntas_hoje=perguntas_hoje,
        perguntas_limite=perguntas_limite,
    )

    return ProfileResponse(
        id=user["id"],
        nome=user["nome"],
        email=user["email"],
        plano=user["plano"],
        trial_end=user.get("trial_end"),
        espm_connected=user.get("espm_login") is not None,
        referral_code=user.get("referral_code"),
        referrals_count=referrals_count,
        usage=usage,
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
