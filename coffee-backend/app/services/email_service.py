"""Email service — SendGrid (HTTP API) with SMTP fallback."""
import asyncio
import logging

import httpx

from app.config import settings

logger = logging.getLogger(__name__)

SENDGRID_URL = "https://api.sendgrid.com/v3/mail/send"


async def _sendgrid_send(to_email: str, subject: str, body: str, reply_to: str | None = None) -> bool:
    """Send email via SendGrid HTTP API."""
    if not settings.SENDGRID_API_KEY:
        return False

    payload = {
        "personalizations": [{"to": [{"email": to_email}]}],
        "from": {"email": settings.SENDGRID_FROM_EMAIL, "name": "Coffee App"},
        "subject": subject,
        "content": [{"type": "text/plain", "value": body}],
    }
    if reply_to:
        payload["reply_to"] = {"email": reply_to}

    try:
        async with httpx.AsyncClient(timeout=15) as client:
            resp = await client.post(
                SENDGRID_URL,
                json=payload,
                headers={
                    "Authorization": f"Bearer {settings.SENDGRID_API_KEY}",
                    "Content-Type": "application/json",
                },
            )
        if resp.status_code in (200, 201, 202):
            logger.info("Email sent via SendGrid to %s", to_email)
            return True
        else:
            logger.error("SendGrid error %s: %s", resp.status_code, resp.text)
            return False
    except Exception as exc:
        logger.error("SendGrid request failed: %s", exc)
        return False


async def _smtp_send(to_email: str, subject: str, body: str, reply_to: str | None = None) -> bool:
    """Fallback: send via SMTP (Hostinger). May fail if ports are blocked."""
    if not (settings.SMTP_HOST and settings.SMTP_USER):
        return False

    try:
        import aiosmtplib
        from email.message import EmailMessage

        msg = EmailMessage()
        msg["From"] = settings.SMTP_USER
        msg["To"] = to_email
        msg["Subject"] = subject
        if reply_to:
            msg["Reply-To"] = reply_to
        msg.set_content(body)

        # Try port 465 (TLS) then 587 (STARTTLS)
        for port, kw in [(465, {"use_tls": True}), (587, {"start_tls": True})]:
            try:
                await aiosmtplib.send(
                    msg,
                    hostname=settings.SMTP_HOST,
                    port=port,
                    username=settings.SMTP_USER,
                    password=settings.SMTP_PASSWORD,
                    timeout=15,
                    **kw,
                )
                logger.info("Email sent via SMTP port %d to %s", port, to_email)
                return True
            except Exception:
                continue
    except Exception as exc:
        logger.error("SMTP send failed: %s", exc)
    return False


async def _send_email(to_email: str, subject: str, body: str, reply_to: str | None = None) -> bool:
    """Try SendGrid first, then SMTP, then log as fallback."""
    if await _sendgrid_send(to_email, subject, body, reply_to):
        return True
    if await _smtp_send(to_email, subject, body, reply_to):
        return True
    logger.warning("All email methods failed for %s — logging only", to_email)
    return False


async def send_support_email(user_email: str, user_nome: str, subject: str, message: str) -> bool:
    """Send support email."""
    full_body = (
        f"De: {user_nome} ({user_email})\n"
        f"Assunto: {subject}\n"
        f"---\n"
        f"{message}\n"
    )

    sent = await _send_email(
        to_email=settings.SUPPORT_EMAIL,
        subject=f"[Coffee Support] {subject}",
        body=full_body,
        reply_to=user_email,
    )
    if not sent:
        logger.info("Support email (fallback log):\nTo: %s\n%s", settings.SUPPORT_EMAIL, full_body)
    return True


async def send_password_reset_email(to_email: str, code: str) -> bool:
    """Send password reset email with 6-digit code."""
    body = (
        f"Seu codigo de recuperacao de senha do Coffee:\n\n"
        f"    {code}\n\n"
        f"Este codigo expira em 15 minutos.\n"
        f"Se voce nao solicitou a recuperacao, ignore este email.\n"
    )

    sent = await _send_email(
        to_email=to_email,
        subject="[Coffee] Recuperacao de senha",
        body=body,
    )
    if not sent:
        logger.info("Password reset code for %s: %s (fallback log)", to_email, code)
    return True
