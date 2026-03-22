import asyncio
import json
from uuid import UUID, uuid4
from datetime import datetime, date, timedelta, timezone
from math import floor
from typing import AsyncGenerator

from fastapi import APIRouter, Depends, HTTPException, status
from fastapi.responses import StreamingResponse

from app.config import settings
from app.dependencies import get_current_user, get_current_user_with_plan
from app.database import fetch_one, fetch_all, execute_query
from app.schemas.chat import (
    CreateChatRequest,
    SendMessageRequest,
    SourceReference,
    MessageResponse,
    ChatSummary,
)
from app.schemas.base import error_response, success_response
from app.services.openai_service import OpenAIService
from app.services.anthropic_service import AnthropicService, ChatResult, SONNET

router = APIRouter(prefix="/api/v1/chats", tags=["chats"])
_openai = OpenAIService()
_anthropic = AnthropicService()

# Minimum cosine similarity for vector search (lowered for RRF — full-text compensates)
_MIN_SIMILARITY = 0.25

# Sonnet 4 pricing (per million tokens)
_INPUT_COST_PER_M = 3.0
_OUTPUT_COST_PER_M = 15.0


# ── Helpers ─────────────────────────────────────────────────

def _build_sources(chunk_rows) -> list[dict]:
    """Build SourceReference dicts from RAG chunk rows."""
    sources = []
    for row in chunk_rows:
        excerpt = (row["texto_chunk"] or "")[:200]
        similarity = float(row["similarity"])

        if row["fonte_tipo"] == "transcricao":
            title = "Transcrição"
            if row.get("gravacao_date"):
                d = row["gravacao_date"]
                title = f"Aula {d.strftime('%d/%m')}" if hasattr(d, 'strftime') else title
            sources.append({
                "type": "transcription",
                "gravacao_id": str(row["fonte_id"]),
                "material_id": None,
                "title": title,
                "date": str(row.get("gravacao_date", "")),
                "excerpt": excerpt,
                "similarity": similarity,
            })
        else:
            sources.append({
                "type": "material",
                "gravacao_id": None,
                "material_id": str(row["fonte_id"]),
                "title": row.get("material_nome") or "Material",
                "date": None,
                "excerpt": excerpt,
                "similarity": similarity,
            })
    return sources


def _reciprocal_rank_fusion(*ranked_lists: list[dict], k: int = 60) -> list[dict]:
    """Merge multiple ranked lists using Reciprocal Rank Fusion.

    RRF score = sum(1 / (k + rank)) across all lists where the item appears.
    Deduplicates by (fonte_id, chunk_index). Returns re-ranked list.
    """
    scores: dict[str, float] = {}
    items: dict[str, dict] = {}

    for ranked_list in ranked_lists:
        for rank, item in enumerate(ranked_list):
            item_key = f"{item['fonte_id']}_{item.get('chunk_index', rank)}"
            scores[item_key] = scores.get(item_key, 0.0) + 1.0 / (k + rank + 1)
            if item_key not in items:
                items[item_key] = item

    sorted_keys = sorted(scores, key=lambda x: scores[x], reverse=True)
    return [items[key] for key in sorted_keys]


async def _validate_source_ownership(user_id: UUID, source_type: str, source_id: UUID):
    if source_type == "disciplina":
        row = await fetch_one(
            "SELECT 1 FROM user_disciplinas WHERE user_id = $1 AND disciplina_id = $2",
            user_id, source_id,
        )
    else:
        row = await fetch_one(
            "SELECT 1 FROM repositorios WHERE id = $1 AND user_id = $2",
            source_id, user_id,
        )
    if not row:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail=error_response("ACCESS_DENIED", "Acesso negado à fonte"))


