"""
Calendar sync service — fetches Canvas planner items and upserts into calendar_events.
Reuses _canvas_api_get_paginated and CANVAS_API_BASE from canvas_token_service.
"""

import asyncio
import logging
from datetime import datetime, timedelta, timezone
from uuid import UUID

import httpx

from app.database import execute_query, fetch_all, fetch_one
from app.services.canvas_token_service import (
    CANVAS_API_BASE,
    CanvasAuthError,
    _canvas_api_get_paginated,
)

logger = logging.getLogger("coffee.calendar_sync")


async def sync_canvas_calendar(user_id: UUID) -> dict:
    """
    Sync Canvas planner items → calendar_events table.

    1. Fetch user's canvas_token
    2. Fetch user's disciplinas with canvas_course_id (for mapping)
    3. GET /planner/items (paginated, -30d to +120d)
    4. Filter assignments + quizzes (skip announcements)
    5. UPSERT into calendar_events
    6. Update users.calendar_last_synced_at

    Returns: { "synced": int, "skipped": int }
    """

    # 1. Get canvas token
    row = await fetch_one(
        "SELECT canvas_token FROM users WHERE id = $1", user_id
    )
    if not row or not row["canvas_token"]:
        raise CanvasAuthError("Canvas não conectado. Conecte sua conta ESPM primeiro.")

    canvas_token = row["canvas_token"]
    headers = {
        "Authorization": f"Bearer {canvas_token}",
        "Accept": "application/json",
    }

    # 2. Build course_id → disciplina_id mapping
    disc_rows = await fetch_all(
        """
        SELECT d.id AS disciplina_id, d.canvas_course_id
        FROM disciplinas d
        JOIN user_disciplinas ud ON d.id = ud.disciplina_id
        WHERE ud.user_id = $1 AND d.canvas_course_id IS NOT NULL
        """,
        user_id,
    )
    course_to_disciplina = {
        int(r["canvas_course_id"]): r["disciplina_id"] for r in disc_rows
    }

    # 3. Fetch planner items
    start_date = (datetime.now(timezone.utc) - timedelta(days=30)).strftime("%Y-%m-%d")
    url = f"{CANVAS_API_BASE}/planner/items"
    params = {"start_date": start_date, "per_page": "50"}

    async with httpx.AsyncClient(timeout=30.0) as client:
        items = await _canvas_api_get_paginated(client, url, headers, params)

    # 4. Filter and upsert
    synced = 0
    skipped = 0

    for item in items:
        plannable_type = item.get("plannable_type")

        # Only sync assignments and quizzes (skip announcements, discussions, etc.)
        if plannable_type not in ("assignment", "quiz"):
            skipped += 1
            continue

        plannable = item.get("plannable", {})
        submissions = item.get("submissions", {})
        course_id = item.get("course_id")
        plannable_id = item.get("plannable_id")

        if not plannable_id:
            skipped += 1
            continue

        # Map course_id → disciplina_id
        disciplina_id = course_to_disciplina.get(course_id) if course_id else None

        # Determine event_type
        event_type = "quiz" if plannable_type == "quiz" else "assignment"

        # Parse dates (Canvas returns ISO strings, asyncpg needs datetime)
        plannable_date_str = item.get("plannable_date")
        due_at_str = plannable.get("due_at")
        start_at_str = plannable_date_str or due_at_str
        if not start_at_str:
            skipped += 1
            continue

        start_at = datetime.fromisoformat(start_at_str.replace("Z", "+00:00"))
        due_at = datetime.fromisoformat(due_at_str.replace("Z", "+00:00")) if due_at_str else None

        # Submissions status (can be False or a dict)
        is_submitted = False
        is_graded = False
        is_late = False
        is_missing = False

        if isinstance(submissions, dict):
            is_submitted = submissions.get("submitted", False)
            is_graded = submissions.get("graded", False)
            is_late = submissions.get("late", False)
            is_missing = submissions.get("missing", False)

        # Canvas URL
        canvas_url = item.get("html_url", "")
        if canvas_url and not canvas_url.startswith("http"):
            canvas_url = f"https://canvas.espm.br{canvas_url}"

        # Context name (course name)
        course_name = item.get("context_name", "")

        # Source
        source = f"canvas_{plannable_type}"

        await execute_query(
            """
            INSERT INTO calendar_events (
                user_id, disciplina_id, source, canvas_plannable_id, plannable_type,
                title, event_type, start_at, due_at,
                points_possible, submitted, graded, late, missing,
                canvas_url, course_name, updated_at
            ) VALUES (
                $1, $2, $3, $4, $5,
                $6, $7, $8::timestamptz, $9::timestamptz,
                $10, $11, $12, $13, $14,
                $15, $16, now()
            )
            ON CONFLICT (user_id, canvas_plannable_id, plannable_type)
                WHERE canvas_plannable_id IS NOT NULL
            DO UPDATE SET
                title = EXCLUDED.title,
                due_at = EXCLUDED.due_at,
                points_possible = EXCLUDED.points_possible,
                submitted = EXCLUDED.submitted,
                graded = EXCLUDED.graded,
                late = EXCLUDED.late,
                missing = EXCLUDED.missing,
                canvas_url = EXCLUDED.canvas_url,
                course_name = EXCLUDED.course_name,
                disciplina_id = EXCLUDED.disciplina_id,
                updated_at = now()
            """,
            user_id,
            disciplina_id,
            source,
            plannable_id,
            plannable_type,
            plannable.get("title", "Sem título"),
            event_type,
            start_at,
            due_at,
            plannable.get("points_possible"),
            is_submitted,
            is_graded,
            is_late,
            is_missing,
            canvas_url,
            course_name,
        )
        synced += 1

    # 6. Update last synced
    await execute_query(
        "UPDATE users SET calendar_last_synced_at = now() WHERE id = $1",
        user_id,
    )

    logger.info("[calendar_sync] user=%s synced=%d skipped=%d", user_id, synced, skipped)
    return {"synced": synced, "skipped": skipped}
