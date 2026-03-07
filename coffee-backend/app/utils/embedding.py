import re
from openai import AsyncOpenAI


def chunk_text(text: str, chunk_size: int = 500, overlap: int = 100) -> list[str]:
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


async def generate_embeddings(texts: list[str], client: AsyncOpenAI) -> list[list[float]]:
    response = await client.embeddings.create(
        model="text-embedding-3-small",
        input=texts,
    )
    return [item.embedding for item in response.data]