def _get_cycle_dates(created_at: datetime) -> tuple[date, date]:
    """Calculate the current 30-day billing cycle start and end dates."""
    now = datetime.now(timezone.utc)
    if created_at.tzinfo is None:
        created_at = created_at.replace(tzinfo=timezone.utc)
    elapsed = (now - created_at).total_seconds()
    cycle_number = floor(elapsed / (30 * 86400))
    cycle_start = (created_at + timedelta(days=cycle_number * 30)).date()
    cycle_end = cycle_start + timedelta(days=30)
    return cycle_start, cycle_end


async def _get_or_create_budget(user_id: UUID, plano: str) -> dict:
    """Get or create usage_budget row for current cycle. Returns dict with budget_usd, used_usd."""
    from app.plan_limits import get_plan_budget

    user_row = await fetch_one("SELECT created_at FROM users WHERE id = $1", user_id)
    if not user_row:
        return {"budget_usd": 0.0, "used_usd": 0.0, "cycle_start": date.today(), "cycle_end": date.today() + timedelta(days=30)}

    cycle_start, cycle_end = _get_cycle_dates(user_row["created_at"])
    budget_usd = get_plan_budget(plano)

    # Try to get existing budget row
    row = await fetch_one(
        "SELECT budget_usd, used_usd FROM usage_budget WHERE user_id = $1 AND cycle_start = $2",
        user_id, cycle_start,
    )
    if row:
        return {"budget_usd": row["budget_usd"], "used_usd": row["used_usd"], "cycle_start": cycle_start, "cycle_end": cycle_end}

    # Create new budget row for this cycle
    await execute_query(
        """INSERT INTO usage_budget (user_id, cycle_start, cycle_end, budget_usd, used_usd)
           VALUES ($1, $2, $3, $4, 0)
           ON CONFLICT (user_id, cycle_start) DO NOTHING""",
        user_id, cycle_start, cycle_end, budget_usd,
    )
    return {"budget_usd": budget_usd, "used_usd": 0.0, "cycle_start": cycle_start, "cycle_end": cycle_end}


def _calc_cost(input_tokens: int, output_tokens: int) -> float:
    """Calculate USD cost from token counts."""
    return round(
        (input_tokens * _INPUT_COST_PER_M / 1_000_000)
        + (output_tokens * _OUTPUT_COST_PER_M / 1_000_000),
        6,
    )


def _usage_percent(used: float, budget: float) -> float:
    """Return usage as percentage (0-100). 100 = fully used."""
    if budget <= 0:
        return 100.0
    return round(min(100.0, (used / budget) * 100), 1)


# ── GET /chats ───────────────────────────────────────────────

@router.get("")
async def list_chats(
    page: int = 1,
    per_page: int = 20,
    user_id: UUID = Depends(get_current_user),
):
    """Listar conversas recentes."""
    offset = (page - 1) * per_page
    rows = await fetch_all(
        """SELECT c.id, c.source_type, c.source_id, c.updated_at,
                  CASE WHEN c.source_type = 'disciplina'
                       THEN (SELECT nome FROM disciplinas WHERE id = c.source_id)
                       ELSE (SELECT nome FROM repositorios WHERE id = c.source_id)
                  END AS source_name,
                  CASE WHEN c.source_type = 'disciplina' THEN 'school'
                       ELSE (SELECT icone FROM repositorios WHERE id = c.source_id)
                  END AS source_icon,
                  (SELECT conteudo FROM mensagens m
                   WHERE m.chat_id = c.id ORDER BY m.created_at DESC LIMIT 1) AS last_message,
                  (SELECT COUNT(*) FROM mensagens m WHERE m.chat_id = c.id) AS message_count
           FROM chats c
           WHERE c.user_id = $1
           ORDER BY c.updated_at DESC
           LIMIT $2 OFFSET $3""",
        user_id, per_page, offset,
    )

    items = [
        ChatSummary(
            id=r["id"],
            source_type=r["source_type"],
            source_id=r["source_id"],
            source_name=r["source_name"] or "Sem nome",
            source_icon=r["source_icon"],
            last_message=r["last_message"],
            message_count=r["message_count"],
            updated_at=r["updated_at"],
        ).model_dump(mode="json")
        for r in rows
    ]
    return success_response(items)


