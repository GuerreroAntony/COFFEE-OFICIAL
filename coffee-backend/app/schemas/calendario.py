from datetime import datetime
from typing import Optional
from uuid import UUID

from pydantic import BaseModel, Field


class CreateEventRequest(BaseModel):
    title: str = Field(min_length=1, max_length=500)
    start_at: datetime
    end_at: Optional[datetime] = None
    due_at: Optional[datetime] = None
    all_day: bool = False
    event_type: str = Field(default="event")  # 'assignment','quiz','exam','deadline','event','reminder'
    description: Optional[str] = None
    location: Optional[str] = None
    disciplina_id: Optional[UUID] = None


class UpdateEventRequest(BaseModel):
    title: Optional[str] = Field(default=None, min_length=1, max_length=500)
    start_at: Optional[datetime] = None
    end_at: Optional[datetime] = None
    due_at: Optional[datetime] = None
    all_day: Optional[bool] = None
    event_type: Optional[str] = None
    description: Optional[str] = None
    location: Optional[str] = None
    completed: Optional[bool] = None


class CalendarEventResponse(BaseModel):
    id: UUID
    user_id: UUID
    disciplina_id: Optional[UUID] = None
    source: str
    canvas_plannable_id: Optional[int] = None
    plannable_type: Optional[str] = None
    title: str
    description: Optional[str] = None
    location: Optional[str] = None
    event_type: str
    start_at: datetime
    end_at: Optional[datetime] = None
    all_day: bool
    due_at: Optional[datetime] = None
    points_possible: Optional[float] = None
    submitted: Optional[bool] = None
    graded: Optional[bool] = None
    late: Optional[bool] = None
    missing: Optional[bool] = None
    canvas_url: Optional[str] = None
    course_name: Optional[str] = None
    completed: bool
    disciplina_nome: Optional[str] = None
    created_at: datetime
    updated_at: datetime


class UpcomingResponse(BaseModel):
    overdue: list[CalendarEventResponse] = []
    today: list[CalendarEventResponse] = []
    tomorrow: list[CalendarEventResponse] = []
    this_week: list[CalendarEventResponse] = []
    total_upcoming: int = 0
