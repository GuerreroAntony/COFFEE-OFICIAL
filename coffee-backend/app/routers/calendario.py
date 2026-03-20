"""
Calendario router — CRUD for calendar events + Canvas sync.
Gated to plano 'black' or 'trial' (active trial).
"""

from datetime import datetime, timedelta, timezone
from typing import Optional
from uuid import UUID

from fastapi import APIRouter, BackgroundTasks, Depends, HTTPException, Query, status

from app.database import execute_query, fetch_all, fetch_one
from app.dependencies import get_current_user_with_plan
from app.schemas.base import error_response, success_response
from app.schemas.calendario import (
    CalendarEventResponse,
    CreateEventRequest,
    UpdateEventRequest,
    UpcomingResponse,
)

router = APIRouter(prefix="/api/v1/calendario", tags=["calendario"])


# ── Guard ──────────────────────────────────────────────────

def _require_black_or_trial(plano: str):
    """Only Black and active Trial users can access the calendar."""
    if plano not in ("black", "trial"):
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail=error_response(
                "PLAN_REQUIRED",
                "O Calendário ESPM é exclusivo do plano Black."
            ),
        )


def _row_to_response(row) -> dict:
    """Convert asyncpg Record to CalendarEventResponse dict."""
    return CalendarEventResponse(
        id=row["id"],
        user_id=row["user_id"],
        disciplina_id=row.get("disciplina_id"),
        source=row["source"],
        canvas_plannable_id=row.get("canvas_plannable_id"),
        plannable_type=row.get("plannable_type"),
        title=row["title"],
        description=row.get("description"),
        location=row.get("location"),
        event_type=row["event_type"],
        start_at=row["start_at"],
        end_at=row.get("end_at"),
        all_day=row["all_day"],
        due_at=row.get("due_at"),
        points_possible=row.get("points_possible"),
        submitted=row.get("submitted"),
        graded=row.get("graded"),
        late=row.get("late"),
        missing=row.get("missing"),
        canvas_url=row.get("canvas_url"),
        course_name=row.get("course_name"),
        completed=row["completed"],
        disciplina_nome=row.get("disciplina_nome"),
        created_at=row["created_at"],
        updated_at=row["updated_at"],
    ).model_dump(mode="json")


# ── Endpoints ──────────────────────────────────────────────

@router.get("/events")
async def list_events(
    start: Optional[str] = Query(None, description="ISO date YYYY-MM-DD"),
    end: Optional[str] = Query(None, description="ISO date YYYY-MM-DD"),
    user_plan: tuple = Depends(get_current_user_with_plan),
):
    """List calendar events in a date range."""
    user_id, plano = user_plan
    _require_black_or_trial(plano)

    # Defaults: -30 days to +120 days
    now = datetime.now(timezone.utc)
    start_dt = datetime.fromisoformat(start) if start else now - timedelta(days=30)
    end_dt = datetime.fromisoformat(end) if end else now + timedelta(days=120)

    rows = await fetch_all(
        """
        SELECT ce.*, d.nome AS disciplina_nome
        FROM calendar_events ce
        LEFT JOIN disciplinas d ON d.id = ce.disciplina_id
        WHERE ce.user_id = $1
          AND ce.start_at >= $2
          AND ce.start_at <= $3
        ORDER BY ce.start_at ASC
        """,
        user_id, start_dt, end_dt,
    )

    events = [_row_to_response(r) for r in rows]
    return success_response(events)


@router.post("/events", status_code=201)
async def create_event(
    body: CreateEventRequest,
    user_plan: tuple = Depends(get_current_user_with_plan),
):
    """Create a manual calendar event."""
    user_id, plano = user_plan
    _require_black_or_trial(plano)

    # Validate disciplina ownership if provided
    if body.disciplina_id:
        own = await fetch_one(
            "SELECT 1 FROM user_disciplinas WHERE user_id = $1 AND disciplina_id = $2",
            user_id, body.disciplina_id,
        )
        if not own:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail=error_response("NOT_FOUND", "Disciplina não encontrada."),
            )

    row = await fetch_one(
        """
        INSERT INTO calendar_events (
            user_id, disciplina_id, source, title, description, location,
            event_type, start_at, end_at, due_at, all_day
        ) VALUES ($1, $2, 'manual', $3, $4, $5, $6, $7, $8, $9, $10)
        RETURNING *
        """,
        user_id,
        body.disciplina_id,
        body.title,
        body.description,
        body.location,
        body.event_type,
        body.start_at,
        body.end_at,
        body.due_at,
        body.all_day,
    )

    # Re-fetch with JOIN for disciplina_nome
    full = await fetch_one(
        """
        SELECT ce.*, d.nome AS disciplina_nome
        FROM calendar_events ce
        LEFT JOIN disciplinas d ON d.id = ce.disciplina_id
        WHERE ce.id = $1
        """,
        row["id"],
    )

    return success_response(_row_to_response(full))


