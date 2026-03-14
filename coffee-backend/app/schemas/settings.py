from typing import Optional

from pydantic import BaseModel


class SettingsResponse(BaseModel):
    espm_connected: bool
    espm_login: Optional[str] = None
