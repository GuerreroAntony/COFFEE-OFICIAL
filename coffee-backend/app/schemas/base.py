from typing import Any, Generic, Optional, TypeVar
from pydantic import BaseModel, ConfigDict

T = TypeVar("T")


class BaseSchema(BaseModel):
    model_config = ConfigDict(from_attributes=True)


class SuccessResponse(BaseSchema, Generic[T]):
    success: bool = True
    data: T


class ErrorResponse(BaseSchema):
    success: bool = False
    error: str
    detail: Optional[Any] = None


class PaginatedResponse(BaseSchema, Generic[T]):
    success: bool = True
    data: list[T]
    total: int
    page: int
    page_size: int