# ── POST /chats ──────────────────────────────────────────────

@router.post("", status_code=status.HTTP_201_CREATED)
async def create_chat(
    body: CreateChatRequest,
    user_id: UUID = Depends(get_current_user),
):
    """Criar nova conversa."""
    await _validate_source_ownership(user_id, body.source_type, body.source_id)

    row = await fetch_one(
        """INSERT INTO chats (user_id, source_type, source_id)
           VALUES ($1, $2, $3)
           RETURNING id, source_type, source_id, created_at, updated_at""",
        user_id, body.source_type, body.source_id,
    )

    if body.source_type == "disciplina":
        source = await fetch_one("SELECT nome FROM disciplinas WHERE id = $1", body.source_id)
    else:
        source = await fetch_one("SELECT nome FROM repositorios WHERE id = $1", body.source_id)

    resp = ChatSummary(
        id=row["id"],
        source_type=row["source_type"],
        source_id=row["source_id"],
        source_name=source["nome"] if source else "Sem nome",
        source_icon="school" if body.source_type == "disciplina" else "folder",
        last_message=None,
        message_count=0,
        updated_at=row["updated_at"],
    )
    return success_response(resp.model_dump(mode="json"))


# ── GET /chats/{id}/messages ─────────────────────────────────

@router.get("/{chat_id}/messages")
async def get_messages(
    chat_id: UUID,
    page: int = 1,
    per_page: int = 50,
    user_id: UUID = Depends(get_current_user),
):
    """Listar mensagens de uma conversa."""
    chat = await fetch_one(
        "SELECT id, source_type, source_id FROM chats WHERE id = $1 AND user_id = $2",
        chat_id, user_id,
    )
    if not chat:
        raise HTTPException(status_code=404, detail=error_response("NOT_FOUND", "Chat não encontrado"))

    if chat["source_type"] == "disciplina":
        source = await fetch_one("SELECT nome FROM disciplinas WHERE id = $1", chat["source_id"])
    else:
        source = await fetch_one("SELECT nome FROM repositorios WHERE id = $1", chat["source_id"])
    source_name = source["nome"] if source else "Geral"

    offset = (page - 1) * per_page
    rows = await fetch_all(
        """SELECT id, role, conteudo, fontes, mode, created_at
           FROM mensagens WHERE chat_id = $1
           ORDER BY created_at ASC
           LIMIT $2 OFFSET $3""",
        chat_id, per_page, offset,
    )

    messages = []
    for r in rows:
        is_ai = r["role"] == "assistant"
        sources = None
        if is_ai and r["fontes"]:
            raw_fontes = r["fontes"] if isinstance(r["fontes"], list) else json.loads(r["fontes"]) if isinstance(r["fontes"], str) else []
            sources = [
                SourceReference(
                    type=f.get("type", "material"),
                    gravacao_id=f.get("gravacao_id"),
                    material_id=f.get("material_id"),
                    title=f.get("title", ""),
                    date=f.get("date"),
                    excerpt=f.get("excerpt", ""),
                    similarity=f.get("similarity", 0.0),
                ).model_dump(mode="json")
                for f in raw_fontes
            ]

        messages.append(
            MessageResponse(
                id=r["id"],
                sender="ai" if is_ai else "user",
                text=r["conteudo"],
                mode=r.get("mode"),
                label=f"Barista de {source_name}" if is_ai else None,
                sources=sources,
                created_at=r["created_at"],
            ).model_dump(mode="json")
        )

    return success_response(messages)


# ── POST /chats/{id}/messages ────────────────────────────────

