from __future__ import annotations

import json
import logging
import re
from uuid import UUID

from openai import AsyncOpenAI

from scraper.config import settings
from scraper.db import save_embeddings_batch

logger = logging.getLogger(__name__)


def chunk_text(text: str, chunk_size: int = 500, overlap: int = 100) -> list[str]:
    """Split text into word-count chunks with overlap.

    Identical logic to coffee-backend/app/utils/embedding.py.
    """
    sentences = re.split(r"(?<=[.!?])\s+", text.strip())
    chunks: list[str] = []
    current_words: list[str] = []

    for sentence in sentences:
        words = sentence.split()
        if len(current_words) + len(words) > chunk_size and current_words:
            chunks.append(" ".join(current_words))
            current_words = current_words[-overlap:] if overlap else []
        current_words.extend(words)

    if current_words:
        chunks.append(" ".join(current_words))

    return chunks


async def generate_embeddings(
    texts: list[str], client: AsyncOpenAI
) -> list[list[float]]:
    """Generate text-embedding-3-small embeddings (1536 dimensions)."""
    response = await client.embeddings.create(
        model="text-embedding-3-small",
        input=texts,
    )
    return [item.embedding for item in response.data]


async def process_material(
    texto: str, disciplina_id: UUID, material_id: UUID
) -> int:
    """Chunk text, generate embeddings, save to DB. Returns chunk count."""
    if not texto or not texto.strip():
        logger.info("No text to embed for material %s", material_id)
        return 0

    chunks = chunk_text(texto)
    if not chunks:
        return 0

    client = AsyncOpenAI(api_key=settings.OPENAI_API_KEY)
    embeddings = await generate_embeddings(chunks, client)

    rows = []
    for i, (chunk, emb) in enumerate(zip(chunks, embeddings)):
        metadata = json.dumps({"material_id": str(material_id), "chunk_index": i})
        rows.append((disciplina_id, material_id, i, chunk, emb, metadata))

    await save_embeddings_batch(rows)
    logger.info("Created %d embedding chunks for material %s", len(rows), material_id)
    return len(rows)
