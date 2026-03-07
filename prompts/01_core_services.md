# Prompt 01 — Services Core (Embedding + Summary + Push)

## Contexto
O backend tem `utils/embedding.py` que NUNCA é chamado por nenhum router (gap principal do RAG). O `openai_service.py` tem um método `transcribe_audio` que não será mais usado (transcrição é on-device). O `push_service.py` está vazio — a implementação real está no scraper. Precisamos de services unificados para: embeddings (gerar e remover), resumos (background task automática), e push (reusável).

## Pré-requisito
Prompt 00 executado (schema v2).

## Arquivos a CRIAR
- `coffee-backend/app/services/embedding_service.py`
- `coffee-backend/app/services/summary_service.py`

## Arquivos a MODIFICAR
- `coffee-backend/app/services/openai_service.py`
- `coffee-backend/app/services/push_service.py`
- `coffee-backend/app/utils/embedding.py`

## Tarefa

### 1. Criar `services/embedding_service.py`
Serviço unificado de embeddings que será chamado por gravacoes.py e materiais.py.

```python
"""
Embedding service — gerar e remover embeddings no pgvector.
Usado por: gravacoes (transcrições), materiais (toggle ai_enabled), scraper.
"""
import json
from uuid import UUID
from app.database import fetch_all, execute_query
from app.utils.embedding import chunk_text, generate_embeddings
from app.services.openai_service import OpenAIService

_openai = OpenAIService()

async def generate_transcription_embeddings(
    transcription: str,
    gravacao_id: UUID,
    disciplina_id: UUID,
) -> int:
    """
    Chunk a transcrição, gera embeddings, salva no pgvector.
    Retorna número de chunks criados.
    
    IMPORTANTE: disciplina_id é necessário pra filtrar embeddings no RAG.
    Para gravações em repositórios, disciplina_id é NULL no pgvector 
    e a busca filtra por fonte_id diretamente.
    """
    if not transcription or not transcription.strip():
        return 0
    
    chunks = chunk_text(transcription)  # 500 palavras, 100 overlap
    if not chunks:
        return 0
    
    embeddings = await _openai.create_embeddings(chunks)
    
    for i, (chunk, emb) in enumerate(zip(chunks, embeddings)):
        vec_str = "[" + ",".join(str(x) for x in emb) + "]"
        metadata = json.dumps({"gravacao_id": str(gravacao_id), "chunk_index": i})
        await execute_query(
            """INSERT INTO embeddings 
               (disciplina_id, fonte_tipo, fonte_id, chunk_index, texto_chunk, embedding, metadata)
               VALUES ($1, 'transcricao', $2, $3, $4, $5::vector, $6::jsonb)""",
            disciplina_id, gravacao_id, i, chunk, vec_str, metadata,
        )
    
    return len(chunks)


async def generate_material_embeddings(
    texto: str,
    material_id: UUID,
    disciplina_id: UUID,
) -> int:
    """Chunk texto do material, gera embeddings, salva no pgvector."""
    if not texto or not texto.strip():
        return 0
    
    chunks = chunk_text(texto)
    if not chunks:
        return 0
    
    embeddings = await _openai.create_embeddings(chunks)
    
    for i, (chunk, emb) in enumerate(zip(chunks, embeddings)):
        vec_str = "[" + ",".join(str(x) for x in emb) + "]"
        metadata = json.dumps({"material_id": str(material_id), "chunk_index": i})
        await execute_query(
            """INSERT INTO embeddings 
               (disciplina_id, fonte_tipo, fonte_id, chunk_index, texto_chunk, embedding, metadata)
               VALUES ($1, 'material', $2, $3, $4, $5::vector, $6::jsonb)""",
            disciplina_id, material_id, i, chunk, vec_str, metadata,
        )
    
    return len(chunks)


async def remove_embeddings(fonte_id: UUID) -> int:
    """Remove todos os embeddings de uma fonte (gravação ou material)."""
    result = await execute_query(
        "DELETE FROM embeddings WHERE fonte_id = $1",
        fonte_id,
    )
    # result é "DELETE N" — extrair N
    try:
        return int(result.split()[-1])
    except:
        return 0
```

### 2. Criar `services/summary_service.py`
Background task que gera resumo automaticamente após salvar gravação.

```python
"""
Summary service — gera resumo estruturado automaticamente.
Chamado como background task pelo router de gravações.
"""
import json
import logging
from uuid import UUID
from app.database import fetch_one, execute_query
from app.services.openai_service import OpenAIService

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
        
        # Atualizar gravação
        await execute_query(
            """UPDATE gravacoes 
               SET short_summary = $1, full_summary = $2::jsonb, status = 'ready'
               WHERE id = $3""",
            short_summary, full_summary, gravacao_id,
        )
        logger.info("Resumo gerado com sucesso para gravação %s", gravacao_id)
        
    except Exception as e:
        logger.error("Erro ao gerar resumo para gravação %s: %s", gravacao_id, e)
        await execute_query(
            "UPDATE gravacoes SET status = 'error' WHERE id = $1", gravacao_id
        )
```

### 3. Modificar `services/openai_service.py`
- Remover o método `transcribe_audio` (transcrição é on-device)
- Manter: `generate_summary`, `chat_rag`, `create_embeddings`
- Nenhuma alteração nos métodos mantidos

### 4. Implementar `services/push_service.py`
Copiar a lógica do `coffee-scraper/scraper/push.py` adaptada pro backend:

```python
"""
Push notification service (FCM v1 via OAuth2).
Adaptado de coffee-scraper/scraper/push.py.
"""
import logging
from typing import Optional
import httpx
from google.oauth2 import service_account
from app.config import settings

logger = logging.getLogger("push_service")
_FCM_SCOPE = "https://www.googleapis.com/auth/firebase.messaging"
_credentials = None

def _get_access_token() -> str:
    global _credentials
    if _credentials is None:
        _credentials = service_account.Credentials.from_service_account_file(
            settings.GOOGLE_APPLICATION_CREDENTIALS,
            scopes=[_FCM_SCOPE],
        )
    if not _credentials.valid:
        from google.auth.transport.requests import Request
        _credentials.refresh(Request())
    return _credentials.token

async def send_push(token: str, title: str, body: str, data: Optional[dict] = None) -> bool:
    if not settings.FIREBASE_PROJECT_ID:
        return False
    
    access_token = _get_access_token()
    url = f"https://fcm.googleapis.com/v1/projects/{settings.FIREBASE_PROJECT_ID}/messages:send"
    
    message = {
        "message": {
            "token": token,
            "notification": {"title": title, "body": body},
            "apns": {"payload": {"aps": {"sound": "default", "badge": 1}}},
        }
    }
    if data:
        message["message"]["data"] = data
    
    async with httpx.AsyncClient() as client:
        resp = await client.post(url, json=message, headers={"Authorization": f"Bearer {access_token}"}, timeout=10)
    
    if resp.status_code == 200:
        return True
    logger.error("FCM push failed (%d): %s", resp.status_code, resp.text)
    return False
```

### 5. Manter `utils/embedding.py` como está
As funções `chunk_text` e `generate_embeddings` são usadas pelo `embedding_service.py`. Não alterar.

## Verificação
1. `embedding_service.py` existe com 3 funções: generate_transcription_embeddings, generate_material_embeddings, remove_embeddings
2. `summary_service.py` existe com 1 função: generate_summary_for_gravacao
3. `openai_service.py` NÃO tem mais o método transcribe_audio
4. `push_service.py` tem implementação funcional (não mais vazio)
5. Nenhum import quebrado
