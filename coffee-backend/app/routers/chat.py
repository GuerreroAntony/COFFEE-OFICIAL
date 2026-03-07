import json
from uuid import UUID, uuid4
from typing import Optional, AsyncGenerator

from fastapi import APIRouter, Depends, HTTPException, Query
from fastapi.responses import StreamingResponse

from app.dependencies import get_current_user
from app.database import fetch_one, fetch_all, execute_query
from app.schemas.chat import (
    ChatSendRequest,
    MensagemResponse,
    HistoryResponse,
    ChatSummaryResponse,
    ChatsListResponse,
)
from app.services.openai_service import OpenAIService

router = APIRouter(prefix="/api/v1/chat", tags=["chat"])
_openai = OpenAIService()


# ── Personality ──────────────────────────────────────────────────────────────

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


def _format_chunks(rows) -> tuple[list[str], list[dict]]:
    context_texts = []
    fontes = []
    for row in rows:
        label = f"[{row['disciplina_nome']} | {row['fonte_tipo']}]"
        context_texts.append(f"{label}\n{row['texto_chunk']}")
        meta = row["metadata"] if isinstance(row["metadata"], dict) else {}
        fontes.append({
            "fonte_id": str(row["fonte_id"]),
            "fonte_tipo": row["fonte_tipo"],
            "disciplina_nome": row["disciplina_nome"],
            "metadata": meta,
            "similarity": float(row["similarity"]),
        })
    return context_texts, fontes


# ── POST /send ────────────────────────────────────────────────────────────────

@router.post("/send")
async def send_message(
    req: ChatSendRequest,
    user_id: UUID = Depends(get_current_user),
):
    # 1. Fetch user's disciplina IDs via junction table
    user_disc_rows = await fetch_all(
        "SELECT disciplina_id FROM user_disciplinas WHERE user_id = $1", user_id
    )
    user_disc_ids = [r["disciplina_id"] for r in user_disc_rows]

    # 2. Create chat if needed
    chat_id = req.chat_id
    if chat_id is None:
        chat_row = await fetch_one(
            """
            INSERT INTO chats (user_id, disciplina_id, modo)
            VALUES ($1, $2, $3)
            RETURNING id
            """,
            user_id,
            req.disciplina_id,
            req.modo,
        )
        chat_id = chat_row["id"]
    else:
        # Verify ownership
        existing = await fetch_one(
            "SELECT id FROM chats WHERE id = $1 AND user_id = $2",
            chat_id,
            user_id,
        )
        if not existing:
            raise HTTPException(status_code=404, detail="Chat não encontrado.")

    # 3. Save user message
    await execute_query(
        "INSERT INTO mensagens (chat_id, role, conteudo) VALUES ($1, 'user', $2)",
        chat_id,
        req.mensagem,
    )

    # 4. Embedding of user message
    embeddings = await _openai.create_embeddings([req.mensagem])
    user_vec = embeddings[0]
    vec_str = "[" + ",".join(str(x) for x in user_vec) + "]"

    # 5. Semantic search
    if req.modo == "disciplina" and req.disciplina_id:
        chunk_rows = await fetch_all(
            """
            SELECT e.texto_chunk, e.metadata, e.fonte_tipo, e.fonte_id,
                   d.nome AS disciplina_nome,
                   1 - (e.embedding <=> $1::vector) AS similarity
            FROM embeddings e
            JOIN disciplinas d ON e.disciplina_id = d.id
            LEFT JOIN materiais m ON e.fonte_tipo = 'material' AND e.fonte_id = m.id
            WHERE e.disciplina_id = $2
              AND (e.fonte_tipo != 'material' OR m.ai_enabled = true)
            ORDER BY e.embedding <=> $1::vector
            LIMIT 8
            """,
            vec_str,
            req.disciplina_id,
        )
    else:
        chunk_rows = await fetch_all(
            """
            SELECT e.texto_chunk, e.metadata, e.fonte_tipo, e.fonte_id,
                   d.nome AS disciplina_nome,
                   1 - (e.embedding <=> $1::vector) AS similarity
            FROM embeddings e
            JOIN disciplinas d ON e.disciplina_id = d.id
            LEFT JOIN materiais m ON e.fonte_tipo = 'material' AND e.fonte_id = m.id
            WHERE e.disciplina_id = ANY($2::uuid[])
              AND (e.fonte_tipo != 'material' OR m.ai_enabled = true)
            ORDER BY e.embedding <=> $1::vector
            LIMIT 8
            """,
            vec_str,
            user_disc_ids,
        )

    context_texts, fontes = _format_chunks(chunk_rows)

    # 6. Fetch last 6 messages for history
    history_rows = await fetch_all(
        """
        SELECT role, conteudo FROM mensagens
        WHERE chat_id = $1
        ORDER BY created_at DESC
        LIMIT 6
        """,
        chat_id,
    )
    history_msgs = [
        {"role": r["role"], "content": r["conteudo"]}
        for r in reversed(history_rows)
    ]

    # 7. Personality
    p_dict = req.personality.model_dump() if req.personality else {}
    personality_instructions = _build_personality_instructions(p_dict)
    personality_config = {"system_prompt": f"Você é o assistente acadêmico do Coffee. {personality_instructions}"}

    # 8. SSE generator
    async def event_stream() -> AsyncGenerator[str, None]:
        full_text = ""
        try:
            async for delta in _openai.chat_rag(history_msgs, context_texts, personality_config):
                full_text += delta
                yield f"data: {json.dumps({'token': delta}, ensure_ascii=False)}\n\n"

            # Save assistant message
            msg_row = await fetch_one(
                """
                INSERT INTO mensagens (chat_id, role, conteudo, fontes)
                VALUES ($1, 'assistant', $2, $3::jsonb)
                RETURNING id
                """,
                chat_id,
                full_text,
                json.dumps(fontes, ensure_ascii=False),
            )
            msg_id = str(msg_row["id"]) if msg_row else str(uuid4())

            yield f"data: {json.dumps({'done': True, 'fontes': fontes, 'message_id': msg_id, 'chat_id': str(chat_id)}, ensure_ascii=False)}\n\n"
        except Exception as e:
            yield f"data: {json.dumps({'error': str(e)})}\n\n"

    return StreamingResponse(
        event_stream(),
        media_type="text/event-stream",
        headers={
            "Cache-Control": "no-cache",
            "X-Accel-Buffering": "no",
        },
    )


