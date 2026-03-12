# mind_map_service.py
# Integrates into the existing summary_service background task pipeline.
# Called AFTER summary is generated, using the summary text as input (not raw transcription).
#
# Integration point: gravacoes router → POST /gravacoes → background_task
# Current flow: save gravacao → generate embeddings → generate summary
# New flow:     save gravacao → generate embeddings → generate summary → generate mind_map
#
# The mind_map field is JSONB stored directly on the gravacoes table.

import json
import logging
from app.services.openai_service import get_openai_client
from app.database import execute_query

logger = logging.getLogger(__name__)

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
6. Se o texto ultrapassar o limite, abrevie de forma inteligível
7. NÃO use emojis, ícones ou caracteres especiais
8. Priorize os 4 conceitos mais importantes como branches
9. Os 3 children de cada branch devem ser os subtópicos mais relevantes
10. Use português brasileiro"""

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
    
    for i, branch in enumerate(data["branches"]):
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
    for branch in data["branches"]:
        branch["topic"] = branch["topic"][:20]
        branch["children"] = [child[:22] for child in branch["children"]]
        # Ensure color is valid
        if branch["color"] not in [0, 1, 2, 3]:
            branch["color"] = data["branches"].index(branch) % 4
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
        client = get_openai_client()
        
        response = await client.chat.completions.create(
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
            logger.warning(f"Mind map validation failed. Raw output: {raw[:200]}")
            return None
        
        return data
        
    except json.JSONDecodeError as e:
        logger.error(f"Mind map JSON parse error: {e}")
        return None
    except Exception as e:
        logger.error(f"Mind map generation error: {e}")
        return None

# ─── DATABASE ─────────────────────────────────────────────────────────────────

async def save_mind_map(gravacao_id: str, mind_map: dict) -> None:
    """Save generated mind map to gravacao record."""
    await execute_query(
        """
        UPDATE gravacoes 
        SET mind_map = $1::jsonb
        WHERE id = $2
        """,
        json.dumps(mind_map),
        gravacao_id,
    )

# ─── PIPELINE INTEGRATION ────────────────────────────────────────────────────

async def generate_and_save_mind_map(gravacao_id: str, summary_text: str) -> None:
    """
    Full pipeline: generate + validate + save.
    Called from the background task after summary generation.
    
    If generation fails, the gravacao simply won't have a mind_map field (null).
    This is graceful — the iOS app checks for null and hides the mind map tab.
    """
    mind_map = await generate_mind_map(summary_text)
    
    if mind_map:
        await save_mind_map(gravacao_id, mind_map)
        logger.info(f"Mind map saved for gravacao {gravacao_id}")
    else:
        logger.warning(f"Mind map generation failed for gravacao {gravacao_id}, skipping")
