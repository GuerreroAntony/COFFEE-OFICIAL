from datetime import datetime
from uuid import UUID

from pydantic import EmailStr, Field, field_validator

from app.schemas.base import BaseSchema


class SignupRequest(BaseSchema):
    nome: str = Field(min_length=2, max_length=255)
    email: EmailStr
    senha: str = Field(min_length=8, max_length=128)

    @field_validator("email")
    @classmethod
    def normalize_email(cls, v: str) -> str:
        return v.lower()


class LoginRequest(BaseSchema):
    email: EmailStr
    senha: str

    @field_validator("email")
    @classmethod
    def normalize_email(cls, v: str) -> str:
        return v.lower()


class UserResponse(BaseSchema):
    id: UUID
    nome: str
    email: str
    created_at: datetime


class AuthResponse(BaseSchema):
    user: UserResponse
    token: str
