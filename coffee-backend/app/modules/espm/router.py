"""
Rotas de autenticação ESPM e extração de grade horária.
Adaptado para arquitetura Coffee (asyncpg raw, tabelas disciplinas + user_disciplinas).

Endpoints:
  POST /api/v1/espm/connect        — Login via portal ESPM + extração de grade
  POST /api/v1/espm/sync           — Re-sincroniza grade (force refresh)
  GET  /api/v1/espm/status         — Status da conexão ESPM
  GET  /api/v1/espm/schedule       — Retorna disciplinas do aluno
"""
from __future__ import annotations

import json
import structlog
from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, Field
from typing import List, Optional

from app.config import settings
from app.database import execute_query, fetch_all, fetch_one
from app.dependencies import get_current_user
from app.modules.espm.auth.authenticator import AuthenticationError, ESPMAuthenticator
from app.schemas.base import error_response, success_response
from app.modules.espm.schedule.extractor import ScheduleExtractor
from playwright.async_api import TimeoutError as PlaywrightTimeoutError

router = APIRouter(prefix="/api/v1/espm", tags=["espm"])
logger = structlog.get_logger(__name__)


# ── Schemas ────────────────────────────────────────────────────────────────────

class ESPMConnectRequest(BaseModel):
    matricula: str = Field(description="Email ESPM (ex: aluno@espm.br)")
    password: str = Field(description="Senha do portal ESPM")

class ESPMConnectResponse(BaseModel):
    user_id: UUID
    session_valid: bool
    disciplines_synced: int
    logs: List[str] = []

class ESPMSyncRequest(BaseModel):
    matricula: str
    password: str

class ESPMSyncResponse(BaseModel):
    disciplines_synced: int
    logs: List[str] = []

class DisciplinaPortalOut(BaseModel):
    id: UUID
    nome: str
    professor: Optional[str]
    horario: Optional[str]
    semestre: Optional[str]
    horarios: Optional[List] = None

class ScheduleResponse(BaseModel):
    disciplinas: List[DisciplinaPortalOut]


# ── Helpers ────────────────────────────────────────────────────────────────────


# ── POST /connect ─────────────────────────────────────────────────────────────

@router.post("/connect")
async def espm_connect(
    body: ESPMConnectRequest,
    user_id: UUID = Depends(get_current_user),
):
    """
    Autentica no portal ESPM via Microsoft SSO e extrai a grade horária.
    Requer JWT do Coffee (o aluno já tem conta no Coffee).
    Na primeira vez, extrai disciplinas e vincula ao aluno.
    """
    if not settings.SECRET_KEY:
        raise HTTPException(status_code=503, detail=error_response("ESPM_UNAVAILABLE", "SECRET_KEY não configurada"))

    auth = ESPMAuthenticator(settings.SECRET_KEY)
    extractor = ScheduleExtractor()
    logs: list[str] = []

    row = await fetch_one(
        "SELECT 1 FROM users WHERE id = $1",
        user_id,
    )
    if not row:
        raise HTTPException(status_code=404, detail=error_response("NOT_FOUND", "Usuário não encontrado"))

    # Login + extração na mesma sessão de browser (storage_state não preserva JS state da SPA)
    try:
        result = await auth.login_and_extract(body.matricula, body.password, extractor)
        logs = result.get("logs", [])
        disciplines = result.get("disciplines", [])
    except AuthenticationError as exc:
        raise HTTPException(status_code=401, detail=error_response("ESPM_AUTH_FAILED", str(exc)))
    except PlaywrightTimeoutError:
        raise HTTPException(status_code=504, detail=error_response("ESPM_TIMEOUT", "Timeout no portal ESPM"))
    except Exception as exc:
        logger.error("espm.connect.error", error=str(exc))
        raise HTTPException(status_code=503, detail=error_response("ESPM_UNAVAILABLE", str(exc)))

    # Salvar credenciais para scraper credential pool
    encrypted_password = auth.encrypt_session({"p": body.password})
    await execute_query(
        """UPDATE users
           SET espm_login = $1,
               encrypted_espm_password = $2
           WHERE id = $3""",
        body.matricula, encrypted_password, user_id,
    )

    # Verificar se já tem disciplinas vinculadas
    count_row = await fetch_one(
        "SELECT COUNT(*) AS cnt FROM user_disciplinas WHERE user_id = $1",
        user_id,
    )
    count = count_row["cnt"] if count_row else 0

    disciplines_synced = 0
    if count == 0:
        try:
            disciplines_synced = await _upsert_disciplinas(user_id, disciplines)
            logs.append(f"Vinculadas {disciplines_synced} disciplinas ao aluno.")
        except Exception as exc:
            logger.error("espm.extract.error", error=str(exc))
            logs.append(f"WARN: Upsert de disciplinas falhou: {str(exc)[:100]}")
    else:
        disciplines_synced = count

    resp = ESPMConnectResponse(
        user_id=user_id,
        session_valid=True,
        disciplines_synced=disciplines_synced,
        logs=logs,
    )
    return success_response(resp.model_dump(mode="json"))


