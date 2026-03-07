import random
import string
from datetime import datetime, timedelta, timezone
from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, status

from app.database import execute_query, fetch_one
from app.dependencies import get_current_user
from app.schemas.auth import (
    AuthResponse,
    ForgotPasswordRequest,
    LoginRequest,
    LogoutRequest,
    SignupRequest,
    TokenResponse,
    UserResponse,
)
from app.schemas.base import error_response, success_response
from app.utils.security import create_jwt, hash_password, verify_password

router = APIRouter(prefix="/api/v1/auth", tags=["auth"])


async def _build_user_response(user_row) -> dict:
    """Build expanded UserResponse from a user DB row."""
    # Check subscription_active
    sub = await fetch_one(
        "SELECT 1 FROM subscriptions WHERE user_id = $1 AND status = 'active'",
        user_row["id"],
    )
    subscription_active = sub is not None and user_row["plano"] == "premium"

    espm_connected = user_row.get("espm_login") is not None

    return UserResponse(
        id=user_row["id"],
        nome=user_row["nome"],
        email=user_row["email"],
        plano=user_row["plano"],
        trial_end=user_row.get("trial_end"),
        subscription_active=subscription_active,
        espm_connected=espm_connected,
        referral_code=user_row.get("referral_code"),
        created_at=user_row["created_at"],
    ).model_dump(mode="json")


def _generate_referral_code(nome: str) -> str:
    """Generate referral code: first 5 chars uppercase + year."""
    clean = "".join(c for c in nome if c.isalpha())[:5].upper()
    if len(clean) < 3:
        clean = clean.ljust(3, "X")
    year = datetime.now().year
    return f"{clean}{year}"


# ── POST /signup ─────────────────────────────────────────────

@router.post("/signup", status_code=status.HTTP_201_CREATED)
async def signup(body: SignupRequest):
    existing = await fetch_one(
        "SELECT id FROM users WHERE email = $1",
        body.email,
    )
    if existing:
        raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail=error_response("EMAIL_EXISTS", "Email já cadastrado"))

    password_hash = hash_password(body.password)
    trial_end = datetime.now(timezone.utc) + timedelta(days=7)

    # Generate unique referral_code
    base_code = _generate_referral_code(body.nome)
    referral_code = base_code
    for _ in range(10):
        conflict = await fetch_one(
            "SELECT 1 FROM users WHERE referral_code = $1", referral_code
        )
        if not conflict:
            break
        suffix = "".join(random.choices(string.digits, k=3))
        referral_code = f"{base_code}{suffix}"

    user = await fetch_one(
        """INSERT INTO users (nome, email, password_hash, plano, trial_end, referral_code)
           VALUES ($1, $2, $3, 'trial', $4, $5)
           RETURNING id, nome, email, plano, trial_end, espm_login, referral_code, created_at""",
        body.nome, body.email, password_hash, trial_end, referral_code,
    )

    # Create user_settings with defaults
    await execute_query(
        "INSERT INTO user_settings (user_id) VALUES ($1)",
        user["id"],
    )

    # Handle referral code if provided
    if body.referral_code:
        referrer = await fetch_one(
            "SELECT id FROM users WHERE referral_code = $1",
            body.referral_code,
        )
        if referrer:
            # Create referral record
            await execute_query(
                """INSERT INTO referrals (referrer_id, referred_id, code)
                   VALUES ($1, $2, $3)""",
                referrer["id"], user["id"], body.referral_code,
            )
            # Add +7 days to referrer's trial_end
            await execute_query(
                """UPDATE users SET trial_end = COALESCE(trial_end, NOW()) + INTERVAL '7 days'
                   WHERE id = $1""",
                referrer["id"],
            )

    token = create_jwt(user["id"])
    user_resp = await _build_user_response(user)
    return success_response(AuthResponse(user=user_resp, token=token).model_dump(mode="json"))


# ── POST /login ──────────────────────────────────────────────

@router.post("/login")
async def login(body: LoginRequest):
    user = await fetch_one(
        """SELECT id, nome, email, password_hash, plano, trial_end,
                  espm_login, referral_code, created_at
           FROM users WHERE email = $1""",
        body.email,
    )
    if not user:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail=error_response("NOT_FOUND", "Usuário não encontrado"))

    if not verify_password(body.password, user["password_hash"]):
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail=error_response("INVALID_CREDENTIALS", "Credenciais inválidas"))

    token = create_jwt(user["id"])
    user_resp = await _build_user_response(user)
    return success_response(AuthResponse(user=user_resp, token=token).model_dump(mode="json"))


# ── POST /logout ─────────────────────────────────────────────

@router.post("/logout")
async def logout(
    body: LogoutRequest,
    user_id: UUID = Depends(get_current_user),
):
    if body.device_token:
        await execute_query(
            "DELETE FROM device_tokens WHERE fcm_token = $1 AND user_id = $2",
            body.device_token, user_id,
        )
    else:
        await execute_query(
            "DELETE FROM device_tokens WHERE user_id = $1",
            user_id,
        )
    return success_response(None)


# ── POST /forgot-password ────────────────────────────────────

@router.post("/forgot-password")
async def forgot_password(body: ForgotPasswordRequest):
    # Always return 200 for security — don't reveal if email exists
    # TODO: integrate with Supabase Auth password reset or email service
    return success_response({"message": "Se o email existir, enviaremos instruções de recuperação."})


# ── POST /refresh ────────────────────────────────────────────

@router.post("/refresh")
async def refresh(user_id: UUID = Depends(get_current_user)):
    token = create_jwt(user_id)
    return success_response(TokenResponse(token=token).model_dump(mode="json"))


# ── GET /me ──────────────────────────────────────────────────

@router.get("/me")
async def me(user_id: UUID = Depends(get_current_user)):
    user = await fetch_one(
        """SELECT id, nome, email, plano, trial_end,
                  espm_login, referral_code, created_at
           FROM users WHERE id = $1""",
        user_id,
    )
    if not user:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail=error_response("NOT_FOUND", "Usuário não encontrado"))

    user_resp = await _build_user_response(user)
    return success_response(user_resp)
