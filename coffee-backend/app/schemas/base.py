from typing import Any
from pydantic import BaseModel, ConfigDict


class BaseSchema(BaseModel):
    model_config = ConfigDict(from_attributes=True)


def success_response(data: Any = None, message: str = "ok") -> dict:
    """Envelope de sucesso padrão."""
    return {"data": data, "error": None, "message": message}


def error_response(error: str, message: str) -> dict:
    """Envelope de erro padrão."""
    return {"data": None, "error": error, "message": message}
