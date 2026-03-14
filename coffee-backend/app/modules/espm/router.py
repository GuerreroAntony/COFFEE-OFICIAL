"""
Rotas de autenticação ESPM e extração de grade horária via Canvas API.

Endpoints:
  POST /api/v1/espm/connect        — Login Canvas SSO + token + cursos
  POST /api/v1/espm/sync           — Re-sincroniza cursos (usa Canvas token)
  GET  /api/v1/espm/status         — Status da conexão ESPM
  POST /api/v1/espm/disconnect     — Desconecta conta ESPM
"""
from __future__ import annotations

import structlog
from datetime import datetime
from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, Field
from typing import List, Optional

from app.config import settings
from app.database import execute_query, fetch_all, fetch_one
from app.dependencies import get_current_user
from app.schemas.base import error_response, success_response
from app.services.canvas_token_service import (
    generate_canvas_token,
    fetch_canvas_courses,
    CanvasAuthError,
    CanvasTimeoutError,
)

router = APIRouter(prefix="/api/v1/espm", tags=["espm"])
logger = structlog.get_logger(__name__)


# ── Schemas (contract v3.1) ───────────────────────────────────────────────────

class ESPMConnectRequest(BaseModel):
    matricula: str = Field(description="Email ESPM (ex: aluno@acad.espm.br)")
    password: str = Field(description="Senha do portal ESPM")

class ESPMSyncRequest(BaseModel):
    matricula: str
    password: str


# ── Helpers ────────────────────────────────────────────────────────────────────

def _encrypt_password(password: str) -> str:
    """
    Encrypt ESPM password for storage (backward compat with coffee-scraper).
    Uses Fernet symmetric encryption from ESPMAuthenticator.
    """
    from app.modules.espm.auth.authenticator import ESPMAuthenticator
    auth = ESPMAuthenticator(settings.SECRET_KEY)
    return auth.encrypt_session({"p": password})


async def _generate_and_save_canvas_token(
    user_id: UUID, login: str, password: str
) -> tuple[bool, str | None]:
    """
    Generate a Canvas API token via Playwright and save to users table.
    Returns (success: bool, token: str | None).

    Raises CanvasAuthError or CanvasTimeoutError to allow the router
    to return specific HTTP error codes (401/504).
    """
    try:
        result = await generate_canvas_token(
            email=login,
            password=password,
            purpose="coffee-auto",
            headless=True,
        )

        token = result["token"]
        expires_at = datetime.fromisoformat(result["expires_at"])

        await execute_query(
            """UPDATE users
               SET canvas_token = $1,
                   canvas_token_expires_at = $2
               WHERE id = $3""",
            token, expires_at, user_id,
        )

        logger.info("canvas_token.generated", user_id=str(user_id),
                     expires_at=expires_at.isoformat())
        return True, token

    except (CanvasAuthError, CanvasTimeoutError):
        raise  # Propagate to router for specific HTTP status codes
    except Exception as exc:
        logger.warning("canvas_token.failed", user_id=str(user_id), error=str(exc))
        return False, None


async def _fetch_courses_list(canvas_token: str) -> list[dict]:
    """Fetch courses and return list of discipline dicts for the response."""
    return await fetch_canvas_courses(canvas_token)


async def _build_connect_response(
    user_id: UUID, disciplines_synced: int
) -> dict:
    """
    Build the response matching contract v3.1 shape:
    {status: "connected", disciplinas_found: N, disciplinas: [...]}
    """
    # Fetch the user's disciplinas from DB for the response
    rows = await fetch_all(
        """SELECT d.id, d.nome, d.turma, d.semestre
           FROM disciplinas d
           JOIN user_disciplinas ud ON d.id = ud.disciplina_id
           WHERE ud.user_id = $1
           ORDER BY d.nome""",
        user_id,
    )

    disciplinas = [
        {
            "id": str(r["id"]),
            "nome": r["nome"],
            "turma": r["turma"],
            "semestre": r["semestre"],
        }
        for r in rows
    ]

    return {
        "status": "connected",
        "disciplinas_found": disciplines_synced,
        "disciplinas": disciplinas,
    }


# ── POST /connect ─────────────────────────────────────────────────────────────

