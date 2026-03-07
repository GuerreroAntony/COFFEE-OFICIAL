import json
from uuid import UUID, uuid4
from datetime import date, datetime
from typing import Optional, AsyncGenerator

from fastapi import APIRouter, Depends, HTTPException, status
from fastapi.responses import StreamingResponse

from app.config import settings
from app.dependencies import get_current_user
from app.database import fetch_one, fetch_all, execute_query
from app.schemas.chat import (
    CreateChatRequest,
    SendMessageRequest,
    PersonalityConfig,
    SourceReference,
    MessageResponse,
    ChatSummary,
)
from app.schemas.base import error_response, success_response
from app.services.openai_service import OpenAIService

router = APIRouter(prefix="/api/v1/chats", tags=["chats"])
_openai = OpenAIService()


# ── Personality ──────────────────────────────────────────────

def _build_personality_instructions(p: dict) -> str:
    lines = []

    prof = p.get("profundidade", 50)
    if prof <= 30:
        lines.append("Responda de forma breve e direta, máximo 2 parágrafos.")
    elif prof <= 70:
        lines.append("Responda com profundidade moderada.")
    else:
        lines.append("Responda de forma detalhada e aprofundada, sem limitar extensão.")

    ling = p.get("linguagem", 50)
    if ling <= 30:
        lines.append("Use tom formal e acadêmico.")
    elif ling <= 70:
        lines.append("Use tom neutro.")
    else:
        lines.append("Use tom casual e acessível, como um amigo explicando.")

    exem = p.get("exemplos", 50)
    if exem <= 30:
        lines.append("Seja direto, sem exemplos.")
    elif exem <= 70:
        lines.append("Inclua 1-2 exemplos quando relevante.")
    else:
        lines.append("Use muitos exemplos e analogias do dia a dia.")

    quest = p.get("questionamento", 50)
    if quest <= 30:
        lines.append("Apenas responda, não faça perguntas.")
    elif quest <= 70:
        lines.append("Ocasionalmente faça uma pergunta reflexiva.")
    else:
        lines.append("Use método socrático, faça perguntas que guiem o raciocínio.")

    foco = p.get("foco", 50)
    if foco <= 30:
        lines.append("Foque em conceitos teóricos e fundamentos.")
    elif foco <= 70:
        lines.append("Equilibre teoria e prática.")
    else:
        lines.append("Foque em aplicações práticas e casos reais.")

    return " ".join(lines)


# ── Source formatting ────────────────────────────────────────

