import json
from uuid import UUID, uuid4
from datetime import datetime, timezone
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
from app.services.anthropic_service import AnthropicService

router = APIRouter(prefix="/api/v1/chats", tags=["chats"])
_openai = OpenAIService()
_anthropic = AnthropicService()

# Mode → model mapping
_MODE_MODELS = {
    "espresso": "gpt-4o-mini",
    "lungo": "gpt-4o",
    "cold_brew": "claude",  # handled separately via AnthropicService
}


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


async def _get_cycle_start(user_id: UUID) -> datetime:
    """Calculate the start of the current 30-day billing cycle."""
    row = await fetch_one("SELECT created_at FROM users WHERE id = $1", user_id)
    if not row:
        return datetime.now(timezone.utc)
    created_at = row["created_at"]
    now = datetime.now(timezone.utc)
    elapsed = (now - created_at).total_seconds()
    cycles = int(elapsed // (30 * 86400))
    from datetime import timedelta
    return created_at + timedelta(days=cycles * 30)


async def _get_questions_remaining(user_id: UUID, cycle_start: datetime) -> dict:
    """Get remaining questions per mode for the current cycle."""
    lungo_row = await fetch_one(
        """SELECT COUNT(*) AS cnt FROM mensagens m
           JOIN chats c ON m.chat_id = c.id
           WHERE c.user_id = $1 AND m.role = 'user' AND m.mode = 'lungo'
             AND m.created_at >= $2""",
        user_id, cycle_start,
    )
    cold_brew_row = await fetch_one(
        """SELECT COUNT(*) AS cnt FROM mensagens m
           JOIN chats c ON m.chat_id = c.id
           WHERE c.user_id = $1 AND m.role = 'user' AND m.mode = 'cold_brew'
             AND m.created_at >= $2""",
        user_id, cycle_start,
    )
    lungo_used = lungo_row["cnt"] if lungo_row else 0
    cold_brew_used = cold_brew_row["cnt"] if cold_brew_row else 0

    return {
        "espresso": -1,  # unlimited
        "lungo": max(0, settings.LUNGO_MONTHLY_LIMIT - lungo_used),
        "cold_brew": max(0, settings.COLD_BREW_MONTHLY_LIMIT - cold_brew_used),
    }


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
    """Enviar pergunta ao Barista (SSE streaming). Requires mode: espresso|lungo|cold_brew."""
    user_id, plano = user_plan

    # Subscription guard: expired users can't chat
    if plano == "expired":
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail=error_response("SUBSCRIPTION_REQUIRED", "Assinatura necessária para usar o chat"),
        )

    # Verify chat ownership
    chat = await fetch_one(
        "SELECT id, source_type, source_id FROM chats WHERE id = $1 AND user_id = $2",
        chat_id, user_id,
    )
    if not chat:
        raise HTTPException(status_code=404, detail=error_response("NOT_FOUND", "Chat não encontrado"))

    # Monthly limit check for lungo and cold_brew
    cycle_start = await _get_cycle_start(user_id)
    questions_remaining = await _get_questions_remaining(user_id, cycle_start)

    if body.mode == "lungo" and questions_remaining["lungo"] <= 0:
        raise HTTPException(
            status_code=429,
            detail=error_response("QUESTION_LIMIT", "Limite mensal de perguntas Lungo atingido"),
        )
    if body.mode == "cold_brew" and questions_remaining["cold_brew"] <= 0:
        raise HTTPException(
            status_code=429,
            detail=error_response("QUESTION_LIMIT", "Limite mensal de perguntas Cold Brew atingido"),
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

    # If gravacao_id is provided, filter RAG to that specific recording
    if body.gravacao_id:
        chunk_rows = await fetch_all(
            """SELECT e.texto_chunk, e.metadata, e.fonte_tipo, e.fonte_id,
                      COALESCE(d.nome, r.nome) AS source_name,
                      1 - (e.embedding <=> $1::vector) AS similarity,
                      CASE WHEN e.fonte_tipo = 'transcricao'
                           THEN (SELECT g.date FROM gravacoes g WHERE g.id = e.fonte_id)
                           ELSE NULL END AS gravacao_date,
                      CASE WHEN e.fonte_tipo = 'material'
                           THEN (SELECT m2.nome FROM materiais m2 WHERE m2.id = e.fonte_id)
                           ELSE NULL END AS material_nome
               FROM embeddings e
               LEFT JOIN disciplinas d ON e.disciplina_id = d.id
               LEFT JOIN repositorios r ON e.fonte_tipo = 'transcricao'
                   AND e.fonte_id IN (SELECT g2.id FROM gravacoes g2 WHERE g2.source_type = 'repositorio' AND g2.source_id = r.id)
               WHERE e.fonte_tipo = 'transcricao' AND e.fonte_id = $2
               ORDER BY e.embedding <=> $1::vector
               LIMIT 8""",
            vec_str, body.gravacao_id,
        )
    elif source_type == "disciplina":
        chunk_rows = await fetch_all(
            """SELECT e.texto_chunk, e.metadata, e.fonte_tipo, e.fonte_id,
                      d.nome AS source_name,
                      1 - (e.embedding <=> $1::vector) AS similarity,
                      CASE WHEN e.fonte_tipo = 'transcricao'
                           THEN (SELECT g.date FROM gravacoes g WHERE g.id = e.fonte_id)
                           ELSE NULL END AS gravacao_date,
                      CASE WHEN e.fonte_tipo = 'material'
                           THEN (SELECT m2.nome FROM materiais m2 WHERE m2.id = e.fonte_id)
                           ELSE NULL END AS material_nome
               FROM embeddings e
               LEFT JOIN disciplinas d ON e.disciplina_id = d.id
               LEFT JOIN materiais m ON e.fonte_tipo = 'material' AND e.fonte_id = m.id
               WHERE e.disciplina_id = $2
                 AND (e.fonte_tipo != 'material' OR m.ai_enabled = true)
               ORDER BY e.embedding <=> $1::vector
               LIMIT 8""",
            vec_str, source_id,
        )
    else:
        chunk_rows = await fetch_all(
            """SELECT e.texto_chunk, e.metadata, e.fonte_tipo, e.fonte_id,
                      r.nome AS source_name,
                      1 - (e.embedding <=> $1::vector) AS similarity,
                      g.date AS gravacao_date,
                      NULL AS material_nome
               FROM embeddings e
               JOIN gravacoes g ON e.fonte_tipo = 'transcricao' AND e.fonte_id = g.id
               JOIN repositorios r ON g.source_type = 'repositorio' AND g.source_id = r.id
               WHERE g.source_type = 'repositorio' AND g.source_id = $2
               ORDER BY e.embedding <=> $1::vector
               LIMIT 8""",
            vec_str, source_id,
        )

    # Build context and sources
    context_texts = []
    for row in chunk_rows:
        label = f"[{row['source_name']} | {row['fonte_tipo']}]"
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
    system_prompt = "Você é o assistente acadêmico do Coffee. Responda com profundidade moderada e tom neutro."

    # SSE stream — route by mode
    async def event_stream() -> AsyncGenerator[str, None]:
        full_text = ""
        try:
            if body.mode == "cold_brew":
                stream_gen = _anthropic.chat_rag(history_msgs, context_texts, system_prompt)
            else:
                model = "gpt-4o-mini" if body.mode == "espresso" else "gpt-4o"
                stream_gen = _openai.chat_rag(history_msgs, context_texts, model=model, system_prompt=system_prompt)

            async for delta in stream_gen:
                full_text += delta
                yield f"data: {json.dumps({'token': delta}, ensure_ascii=False)}\n\n"

            # Save assistant message with sources and mode
            msg_row = await fetch_one(
                """INSERT INTO mensagens (chat_id, role, conteudo, fontes, mode)
                   VALUES ($1, 'assistant', $2, $3::jsonb, $4)
                   RETURNING id""",
                chat_id, full_text,
                json.dumps(sources, ensure_ascii=False),
                body.mode,
            )
            msg_id = str(msg_row["id"]) if msg_row else str(uuid4())

            # Update chat updated_at
            await execute_query(
                "UPDATE chats SET updated_at = NOW() WHERE id = $1", chat_id
            )

            # Recalculate remaining after this message
            updated_remaining = await _get_questions_remaining(user_id, cycle_start)

            done_payload = {
                "done": True,
                "message_id": msg_id,
                "chat_id": str(chat_id),
                "sources": sources,
                "label": f"Barista de {source_name}",
                "questions_remaining": updated_remaining,
            }
            yield f"data: {json.dumps(done_payload, ensure_ascii=False)}\n\n"

        except Exception as e:
            yield f"data: {json.dumps({'error': str(e)})}\n\n"

    # Decrement remaining for the mode used (before streaming, for headers)
    if body.mode == "lungo":
        remaining_for_mode = max(0, questions_remaining["lungo"] - 1)
    elif body.mode == "cold_brew":
        remaining_for_mode = max(0, questions_remaining["cold_brew"] - 1)
    else:
        remaining_for_mode = -1

    headers = {
        "Cache-Control": "no-cache",
        "X-Accel-Buffering": "no",
        "X-Questions-Remaining-Espresso": str(questions_remaining["espresso"]),
        "X-Questions-Remaining-Lungo": str(remaining_for_mode if body.mode == "lungo" else questions_remaining["lungo"]),
        "X-Questions-Remaining-ColdBrew": str(remaining_for_mode if body.mode == "cold_brew" else questions_remaining["cold_brew"]),
    }

    return StreamingResponse(
        event_stream(),
        media_type="text/event-stream",
        headers=headers,
    )
