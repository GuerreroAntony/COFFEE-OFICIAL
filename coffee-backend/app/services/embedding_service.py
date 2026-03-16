"""
Embedding service — gerar e remover embeddings no pgvector.
Usado por: gravacoes (transcrições), materiais (toggle ai_enabled), scraper.

Contextual Retrieval: antes de embedar, GPT-4o-mini gera um prefixo de contexto
que situa cada chunk dentro do documento completo. O embedding é feito sobre
chunk+prefixo, mas o texto_chunk armazenado é o original (sem prefixo).
Isso melhora a qualidade da busca semântica em ~49% (benchmark Anthropic).
"""
import asyncio
import json
import logging
from typing import Optional
from uuid import UUID
from app.database import fetch_all, execute_query
from app.utils.embedding import chunk_text, generate_embeddings
from app.services.openai_service import OpenAIService

logger = logging.getLogger("embedding_service")
_openai = OpenAIService()

# Max concurrent context prefix calls to avoid rate limiting
_CONTEXT_SEMAPHORE = asyncio.Semaphore(5)


async def _generate_prefix_safe(full_doc: str, chunk: str) -> str:
    """Generate context prefix with concurrency control and error handling."""
    async with _CONTEXT_SEMAPHORE:
        try:
            return await _openai.generate_context_prefix(full_doc, chunk)
        except Exception as e:
            logger.warning("Context prefix generation failed, using empty prefix: %s", e)
            return ""


async def generate_transcription_embeddings(
    transcription: str,
    gravacao_id: UUID,
    disciplina_id: Optional[UUID],
) -> int:
    """
    Chunk a transcrição, gera embeddings com contextual retrieval, salva no pgvector.
    Retorna número de chunks criados.

    Contextual Retrieval: cada chunk recebe um prefixo de contexto gerado por
    GPT-4o-mini antes de ser embedado. O texto_chunk armazenado é o ORIGINAL
    (sem prefixo) — o prefixo só melhora a representação vetorial.

    IMPORTANTE: disciplina_id é necessário pra filtrar embeddings no RAG.
    Para gravações em repositórios, disciplina_id é NULL no pgvector
    e a busca filtra por fonte_id diretamente.
    """
    try:
        if not transcription or not transcription.strip():
            return 0

        chunks = chunk_text(transcription)  # 500 palavras, 100 overlap
        if not chunks:
            return 0

        # Generate context prefixes in parallel (with concurrency limit)
        prefix_tasks = [_generate_prefix_safe(transcription, chunk) for chunk in chunks]
        prefixes = await asyncio.gather(*prefix_tasks)

        # Embed the prefixed versions (better semantic representation)
        prefixed_chunks = [
            f"{prefix}\n\n{chunk}" if prefix else chunk
            for prefix, chunk in zip(prefixes, chunks)
        ]
        embeddings = await _openai.create_embeddings(prefixed_chunks)

        # Store ORIGINAL chunk text (not prefixed) — prefix only improves embedding
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
    except Exception as e:
        logger.error("Erro ao gerar embeddings para gravação %s: %s", gravacao_id, e)
        return 0


async def generate_material_embeddings(
    texto: str,
    material_id: UUID,
    disciplina_id: UUID,
    material_nome: str = "Material",
) -> int:
    """Chunk texto do material, gera embeddings com contextual retrieval, salva no pgvector.

    material_nome is used to enrich the context prefix generation.
    """
    if not texto or not texto.strip():
        return 0

    chunks = chunk_text(texto)
    if not chunks:
        return 0

    # Prepend material name to the document context for better prefix generation
    doc_with_context = f"Material: {material_nome}\n\n{texto}"

    # Generate context prefixes in parallel
    prefix_tasks = [_generate_prefix_safe(doc_with_context, chunk) for chunk in chunks]
    prefixes = await asyncio.gather(*prefix_tasks)

    # Embed prefixed versions
    prefixed_chunks = [
        f"{prefix}\n\n{chunk}" if prefix else chunk
        for prefix, chunk in zip(prefixes, chunks)
    ]
    embeddings = await _openai.create_embeddings(prefixed_chunks)

    # Store original chunk text
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
