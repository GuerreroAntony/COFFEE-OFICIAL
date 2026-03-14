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
2. O JSON deve ter exatamente 1 campo "topic" (tema central) e 1 array "branches" com exatamente 4 itens
3. Cada branch deve ter exatamente 3 "children" (subtópicos)
4. Campo "color" em cada branch: 0, 1, 2 ou 3 (atribuído sequencialmente)
5. Limite de caracteres:
   - topic (raiz): máximo 30 caracteres
   - topic (branch): máximo 20 caracteres
   - children (folha): máximo 22 caracteres
6. Se o texto ultrapassar o limite, abrevie de forma inteligível (ex: "Comportamento do Consumidor" → "Comport. Consumidor")
7. NÃO use emojis, ícones ou caracteres especiais
8. Priorize os 4 conceitos mais importantes como branches
9. Os 3 children de cada branch devem ser os subtópicos mais relevantes daquele conceito
10. Use português brasileiro

FORMATO EXATO DO JSON:
{
  "topic": "Tema Central da Aula",
  "branches": [
    {
      "topic": "Conceito 1",
      "color": 0,
      "children": ["Subtópico 1.1", "Subtópico 1.2", "Subtópico 1.3"]
    },
    {
      "topic": "Conceito 2",
      "color": 1,
      "children": ["Subtópico 2.1", "Subtópico 2.2", "Subtópico 2.3"]
    },
    {
      "topic": "Conceito 3",
      "color": 2,
      "children": ["Subtópico 3.1", "Subtópico 3.2", "Subtópico 3.3"]
    },
    {
      "topic": "Conceito 4",
      "color": 3,
      "children": ["Subtópico 4.1", "Subtópico 4.2", "Subtópico 4.3"]
    }
  ]
}"""

MIND_MAP_USER_PROMPT = "Gere o mapa mental JSON para o seguinte resumo de aula:\n\n{summary}"


# ─── VALIDATION ───────────────────────────────────────────────────────────────

def validate_mind_map(data: dict) -> bool:
    """Validate that GPT output conforms to expected schema."""
    if not isinstance(data, dict):
        return False
    if "topic" not in data or "branches" not in data:
        return False
    if not isinstance(data["topic"], str) or len(data["topic"]) > 30:
        return False
    if not isinstance(data["branches"], list) or len(data["branches"]) != 4:
        return False

    for branch in data["branches"]:
        if not isinstance(branch, dict):
            return False
        if "topic" not in branch or "color" not in branch or "children" not in branch:
            return False
        if not isinstance(branch["topic"], str) or len(branch["topic"]) > 20:
            return False
        if branch["color"] not in [0, 1, 2, 3]:
            return False
        if not isinstance(branch["children"], list) or len(branch["children"]) != 3:
            return False
        for child in branch["children"]:
            if not isinstance(child, str) or len(child) > 22:
                return False

    return True


# ─── TRUNCATION FALLBACK ─────────────────────────────────────────────────────

def truncate_mind_map(data: dict) -> dict:
    """If GPT slightly exceeds char limits, truncate gracefully instead of failing."""
    data["topic"] = data["topic"][:30]
    for i, branch in enumerate(data["branches"]):
        branch["topic"] = branch["topic"][:20]
        branch["children"] = [child[:22] for child in branch["children"]]
        # Ensure color is valid
        if branch["color"] not in [0, 1, 2, 3]:
            branch["color"] = i % 4
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
            max_tokens=500,   # Mind map JSON is ~300 tokens max
        )

        raw = response.choices[0].message.content
        data = json.loads(raw)

        # Try truncation before validation (GPT sometimes exceeds by 1-2 chars)
        data = truncate_mind_map(data)

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
