from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, status

from app.database import execute_query, fetch_all, fetch_one
from app.dependencies import get_current_user
from app.schemas.base import error_response, success_response
from app.schemas.repositorios import CriarRepositorioRequest, RepositorioResponse

router = APIRouter(prefix="/api/v1/repositorios", tags=["repositorios"])


# ── GET /repositorios ────────────────────────────────────────

@router.get("")
async def listar_repositorios(
    user_id: UUID = Depends(get_current_user),
):
    """Listar repositórios do aluno."""
    rows = await fetch_all(
        """SELECT r.id, r.nome, r.icone, r.created_at,
                  (SELECT COUNT(*) FROM gravacoes g
                   WHERE g.source_type = 'repositorio' AND g.source_id = r.id) AS gravacoes_count,
                  EXISTS(
                      SELECT 1 FROM gravacoes g
                      WHERE g.source_type = 'repositorio' AND g.source_id = r.id AND g.status = 'ready'
                  ) AS ai_active
           FROM repositorios r
           WHERE r.user_id = $1
           ORDER BY r.created_at DESC""",
        user_id,
    )

    items = [
        RepositorioResponse(
            id=r["id"],
            nome=r["nome"],
            icone=r["icone"],
            gravacoes_count=r["gravacoes_count"],
            ai_active=r["ai_active"],
            created_at=r["created_at"],
        ).model_dump(mode="json")
        for r in rows
    ]
    return success_response(items)


# ── POST /repositorios ───────────────────────────────────────

@router.post("", status_code=status.HTTP_201_CREATED)
async def criar_repositorio(
    body: CriarRepositorioRequest,
    user_id: UUID = Depends(get_current_user),
):
    """Criar novo repositório."""
    row = await fetch_one(
        """INSERT INTO repositorios (user_id, nome, icone)
           VALUES ($1, $2, $3)
           RETURNING id, nome, icone, created_at""",
        user_id, body.nome, body.icone,
    )

    resp = RepositorioResponse(
        id=row["id"],
        nome=row["nome"],
        icone=row["icone"],
        gravacoes_count=0,
        ai_active=False,
        created_at=row["created_at"],
    )
    return success_response(resp.model_dump(mode="json"))


# ── DELETE /repositorios/{id} ─────────────────────────────────

@router.delete("/{repo_id}", status_code=status.HTTP_204_NO_CONTENT)
async def deletar_repositorio(
    repo_id: UUID,
    user_id: UUID = Depends(get_current_user),
):
    """Excluir repositório. Gravações órfãs ficam com source_id=NULL."""
    # Verify ownership
    row = await fetch_one(
        "SELECT id FROM repositorios WHERE id = $1 AND user_id = $2",
        repo_id, user_id,
    )
    if not row:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail=error_response("NOT_FOUND", "Repositório não encontrado"))

    # Set orphan gravações source_id to NULL
    await execute_query(
        "UPDATE gravacoes SET source_id = NULL WHERE source_type = 'repositorio' AND source_id = $1",
        repo_id,
    )

    # Delete repository
    await execute_query(
        "DELETE FROM repositorios WHERE id = $1",
        repo_id,
    )
