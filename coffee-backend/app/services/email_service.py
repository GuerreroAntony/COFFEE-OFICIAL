"""Email service for sending support emails."""
import asyncio
import logging

import httpx

from app.config import settings

logger = logging.getLogger(__name__)


async def _smtp_send(msg) -> bool:
    """Try to send email via SMTP. Tries port 465 (TLS) then 587 (STARTTLS)."""
    import aiosmtplib

    # Attempt 1: port 465 with implicit TLS
    try:
        await aiosmtplib.send(
            msg,
            hostname=settings.SMTP_HOST,
            port=465,
            username=settings.SMTP_USER,
            password=settings.SMTP_PASSWORD,
            use_tls=True,
            timeout=15,
        )
        logger.info("Email sent via port 465 (TLS)")
        return True
    except Exception as exc:
        logger.warning("SMTP port 465 failed: %s. Trying 587...", exc)

    # Attempt 2: port 587 with STARTTLS
    try:
        await aiosmtplib.send(
            msg,
            hostname=settings.SMTP_HOST,
            port=587,
            username=settings.SMTP_USER,
            password=settings.SMTP_PASSWORD,
            start_tls=True,
            timeout=15,
        )
        logger.info("Email sent via port 587 (STARTTLS)")
        return True
    except Exception as exc:
        logger.error("SMTP port 587 also failed: %s", exc)
        return False


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
            from email.message import EmailMessage

            msg = EmailMessage()
            msg["From"] = settings.SMTP_USER
            msg["To"] = settings.SUPPORT_EMAIL
            msg["Subject"] = f"[Coffee Support] {subject}"
            msg["Reply-To"] = user_email
            msg.set_content(full_body)

            sent = await _smtp_send(msg)
            if sent:
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
            from email.message import EmailMessage

            msg = EmailMessage()
            msg["From"] = settings.SMTP_USER
            msg["To"] = to_email
            msg["Subject"] = "[Coffee] Recuperacao de senha"
            msg.set_content(body)

            sent = await _smtp_send(msg)
            if sent:
                logger.info("Password reset email sent to %s", to_email)
                return True
        except Exception as exc:
            logger.error("Failed to send password reset email via SMTP: %s", exc)

    # Fallback: log the code (dev/staging)
    logger.info("Password reset code for %s: %s", to_email, code)
    return True
