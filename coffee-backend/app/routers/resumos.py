import json
from typing import Optional
from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, status

from app.database import fetch_all, fetch_one
from app.dependencies import get_current_user
from app.schemas.base import error_response, success_response
from app.schemas.resumos import AtualizarTituloRequest, GerarResumoRequest, ResumoResponse
from app.services.openai_service import OpenAIService

router = APIRouter(prefix="/api/v1/resumos", tags=["resumos"])

_openai = OpenAIService()


def _row_to_resumo(row) -> ResumoResponse:
    data = dict(row)
    topicos_raw = data["topicos"]
    if isinstance(topicos_raw, str):
        topicos_raw = json.loads(topicos_raw)
    topicos = [
        t if isinstance(t, dict) else {"titulo": t, "conteudo": ""}
        for t in (topicos_raw or [])
    ]

    conceitos = data["conceitos_chave"]
    if isinstance(conceitos, str):
        conceitos = json.loads(conceitos)

    return ResumoResponse(
        id=data["id"],
        transcricao_id=data["transcricao_id"],
        titulo=data["titulo"] or "",
        topicos=topicos,
        conceitos_chave=conceitos or [],
        resumo_geral=data["resumo_geral"] or "",
        modelo_usado=data["modelo_usado"] or "gpt-4o-mini",
        tokens_usados=data["tokens_usados"] or 0,
        created_at=data["created_at"],
    )


# ── POST /api/v1/resumos ──────────────────────────────────────────────────────

@router.post("", status_code=status.HTTP_201_CREATED)
async def gerar_resumo(
    body: GerarResumoRequest,
    user_id: UUID = Depends(get_current_user),
):
    """Gera um resumo estruturado via GPT-4o-mini para uma transcrição."""
    trans_row = await fetch_one(
        """
        SELECT t.id, t.texto, g.user_id, g.disciplina_id
        FROM transcricoes t
        JOIN gravacoes g ON g.id = t.gravacao_id
        WHERE t.id = $1
        """,
        body.transcricao_id,
    )
    if not trans_row:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND,
                            detail=error_response("NOT_FOUND", "Transcrição não encontrada"))
    if trans_row["user_id"] != user_id:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN,
                            detail=error_response("ACCESS_DENIED", "Acesso negado"))

    existing = await fetch_one(
        "SELECT * FROM resumos WHERE transcricao_id = $1",
        body.transcricao_id,
    )
    if existing:
        return success_response(_row_to_resumo(existing).model_dump(mode="json"))

    disc_row = await fetch_one(
        "SELECT nome FROM disciplinas WHERE id = $1",
        trans_row["disciplina_id"],
    )
    course_name = disc_row["nome"] if disc_row else "Disciplina"

    try:
        summary = await _openai.generate_summary(trans_row["texto"], course_name)
    except Exception as exc:
        raise HTTPException(
            status_code=status.HTTP_502_BAD_GATEWAY,
            detail=error_response("AI_ERROR", "Erro ao gerar resumo"),
        )

    topicos = summary.get("topicos", [])
    conceitos = summary.get("conceitos_chave", [])
    tokens_usados = summary.get("tokens_usados", 0)

    row = await fetch_one(
        """
        INSERT INTO resumos (
            transcricao_id, titulo, topicos, conceitos_chave,
            resumo_geral, modelo_usado, tokens_usados
        )
        VALUES ($1, $2, $3::jsonb, $4::jsonb, $5, 'gpt-4o-mini', $6)
        RETURNING *
        """,
        body.transcricao_id,
        summary.get("titulo", ""),
        json.dumps(topicos),
        json.dumps(conceitos),
        summary.get("resumo_geral", ""),
        tokens_usados,
    )
    return success_response(_row_to_resumo(row).model_dump(mode="json"))


# ── GET /api/v1/resumos/{transcricao_id} ─────────────────────────────────────

@router.get("/{transcricao_id}")
async def get_resumo(
    transcricao_id: UUID,
    user_id: UUID = Depends(get_current_user),
):
    """Retorna o resumo de uma transcrição específica."""
    row = await fetch_one(
        """
        SELECT r.*
        FROM resumos r
        JOIN transcricoes t ON t.id = r.transcricao_id
        JOIN gravacoes g ON g.id = t.gravacao_id
        WHERE r.transcricao_id = $1 AND g.user_id = $2
        """,
        transcricao_id,
        user_id,
    )
    if not row:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND,
                            detail=error_response("NOT_FOUND", "Resumo não encontrado"))
    return success_response(_row_to_resumo(row).model_dump(mode="json"))


# ── PATCH /api/v1/resumos/{resumo_id}/titulo ─────────────────────────────────

@router.patch("/{resumo_id}/titulo")
async def atualizar_titulo(
    resumo_id: UUID,
    body: AtualizarTituloRequest,
    user_id: UUID = Depends(get_current_user),
):
    row = await fetch_one(
        """
        UPDATE resumos SET titulo=$1 WHERE id=$2
        RETURNING *
        """,
        body.titulo, resumo_id,
    )
    if not row:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND,
                            detail=error_response("NOT_FOUND", "Resumo não encontrado"))
    return success_response(_row_to_resumo(row).model_dump(mode="json"))


# ── GET /api/v1/resumos?disciplina_id= ───────────────────────────────────────

@router.get("")
async def listar_resumos(
    disciplina_id: Optional[UUID] = None,
    user_id: UUID = Depends(get_current_user),
):
    """Lista resumos do usuário, opcionalmente filtrado por disciplina."""
    if disciplina_id:
        rows = await fetch_all(
            """
            SELECT r.*
            FROM resumos r
            JOIN transcricoes t ON t.id = r.transcricao_id
            JOIN gravacoes g ON g.id = t.gravacao_id
            WHERE g.user_id = $1 AND g.disciplina_id = $2
            ORDER BY r.created_at DESC
            """,
            user_id,
            disciplina_id,
        )
    else:
        rows = await fetch_all(
            """
            SELECT r.*
            FROM resumos r
            JOIN transcricoes t ON t.id = r.transcricao_id
            JOIN gravacoes g ON g.id = t.gravacao_id
            WHERE g.user_id = $1
            ORDER BY r.created_at DESC
            """,
            user_id,
        )
    return success_response([_row_to_resumo(r).model_dump(mode="json") for r in rows])