@router.patch("/events/{event_id}")
async def update_event(
    event_id: UUID,
    body: UpdateEventRequest,
    user_plan: tuple = Depends(get_current_user_with_plan),
):
    """Update a manual calendar event."""
    user_id, plano = user_plan
    _require_black_or_trial(plano)

    # Check ownership + manual only
    existing = await fetch_one(
        "SELECT id, source FROM calendar_events WHERE id = $1 AND user_id = $2",
        event_id, user_id,
    )
    if not existing:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=error_response("NOT_FOUND", "Evento não encontrado."),
        )
    if existing["source"] != "manual":
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=error_response("CANVAS_EVENT", "Eventos do Canvas não podem ser editados."),
        )

    # Build dynamic SET clause
    updates = {}
    if body.title is not None:
        updates["title"] = body.title
    if body.start_at is not None:
        updates["start_at"] = body.start_at
    if body.end_at is not None:
        updates["end_at"] = body.end_at
    if body.due_at is not None:
        updates["due_at"] = body.due_at
    if body.all_day is not None:
        updates["all_day"] = body.all_day
    if body.event_type is not None:
        updates["event_type"] = body.event_type
    if body.description is not None:
        updates["description"] = body.description
    if body.location is not None:
        updates["location"] = body.location
    if body.completed is not None:
        updates["completed"] = body.completed

    if not updates:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=error_response("NO_CHANGES", "Nenhum campo para atualizar."),
        )

    # Build parameterized query
    set_parts = []
    values = []
    for i, (col, val) in enumerate(updates.items(), start=1):
        set_parts.append(f"{col} = ${i}")
        values.append(val)
    set_parts.append(f"updated_at = now()")
    values.append(event_id)
    values.append(user_id)

    query = f"""
        UPDATE calendar_events
        SET {', '.join(set_parts)}
        WHERE id = ${len(values) - 1} AND user_id = ${len(values)}
    """
    await execute_query(query, *values)

    # Return updated
    full = await fetch_one(
        """
        SELECT ce.*, d.nome AS disciplina_nome
        FROM calendar_events ce
        LEFT JOIN disciplinas d ON d.id = ce.disciplina_id
        WHERE ce.id = $1
        """,
        event_id,
    )
    return success_response(_row_to_response(full))


@router.delete("/events/{event_id}")
async def delete_event(
    event_id: UUID,
    user_plan: tuple = Depends(get_current_user_with_plan),
):
    """Delete a manual calendar event."""
    user_id, plano = user_plan
    _require_black_or_trial(plano)

    existing = await fetch_one(
        "SELECT id, source FROM calendar_events WHERE id = $1 AND user_id = $2",
        event_id, user_id,
    )
    if not existing:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=error_response("NOT_FOUND", "Evento não encontrado."),
        )
    if existing["source"] != "manual":
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=error_response("CANVAS_EVENT", "Eventos do Canvas não podem ser excluídos."),
        )

    await execute_query(
        "DELETE FROM calendar_events WHERE id = $1 AND user_id = $2",
        event_id, user_id,
    )
    return success_response(message="Evento excluído.")


@router.post("/sync")
async def sync_canvas(
    background_tasks: BackgroundTasks,
    user_plan: tuple = Depends(get_current_user_with_plan),
):
    """Sync Canvas planner items to calendar. Runs in background. Cooldown: 15 min."""
    user_id, plano = user_plan
    _require_black_or_trial(plano)

    # Check cooldown (15 minutes)
    row = await fetch_one(
        "SELECT calendar_last_synced_at FROM users WHERE id = $1", user_id
    )
    if row and row["calendar_last_synced_at"]:
        last_sync = row["calendar_last_synced_at"]
        if last_sync.tzinfo is None:
            last_sync = last_sync.replace(tzinfo=timezone.utc)
        cooldown = timedelta(minutes=15)
        if datetime.now(timezone.utc) - last_sync < cooldown:
            remaining = cooldown - (datetime.now(timezone.utc) - last_sync)
            mins = int(remaining.total_seconds() // 60)
            return success_response(
                {"status": "cooldown", "remaining_minutes": mins},
                message=f"Sincronização disponível em {mins} minutos.",
            )

    # Run sync in background
    from app.services.calendar_sync_service import sync_canvas_calendar

    background_tasks.add_task(sync_canvas_calendar, user_id)
    return success_response(
        {"status": "syncing"},
        message="Sincronização iniciada. Os eventos aparecerão em instantes.",
    )


@router.get("/upcoming")
async def get_upcoming(
    user_plan: tuple = Depends(get_current_user_with_plan),
):
    """Get upcoming events grouped: overdue, today, tomorrow, this_week."""
    user_id, plano = user_plan
    _require_black_or_trial(plano)

    now = datetime.now(timezone.utc)
    today_start = now.replace(hour=0, minute=0, second=0, microsecond=0)
    tomorrow_start = today_start + timedelta(days=1)
    tomorrow_end = today_start + timedelta(days=2)
    week_end = today_start + timedelta(days=7)

    rows = await fetch_all(
        """
        SELECT ce.*, d.nome AS disciplina_nome
        FROM calendar_events ce
        LEFT JOIN disciplinas d ON d.id = ce.disciplina_id
        WHERE ce.user_id = $1
          AND ce.start_at >= $2
          AND ce.start_at <= $3
          AND ce.completed = false
        ORDER BY ce.start_at ASC
        """,
        user_id,
        today_start - timedelta(days=30),  # include overdue from past 30 days
        week_end,
    )

    overdue = []
    today = []
    tomorrow = []
    this_week = []

    for r in rows:
        evt = _row_to_response(r)
        start = r["start_at"]
        if start.tzinfo is None:
            start = start.replace(tzinfo=timezone.utc)

        # Overdue: past + not submitted
        if start < today_start and not r.get("submitted", False):
            overdue.append(evt)
        elif today_start <= start < tomorrow_start:
            today.append(evt)
        elif tomorrow_start <= start < tomorrow_end:
            tomorrow.append(evt)
        elif tomorrow_end <= start < week_end:
            this_week.append(evt)

    result = UpcomingResponse(
        overdue=overdue,
        today=today,
        tomorrow=tomorrow,
        this_week=this_week,
        total_upcoming=len(overdue) + len(today) + len(tomorrow) + len(this_week),
    )
    return success_response(result.model_dump(mode="json"))
