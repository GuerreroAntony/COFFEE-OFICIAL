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


async def send_password_reset_email(to_email: str, code: str) -> bool:
    """
    Send password reset email with 6-digit code.
    Uses SMTP if configured, otherwise logs the code.
    """
    body = (
        f"Seu codigo de recuperacao de senha do Coffee:\n\n"
        f"    {code}\n\n"
        f"Este codigo expira em 15 minutos.\n"
        f"Se voce nao solicitou a recuperacao, ignore este email.\n"
    )

    if settings.SMTP_HOST and settings.SMTP_USER:
        try:
            import aiosmtplib
            from email.message import EmailMessage

            msg = EmailMessage()
            msg["From"] = settings.SMTP_USER
            msg["To"] = to_email
            msg["Subject"] = "[Coffee] Recuperacao de senha"
            msg.set_content(body)

            await aiosmtplib.send(
                msg,
                hostname=settings.SMTP_HOST,
                port=settings.SMTP_PORT,
                username=settings.SMTP_USER,
                password=settings.SMTP_PASSWORD,
                use_tls=True,
            )
            logger.info("Password reset email sent to %s", to_email)
            return True
        except Exception as exc:
            logger.error("Failed to send password reset email via SMTP: %s", exc)

    # Fallback: log the code (dev/staging)
    logger.info("Password reset code for %s: %s", to_email, code)
    return True
