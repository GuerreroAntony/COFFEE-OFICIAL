"""
Calendar notification service — sends push notifications for upcoming events.

Runs periodically (called from processing_loop or standalone).
Sends notifications:
  - 24h before: "Amanhã: {title}"
  - 1h before: "Em 1 hora: {title}"

Only notifies Black/Trial users (calendar is gated).
"""

import logging
from datetime import datetime, timedelta, timezone

from app.database import execute_query, fetch_all

logger = logging.getLogger("coffee.calendar_notifications")


async def check_and_send_calendar_notifications() -> dict:
    """
    Check for upcoming calendar events and send push notifications.

    Returns: {"notified_1d": int, "notified_1h": int}
    """
    now = datetime.now(timezone.utc)
    sent_1d = 0
    sent_1h = 0

    # --- 24h notifications ---
    # Events starting between 23h and 25h from now that haven't been notified
    window_1d_start = now + timedelta(hours=23)
    window_1d_end = now + timedelta(hours=25)

    events_1d = await fetch_all(
        """
        SELECT ce.id, ce.user_id, ce.title, ce.event_type, ce.start_at,
               ce.course_name, ce.disciplina_id,
               COALESCE(d.nome, ce.course_name, '') AS disciplina_nome
        FROM calendar_events ce
        LEFT JOIN disciplinas d ON d.id = ce.disciplina_id
        JOIN users u ON u.id = ce.user_id
        WHERE ce.notified_1d = false
          AND ce.start_at BETWEEN $1 AND $2
          AND ce.completed = false
          AND u.plano IN ('black', 'trial')
        ORDER BY ce.start_at
        """,
        window_1d_start,
        window_1d_end,
    )

    for event in events_1d:
        try:
            await _send_event_notification(
                event, notification_type="1d"
            )
            await execute_query(
                "UPDATE calendar_events SET notified_1d = true WHERE id = $1",
                event["id"],
            )
            sent_1d += 1
        except Exception as e:
            logger.warning(
                "Failed to send 1d notification for event %s: %s",
                event["id"], e,
            )

    # --- 1h notifications ---
    # Events starting between 50min and 70min from now that haven't been notified
    window_1h_start = now + timedelta(minutes=50)
    window_1h_end = now + timedelta(minutes=70)

    events_1h = await fetch_all(
        """
        SELECT ce.id, ce.user_id, ce.title, ce.event_type, ce.start_at,
               ce.course_name, ce.disciplina_id,
               COALESCE(d.nome, ce.course_name, '') AS disciplina_nome
        FROM calendar_events ce
        LEFT JOIN disciplinas d ON d.id = ce.disciplina_id
        JOIN users u ON u.id = ce.user_id
        WHERE ce.notified_1h = false
          AND ce.start_at BETWEEN $1 AND $2
          AND ce.completed = false
          AND u.plano IN ('black', 'trial')
        ORDER BY ce.start_at
        """,
        window_1h_start,
        window_1h_end,
    )

    for event in events_1h:
        try:
            await _send_event_notification(
                event, notification_type="1h"
            )
            await execute_query(
                "UPDATE calendar_events SET notified_1h = true WHERE id = $1",
                event["id"],
            )
            sent_1h += 1
        except Exception as e:
            logger.warning(
                "Failed to send 1h notification for event %s: %s",
                event["id"], e,
            )

    if sent_1d or sent_1h:
        logger.info(
            "[calendar_notifications] sent: 1d=%d, 1h=%d", sent_1d, sent_1h
        )

    return {"notified_1d": sent_1d, "notified_1h": sent_1h}


async def _send_event_notification(event: dict, notification_type: str) -> None:
    """Send push + save to notificacoes table for a single event."""
    from app.services.push_service import send_push_to_user

    user_id = event["user_id"]
    title_text = event["title"]
    event_type = event["event_type"]
    disciplina = event["disciplina_nome"]
    start_at: datetime = event["start_at"]

    # Format time
    hour_str = start_at.strftime("%H:%M")

    # Build notification content
    type_labels = {
        "assignment": "Atividade",
        "quiz": "Quiz",
        "exam": "Prova",
        "deadline": "Prazo",
        "event": "Evento",
        "reminder": "Lembrete",
    }
    type_label = type_labels.get(event_type, "Evento")

    if notification_type == "1d":
        push_title = f"Amanhã: {title_text}"
        push_body = f"{type_label} às {hour_str}"
        if disciplina:
            push_body += f" · {disciplina}"
    else:
        push_title = f"Em 1 hora: {title_text}"
        push_body = f"{type_label} às {hour_str}"
        if disciplina:
            push_body += f" · {disciplina}"

    # Save to notificacoes table
    await execute_query(
        """
        INSERT INTO notificacoes (user_id, tipo, titulo, corpo, disciplina_id, data_payload)
        VALUES ($1, 'calendario', $2, $3, $4, $5::jsonb)
        """,
        user_id,
        push_title,
        push_body,
        event["disciplina_id"],
        f'{{"event_id": "{event["id"]}", "type": "calendar_reminder", "notification_type": "{notification_type}"}}',
    )

    # Send FCM push
    await send_push_to_user(
        user_id,
        push_title,
        push_body,
        {
            "type": "calendar_reminder",
            "event_id": str(event["id"]),
            "notification_type": notification_type,
        },
    )
