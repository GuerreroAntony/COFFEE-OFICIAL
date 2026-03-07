from typing import Optional
from uuid import UUID
from pydantic import BaseModel, Field


class SettingsResponse(BaseModel):
    auto_transcription: bool
    auto_summaries: bool
    push_notifications: bool
    class_reminders: bool
    audio_quality: str
    summary_language: str


class UpdateSettingsRequest(BaseModel):
    auto_transcription: Optional[bool] = None
    auto_summaries: Optional[bool] = None
    push_notifications: Optional[bool] = None
    class_reminders: Optional[bool] = None
    audio_quality: Optional[str] = Field(None, pattern="^(high|medium|low)$")
    summary_language: Optional[str] = None
