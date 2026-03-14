from math import ceil
from typing import Any

from pydantic import BaseModel, ConfigDict


class BaseSchema(BaseModel):
    model_config = ConfigDict(from_attributes=True)


def success_response(data: Any = None, message: str = "ok") -> dict:
    """Envelope de sucesso padrão."""
    return {"data": data, "error": None, "message": message}


def error_response(error: str, message: str, extra: dict = None) -> dict:
    """Envelope de erro padrão."""
    resp = {"data": None, "error": error, "message": message}
    if extra:
        resp["data"] = extra
    return resp


def paginated_response(data: list, total: int, page: int, per_page: int, message: str = "ok") -> dict:
    """Envelope de sucesso com paginação."""
    return {
        "data": data,
        "pagination": {
            "page": page,
            "per_page": per_page,
            "total": total,
            "pages": ceil(total / per_page) if per_page > 0 else 0,
        },
        "error": None,
        "message": message,
    }