@router.post("/{chat_id}/messages")
async def send_message(
    chat_id: UUID,
    body: SendMessageRequest,
    user_plan: tuple = Depends(get_current_user_with_plan),
):
    """Enviar pergunta ao Barista (SSE streaming). Mode: rapido|professor|amigo (legacy: espresso|lungo|cold_brew)."""
    user_id, plano = user_plan

    # Subscription guard: expired users can't chat
    if plano == "expired":
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail=error_response("SUBSCRIPTION_REQUIRED", "Assinatura necessária para usar o chat"),
        )

    # Plan guard: Barista IA requires cafe_com_leite or black (not cafe_curto)
    if plano == "cafe_curto":
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail=error_response("PLAN_REQUIRED", "O Barista IA está disponível a partir do plano Café com Leite."),
        )

    # Verify chat ownership
    chat = await fetch_one(
        "SELECT id, source_type, source_id FROM chats WHERE id = $1 AND user_id = $2",
        chat_id, user_id,
    )
    if not chat:
        raise HTTPException(status_code=404, detail=error_response("NOT_FOUND", "Chat não encontrado"))

    # Budget check
    budget_info = await _get_or_create_budget(user_id, plano)
    if budget_info["used_usd"] >= budget_info["budget_usd"]:
        raise HTTPException(
            status_code=429,
            detail=error_response(
                "BUDGET_EXHAUSTED",
                "Seu limite mensal do Barista foi atingido. Ele renova automaticamente no próximo ciclo."
            ),
        )

    # Save user message with mode
    await execute_query(
        "INSERT INTO mensagens (chat_id, role, conteudo, mode) VALUES ($1, 'user', $2, $3)",
        chat_id, body.text, body.mode,
    )

    # Embed question
    embeddings = await _openai.create_embeddings([body.text])
    vec_str = "[" + ",".join(str(x) for x in embeddings[0]) + "]"

    # RAG: semantic search
    source_type = chat["source_type"]
    source_id = chat["source_id"]

    # ── RAG: hybrid search — 4 transcription + 4 material = 8 chunks ──

    if body.gravacao_id:
        # Single recording context
        chunk_rows = await fetch_all(
            """SELECT e.texto_chunk, e.metadata, e.fonte_tipo, e.fonte_id, e.chunk_index,
                      COALESCE(d.nome, r.nome) AS source_name,
                      1 - (e.embedding <=> $1::vector) AS similarity,
                      g.date AS gravacao_date,
                      NULL AS material_nome
               FROM embeddings e
               LEFT JOIN disciplinas d ON e.disciplina_id = d.id
               LEFT JOIN gravacoes g ON e.fonte_id = g.id
               LEFT JOIN repositorios r ON g.source_type = 'repositorio' AND g.source_id = r.id
               WHERE e.fonte_tipo = 'transcricao' AND e.fonte_id = $2
                 AND 1 - (e.embedding <=> $1::vector) >= $3
               ORDER BY e.embedding <=> $1::vector
               LIMIT 8""",
            vec_str, body.gravacao_id, _MIN_SIMILARITY,
        )
    elif source_type == "disciplina":
        # Hybrid search: vector + full-text in parallel, merged via RRF
        vec_transcription_task = fetch_all(
            """SELECT e.texto_chunk, e.metadata, e.fonte_tipo, e.fonte_id, e.chunk_index,
                      d.nome AS source_name,
                      1 - (e.embedding <=> $1::vector) AS similarity,
                      g.date AS gravacao_date,
                      NULL AS material_nome
               FROM embeddings e
               LEFT JOIN disciplinas d ON e.disciplina_id = d.id
               LEFT JOIN gravacoes g ON e.fonte_id = g.id
               WHERE e.disciplina_id = $2
                 AND e.fonte_tipo = 'transcricao'
                 AND 1 - (e.embedding <=> $1::vector) >= $3
               ORDER BY e.embedding <=> $1::vector
               LIMIT 12""",
            vec_str, source_id, _MIN_SIMILARITY,
        )
        vec_material_task = fetch_all(
            """SELECT e.texto_chunk, e.metadata, e.fonte_tipo, e.fonte_id, e.chunk_index,
                      d.nome AS source_name,
                      1 - (e.embedding <=> $1::vector) AS similarity,
                      NULL AS gravacao_date,
                      m.nome AS material_nome
               FROM embeddings e
               LEFT JOIN disciplinas d ON e.disciplina_id = d.id
               JOIN materiais m ON e.fonte_id = m.id
               WHERE e.disciplina_id = $2
                 AND e.fonte_tipo = 'material'
                 AND m.ai_enabled = true
                 AND 1 - (e.embedding <=> $1::vector) >= $3
               ORDER BY e.embedding <=> $1::vector
               LIMIT 12""",
            vec_str, source_id, _MIN_SIMILARITY,
        )
        fts_transcription_task = fetch_all(
            """SELECT e.texto_chunk, e.metadata, e.fonte_tipo, e.fonte_id, e.chunk_index,
                      d.nome AS source_name,
                      ts_rank_cd(e.tsv, plainto_tsquery('portuguese', $1)) AS similarity,
                      g.date AS gravacao_date,
                      NULL AS material_nome
               FROM embeddings e
               LEFT JOIN disciplinas d ON e.disciplina_id = d.id
               LEFT JOIN gravacoes g ON e.fonte_id = g.id
               WHERE e.disciplina_id = $2
                 AND e.fonte_tipo = 'transcricao'
                 AND e.tsv @@ plainto_tsquery('portuguese', $1)
               ORDER BY similarity DESC
               LIMIT 12""",
            body.text, source_id,
        )
        fts_material_task = fetch_all(
            """SELECT e.texto_chunk, e.metadata, e.fonte_tipo, e.fonte_id, e.chunk_index,
                      d.nome AS source_name,
                      ts_rank_cd(e.tsv, plainto_tsquery('portuguese', $1)) AS similarity,
                      NULL AS gravacao_date,
                      m.nome AS material_nome
               FROM embeddings e
               LEFT JOIN disciplinas d ON e.disciplina_id = d.id
               JOIN materiais m ON e.fonte_id = m.id
               WHERE e.disciplina_id = $2
                 AND e.fonte_tipo = 'material'
                 AND m.ai_enabled = true
                 AND e.tsv @@ plainto_tsquery('portuguese', $1)
               ORDER BY similarity DESC
               LIMIT 12""",
            body.text, source_id,
        )

        vec_trans, vec_mat, fts_trans, fts_mat = await asyncio.gather(
            vec_transcription_task, vec_material_task,
            fts_transcription_task, fts_material_task,
        )

        # RRF merge per source type, then take top 4 of each = 8 total
        merged_trans = _reciprocal_rank_fusion(list(vec_trans), list(fts_trans))[:4]
        merged_mat = _reciprocal_rank_fusion(list(vec_mat), list(fts_mat))[:4]
        chunk_rows = merged_trans + merged_mat
    else:
        # Repository: only transcriptions
        chunk_rows = await fetch_all(
            """SELECT e.texto_chunk, e.metadata, e.fonte_tipo, e.fonte_id, e.chunk_index,
                      r.nome AS source_name,
                      1 - (e.embedding <=> $1::vector) AS similarity,
                      g.date AS gravacao_date,
                      NULL AS material_nome
               FROM embeddings e
               JOIN gravacoes g ON e.fonte_tipo = 'transcricao' AND e.fonte_id = g.id
               JOIN repositorios r ON g.source_type = 'repositorio' AND g.source_id = r.id
               WHERE g.source_type = 'repositorio' AND g.source_id = $2
                 AND 1 - (e.embedding <=> $1::vector) >= $3
               ORDER BY e.embedding <=> $1::vector
               LIMIT 8""",
            vec_str, source_id, _MIN_SIMILARITY,
        )

    # Build context with rich labels
    context_texts = []
    for row in chunk_rows:
        if row["fonte_tipo"] == "transcricao" and row.get("gravacao_date"):
            d = row["gravacao_date"]
            label = f"[Aula {d.strftime('%d/%m/%Y')} | Transcrição]" if hasattr(d, 'strftime') else "[Transcrição]"
        elif row["fonte_tipo"] == "material" and row.get("material_nome"):
            label = f"[{row['material_nome']} | Material]"
        else:
            label = f"[{row.get('source_name', 'Fonte')} | {row['fonte_tipo']}]"
        context_texts.append(f"{label}\n{row['texto_chunk']}")

    sources = _build_sources(chunk_rows)

    # Fetch last 6 messages for history
    history_rows = await fetch_all(
        """SELECT role, conteudo FROM mensagens
           WHERE chat_id = $1
           ORDER BY created_at DESC LIMIT 6""",
        chat_id,
    )
    history_msgs = [
        {"role": r["role"], "content": r["conteudo"]}
        for r in reversed(history_rows)
    ]

    source_name = chunk_rows[0]["source_name"] if chunk_rows else "Geral"

    # Select personality prompt by mode
    from app.prompts import MODE_PROMPTS, RAPIDO_PROMPT
    system_prompt = MODE_PROMPTS.get(body.mode, RAPIDO_PROMPT)

    # Token usage tracker
    chat_result = ChatResult()

    # SSE stream — ALL modes use Sonnet 4 via Anthropic
    async def event_stream() -> AsyncGenerator[str, None]:
        full_text = ""
        try:
            stream_gen = _anthropic.chat_rag(
                history_msgs,
                context_texts,
                model=SONNET,
                system_prompt=system_prompt,
                result_holder=chat_result,
            )

            async for delta in stream_gen:
                full_text += delta
                yield f"data: {json.dumps({'token': delta}, ensure_ascii=False)}\n\n"

            # Calculate cost from actual token usage
            cost = _calc_cost(chat_result.input_tokens, chat_result.output_tokens)

            # Save assistant message with sources, mode, and token tracking
            msg_row = await fetch_one(
                """INSERT INTO mensagens (chat_id, role, conteudo, fontes, mode, input_tokens, output_tokens, cost_usd)
                   VALUES ($1, 'assistant', $2, $3::jsonb, $4, $5, $6, $7)
                   RETURNING id""",
                chat_id, full_text,
                json.dumps(sources, ensure_ascii=False),
                body.mode,
                chat_result.input_tokens,
                chat_result.output_tokens,
                cost,
            )
            msg_id = str(msg_row["id"]) if msg_row else str(uuid4())

            # Update budget used
            await execute_query(
                """UPDATE usage_budget SET used_usd = used_usd + $1
                   WHERE user_id = $2 AND cycle_start = $3""",
                cost, user_id, budget_info["cycle_start"],
            )

            # Update chat updated_at
            await execute_query(
                "UPDATE chats SET updated_at = NOW() WHERE id = $1", chat_id
            )

            # Calculate updated usage percentage
            new_used = budget_info["used_usd"] + cost
            usage_pct = _usage_percent(new_used, budget_info["budget_usd"])

            done_payload = {
                "done": True,
                "message_id": msg_id,
                "chat_id": str(chat_id),
                "sources": sources,
                "label": f"Barista de {source_name}",
                "usage_percent": usage_pct,
                "budget_usd": budget_info["budget_usd"],
                "used_usd": round(new_used, 4),
                # Legacy: keep questions_remaining for old iOS versions
                "questions_remaining": {
                    "espresso": -1,
                    "lungo": -1,
                    "cold_brew": -1,
                },
            }
            yield f"data: {json.dumps(done_payload, ensure_ascii=False)}\n\n"

        except Exception as e:
            yield f"data: {json.dumps({'error': str(e)})}\n\n"

    current_pct = _usage_percent(budget_info["used_usd"], budget_info["budget_usd"])

    headers = {
        "Cache-Control": "no-cache",
        "X-Accel-Buffering": "no",
        "X-Usage-Percent": str(current_pct),
        "X-Budget-USD": str(budget_info["budget_usd"]),
    }

    return StreamingResponse(
        event_stream(),
        media_type="text/event-stream",
        headers=headers,
    )
