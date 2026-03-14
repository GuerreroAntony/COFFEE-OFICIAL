"""
FCM Push Notification Service — HTTP v1 API with Google OAuth2.
"""
from __future__ import annotations

import logging
from typing import Any, Optional
from uuid import UUID

import httpx
from google.oauth2 import service_account

from app.config import get_settings

logger = logging.getLogger(__name__)

_FCM_SCOPE = "https://www.googleapis.com/auth/firebase.messaging"
_credentials: Optional[service_account.Credentials] = None


def _get_access_token() -> str:
    """Get a fresh OAuth2 access token for FCM."""
    global _credentials
    cfg = get_settings()

    if _credentials is None:
        _credentials = service_account.Credentials.from_service_account_file(
            cfg.GOOGLE_APPLICATION_CREDENTIALS,
            scopes=[_FCM_SCOPE],
        )

    if not _credentials.valid:
        from google.auth.transport.requests import Request
        _credentials.refresh(Request())

    return _credentials.token


async def send_push(
    token: str,
    title: str,
    body: str,
    data: Optional[dict[str, str]] = None,
) -> bool:
    """Send a push notification to a single FCM token.

    Returns True on success, False on failure.
    """
    cfg = get_settings()
    if not cfg.FIREBASE_PROJECT_ID:
        logger.warning("FIREBASE_PROJECT_ID not set, skipping push")
        return False

    access_token = _get_access_token()
    url = (
        f"https://fcm.googleapis.com/v1/projects/"
        f"{cfg.FIREBASE_PROJECT_ID}/messages:send"
    )

    message: dict[str, Any] = {
        "message": {
            "token": token,
            "notification": {"title": title, "body": body},
            "apns": {
                "payload": {
                    "aps": {"sound": "default", "badge": 1}
                }
            },
        }
    }
    if data:
        message["message"]["data"] = data

    async with httpx.AsyncClient() as client:
        resp = await client.post(
            url,
            json=message,
            headers={"Authorization": f"Bearer {access_token}"},
            timeout=10,
        )

    if resp.status_code == 200:
        return True

    logger.error("FCM push failed (%d): %s", resp.status_code, resp.text)
    return False


async def send_push_to_user(
    user_id: UUID,
    title: str,
    body: str,
    data: Optional[dict[str, str]] = None,
) -> int:
    """Send push to all device tokens for a user.

    Removes invalid tokens automatically.
    Returns number of successful sends.
    """
    from app.database import fetch_all, execute_query

    rows = await fetch_all(
        "SELECT id, fcm_token FROM device_tokens WHERE user_id = $1",
        user_id,
    )
    if not rows:
        return 0

    sent = 0
    for row in rows:
        success = await send_push(row["fcm_token"], title, body, data)
        if success:
            sent += 1
        else:
            await execute_query(
                "DELETE FROM device_tokens WHERE id = $1", row["id"]
            )
            logger.info("Removed invalid FCM token for user %s", user_id)

    return sent
