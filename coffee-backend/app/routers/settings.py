from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException

from app.database import fetch_one
from app.dependencies import get_current_user
from app.schemas.base import error_response, success_response
from app.schemas.settings import SettingsResponse

router = APIRouter(prefix="/api/v1/settings", tags=["settings"])


@router.get("")
async def get_settings(user_id: UUID = Depends(get_current_user)):
    """Retorna status de conexão ESPM."""
    row = await fetch_one(
        "SELECT espm_login FROM users WHERE id = $1",
        user_id,
    )
    if not row:
        raise HTTPException(status_code=404, detail=error_response("NOT_FOUND", "Usuário não encontrado"))

    resp = SettingsResponse(
        espm_connected=row["espm_login"] is not None,
        espm_login=row["espm_login"],
    )
    return success_response(resp.model_dump(mode="json"))
