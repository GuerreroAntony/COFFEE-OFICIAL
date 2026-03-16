from __future__ import annotations
from typing import AsyncGenerator, Optional
from openai import AsyncOpenAI
from app.config import settings


class OpenAIService:
    def __init__(self):
        self.client = AsyncOpenAI(api_key=settings.OPENAI_API_KEY)

    async def generate_summary(self, transcription: str, course_name: str) -> dict:
        response = await self.client.chat.completions.create(
            model="gpt-4o-mini",
            messages=[
                {
                    "role": "system",
                    "content": (
                        "Você é um assistente acadêmico. A partir da transcrição abaixo de uma aula, "
                        "gere um resumo estruturado.\n\n"
                        "Retorne APENAS um JSON válido neste formato:\n"
                        "{\n"
                        '  "titulo": "Tema da Aula (MÁXIMO 4 palavras)",\n'
                        '  "topicos": [\n'
                        '    {\n'
                        '      "titulo": "Nome do tópico",\n'
                        '      "conteudo": "Resumo do conteúdo desse tópico em 2-4 frases."\n'
                        '    }\n'
                        '  ],\n'
                        '  "conceitos_chave": [\n'
                        '    {"termo": "termo", "definicao": "definição"}\n'
                        '  ],\n'
                        '  "resumo_geral": "resumo geral aqui"\n'
                        "}\n\n"
                        "Regras:\n"
                        "- Entre 3 e 6 tópicos\n"
                        "- Linguagem clara e objetiva\n"
                        "- Preserve termos técnicos da área\n"
                        "- Não inclua nada fora do JSON"
                    ),
                },
                {
                    "role": "user",
                    "content": f"Disciplina: {course_name}\n\nTranscrição:\n{transcription}",
                },
            ],
            response_format={"type": "json_object"},
        )
        import json
        return json.loads(response.choices[0].message.content)

    async def chat_rag(
        self,
        messages: list,
        context_chunks: list,
        model: str = "gpt-4o",
        system_prompt: str | None = None,
    ) -> AsyncGenerator[str, None]:
        formatted_context = "\n\n---\n\n".join(context_chunks)
        base_prompt = system_prompt or "Você é o assistente acadêmico do Coffee. Responda com profundidade moderada e tom neutro."
        full_system = (
            f"{base_prompt}\n\n"
            "Você tem acesso aos seguintes materiais de aula do aluno:\n\n"
            f"{formatted_context}\n\n"
            "Sempre cite a fonte quando usar informação dos materiais. "
            "Formato de citação: [Aula DD/MM] ou [Transcrição DD/MM]. "
            "Se não encontrar a informação nos materiais, diga isso claramente."
        )

        stream = await self.client.chat.completions.create(
            model=model,
            messages=[{"role": "system", "content": full_system}, *messages],
            stream=True,
        )
        async for chunk in stream:
            delta = chunk.choices[0].delta.content
            if delta:
                yield delta

    async def generate_context_prefix(self, full_document: str, chunk_text: str) -> str:
        """Generate a concise context prefix for a chunk using GPT-4o-mini.

        Anthropic's Contextual Retrieval technique: before embedding a chunk,
        we ask a fast LLM to generate 1-2 sentences situating the chunk within
        the full document. This prefix is prepended to the chunk text ONLY for
        embedding — the stored texto_chunk remains the original text.
        """
        # Truncate document to ~15k chars to stay within token limits
        doc_preview = full_document[:15000]

        response = await self.client.chat.completions.create(
            model="gpt-4o-mini",
            messages=[
                {
                    "role": "user",
                    "content": (
                        f"<document>\n{doc_preview}\n</document>\n\n"
                        f"Aqui está um trecho desse documento:\n<chunk>\n{chunk_text}\n</chunk>\n\n"
                        "Forneça um contexto curto e específico (1-2 frases) para situar "
                        "este trecho dentro do documento completo. "
                        "Responda APENAS com o contexto, sem explicações."
                    ),
                }
            ],
            max_tokens=150,
            temperature=0,
        )
        return response.choices[0].message.content.strip()

    async def create_embeddings(self, texts: list[str]) -> list[list[float]]:
        response = await self.client.embeddings.create(
            model="text-embedding-3-small",
            input=texts,
        )
        return [item.embedding for item in response.data]
