"""
Rotas de autenticação ESPM e extração de grade horária.
Adaptado para arquitetura Coffee (asyncpg raw, tabelas disciplinas + user_disciplinas).

Endpoints:
  POST /api/v1/espm/login          — Login via portal ESPM + extração de grade
  POST /api/v1/espm/sync-schedule  — Re-sincroniza grade (force refresh)
  GET  /api/v1/espm/schedule       — Retorna disciplinas do aluno (dados extraídos)
"""
from __future__ import annotations

import json
import structlog
from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, Field
from typing import List, Optional

from app.config import Settings, get_settings
from app.dependencies import get_db, get_current_user
from app.modules.espm.auth.authenticator import AuthenticationError, ESPMAuthenticator
from app.modules.espm.schedule.extractor import ScheduleExtractor
from playwright.async_api import TimeoutError as PlaywrightTimeoutError

router = APIRouter(prefix="/api/v1/espm", tags=["espm"])
logger = structlog.get_logger(__name__)


# ── Schemas ────────────────────────────────────────────────────────────────────

class ESPMLoginRequest(BaseModel):
    login: str = Field(description="Email ESPM (ex: aluno@espm.br)")
    password: str = Field(description="Senha do portal ESPM")

class ESPMLoginResponse(BaseModel):
    user_id: UUID
    session_valid: bool
    disciplines_synced: int
    logs: List[str] = []

class ESPMSyncRequest(BaseModel):
    login: str
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


# ── POST /login ────────────────────────────────────────────────────────────────

@router.post("/login", response_model=ESPMLoginResponse)
async def espm_login(
    body: ESPMLoginRequest,
    user_id: UUID = Depends(get_current_user),
    db=Depends(get_db),
    cfg: Settings = Depends(get_settings),
):
    """
    Autentica no portal ESPM via Microsoft SSO e extrai a grade horária.
    Requer JWT do Coffee (o aluno já tem conta no Coffee).
    Na primeira vez, extrai disciplinas e vincula ao aluno.
    """
    auth = ESPMAuthenticator(cfg.secret_key)
    logs: list[str] = []

    # Verificar se já tem sessão salva
    row = await db.fetchrow(
        "SELECT encrypted_portal_session FROM users WHERE id = $1",
        user_id
    )
    if not row:
        raise HTTPException(status_code=404, detail="Usuário não encontrado.")

    # Tentar sessão existente ou login novo
    try:
        if row["encrypted_portal_session"]:
            result_auth, logs = await auth.get_or_refresh_session(
                row["encrypted_portal_session"], body.login, body.password
            )
            state = result_auth["state"]
        else:
            result_auth = await auth.login(body.login, body.password)
            state = result_auth["state"]
            logs = result_auth.get("logs", [])
    except AuthenticationError as exc:
        raise HTTPException(status_code=401, detail=str(exc))
    except PlaywrightTimeoutError as exc:
        raise HTTPException(status_code=504, detail=f"Timeout no portal: {exc}")

    # Salvar sessão criptografada + senha para scraper credential pool
    encrypted = auth.encrypt_session(state)
    encrypted_password = auth.encrypt_session({"p": body.password})
    await db.execute(
        """UPDATE users
           SET encrypted_portal_session = $1,
               espm_login = $2,
               encrypted_espm_password = $3
           WHERE id = $4""",
        encrypted, body.login, encrypted_password, user_id
    )

    # Verificar se já tem disciplinas vinculadas
    count = await db.fetchval(
        "SELECT COUNT(*) FROM user_disciplinas WHERE user_id = $1",
        user_id
    )

    disciplines_synced = 0
    if count == 0:
        # Primeira vez: extrair grade e vincular
        extractor = ScheduleExtractor()
        disciplines = await extractor.extract(state, logs)
        disciplines_synced = await _upsert_disciplinas(db, user_id, disciplines)
        logs.append(f"Vinculadas {disciplines_synced} disciplinas ao aluno.")
    else:
        disciplines_synced = count

    return ESPMLoginResponse(
        user_id=user_id,
        session_valid=True,
        disciplines_synced=disciplines_synced,
        logs=logs,
    )


# ── POST /sync-schedule ───────────────────────────────────────────────────────

