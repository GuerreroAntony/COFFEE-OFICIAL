"""
Re-embedding script: regenera todos os embeddings existentes com Contextual Retrieval.

Uso:
    cd coffee-backend
    python -m scripts.reembed_with_context

O que faz:
1. Busca todas as gravações e materiais que já têm embeddings
2. Deleta embeddings antigos
3. Re-gera com prefixo de contexto (GPT-4o-mini) antes de embedar

ATENÇÃO: Este script consome tokens da OpenAI (GPT-4o-mini para prefixos +
text-embedding-3-small para embeddings). Custo estimado: ~$0.0006 por documento.
"""
import asyncio
import logging
import sys

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
logger = logging.getLogger("reembed")


async def main():
    # Import after setting up — these need the app config loaded
    from app.database import fetch_all, execute_query, get_pool, close_pool
    from app.services.embedding_service import (
        generate_transcription_embeddings,
        generate_material_embeddings,
        remove_embeddings,
    )

    await get_pool()  # Initialize connection pool

    try:
        # ── Re-embed transcriptions ──
        gravacoes = await fetch_all(
            """SELECT DISTINCT g.id, g.transcription, g.source_type, g.source_id,
                      CASE WHEN g.source_type = 'disciplina' THEN g.source_id ELSE NULL END AS disciplina_id
               FROM gravacoes g
               JOIN embeddings e ON e.fonte_tipo = 'transcricao' AND e.fonte_id = g.id
               WHERE g.transcription IS NOT NULL AND g.transcription != ''
               ORDER BY g.id"""
        )
        logger.info("Found %d transcriptions to re-embed", len(gravacoes))

        for i, g in enumerate(gravacoes):
            logger.info("[%d/%d] Re-embedding transcription %s...", i + 1, len(gravacoes), g["id"])
            await remove_embeddings(g["id"])
            count = await generate_transcription_embeddings(
                g["transcription"], g["id"], g["disciplina_id"]
            )
            logger.info("  → %d chunks created", count)

        # ── Re-embed materials ──
        materiais = await fetch_all(
            """SELECT DISTINCT m.id, m.nome, m.texto_extraido, m.disciplina_id
               FROM materiais m
               JOIN embeddings e ON e.fonte_tipo = 'material' AND e.fonte_id = m.id
               WHERE m.texto_extraido IS NOT NULL AND m.texto_extraido != ''
                 AND m.ai_enabled = true
               ORDER BY m.id"""
        )
        logger.info("Found %d materials to re-embed", len(materiais))

        for i, m in enumerate(materiais):
            logger.info("[%d/%d] Re-embedding material '%s' (%s)...", i + 1, len(materiais), m["nome"], m["id"])
            await remove_embeddings(m["id"])
            count = await generate_material_embeddings(
                m["texto_extraido"], m["id"], m["disciplina_id"], m["nome"]
            )
            logger.info("  → %d chunks created", count)

        logger.info("✅ Done! All embeddings regenerated with contextual retrieval.")

    finally:
        await close_pool()


if __name__ == "__main__":
    asyncio.run(main())
