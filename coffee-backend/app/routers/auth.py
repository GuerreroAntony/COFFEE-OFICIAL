import hashlib
from datetime import datetime, timedelta, timezone
from typing import Optional
from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, Request, status

from app.config import settings
from app.database import execute_query, fetch_one
from app.dependencies import get_current_user
from app.schemas.auth import (
    AuthResponse,
    ForgotPasswordRequest,
    LoginRequest,
    LogoutRequest,
    ResetPasswordRequest,
    SignupRequest,
    TokenResponse,
    UserResponse,
)
from app.schemas.base import error_response, success_response
from app.services.email_service import send_password_reset_email
from app.utils.security import create_jwt, decode_jwt, hash_password, verify_password

router = APIRouter(prefix="/api/v1/auth", tags=["auth"])


async def _build_user_response(user_row) -> dict:
    """Build expanded UserResponse from a user DB row."""
    sub = await fetch_one(
        "SELECT 1 FROM subscriptions WHERE user_id = $1 AND status = 'active'",
        user_row["id"],
    )
    # Active if premium with subscription OR trial still valid
    trial_end = user_row.get("trial_end")
    trial_valid = (
        user_row["plano"] == "trial"
        and trial_end is not None
        and (trial_end if trial_end.tzinfo else trial_end.replace(tzinfo=timezone.utc)) > datetime.now(timezone.utc)
    )
    subscription_active = (sub is not None and user_row["plano"] == "premium") or trial_valid
    espm_connected = user_row.get("espm_login") is not None

    return UserResponse(
        id=user_row["id"],
        nome=user_row["nome"],
        email=user_row["email"],
        plano=user_row["plano"],
        trial_end=user_row.get("trial_end"),
        subscription_active=subscription_active,
        espm_connected=espm_connected,
        created_at=user_row["created_at"],
    ).model_dump(mode="json")


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
    trial_days = settings.TRIAL_DAYS

    # Validate gift code if provided
    if body.gift_code:
        gc = await fetch_one(
            "SELECT id, owner_id FROM gift_codes WHERE code = $1 AND redeemed_by IS NULL",
            body.gift_code,
        )
        if not gc:
            raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail=error_response("INVALID_CODE", "Código não encontrado ou já utilizado"))
        trial_days += settings.GIFT_CODE_BONUS_DAYS

    trial_end = datetime.now(timezone.utc) + timedelta(days=trial_days)

    user = await fetch_one(
        """INSERT INTO users (nome, email, password_hash, plano, trial_end)
           VALUES ($1, $2, $3, 'trial', $4)
           RETURNING id, nome, email, plano, trial_end, espm_login, created_at""",
        body.nome, body.email, password_hash, trial_end,
    )

    # Mark gift code as redeemed
    if body.gift_code:
        await execute_query(
            "UPDATE gift_codes SET redeemed_by = $1, redeemed_at = NOW() WHERE code = $2",
            user["id"], body.gift_code,
        )

    token = create_jwt(user["id"])
    user_resp = await _build_user_response(user)
    return success_response(AuthResponse(user=user_resp, token=token).model_dump(mode="json"))


# ── POST /login ──────────────────────────────────────────────

@router.post("/login")
async def login(body: LoginRequest):
    user = await fetch_one(
        """SELECT id, nome, email, password_hash, plano, trial_end,
                  espm_login, created_at
           FROM users WHERE email = $1""",
        body.email,
    )
    if not user or not verify_password(body.password, user["password_hash"]):
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail=error_response("INVALID_CREDENTIALS", "Email ou senha incorretos"))

    token = create_jwt(user["id"])
    user_resp = await _build_user_response(user)
    return success_response(AuthResponse(user=user_resp, token=token).model_dump(mode="json"))


# ── POST /logout ─────────────────────────────────────────────

@router.post("/logout")
async def logout(
    request: Request,
    user_id: UUID = Depends(get_current_user),
    body: Optional[LogoutRequest] = None,
):
    # Blacklist current token
    token = request.headers.get("Authorization", "").replace("Bearer ", "")
    if token:
        token_hash = hashlib.sha256(token.encode()).hexdigest()
        payload = decode_jwt(token)
        exp = datetime.fromtimestamp(payload["exp"], tz=timezone.utc)
        await execute_query(
            "INSERT INTO token_blacklist (token_hash, expires_at) VALUES ($1, $2)",
            token_hash, exp,
        )

    if body and body.device_token:
        await execute_query(
            "DELETE FROM device_tokens WHERE fcm_token = $1 AND user_id = $2",
            body.device_token, user_id,
        )
    else:
        await execute_query(
            "DELETE FROM device_tokens WHERE user_id = $1",
            user_id,
        )
    return success_response(None, "Logged out")


# ── POST /forgot-password ────────────────────────────────────

@router.post("/forgot-password")
async def forgot_password(body: ForgotPasswordRequest):
    """Gera código de 6 dígitos e envia por email. Sempre retorna 200."""
    import secrets

    user = await fetch_one("SELECT id FROM users WHERE email = $1", body.email.lower())

    if user:
        code = f"{secrets.randbelow(1000000):06d}"
        code_hash = hashlib.sha256(code.encode()).hexdigest()
        expires = datetime.now(timezone.utc) + timedelta(minutes=15)

        await execute_query(
            "UPDATE users SET reset_code_hash = $1, reset_code_expires = $2 WHERE id = $3",
            code_hash, expires, user["id"],
        )

        await send_password_reset_email(body.email, code)

    # Always return 200 — don't reveal if email exists
    return success_response(None, "Se o email existir, enviaremos instrucoes de recuperacao.")


# ── POST /reset-password ────────────────────────────────────

@router.post("/reset-password")
async def reset_password(body: ResetPasswordRequest):
    """Valida código de reset e atualiza senha."""
    user = await fetch_one(
        "SELECT id, reset_code_hash, reset_code_expires FROM users WHERE email = $1",
        body.email.lower(),
    )

    if not user or not user["reset_code_hash"]:
        raise HTTPException(status_code=400, detail=error_response("INVALID_CODE", "Codigo invalido ou expirado"))

    # Check expiry
    expires = user["reset_code_expires"]
    if expires.tzinfo is None:
        expires = expires.replace(tzinfo=timezone.utc)
    if datetime.now(timezone.utc) > expires:
        await execute_query(
            "UPDATE users SET reset_code_hash = NULL, reset_code_expires = NULL WHERE id = $1",
            user["id"],
        )
        raise HTTPException(status_code=400, detail=error_response("CODE_EXPIRED", "Codigo expirado. Solicite um novo."))

    # Verify code
    code_hash = hashlib.sha256(body.code.encode()).hexdigest()
    if code_hash != user["reset_code_hash"]:
        raise HTTPException(status_code=400, detail=error_response("INVALID_CODE", "Codigo invalido ou expirado"))

    # Update password and clear reset code
    new_hash = hash_password(body.new_password)
    await execute_query(
        "UPDATE users SET password_hash = $1, reset_code_hash = NULL, reset_code_expires = NULL, updated_at = NOW() WHERE id = $2",
        new_hash, user["id"],
    )

    return success_response(None, "Senha atualizada com sucesso.")


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
                  espm_login, created_at
           FROM users WHERE id = $1""",
        user_id,
    )
    if not user:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail=error_response("NOT_FOUND", "Usuário não encontrado"))

    user_resp = await _build_user_response(user)
    return success_response(user_resp)