def _build_sources(chunk_rows) -> list[dict]:
    """Build SourceReference dicts from RAG chunk rows."""
    sources = []
    for row in chunk_rows:
        meta = row["metadata"] if isinstance(row["metadata"], dict) else {}
        excerpt = (row["texto_chunk"] or "")[:200]
        similarity = float(row["similarity"])

        if row["fonte_tipo"] == "transcricao":
            gravacao_id = meta.get("gravacao_id")
            # Try to format date from metadata or use generic title
            title = f"Transcrição"
            if row.get("gravacao_date"):
                d = row["gravacao_date"]
                title = f"Aula {d.strftime('%d/%m')}" if hasattr(d, 'strftime') else title
            sources.append({
                "type": "transcription",
                "gravacao_id": gravacao_id,
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


# ── Ownership validation ─────────────────────────────────────

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


# ── GET /chats ───────────────────────────────────────────────

@router.get("")
async def list_chats(
    user_id: UUID = Depends(get_current_user),
):
    """Listar conversas recentes."""
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
           ORDER BY c.updated_at DESC""",
        user_id,
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

    # Get source name
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
    user_id: UUID = Depends(get_current_user),
):
    """Listar mensagens de uma conversa."""
    chat = await fetch_one(
        "SELECT id, source_type, source_id FROM chats WHERE id = $1 AND user_id = $2",
        chat_id, user_id,
    )
    if not chat:
        raise HTTPException(status_code=404, detail=error_response("NOT_FOUND", "Chat não encontrado"))

    # Get source name for AI label
    if chat["source_type"] == "disciplina":
        source = await fetch_one("SELECT nome FROM disciplinas WHERE id = $1", chat["source_id"])
    else:
        source = await fetch_one("SELECT nome FROM repositorios WHERE id = $1", chat["source_id"])
    source_name = source["nome"] if source else "Geral"

    rows = await fetch_all(
        """SELECT id, role, conteudo, fontes, created_at
           FROM mensagens WHERE chat_id = $1
           ORDER BY created_at ASC""",
        chat_id,
    )

    messages = []
    for r in rows:
        is_ai = r["role"] == "assistant"
        # Parse sources
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
    user_id: UUID = Depends(get_current_user),
):
    """Enviar pergunta ao Barista (SSE streaming)."""
    # Verify chat ownership
    chat = await fetch_one(
        "SELECT id, source_type, source_id FROM chats WHERE id = $1 AND user_id = $2",
        chat_id, user_id,
    )
    if not chat:
        raise HTTPException(status_code=404, detail=error_response("NOT_FOUND", "Chat não encontrado"))

    # Question limit: trial users max 10/day
    user = await fetch_one("SELECT plano FROM users WHERE id = $1", user_id)
    questions_today = 0
    daily_limit = settings.QUESTION_LIMIT_TRIAL
    if user and user["plano"] == "trial":
        count_row = await fetch_one(
            """SELECT COUNT(*) AS cnt FROM mensagens m
               JOIN chats c ON m.chat_id = c.id
               WHERE c.user_id = $1 AND m.role = 'user'
                 AND m.created_at >= CURRENT_DATE""",
            user_id,
        )
        questions_today = count_row["cnt"] if count_row else 0
        if questions_today >= daily_limit:
            raise HTTPException(
                status_code=429,
                detail=error_response("QUESTION_LIMIT", "Limite de perguntas atingido"),
                headers={"X-Questions-Remaining": "0"},
            )

    remaining = max(0, daily_limit - questions_today - 1) if user and user["plano"] == "trial" else -1

    # Save user message
    await execute_query(
        "INSERT INTO mensagens (chat_id, role, conteudo) VALUES ($1, 'user', $2)",
        chat_id, body.text,
    )

    # Embed question
    embeddings = await _openai.create_embeddings([body.text])
    vec_str = "[" + ",".join(str(x) for x in embeddings[0]) + "]"

    # RAG: semantic search based on source_type
    source_type = chat["source_type"]
    source_id = chat["source_id"]

    if source_type == "disciplina":
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
        # Repositório: busca embeddings de gravações vinculadas ao repo
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

    # Personality
    p_dict = body.personality.model_dump() if body.personality else {}
    personality_instructions = _build_personality_instructions(p_dict)
    personality_config = {"system_prompt": f"Você é o assistente acadêmico do Coffee. {personality_instructions}"}

    # Get source name for label
    source_name = chunk_rows[0]["source_name"] if chunk_rows else "Geral"

    # SSE stream
    async def event_stream() -> AsyncGenerator[str, None]:
        full_text = ""
        try:
            async for delta in _openai.chat_rag(history_msgs, context_texts, personality_config):
                full_text += delta
                yield f"data: {json.dumps({'token': delta}, ensure_ascii=False)}\n\n"

            # Save assistant message with sources
            msg_row = await fetch_one(
                """INSERT INTO mensagens (chat_id, role, conteudo, fontes)
                   VALUES ($1, 'assistant', $2, $3::jsonb)
                   RETURNING id""",
                chat_id, full_text,
                json.dumps(sources, ensure_ascii=False),
            )
            msg_id = str(msg_row["id"]) if msg_row else str(uuid4())

            # Update chat updated_at
            await execute_query(
                "UPDATE chats SET updated_at = NOW() WHERE id = $1", chat_id
            )

            done_payload = {
                "done": True,
                "message_id": msg_id,
                "chat_id": str(chat_id),
                "sources": sources,
                "label": f"Barista de {source_name}",
            }
            yield f"data: {json.dumps(done_payload, ensure_ascii=False)}\n\n"

        except Exception as e:
            yield f"data: {json.dumps({'error': str(e)})}\n\n"

    headers = {
        "Cache-Control": "no-cache",
        "X-Accel-Buffering": "no",
    }
    if remaining >= 0:
        headers["X-Questions-Remaining"] = str(remaining)

    return StreamingResponse(
        event_stream(),
        media_type="text/event-stream",
        headers=headers,
    )
