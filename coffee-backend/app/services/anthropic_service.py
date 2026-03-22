"""Anthropic Claude integration — single model for all Barista chat modes."""
from __future__ import annotations

import logging
from dataclasses import dataclass
from typing import AsyncGenerator

import anthropic
from app.config import settings

logger = logging.getLogger("coffee.anthropic")

# Single model for all modes (Barista v2)
SONNET = "claude-sonnet-4-20250514"
# Keep OPUS constant for backward compat but no longer used in chat
OPUS = "claude-opus-4-20250514"


@dataclass
class ChatResult:
    """Holds streaming text + token usage after stream completes."""
    input_tokens: int = 0
    output_tokens: int = 0


class AnthropicService:
    def __init__(self):
        self.client = anthropic.AsyncAnthropic(api_key=settings.ANTHROPIC_API_KEY)

    async def chat_rag(
        self,
        messages: list[dict],
        context_chunks: list[str],
        model: str = SONNET,
        system_prompt: str | None = None,
        result_holder: ChatResult | None = None,
    ) -> AsyncGenerator[str, None]:
        """Stream chat response with RAG context.

        If result_holder is provided, populates it with token counts
        after the stream completes (for budget tracking).
        """
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
            model=model,
            max_tokens=4096,
            system=system,
            messages=messages,
        ) as stream:
            async for text in stream.text_stream:
                yield text

            # After stream completes, capture usage
            if result_holder is not None:
                final_message = await stream.get_final_message()
                result_holder.input_tokens = final_message.usage.input_tokens
                result_holder.output_tokens = final_message.usage.output_tokens
