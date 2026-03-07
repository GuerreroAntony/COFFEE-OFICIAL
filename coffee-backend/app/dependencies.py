from uuid import UUID
from typing import AsyncGenerator

import asyncpg
from fastapi import Depends, HTTPException, status
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer

import structlog

from app.database import get_pool
from app.utils.security import decode_jwt

bearer_scheme = HTTPBearer()
_log = structlog.get_logger("dependencies")


async def get_db() -> AsyncGenerator[asyncpg.Connection, None]:
    pool = await get_pool()
    async with pool.acquire() as conn:
        yield conn


async def get_current_user(
    credentials: HTTPAuthorizationCredentials = Depends(bearer_scheme),
) -> UUID:
    token = credentials.credentials
    try:
        payload = decode_jwt(token)
        user_id = UUID(payload["sub"])
        return user_id
    except Exception as exc:
        _log.warning("auth.jwt.invalid", error=str(exc), token_prefix=token[:20] if token else "")
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid or expired token",
            headers={"WWW-Authenticate": "Bearer"},
        )