# ── GET /history/{chat_id} ────────────────────────────────────────────────────

@router.get("/history/{chat_id}", response_model=HistoryResponse)
async def get_history(
    chat_id: UUID,
    user_id: UUID = Depends(get_current_user),
):
    chat = await fetch_one(
        "SELECT id FROM chats WHERE id = $1 AND user_id = $2",
        chat_id,
        user_id,
    )
    if not chat:
        raise HTTPException(status_code=404, detail="Chat não encontrado.")

    rows = await fetch_all(
        """
        SELECT id, chat_id, role, conteudo, fontes, created_at
        FROM mensagens
        WHERE chat_id = $1
        ORDER BY created_at ASC
        """,
        chat_id,
    )

    messages = [
        MensagemResponse(
            id=r["id"],
            chat_id=r["chat_id"],
            role=r["role"],
            conteudo=r["conteudo"],
            fontes=r["fontes"] if r["fontes"] else [],
            created_at=r["created_at"],
        )
        for r in rows
    ]
    return HistoryResponse(messages=messages)


# ── GET /list ─────────────────────────────────────────────────────────────────

@router.get("/list", response_model=ChatsListResponse)
async def list_chats(
    disciplina_id: Optional[UUID] = Query(default=None),
    user_id: UUID = Depends(get_current_user),
):
    if disciplina_id:
        rows = await fetch_all(
            """
            SELECT c.id, c.disciplina_id, d.nome AS disciplina_nome, c.modo, c.created_at,
                   (SELECT conteudo FROM mensagens m
                    WHERE m.chat_id = c.id
                    ORDER BY m.created_at DESC LIMIT 1) AS last_message_preview
            FROM chats c
            LEFT JOIN disciplinas d ON c.disciplina_id = d.id
            WHERE c.user_id = $1 AND c.disciplina_id = $2
            ORDER BY c.created_at DESC
            """,
            user_id,
            disciplina_id,
        )
    else:
        rows = await fetch_all(
            """
            SELECT c.id, c.disciplina_id, d.nome AS disciplina_nome, c.modo, c.created_at,
                   (SELECT conteudo FROM mensagens m
                    WHERE m.chat_id = c.id
                    ORDER BY m.created_at DESC LIMIT 1) AS last_message_preview
            FROM chats c
            LEFT JOIN disciplinas d ON c.disciplina_id = d.id
            WHERE c.user_id = $1
            ORDER BY c.created_at DESC
            """,
            user_id,
        )

    chats = [
        ChatSummaryResponse(
            id=r["id"],
            disciplina_id=r["disciplina_id"],
            disciplina_nome=r["disciplina_nome"],
            modo=r["modo"],
            last_message_preview=r["last_message_preview"],
            created_at=r["created_at"],
        )
        for r in rows
    ]
    return ChatsListResponse(chats=chats)
