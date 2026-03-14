import hashlib
from uuid import UUID
from typing import AsyncGenerator, Tuple

import asyncpg
from fastapi import Depends, HTTPException, status
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer

import structlog

from app.database import fetch_one, get_pool
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

        # Check token blacklist
        token_hash = hashlib.sha256(token.encode()).hexdigest()
        blacklisted = await fetch_one(
            "SELECT 1 FROM token_blacklist WHERE token_hash = $1",
            token_hash,
        )
        if blacklisted:
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail="Token expired",
                headers={"WWW-Authenticate": "Bearer"},
            )

        return user_id
    except HTTPException:
        raise
    except Exception as exc:
        _log.warning("auth.jwt.invalid", error=str(exc), token_prefix=token[:20] if token else "")
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid or expired token",
            headers={"WWW-Authenticate": "Bearer"},
        )


async def get_current_user_with_plan(
    credentials: HTTPAuthorizationCredentials = Depends(bearer_scheme),
) -> Tuple[UUID, str]:
    """Returns (user_id, plano). Use for endpoints that need subscription guard."""
    user_id = await get_current_user(credentials)
    row = await fetch_one("SELECT plano FROM users WHERE id = $1", user_id)
    plano = row["plano"] if row else "trial"
    return user_id, plano
