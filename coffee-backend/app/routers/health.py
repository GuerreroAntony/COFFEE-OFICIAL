from datetime import datetime, timezone

from fastapi import APIRouter

from app.schemas.base import success_response

router = APIRouter(tags=["health"])


@router.get("/health")
async def health_check():
    return success_response({
        "status": "ok",
        "timestamp": datetime.now(timezone.utc).isoformat(),
    })


@router.get("/health/smtp")
async def smtp_check():
    """Temporary debug endpoint to check SMTP config. Remove after verifying."""
    from app.config import settings
    return success_response({
        "smtp_host": settings.SMTP_HOST or "(empty)",
        "smtp_port": settings.SMTP_PORT,
        "smtp_user": settings.SMTP_USER or "(empty)",
        "smtp_password_set": bool(settings.SMTP_PASSWORD),
        "support_email": settings.SUPPORT_EMAIL,
    })
