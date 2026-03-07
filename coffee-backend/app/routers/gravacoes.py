from uuid import UUID

from fastapi import APIRouter, Depends, File, HTTPException, UploadFile, status

from app.database import execute_query, fetch_all, fetch_one
from app.dependencies import get_current_user
from app.schemas.gravacoes import (
    CriarGravacaoRequest,
    GravacaoListResponse,
    GravacaoResponse,
    TranscricaoResponse,
)
from app.services.openai_service import OpenAIService

router = APIRouter(prefix="/api/v1/gravacoes", tags=["gravacoes"])

_openai = OpenAIService()


@router.post("", response_model=GravacaoResponse, status_code=status.HTTP_201_CREATED)
async def criar_gravacao(
    body: CriarGravacaoRequest,
    user_id: UUID = Depends(get_current_user),
):
    """Create a gravacao entry before uploading audio."""
    enrolled = await fetch_one(
        "SELECT 1 FROM user_disciplinas WHERE user_id = $1 AND disciplina_id = $2",
        user_id,
        body.disciplina_id,
    )
    if not enrolled:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Acesso negado")

    row = await fetch_one(
        """
        INSERT INTO gravacoes (user_id, disciplina_id, data_aula, status)
        VALUES ($1, $2, $3, 'recording')
        RETURNING id, disciplina_id, data_aula, duracao_segundos, status, created_at
        """,
        user_id,
        body.disciplina_id,
        body.data_aula,
    )
    return GravacaoResponse(**dict(row))


@router.post("/{gravacao_id}/upload", response_model=GravacaoResponse)
async def upload_audio(
    gravacao_id: UUID,
    file: UploadFile = File(...),
    user_id: UUID = Depends(get_current_user),
):
    """Upload audio file, transcribe with Whisper, save result."""
    row = await fetch_one(
        "SELECT * FROM gravacoes WHERE id = $1 AND user_id = $2",
        gravacao_id,
        user_id,
    )
    if not row:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Gravação não encontrada")

    audio_bytes = await file.read()
    filename = file.filename or "audio.m4a"

    # Transcribe via Whisper
    await execute_query(
        "UPDATE gravacoes SET status = 'processing' WHERE id = $1",
        gravacao_id,
    )
    try:
        texto = await _openai.transcribe_audio(audio_bytes, filename)
    except Exception as exc:
        await execute_query(
            "UPDATE gravacoes SET status = 'failed' WHERE id = $1",
            gravacao_id,
        )
        raise HTTPException(
            status_code=status.HTTP_502_BAD_GATEWAY,
            detail=f"Erro na transcrição: {exc}",
        )

    # Estimate duration from file size (rough: ~16kbps for m4a)
    duracao = max(1, len(audio_bytes) // 2000)

    # Save transcription
    trans_row = await fetch_one(
        """
        INSERT INTO transcricoes (gravacao_id, texto, idioma, confianca)
        VALUES ($1, $2, 'pt-BR', 1.0)
        RETURNING id, gravacao_id, texto, idioma, confianca, created_at
        """,
        gravacao_id,
        texto,
    )

    # Mark completed
    updated = await fetch_one(
        """
        UPDATE gravacoes SET status = 'completed', duracao_segundos = $2
        WHERE id = $1
        RETURNING id, disciplina_id, data_aula, duracao_segundos, status, created_at
        """,
        gravacao_id,
        duracao,
    )

    return GravacaoResponse(
        **dict(updated),
        transcricao=TranscricaoResponse(**dict(trans_row)),
    )


@router.get("/disciplina/{disciplina_id}", response_model=GravacaoListResponse)
async def listar_gravacoes(
    disciplina_id: UUID,
    user_id: UUID = Depends(get_current_user),
):
    """List all completed recordings for a discipline."""
    enrolled = await fetch_one(
        "SELECT 1 FROM user_disciplinas WHERE user_id = $1 AND disciplina_id = $2",
        user_id,
        disciplina_id,
    )
    if not enrolled:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Acesso negado")

    rows = await fetch_all(
        """
        SELECT g.id, g.disciplina_id, g.data_aula, g.duracao_segundos, g.status, g.created_at,
               t.id AS t_id, t.gravacao_id AS t_gravacao_id,
               t.texto, t.idioma, t.confianca, t.created_at AS t_created_at
        FROM gravacoes g
        LEFT JOIN transcricoes t ON t.gravacao_id = g.id
        WHERE g.user_id = $1 AND g.disciplina_id = $2
        ORDER BY g.data_aula DESC, g.created_at DESC
        """,
        user_id,
        disciplina_id,
    )

    gravacoes = []
    for r in rows:
        trans = None
        if r["t_id"]:
            trans = TranscricaoResponse(
                id=r["t_id"],
                gravacao_id=r["t_gravacao_id"],
                texto=r["texto"],
                idioma=r["idioma"],
                confianca=r["confianca"],
                created_at=r["t_created_at"],
            )
        gravacoes.append(
            GravacaoResponse(
                id=r["id"],
                disciplina_id=r["disciplina_id"],
                data_aula=r["data_aula"],
                duracao_segundos=r["duracao_segundos"],
                status=r["status"],
                created_at=r["created_at"],
                transcricao=trans,
            )
        )
    return GravacaoListResponse(gravacoes=gravacoes)


@router.get("/{gravacao_id}", response_model=GravacaoResponse)
async def get_gravacao(
    gravacao_id: UUID,
    user_id: UUID = Depends(get_current_user),
):
    """Get a single recording with its transcription."""
    row = await fetch_one(
        """
        SELECT g.id, g.disciplina_id, g.data_aula, g.duracao_segundos, g.status, g.created_at,
               t.id AS t_id, t.gravacao_id AS t_gravacao_id,
               t.texto, t.idioma, t.confianca, t.created_at AS t_created_at
        FROM gravacoes g
        LEFT JOIN transcricoes t ON t.gravacao_id = g.id
        WHERE g.id = $1 AND g.user_id = $2
        """,
        gravacao_id,
        user_id,
    )
    if not row:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Gravação não encontrada")

    trans = None
    if row["t_id"]:
        trans = TranscricaoResponse(
            id=row["t_id"],
            gravacao_id=row["t_gravacao_id"],
            texto=row["texto"],
            idioma=row["idioma"],
            confianca=row["confianca"],
            created_at=row["t_created_at"],
        )
    return GravacaoResponse(
        id=row["id"],
        disciplina_id=row["disciplina_id"],
        data_aula=row["data_aula"],
        duracao_segundos=row["duracao_segundos"],
        status=row["status"],
        created_at=row["created_at"],
        transcricao=trans,
    )


@router.delete("/{gravacao_id}", status_code=status.HTTP_204_NO_CONTENT)
async def deletar_gravacao(
    gravacao_id: UUID,
    user_id: UUID = Depends(get_current_user),
):
    """Delete a recording and its transcription (cascade)."""
    result = await execute_query(
        "DELETE FROM gravacoes WHERE id = $1 AND user_id = $2",
        gravacao_id,
        user_id,
    )
    if result == "DELETE 0":
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Gravação não encontrada")
