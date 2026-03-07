from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, status

from app.config import settings
from app.database import execute_query, fetch_all, fetch_one
from app.dependencies import get_current_user
from app.schemas.disciplinas import (
    CriarDisciplinaRequest,
    DisciplinaDetailResponse,
    DisciplinaListResponse,
    DisciplinaResponse,
    SeedRequest,
    VincularRequest,
)

router = APIRouter(prefix="/api/v1/disciplinas", tags=["disciplinas"])

_SEED_DATA = [
    ("Marketing Digital", "Prof. Ana Silva", "Seg 19h-21h", "2026.1"),
    ("Branding", "Prof. Carlos Lima", "Qua 19h-21h", "2026.1"),
    ("Finanças Corporativas", "Prof. Maria Santos", "Ter 21h-23h", "2026.1"),
    ("Gestão de Projetos", "Prof. Roberto Alves", "Qui 19h-21h", "2026.1"),
]


@router.post("", response_model=DisciplinaResponse, status_code=status.HTTP_201_CREATED)
async def criar_disciplina(body: CriarDisciplinaRequest, user_id: UUID = Depends(get_current_user)):
    row = await fetch_one(
        """INSERT INTO disciplinas (nome, professor, semestre)
           VALUES ($1, $2, $3)
           RETURNING id, nome,
                     COALESCE(professor,'') AS professor,
                     COALESCE(horario,'') AS horario,
                     COALESCE(semestre,'') AS semestre,
                     0 AS gravacoes_count""",
        body.nome, body.professor or "", body.semestre or "",
    )
    await execute_query(
        "INSERT INTO user_disciplinas (user_id, disciplina_id) VALUES ($1, $2)",
        user_id, row["id"],
    )
    return DisciplinaResponse(**dict(row))


@router.get("", response_model=DisciplinaListResponse)
async def list_disciplinas(user_id: UUID = Depends(get_current_user)):
    rows = await fetch_all(
        """
        SELECT d.id, d.nome, d.professor, d.horario, d.semestre, d.horarios,
               COUNT(g.id) FILTER (WHERE g.status = 'completed') AS gravacoes_count
        FROM disciplinas d
        JOIN user_disciplinas ud ON d.id = ud.disciplina_id
        LEFT JOIN gravacoes g ON d.id = g.disciplina_id AND g.user_id = $1
        WHERE ud.user_id = $1
        GROUP BY d.id
        ORDER BY d.nome
        """,
        user_id,
    )
    return DisciplinaListResponse(
        disciplinas=[DisciplinaResponse(**dict(r)) for r in rows]
    )


@router.post("/vincular", status_code=status.HTTP_201_CREATED)
async def vincular_disciplina(
    body: VincularRequest,
    user_id: UUID = Depends(get_current_user),
):
    await execute_query(
        """
        INSERT INTO user_disciplinas (user_id, disciplina_id)
        VALUES ($1, $2)
        ON CONFLICT DO NOTHING
        """,
        user_id,
        body.disciplina_id,
    )
    return {"message": "vinculado"}


@router.get("/{disciplina_id}", response_model=DisciplinaDetailResponse)
async def get_disciplina(
    disciplina_id: UUID,
    user_id: UUID = Depends(get_current_user),
):
    enrolled = await fetch_one(
        "SELECT 1 FROM user_disciplinas WHERE user_id = $1 AND disciplina_id = $2",
        user_id,
        disciplina_id,
    )
    if not enrolled:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Acesso negado")

    row = await fetch_one(
        """
        SELECT d.id, d.nome, d.professor, d.horario, d.semestre,
               COUNT(DISTINCT g.id) FILTER (WHERE g.status = 'completed') AS gravacoes_count
        FROM disciplinas d
        LEFT JOIN gravacoes g ON d.id = g.disciplina_id AND g.user_id = $2
        WHERE d.id = $1
        GROUP BY d.id
        """,
        disciplina_id,
        user_id,
    )
    if not row:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Disciplina não encontrada")

    materiais_count_row = await fetch_one(
        "SELECT COUNT(*) AS cnt FROM materiais WHERE disciplina_id = $1",
        disciplina_id,
    )
    materiais_count = materiais_count_row["cnt"] if materiais_count_row else 0

    return DisciplinaDetailResponse(
        disciplina=DisciplinaResponse(**dict(row)),
        gravacoes_count=row["gravacoes_count"] or 0,
        materiais_count=materiais_count,
    )


@router.post("/seed", status_code=status.HTTP_201_CREATED)
async def seed_disciplinas(body: SeedRequest):
    if settings.ENVIRONMENT != "development":
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Apenas em desenvolvimento")

    created = []
    for nome, professor, horario, semestre in _SEED_DATA:
        row = await fetch_one(
            """
            INSERT INTO disciplinas (nome, professor, horario, semestre)
            VALUES ($1, $2, $3, $4)
            ON CONFLICT DO NOTHING
            RETURNING id, nome, professor, horario, semestre
            """,
            nome, professor, horario, semestre,
        )
        if row:
            await execute_query(
                """
                INSERT INTO user_disciplinas (user_id, disciplina_id)
                VALUES ($1, $2) ON CONFLICT DO NOTHING
                """,
                body.user_id,
                row["id"],
            )
            created.append(row["nome"])

    return {"created": created, "total": len(created)}
