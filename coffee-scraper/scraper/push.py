"""
Lightweight FCM push sender for the scraper.
Uses Google OAuth2 + FCM HTTP v1 API.
"""
from __future__ import annotations

import logging
from typing import Any, Optional

import httpx
from google.oauth2 import service_account

from scraper.config import settings

logger = logging.getLogger(__name__)

_FCM_SCOPE = "https://www.googleapis.com/auth/firebase.messaging"
_credentials: Optional[service_account.Credentials] = None


def _get_access_token() -> str:
    """Get a fresh OAuth2 access token for FCM."""
    global _credentials

    if _credentials is None:
        _credentials = service_account.Credentials.from_service_account_file(
            settings.GOOGLE_APPLICATION_CREDENTIALS,
            scopes=[_FCM_SCOPE],
        )

    if not _credentials.valid:
        from google.auth.transport.requests import Request
        _credentials.refresh(Request())

    return _credentials.token


async def send_fcm_push(
    token: str,
    title: str,
    body: str,
    data: Optional[dict[str, str]] = None,
) -> bool:
    """Send a single FCM push notification. Returns True on success."""
    if not settings.FIREBASE_PROJECT_ID:
        logger.warning("FIREBASE_PROJECT_ID not set, skipping push")
        return False

    access_token = _get_access_token()
    url = (
        f"https://fcm.googleapis.com/v1/projects/"
        f"{settings.FIREBASE_PROJECT_ID}/messages:send"
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
