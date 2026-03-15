from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, status

from app.database import fetch_all, fetch_one
from app.dependencies import get_current_user
from app.schemas.base import error_response, success_response
from app.schemas.disciplinas import (
    DisciplinaDetailResponse,
    DisciplinaResponse,
)

router = APIRouter(prefix="/api/v1/disciplinas", tags=["disciplinas"])


@router.get("")
async def list_disciplinas(user_id: UUID = Depends(get_current_user)):
    """Lista disciplinas do aluno com contagens e ai_active."""
    rows = await fetch_all(
        """
        SELECT d.id, d.nome, d.turma, d.semestre, d.sala, d.canvas_course_id,
               to_char(d.last_scraped_at AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"') AS last_synced_at,
               COUNT(DISTINCT g.id) FILTER (WHERE g.status = 'ready') AS gravacoes_count,
               COUNT(DISTINCT m.id) AS materiais_count,
               EXISTS (SELECT 1 FROM embeddings e WHERE e.disciplina_id = d.id) AS ai_active
        FROM disciplinas d
        JOIN user_disciplinas ud ON d.id = ud.disciplina_id
        LEFT JOIN gravacoes g ON g.source_type = 'disciplina' AND g.source_id = d.id AND g.user_id = $1
        LEFT JOIN materiais m ON m.disciplina_id = d.id
        WHERE ud.user_id = $1
        GROUP BY d.id
        ORDER BY d.nome
        """,
        user_id,
    )
    disciplinas = [DisciplinaResponse(**dict(r)).model_dump(mode="json") for r in rows]
    return success_response(disciplinas)


@router.get("/{disciplina_id}")
async def get_disciplina(
    disciplina_id: UUID,
    user_id: UUID = Depends(get_current_user),
):
    """Detalhe de uma disciplina."""
    enrolled = await fetch_one(
        "SELECT 1 FROM user_disciplinas WHERE user_id = $1 AND disciplina_id = $2",
        user_id, disciplina_id,
    )
    if not enrolled:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail=error_response("ACCESS_DENIED", "Acesso negado"))

    row = await fetch_one(
        """
        SELECT d.id, d.nome, d.turma, d.semestre, d.sala, d.canvas_course_id,
               to_char(d.last_scraped_at AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"') AS last_synced_at,
               COUNT(DISTINCT g.id) FILTER (WHERE g.status = 'ready') AS gravacoes_count,
               COUNT(DISTINCT m.id) AS materiais_count,
               EXISTS (SELECT 1 FROM embeddings e WHERE e.disciplina_id = d.id) AS ai_active
        FROM disciplinas d
        LEFT JOIN gravacoes g ON g.source_type = 'disciplina' AND g.source_id = d.id AND g.user_id = $2
        LEFT JOIN materiais m ON m.disciplina_id = d.id
        WHERE d.id = $1
        GROUP BY d.id
        """,
        disciplina_id, user_id,
    )
    if not row:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail=error_response("NOT_FOUND", "Disciplina não encontrada"))

    # Contract v3.1: "Same object as list item" (flat, no wrapping)
    disc = DisciplinaResponse(**dict(row))
    return success_response(disc.model_dump(mode="json"))
