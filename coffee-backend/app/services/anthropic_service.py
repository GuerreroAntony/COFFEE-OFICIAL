"""Anthropic Claude integration for Cold Brew chat mode."""
from __future__ import annotations

from typing import AsyncGenerator

import anthropic
from app.config import settings


class AnthropicService:
    def __init__(self):
        self.client = anthropic.AsyncAnthropic(api_key=settings.ANTHROPIC_API_KEY)

    async def chat_rag(
        self,
        messages: list[dict],
        context_chunks: list[str],
        system_prompt: str | None = None,
    ) -> AsyncGenerator[str, None]:
        formatted_context = "\n\n---\n\n".join(context_chunks)
        system = (
            f"{system_prompt or 'Você é o assistente acadêmico do Coffee.'}\n\n"
            "Você tem acesso aos seguintes materiais de aula do aluno:\n\n"
            f"{formatted_context}\n\n"
            "Sempre cite a fonte quando usar informação dos materiais. "
            "Formato de citação: [Aula DD/MM] ou [Transcrição DD/MM]. "
            "Se não encontrar a informação nos materiais, diga isso claramente."
        )

        async with self.client.messages.stream(
            model="claude-opus-4-20250514",
            max_tokens=4096,
            system=system,
            messages=messages,
        ) as stream:
            async for text in stream.text_stream:
                yield text
