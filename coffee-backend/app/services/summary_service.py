"""
Summary service — gera resumo estruturado automaticamente.
Chamado como background task pelo router de gravações.
"""
import json
import logging
from uuid import UUID
from app.database import fetch_one, execute_query
from app.services.openai_service import OpenAIService
from app.services.mindmap_service import generate_mindmap_for_gravacao

logger = logging.getLogger("summary_service")
_openai = OpenAIService()


async def generate_summary_for_gravacao(gravacao_id: UUID) -> None:
    """
    Background task: gera resumo e atualiza a gravação.
    Chamado automaticamente ao salvar gravação.

    Fluxo:
    1. Busca transcrição da gravação
    2. Identifica nome da disciplina/repositório
    3. Gera resumo via GPT-4o-mini
    4. Salva short_summary + full_summary na gravação
    5. Atualiza status pra 'ready'

    Em caso de erro: status = 'error'.
    """
    try:
        # Buscar gravação
        grav = await fetch_one(
            "SELECT id, source_type, source_id, transcription FROM gravacoes WHERE id = $1",
            gravacao_id,
        )
        if not grav or not grav["transcription"]:
            logger.error("Gravação %s não encontrada ou sem transcrição", gravacao_id)
            await execute_query(
                "UPDATE gravacoes SET status = 'error' WHERE id = $1", gravacao_id
            )
            return

        # Buscar nome da fonte
        if grav["source_type"] == "disciplina":
            source = await fetch_one(
                "SELECT nome FROM disciplinas WHERE id = $1", grav["source_id"]
            )
        else:
            source = await fetch_one(
                "SELECT nome FROM repositorios WHERE id = $1", grav["source_id"]
            )
        source_name = source["nome"] if source else "Aula"

        # Gerar resumo via GPT-4o-mini
        summary = await _openai.generate_summary(grav["transcription"], source_name)

        # Extrair short_summary (resumo_geral truncado) e full_summary (topicos completos)
        short_summary = summary.get("resumo_geral", "")[:300]
        full_summary = json.dumps(summary.get("topicos", []), ensure_ascii=False)

        # Salvar summary (sem marcar ready ainda)
        await execute_query(
            """UPDATE gravacoes
               SET short_summary = $1, full_summary = $2::jsonb
               WHERE id = $3""",
            short_summary, full_summary, gravacao_id,
        )
        logger.info("Resumo gerado com sucesso para gravação %s", gravacao_id)

        # Generate mind map (if it fails, mind_map stays null)
        try:
            await generate_mindmap_for_gravacao(gravacao_id)
        except Exception as e:
            logger.warning("Mind map generation failed for %s: %s", gravacao_id, e)

        # Agora sim marcar como ready (após summary + mindmap)
        await execute_query(
            "UPDATE gravacoes SET status = 'ready' WHERE id = $1",
            gravacao_id,
        )

    except Exception as e:
        logger.error("Erro ao gerar resumo para gravação %s: %s", gravacao_id, e)
        await execute_query(
            "UPDATE gravacoes SET status = 'error' WHERE id = $1", gravacao_id
        )