@router.post("/connect")
async def espm_connect(
    body: ESPMConnectRequest,
    user_id: UUID = Depends(get_current_user),
):
    """
    Conecta conta ESPM via Canvas API.

    Fluxo:
    1. Playwright login no Canvas SSO → gera API token (~19s)
    2. REST API busca cursos do aluno (~2s)
    3. Upsert disciplinas no banco
    4. Salva credenciais encriptadas (para coffee-scraper)
    """
    if not settings.SECRET_KEY:
        raise HTTPException(status_code=503, detail=error_response(
            "ESPM_UNAVAILABLE", "SECRET_KEY não configurada"))

    # Verify user exists
    row = await fetch_one("SELECT 1 FROM users WHERE id = $1", user_id)
    if not row:
        raise HTTPException(status_code=404, detail=error_response(
            "NOT_FOUND", "Usuário não encontrado"))

    # 1. Generate Canvas API token via Playwright
    try:
        canvas_ok, canvas_token = await _generate_and_save_canvas_token(
            user_id, body.matricula, body.password
        )
    except CanvasAuthError:
        raise HTTPException(status_code=401, detail=error_response(
            "ESPM_AUTH_FAILED", "Credenciais ESPM inválidas."))
    except CanvasTimeoutError:
        raise HTTPException(status_code=504, detail=error_response(
            "ESPM_TIMEOUT", "Timeout ao conectar ao Canvas ESPM."))

    if not canvas_ok or not canvas_token:
        raise HTTPException(status_code=503, detail=error_response(
            "ESPM_UNAVAILABLE",
            "Não foi possível gerar token Canvas."))

    # 2. Fetch courses via Canvas REST API and upsert
    disciplines_synced = 0
    try:
        disciplines = await _fetch_courses_list(canvas_token)
        disciplines_synced = await _upsert_disciplinas(user_id, disciplines)
    except Exception as exc:
        logger.error("espm.connect.fetch_courses.error", error=str(exc))

    # 3. Save encrypted credentials (backward compat with coffee-scraper)
    try:
        encrypted_password = _encrypt_password(body.password)
        await execute_query(
            """UPDATE users
               SET espm_login = $1,
                   encrypted_espm_password = $2
               WHERE id = $3""",
            body.matricula, encrypted_password, user_id,
        )
    except Exception as exc:
        logger.warning("espm.connect.encrypt.error", error=str(exc))
        await execute_query(
            "UPDATE users SET espm_login = $1 WHERE id = $2",
            body.matricula, user_id,
        )

    # Build response matching contract v3.1
    resp = await _build_connect_response(user_id, disciplines_synced)
    return success_response(resp)


# ── POST /sync ────────────────────────────────────────────────────────────────

@router.post("/sync")
async def sync_schedule(
    body: ESPMSyncRequest,
    user_id: UUID = Depends(get_current_user),
):
    """
    Força re-sincronização dos cursos.
    Response: same format as /connect (contract v3.1).
    """
    if not settings.SECRET_KEY:
        raise HTTPException(status_code=503, detail=error_response(
            "ESPM_UNAVAILABLE", "SECRET_KEY não configurada"))

    # Check if user has a valid canvas_token
    user_row = await fetch_one(
        "SELECT canvas_token, canvas_token_expires_at FROM users WHERE id = $1",
        user_id,
    )
    canvas_token = user_row["canvas_token"] if user_row else None
    token_expires = user_row["canvas_token_expires_at"] if user_row else None
    token_valid = (
        canvas_token is not None
        and token_expires is not None
        and token_expires > datetime.utcnow()
    )

    disciplines_synced = 0

    if token_valid:
        # ── Fast path: Canvas REST API with saved token ──
        try:
            disciplines = await _fetch_courses_list(canvas_token)
            disciplines_synced = await _upsert_disciplinas(user_id, disciplines)
        except Exception as exc:
            logger.warning("espm.sync.fast_path_failed", error=str(exc))
            token_valid = False  # fallback to slow path

    if not token_valid:
        # ── Slow path: regenerate token via Playwright ──
        try:
            canvas_ok, new_token = await _generate_and_save_canvas_token(
                user_id, body.matricula, body.password
            )
        except CanvasAuthError:
            raise HTTPException(status_code=401, detail=error_response(
                "ESPM_AUTH_FAILED", "Credenciais ESPM inválidas."))
        except CanvasTimeoutError:
            raise HTTPException(status_code=504, detail=error_response(
                "ESPM_TIMEOUT", "Timeout ao conectar ao Canvas ESPM."))

        if not canvas_ok or not new_token:
            raise HTTPException(status_code=503, detail=error_response(
                "ESPM_UNAVAILABLE",
                "Não foi possível regenerar token Canvas."))

        try:
            disciplines = await _fetch_courses_list(new_token)
            disciplines_synced = await _upsert_disciplinas(user_id, disciplines)
        except Exception as exc:
            logger.error("espm.sync.slow_path_failed", error=str(exc))
            raise HTTPException(status_code=503, detail=error_response(
                "ESPM_UNAVAILABLE", str(exc)))

    # Update encrypted credentials (backward compat with coffee-scraper)
    try:
        encrypted_password = _encrypt_password(body.password)
        await execute_query(
            """UPDATE users
               SET espm_login = $1,
                   encrypted_espm_password = $2
               WHERE id = $3""",
            body.matricula, encrypted_password, user_id,
        )
    except Exception as exc:
        logger.warning("espm.sync.encrypt.error", error=str(exc))

    # Same response format as /connect (contract v3.1)
    resp = await _build_connect_response(user_id, disciplines_synced)
    return success_response(resp)


