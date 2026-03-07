# Prompt 04 — Chat/RAG (Adaptar)

## Contexto
O chat.py atual é o mais completo do backend — SSE streaming, personality, RAG com pgvector. Mas tem problemas: só funciona com disciplina_id (não suporta repositórios), fontes citadas não incluem gravacao_id/timestamp pra navegação, e não tem controle de limite de perguntas.

A query RAG em si está correta (busca por similaridade com filtro, JOIN com materiais pra checar ai_enabled, retorna 8 chunks). Mas como transcrições nunca tinham embeddings (fix do Prompt 01), o RAG só encontrava materiais. Agora com o embedding_service gerando embeddings de transcrições, o RAG vai funcionar ponta a ponta.

## Pré-requisitos
Prompts 00, 01, 02 executados.

## Arquivos a MODIFICAR
- `coffee-backend/app/routers/chat.py` (adaptar significativamente)
- `coffee-backend/app/schemas/chat.py` (reescrever)

## Tarefa

### 1. Reescrever `schemas/chat.py`

```python
from uuid import UUID
from datetime import datetime
from typing import Optional
from pydantic import BaseModel, Field

class PersonalityConfig(BaseModel):
    profundidade: int = Field(default=50, ge=0, le=100)
    linguagem: int = Field(default=50, ge=0, le=100)
    exemplos: int = Field(default=50, ge=0, le=100)
    questionamento: int = Field(default=50, ge=0, le=100)
    foco: int = Field(default=50, ge=0, le=100)

class CreateChatRequest(BaseModel):
    source_type: str = Field(pattern="^(disciplina|repositorio)$")
    source_id: UUID

class SendMessageRequest(BaseModel):
    text: str = Field(min_length=1, max_length=5000)
    personality: Optional[PersonalityConfig] = None

class SourceReference(BaseModel):
    type: str  # "transcription" ou "material"
    gravacao_id: Optional[UUID] = None  # se type=transcription
    material_id: Optional[UUID] = None  # se type=material
    title: str
    date: Optional[str] = None
    excerpt: str
    similarity: float

class MessageResponse(BaseModel):
    id: UUID
    sender: str  # "user" ou "ai"
    text: str
    label: Optional[str] = None  # "Barista de Marketing" (só pra ai)
    sources: Optional[list[SourceReference]] = None  # só pra ai
    created_at: datetime

class ChatSummary(BaseModel):
    id: UUID
    source_type: str
    source_id: UUID
    source_name: str
    source_icon: Optional[str] = None
    last_message: Optional[str] = None
    message_count: int
    updated_at: datetime
```

### 2. Adaptar `routers/chat.py`

O router deve ter 4 endpoints:

**GET /chats** — Listar conversas recentes
- JOIN com disciplinas ou repositorios pra pegar source_name
- Subquery pra last_message e message_count
- source_icon: pra disciplinas usar ícone padrão "school", pra repos usar o campo icone
- Ordenar por updated_at DESC

**POST /chats** — Criar conversa
- Recebe: source_type, source_id
- Valida ownership da fonte
- Cria chat no banco
- Retorna chat com id

**GET /chats/{id}/messages** — Listar mensagens
- Retorna mensagens ordenadas por created_at ASC
- Pra mensagens do AI: parsear fontes JSONB e incluir como SourceReference[]
- label: "Barista de {source_name}"

**POST /chats/{id}/messages** — Enviar pergunta (SSE)
- Recebe: text, personality (opcional)
- Verifica ownership do chat
- **Controle de limite:** contar mensagens do user hoje (role='user', created_at >= hoje 00:00). Se user está em trial e count >= 10, retorna 429 QUESTION_LIMIT.
- Pipeline RAG:
  1. Embed a pergunta via create_embeddings
  2. Buscar source_type e source_id do chat
  3. Se source_type='disciplina': filtrar embeddings por disciplina_id = source_id
  4. Se source_type='repositorio': filtrar embeddings por fonte_id IN (SELECT id FROM gravacoes WHERE source_type='repositorio' AND source_id=$1)
  5. Em ambos: JOIN com materiais pra checar ai_enabled (quando fonte_tipo='material')
  6. Top 8 chunks por similaridade
  7. Formatar chunks como contexto
- SSE stream via GPT-4o
- Ao finalizar: salvar mensagem + fontes no banco
- Fontes no done event devem incluir:
  - type: "transcription" → gravacao_id (extrair do metadata), title (formatar "Aula DD/MM"), date, excerpt (texto_chunk truncado)
  - type: "material" → material_id, title (nome do material), excerpt
- Header X-Questions-Remaining no response
- Atualizar chats.updated_at

### Mudanças na query RAG (adaptar a query existente):

A query atual já está boa pra disciplinas. Pra repositórios, a query muda:

```sql
-- Para disciplinas (disciplina_id é o source_id direto):
SELECT e.texto_chunk, e.metadata, e.fonte_tipo, e.fonte_id,
       d.nome AS source_name,
       1 - (e.embedding <=> $1::vector) AS similarity
FROM embeddings e
LEFT JOIN disciplinas d ON e.disciplina_id = d.id
LEFT JOIN materiais m ON e.fonte_tipo = 'material' AND e.fonte_id = m.id
WHERE e.disciplina_id = $2
  AND (e.fonte_tipo != 'material' OR m.ai_enabled = true)
ORDER BY e.embedding <=> $1::vector
LIMIT 8

-- Para repositórios (busca por gravações vinculadas ao repo):
SELECT e.texto_chunk, e.metadata, e.fonte_tipo, e.fonte_id,
       r.nome AS source_name,
       1 - (e.embedding <=> $1::vector) AS similarity
FROM embeddings e
JOIN gravacoes g ON e.fonte_tipo = 'transcricao' AND e.fonte_id = g.id
JOIN repositorios r ON g.source_type = 'repositorio' AND g.source_id = r.id
WHERE g.source_type = 'repositorio' AND g.source_id = $2
ORDER BY e.embedding <=> $1::vector
LIMIT 8
```

### Manter do código atual:
- `_build_personality_instructions()` — manter intacto
- SSE streaming pattern — manter
- Últimas 6 mensagens como histórico — manter

## Verificação
1. GET /chats retorna source_type, source_id, source_name, source_icon, last_message, message_count
2. POST /chats aceita source_type/source_id (NÃO disciplina_id/modo)
3. GET /chats/{id}/messages retorna sources parseadas com gravacao_id, material_id, excerpt
4. POST /chats/{id}/messages verifica limite de perguntas (429 se trial e >= 10)
5. POST /chats/{id}/messages retorna header X-Questions-Remaining
6. RAG funciona tanto pra disciplinas quanto pra repositórios
7. done event inclui sources com type, gravacao_id/material_id, title, excerpt, similarity
8. Personality config funciona (5 sliders)
9. Envelope padrão em todos os responses
