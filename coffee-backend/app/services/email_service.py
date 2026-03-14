"""Email service for sending support emails."""
import logging

import httpx

from app.config import settings

logger = logging.getLogger(__name__)


async def send_support_email(user_email: str, user_nome: str, subject: str, message: str) -> bool:
    """
    Send support email. Uses SMTP if configured, otherwise logs the message.
    Returns True if sent successfully (or logged as fallback).
    """
    full_body = (
        f"De: {user_nome} ({user_email})\n"
        f"Assunto: {subject}\n"
        f"---\n"
        f"{message}\n"
    )

    if settings.SMTP_HOST and settings.SMTP_USER:
        try:
            import aiosmtplib
            from email.message import EmailMessage

            msg = EmailMessage()
            msg["From"] = settings.SMTP_USER
            msg["To"] = settings.SUPPORT_EMAIL
            msg["Subject"] = f"[Coffee Support] {subject}"
            msg["Reply-To"] = user_email
            msg.set_content(full_body)

            await aiosmtplib.send(
                msg,
                hostname=settings.SMTP_HOST,
                port=settings.SMTP_PORT,
                username=settings.SMTP_USER,
                password=settings.SMTP_PASSWORD,
                use_tls=True,
            )
            return True
        except Exception as exc:
            logger.error("Failed to send support email via SMTP: %s", exc)
            # Fall through to log

    # Fallback: log the message
    logger.info("Support email (no SMTP configured):\nTo: %s\n%s", settings.SUPPORT_EMAIL, full_body)
    return True
