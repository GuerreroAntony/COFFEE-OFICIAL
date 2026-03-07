"""
Embedding service — gerar e remover embeddings no pgvector.
Usado por: gravacoes (transcrições), materiais (toggle ai_enabled), scraper.
"""
import json
from uuid import UUID
from app.database import fetch_all, execute_query
from app.utils.embedding import chunk_text, generate_embeddings
from app.services.openai_service import OpenAIService

_openai = OpenAIService()


async def generate_transcription_embeddings(
    transcription: str,
    gravacao_id: UUID,
    disciplina_id: UUID,
) -> int:
    """
    Chunk a transcrição, gera embeddings, salva no pgvector.
    Retorna número de chunks criados.

    IMPORTANTE: disciplina_id é necessário pra filtrar embeddings no RAG.
    Para gravações em repositórios, disciplina_id é NULL no pgvector
    e a busca filtra por fonte_id diretamente.
    """
    if not transcription or not transcription.strip():
        return 0

    chunks = chunk_text(transcription)  # 500 palavras, 100 overlap
    if not chunks:
        return 0

    embeddings = await _openai.create_embeddings(chunks)

    for i, (chunk, emb) in enumerate(zip(chunks, embeddings)):
        vec_str = "[" + ",".join(str(x) for x in emb) + "]"
        metadata = json.dumps({"gravacao_id": str(gravacao_id), "chunk_index": i})
        await execute_query(
            """INSERT INTO embeddings
               (disciplina_id, fonte_tipo, fonte_id, chunk_index, texto_chunk, embedding, metadata)
               VALUES ($1, 'transcricao', $2, $3, $4, $5::vector, $6::jsonb)""",
            disciplina_id, gravacao_id, i, chunk, vec_str, metadata,
        )

    return len(chunks)


async def generate_material_embeddings(
    texto: str,
    material_id: UUID,
    disciplina_id: UUID,
) -> int:
    """Chunk texto do material, gera embeddings, salva no pgvector."""
    if not texto or not texto.strip():
        return 0

    chunks = chunk_text(texto)
    if not chunks:
        return 0

    embeddings = await _openai.create_embeddings(chunks)

    for i, (chunk, emb) in enumerate(zip(chunks, embeddings)):
        vec_str = "[" + ",".join(str(x) for x in emb) + "]"
        metadata = json.dumps({"material_id": str(material_id), "chunk_index": i})
        await execute_query(
            """INSERT INTO embeddings
               (disciplina_id, fonte_tipo, fonte_id, chunk_index, texto_chunk, embedding, metadata)
               VALUES ($1, 'material', $2, $3, $4, $5::vector, $6::jsonb)""",
            disciplina_id, material_id, i, chunk, vec_str, metadata,
        )

    return len(chunks)


async def remove_embeddings(fonte_id: UUID) -> int:
    """Remove todos os embeddings de uma fonte (gravação ou material)."""
    result = await execute_query(
        "DELETE FROM embeddings WHERE fonte_id = $1",
        fonte_id,
    )
    # result é "DELETE N" — extrair N
    try:
        return int(result.split()[-1])
    except:
        return 0
