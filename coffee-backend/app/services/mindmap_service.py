"""
Mind Map service — generates 4x3 JSONB mind map via GPT-4o-mini.
Called after summary generation in the pipeline.

Based on reference implementation from mind-map-code/.
Includes validation + truncation for iOS layout safety.
"""
from __future__ import annotations

import json
import logging
from uuid import UUID

from app.database import fetch_one, execute_query
from app.services.openai_service import OpenAIService

logger = logging.getLogger("mindmap_service")
_openai = OpenAIService()

# ─── PROMPT ───────────────────────────────────────────────────────────────────

MIND_MAP_SYSTEM_PROMPT = """Você é um assistente acadêmico que gera mapas mentais estruturados a partir de resumos de aulas universitárias.

REGRAS OBRIGATÓRIAS:
1. Retorne APENAS JSON válido, sem markdown, sem explicação
2. O JSON deve ter 1 campo "topic" (tema central) e 1 array "branches"
3. Número de branches: entre 3 e 6 — escolha com base na complexidade do conteúdo
4. Cada branch deve ter entre 2 e 5 "children" (subtópicos)
5. Campo "color" em cada branch: 0, 1, 2, 3, 4 ou 5 (atribuído sequencialmente)
6. ESCREVA PALAVRAS COMPLETAS — nunca abrevie ou trunque. Use frases curtas mas completas
7. NÃO use emojis, ícones ou caracteres especiais
8. Priorize os conceitos mais importantes como branches
9. Os children de cada branch devem ser os subtópicos mais relevantes daquele conceito
10. Use português brasileiro

FORMATO DO JSON:
{
  "topic": "Tema Central da Aula",
  "branches": [
    {
      "topic": "Conceito Principal",
      "color": 0,
      "children": ["Subtópico completo", "Outro subtópico", "Mais um subtópico"]
    },
    {
      "topic": "Segundo Conceito",
      "color": 1,
      "children": ["Detalhamento claro", "Explicação breve"]
    }
  ]
}

DICAS:
- topic central: até 50 caracteres, claro e descritivo
- topic de branch: até 35 caracteres
- children: até 40 caracteres cada
- Mais branches para aulas densas, menos para aulas focadas
- Cada child deve ser autoexplicativo mesmo fora de contexto"""

MIND_MAP_USER_PROMPT = "Gere o mapa mental JSON para o seguinte resumo de aula:\n\n{summary}"


# ─── VALIDATION ───────────────────────────────────────────────────────────────

def validate_mind_map(data: dict) -> bool:
    """Validate that GPT output conforms to expected schema (flexible structure)."""
    if not isinstance(data, dict):
        return False
    if "topic" not in data or "branches" not in data:
        return False
    if not isinstance(data["topic"], str) or not data["topic"]:
        return False
    if not isinstance(data["branches"], list) or not (3 <= len(data["branches"]) <= 6):
        return False

    for branch in data["branches"]:
        if not isinstance(branch, dict):
            return False
        if "topic" not in branch or "children" not in branch:
            return False
        if not isinstance(branch["topic"], str) or not branch["topic"]:
            return False
        if not isinstance(branch["children"], list) or not (2 <= len(branch["children"]) <= 5):
            return False
        for child in branch["children"]:
            if not isinstance(child, str) or not child:
                return False

    return True


def normalize_mind_map(data: dict) -> dict:
    """Ensure color fields are valid and sequential."""
    for i, branch in enumerate(data["branches"]):
        branch["color"] = i % 6
    return data


# ─── GENERATION ───────────────────────────────────────────────────────────────

async def generate_mind_map(summary_text: str) -> dict | None:
    """
    Generate mind map JSON from a lecture summary.

    Args:
        summary_text: The full_summary or short_summary text from the gravacao.
                      Using the summary (not raw transcription) keeps input small
                      (~500-1000 tokens) and improves quality since noise is already filtered.

    Returns:
        dict: Valid mind map JSON, or None if generation fails.

    Cost: ~$0.0005-0.001 per call (GPT-4o-mini with small input).
    """
    try:
        response = await _openai.client.chat.completions.create(
            model="gpt-4o-mini",
            messages=[
                {"role": "system", "content": MIND_MAP_SYSTEM_PROMPT},
                {"role": "user", "content": MIND_MAP_USER_PROMPT.format(summary=summary_text)},
            ],
            response_format={"type": "json_object"},
            temperature=0.3,  # Low temperature for consistent structure
            max_tokens=800,   # Flexible structure needs more tokens
        )

        raw = response.choices[0].message.content
        data = json.loads(raw)

        # Normalize colors and validate structure
        data = normalize_mind_map(data)

        if not validate_mind_map(data):
            logger.warning("Mind map validation failed. Raw output: %s", raw[:200])
            return None

        return data

    except json.JSONDecodeError as e:
        logger.error("Mind map JSON parse error: %s", e)
        return None
    except Exception as e:
        logger.error("Mind map generation error: %s", e)
        return None


# ─── PIPELINE INTEGRATION ────────────────────────────────────────────────────

async def generate_mindmap_for_gravacao(gravacao_id: UUID) -> None:
    """
    Full pipeline: read gravação → generate mind map → validate → save.
    Called from summary_service after summary generation.

    If generation fails, the gravacao simply won't have a mind_map field (null).
    This is graceful — the iOS app checks for null and hides the mind map tab.
    """
    try:
        grav = await fetch_one(
            "SELECT id, full_summary, short_summary, transcription FROM gravacoes WHERE id = $1",
            gravacao_id,
        )
        if not grav:
            logger.error("Gravação %s não encontrada", gravacao_id)
            return

        # Use full_summary if available, fallback to transcription
        content = ""
        if grav["full_summary"]:
            raw = grav["full_summary"]
            if isinstance(raw, str):
                content = raw
            else:
                content = json.dumps(raw, ensure_ascii=False)
        elif grav["short_summary"]:
            content = grav["short_summary"]
        elif grav["transcription"]:
            content = grav["transcription"][:4000]
        else:
            logger.warning("Gravação %s sem conteúdo para mind map", gravacao_id)
            return

        mind_map = await generate_mind_map(content)

        if mind_map:
            await execute_query(
                "UPDATE gravacoes SET mind_map = $1::jsonb WHERE id = $2",
                json.dumps(mind_map, ensure_ascii=False),
                gravacao_id,
            )
            logger.info("Mind map salvo para gravação %s", gravacao_id)
        else:
            logger.warning("Mind map generation failed for gravação %s, skipping", gravacao_id)

    except Exception as e:
        logger.error("Erro ao gerar mind map para gravação %s: %s", gravacao_id, e)
        # Don't fail the pipeline — mind_map stays null
