"""
Device token management for push notifications.
"""
from __future__ import annotations

from uuid import UUID

from fastapi import APIRouter, Depends, status
from pydantic import BaseModel

from app.database import execute_query
from app.dependencies import get_current_user
from app.schemas.base import success_response

router = APIRouter(prefix="/api/v1/devices", tags=["devices"])


class DeviceTokenRequest(BaseModel):
    token: str
    platform: str = "ios"


@router.post("", status_code=status.HTTP_201_CREATED)
async def register_device(
    body: DeviceTokenRequest,
    user_id: UUID = Depends(get_current_user),
):
    """Register or update an FCM device token."""
    await execute_query(
        """INSERT INTO device_tokens (user_id, fcm_token, platform)
           VALUES ($1, $2, $3)
           ON CONFLICT (fcm_token)
           DO UPDATE SET user_id = $1, platform = $3, updated_at = NOW()""",
        user_id,
        body.token,
        body.platform,
    )
    return success_response(None, "Device registrado")


@router.delete("/{token}")
async def unregister_device(
    token: str,
    user_id: UUID = Depends(get_current_user),
):
    """Unregister a device token (e.g. on logout)."""
    await execute_query(
        "DELETE FROM device_tokens WHERE fcm_token = $1 AND user_id = $2",
        token,
        user_id,
    )
    return success_response(None, "Device removido")