# ── POST /sync ────────────────────────────────────────────────────────────────

@router.post("/sync")
async def sync_schedule(
    body: ESPMSyncRequest,
    user_id: UUID = Depends(get_current_user),
):
    """
    Força re-sincronização da grade horária.
    Faz login novo no portal (ignora sessão salva) e extrai disciplinas.
    """
    if not settings.SECRET_KEY:
        raise HTTPException(status_code=503, detail=error_response("ESPM_UNAVAILABLE", "SECRET_KEY não configurada"))

    auth = ESPMAuthenticator(settings.SECRET_KEY)
    extractor = ScheduleExtractor()
    logs: list[str] = []

    try:
        result = await auth.login_and_extract(body.matricula, body.password, extractor)
        state = result["state"]
        disciplines = result["disciplines"]
        logs = result.get("logs", [])
    except AuthenticationError as exc:
        raise HTTPException(status_code=401, detail=error_response("ESPM_AUTH_FAILED", str(exc)))
    except PlaywrightTimeoutError:
        raise HTTPException(status_code=504, detail=error_response("ESPM_TIMEOUT", "Timeout no portal ESPM"))
    except Exception as exc:
        logger.error("espm.sync.error", error=str(exc))
        raise HTTPException(status_code=503, detail=error_response("ESPM_UNAVAILABLE", str(exc)))

    # Salvar credenciais para scraper credential pool
    encrypted_password = auth.encrypt_session({"p": body.password})
    await execute_query(
        """UPDATE users
           SET espm_login = $1,
               encrypted_espm_password = $2
           WHERE id = $3""",
        body.matricula, encrypted_password, user_id,
    )

    synced = await _upsert_disciplinas(user_id, disciplines)
    logs.append(f"Sync completo: {synced} disciplinas.")

    resp = ESPMSyncResponse(disciplines_synced=synced, logs=logs)
    return success_response(resp.model_dump(mode="json"))


# ── GET /status ───────────────────────────────────────────────────────────────

@router.get("/status")
async def espm_status(user_id: UUID = Depends(get_current_user)):
    """Status da conexão ESPM do aluno."""
    row = await fetch_one(
        """SELECT espm_login,
                  (espm_login IS NOT NULL) AS connected
           FROM users WHERE id = $1""",
        user_id,
    )
    if not row:
        raise HTTPException(status_code=404, detail=error_response("NOT_FOUND", "Usuário não encontrado"))

    count_row = await fetch_one(
        "SELECT COUNT(*) AS cnt FROM user_disciplinas WHERE user_id = $1",
        user_id,
    )

    return success_response({
        "connected": row["connected"],
        "matricula": row["espm_login"],
        "disciplinas_count": count_row["cnt"] if count_row else 0,
    })


# ── GET /schedule ─────────────────────────────────────────────────────────────

@router.get("/schedule")
async def get_schedule(user_id: UUID = Depends(get_current_user)):
    """Retorna as disciplinas do aluno extraídas do portal ESPM."""
    rows = await fetch_all(
        """SELECT d.id, d.nome, d.professor, d.horario, d.semestre, d.horarios
           FROM disciplinas d
           JOIN user_disciplinas ud ON d.id = ud.disciplina_id
           WHERE ud.user_id = $1
           ORDER BY d.nome""",
        user_id,
    )
    disciplinas = [DisciplinaPortalOut(**dict(r)).model_dump(mode="json") for r in rows]
    return success_response({"disciplinas": disciplinas})


# ── Helper: upsert disciplinas ────────────────────────────────────────────────

async def _upsert_disciplinas(user_id: UUID, disciplines: list[dict]) -> int:
    """
    Faz upsert das disciplinas extraídas do portal e vincula ao aluno.
    Usa (nome, semestre) como chave de dedup.
    Retorna quantidade de disciplinas vinculadas.
    """
    if not disciplines:
        return 0

    count = 0
    for disc in disciplines:
        try:
            horarios_json = json.dumps(disc.get("horarios") or [])

            row = await fetch_one(
                """
                INSERT INTO disciplinas (turma, nome, professor, horario, semestre, horarios)
                VALUES ($1, $2, $3, $4, $5, $6::jsonb)
                ON CONFLICT ON CONSTRAINT disciplinas_nome_semestre_unique
                DO UPDATE SET
                    turma     = COALESCE(EXCLUDED.turma,     disciplinas.turma),
                    professor = COALESCE(EXCLUDED.professor, disciplinas.professor),
                    horario   = COALESCE(EXCLUDED.horario,   disciplinas.horario),
                    horarios  = COALESCE(EXCLUDED.horarios,  disciplinas.horarios)
                RETURNING id
                """,
                disc.get("turma"),
                disc["nome"],
                disc.get("professor"),
                disc.get("horario"),
                disc.get("semestre"),
                horarios_json,
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