@router.post("/sync-schedule", response_model=ESPMSyncResponse)
async def sync_schedule(
    body: ESPMSyncRequest,
    user_id: UUID = Depends(get_current_user),
    db=Depends(get_db),
    cfg: Settings = Depends(get_settings),
):
    """
    Força re-sincronização da grade horária.
    Faz login novo no portal (ignora sessão salva) e extrai disciplinas.
    """
    auth = ESPMAuthenticator(cfg.secret_key)
    extractor = ScheduleExtractor()
    logs: list[str] = []

    try:
        # login_and_extract usa uma única janela de browser (mais eficiente)
        result = await auth.login_and_extract(body.login, body.password, extractor)
        state = result["state"]
        disciplines = result["disciplines"]
        logs = result.get("logs", [])
    except AuthenticationError as exc:
        raise HTTPException(status_code=401, detail=str(exc))
    except PlaywrightTimeoutError as exc:
        raise HTTPException(status_code=504, detail=f"Timeout no portal: {exc}")

    # Salvar sessão + senha para scraper credential pool
    encrypted = auth.encrypt_session(state)
    encrypted_password = auth.encrypt_session({"p": body.password})
    await db.execute(
        """UPDATE users
           SET encrypted_portal_session = $1,
               espm_login = $2,
               encrypted_espm_password = $3
           WHERE id = $4""",
        encrypted, body.login, encrypted_password, user_id
    )

    synced = await _upsert_disciplinas(db, user_id, disciplines)
    logs.append(f"Sync completo: {synced} disciplinas.")

    return ESPMSyncResponse(disciplines_synced=synced, logs=logs)


# ── GET /schedule ──────────────────────────────────────────────────────────────

@router.get("/schedule", response_model=ScheduleResponse)
async def get_schedule(
    user_id: UUID = Depends(get_current_user),
    db=Depends(get_db),
):
    """Retorna as disciplinas do aluno extraídas do portal ESPM."""
    rows = await db.fetch(
        """
        SELECT d.id, d.nome, d.professor, d.horario, d.semestre, d.horarios
        FROM disciplinas d
        JOIN user_disciplinas ud ON d.id = ud.disciplina_id
        WHERE ud.user_id = $1
        ORDER BY d.nome
        """,
        user_id
    )
    disciplinas = [DisciplinaPortalOut(**dict(r)) for r in rows]
    return ScheduleResponse(disciplinas=disciplinas)


# ── Helper: upsert disciplinas ────────────────────────────────────────────────

async def _upsert_disciplinas(db, user_id: UUID, disciplines: list[dict]) -> int:
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
            # asyncpg needs a JSON string for JSONB columns
            horarios_json = json.dumps(disc.get("horarios") or [])
            # days is text[] in DB — pass list directly (asyncpg handles it)
            days_val = disc.get("days") or []

            disc_id = await db.fetchval(
                """
                INSERT INTO disciplinas (
                    turma, nome, professor, horario, semestre, codigo_espm,
                    horarios, days, time_start, time_end, period_start, period_end
                )
                VALUES ($1,$2,$3,$4,$5,$6,$7::jsonb,$8,$9,$10,$11,$12)
                ON CONFLICT ON CONSTRAINT disciplinas_nome_semestre_unique
                DO UPDATE SET
                    turma        = COALESCE(EXCLUDED.turma,       disciplinas.turma),
                    professor    = COALESCE(EXCLUDED.professor,   disciplinas.professor),
                    horario      = COALESCE(EXCLUDED.horario,     disciplinas.horario),
                    horarios     = COALESCE(EXCLUDED.horarios,    disciplinas.horarios),
                    days         = COALESCE(EXCLUDED.days,        disciplinas.days),
                    time_start   = COALESCE(EXCLUDED.time_start,  disciplinas.time_start),
                    time_end     = COALESCE(EXCLUDED.time_end,    disciplinas.time_end),
                    period_start = COALESCE(EXCLUDED.period_start,disciplinas.period_start),
                    period_end   = COALESCE(EXCLUDED.period_end,  disciplinas.period_end)
                RETURNING id
                """,
                disc.get("turma"),
                disc["nome"],
                disc.get("professor"),
                disc.get("horario"),
                disc.get("semestre"),
                disc.get("codigo_espm"),
                horarios_json,
                days_val,
                disc.get("time_start"),
                disc.get("time_end"),
                disc.get("period_start"),
                disc.get("period_end"),
            )

            await db.execute(
                """
                INSERT INTO user_disciplinas (user_id, disciplina_id)
                VALUES ($1, $2)
                ON CONFLICT (user_id, disciplina_id) DO NOTHING
                """,
                user_id, disc_id,
            )
            count += 1

        except Exception as exc:
            logger.error(
                "upsert_disciplinas.error",
                name=disc.get("nome"),
                error=str(exc),
            )

    return count