# ── GET /status ───────────────────────────────────────────────────────────────

@router.get("/status")
async def espm_status(user_id: UUID = Depends(get_current_user)):
    """Status da conexão ESPM do aluno."""
    row = await fetch_one(
        """SELECT espm_login, canvas_token_expires_at,
                  (espm_login IS NOT NULL) AS connected
           FROM users WHERE id = $1""",
        user_id,
    )
    if not row:
        raise HTTPException(status_code=404, detail=error_response(
            "NOT_FOUND", "Usuário não encontrado"))

    count_row = await fetch_one(
        "SELECT COUNT(*) AS cnt FROM user_disciplinas WHERE user_id = $1",
        user_id,
    )

    return success_response({
        "connected": row["connected"],
        "matricula": row["espm_login"],
        "disciplinas_count": count_row["cnt"] if count_row else 0,
        "token_expires_at": row["canvas_token_expires_at"].isoformat()
            if row["canvas_token_expires_at"] else None,
    })


# ── POST /disconnect ─────────────────────────────────────────────────────────

@router.post("/disconnect")
async def espm_disconnect(user_id: UUID = Depends(get_current_user)):
    """Desconecta conta ESPM. App fica inutilizável até reconexão."""
    await execute_query(
        """UPDATE users
           SET espm_login = NULL,
               canvas_token = NULL,
               canvas_token_expires_at = NULL,
               encrypted_espm_password = NULL
           WHERE id = $1""",
        user_id,
    )
    return success_response(None, "ESPM desconectado")


# ── Helper: upsert disciplinas ────────────────────────────────────────────────

async def _upsert_disciplinas(user_id: UUID, disciplines: list[dict]) -> int:
    """
    Faz upsert das disciplinas extraídas do Canvas e vincula ao aluno.
    Usa (nome, semestre) como chave de dedup.
    """
    if not disciplines:
        return 0

    count = 0
    for disc in disciplines:
        try:
            canvas_id = disc.get("canvas_course_id")

            if canvas_id:
                row = await fetch_one(
                    """
                    INSERT INTO disciplinas (turma, nome, semestre, canvas_course_id)
                    VALUES ($1, $2, $3, $4)
                    ON CONFLICT ON CONSTRAINT disciplinas_nome_semestre_unique
                    DO UPDATE SET
                        turma = COALESCE(EXCLUDED.turma, disciplinas.turma),
                        canvas_course_id = COALESCE(EXCLUDED.canvas_course_id, disciplinas.canvas_course_id)
                    RETURNING id
                    """,
                    disc.get("turma"),
                    disc["nome"],
                    disc.get("semestre"),
                    canvas_id,
                )
            else:
                row = await fetch_one(
                    """
                    INSERT INTO disciplinas (turma, nome, semestre)
                    VALUES ($1, $2, $3)
                    ON CONFLICT ON CONSTRAINT disciplinas_nome_semestre_unique
                    DO UPDATE SET
                        turma = COALESCE(EXCLUDED.turma, disciplinas.turma)
                    RETURNING id
                    """,
                    disc.get("turma"),
                    disc["nome"],
                    disc.get("semestre"),
                )

            if row:
                await execute_query(
                    """INSERT INTO user_disciplinas (user_id, disciplina_id)
                       VALUES ($1, $2)
                       ON CONFLICT (user_id, disciplina_id) DO NOTHING""",
                    user_id, row["id"],
                )
                count += 1

        except Exception as exc:
            logger.error(
                "upsert_disciplinas.error",
                name=disc.get("nome"),
                error=str(exc),
            )

    return count
