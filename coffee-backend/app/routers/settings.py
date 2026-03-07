from uuid import UUID

from fastapi import APIRouter, Depends

from app.database import execute_query, fetch_one
from app.dependencies import get_current_user
from app.schemas.base import success_response
from app.schemas.settings import SettingsResponse, UpdateSettingsRequest

router = APIRouter(prefix="/api/v1/settings", tags=["settings"])

DEFAULTS = {
    "auto_transcription": True,
    "auto_summaries": True,
    "push_notifications": True,
    "class_reminders": True,
    "audio_quality": "high",
    "summary_language": "pt-BR",
}



@router.get("")
async def get_settings(user_id: UUID = Depends(get_current_user)):
    """Busca user_settings (ou cria com defaults se não existe)."""
    row = await fetch_one(
        """SELECT auto_transcription, auto_summaries, push_notifications,
                  class_reminders, audio_quality, summary_language
           FROM user_settings WHERE user_id = $1""",
        user_id,
    )
    if not row:
        await execute_query(
            """INSERT INTO user_settings
                   (user_id, auto_transcription, auto_summaries, push_notifications,
                    class_reminders, audio_quality, summary_language)
               VALUES ($1, $2, $3, $4, $5, $6, $7)""",
            user_id,
            DEFAULTS["auto_transcription"],
            DEFAULTS["auto_summaries"],
            DEFAULTS["push_notifications"],
            DEFAULTS["class_reminders"],
            DEFAULTS["audio_quality"],
            DEFAULTS["summary_language"],
        )
        row = DEFAULTS

    resp = SettingsResponse(**dict(row) if not isinstance(row, dict) else row)
    return success_response(resp.model_dump(mode="json"))


@router.patch("")
async def update_settings(
    body: UpdateSettingsRequest,
    user_id: UUID = Depends(get_current_user),
):
    """Atualiza apenas campos enviados (partial update)."""
    updates = body.model_dump(exclude_none=True)
    if not updates:
        return await get_settings(user_id)

    # Ensure row exists
    exists = await fetch_one(
        "SELECT 1 FROM user_settings WHERE user_id = $1", user_id
    )
    if not exists:
        await execute_query(
            """INSERT INTO user_settings
                   (user_id, auto_transcription, auto_summaries, push_notifications,
                    class_reminders, audio_quality, summary_language)
               VALUES ($1, $2, $3, $4, $5, $6, $7)""",
            user_id,
            DEFAULTS["auto_transcription"],
            DEFAULTS["auto_summaries"],
            DEFAULTS["push_notifications"],
            DEFAULTS["class_reminders"],
            DEFAULTS["audio_quality"],
            DEFAULTS["summary_language"],
        )

    set_clauses = []
    params = []
    for i, (key, value) in enumerate(updates.items(), start=2):
        set_clauses.append(f"{key} = ${i}")
        params.append(value)

    row = await fetch_one(
        f"""UPDATE user_settings
            SET {', '.join(set_clauses)}
            WHERE user_id = $1
            RETURNING auto_transcription, auto_summaries, push_notifications,
                      class_reminders, audio_quality, summary_language""",
        user_id,
        *params,
    )

    resp = SettingsResponse(**dict(row))
    return success_response(resp.model_dump(mode="json"))
