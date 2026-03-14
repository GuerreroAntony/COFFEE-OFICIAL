import hashlib
from datetime import datetime, timezone
from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, Request

from app.database import execute_query, fetch_all, fetch_one
from app.dependencies import get_current_user
from app.schemas.account import DeleteAccountRequest, SupportContactRequest
from app.schemas.base import error_response, success_response
from app.services.email_service import send_support_email
from app.utils.security import decode_jwt

router = APIRouter(prefix="/api/v1", tags=["account"])


@router.delete("/account")
async def delete_account(
    body: DeleteAccountRequest,
    request: Request,
    user_id: UUID = Depends(get_current_user),
):
    """Delete user account and all associated data (LGPD compliance)."""
    if not body.confirm:
        raise HTTPException(status_code=422, detail=error_response("VALIDATION_ERROR", "Confirmação necessária"))

    # Verify user exists
    user = await fetch_one("SELECT id FROM users WHERE id = $1", user_id)
    if not user:
        raise HTTPException(status_code=404, detail=error_response("NOT_FOUND", "Usuário não encontrado"))

    # Blacklist current JWT
    token = request.headers.get("Authorization", "").replace("Bearer ", "")
    if token:
        token_hash = hashlib.sha256(token.encode()).hexdigest()
        payload = decode_jwt(token)
        exp = datetime.fromtimestamp(payload["exp"], tz=timezone.utc)
        await execute_query(
            "INSERT INTO token_blacklist (token_hash, expires_at) VALUES ($1, $2)",
            token_hash, exp,
        )

    # Cascade delete: FK ON DELETE CASCADE handles most tables
    # (gravacoes, chats, device_tokens, notificacoes, user_disciplinas,
    #  compartilhamentos, gift_codes, subscriptions, gravacao_media via gravacoes)
    # Embeddings need manual cleanup since they reference fonte_id not user_id
    await execute_query(
        """DELETE FROM embeddings WHERE fonte_id IN (
               SELECT id FROM gravacoes WHERE user_id = $1
           )""",
        user_id,
    )

    # Delete user (cascades everything else)
    await execute_query("DELETE FROM users WHERE id = $1", user_id)

    return success_response(None, "Conta excluida com sucesso")


@router.post("/support/contact")
async def support_contact(
    body: SupportContactRequest,
    user_id: UUID = Depends(get_current_user),
):
    """Send support message via email."""
    user = await fetch_one(
        "SELECT nome, email FROM users WHERE id = $1", user_id
    )
    if not user:
        raise HTTPException(status_code=404, detail=error_response("NOT_FOUND", "Usuário não encontrado"))

    await send_support_email(
        user_email=user["email"],
        user_nome=user["nome"],
        subject=body.subject,
        message=body.message,
    )

    return success_response(None, "Mensagem enviada com sucesso")
