# Prompt 09 — Envelope de Resposta Padronizado

## Contexto
O contrato define que TODAS as respostas seguem o envelope `{ "data": ..., "error": null, "message": "ok" }`. O backend atual retorna formatos inconsistentes: alguns routers usam SuccessResponse do base.py, outros retornam Pydantic models diretamente, outros retornam dicts crus.

## Pré-requisitos
Todos os prompts anteriores (00-08) executados.

## Arquivos a MODIFICAR
- `coffee-backend/app/schemas/base.py` — criar helpers de envelope
- `coffee-backend/app/routers/*.py` — padronizar todos os responses
- `coffee-backend/app/main.py` — exception handler padronizado

## Tarefa

### 1. Atualizar `schemas/base.py`
Criar helpers reutilizáveis:

```python
from typing import Any, Optional
from pydantic import BaseModel, ConfigDict

class BaseSchema(BaseModel):
    model_config = ConfigDict(from_attributes=True)

def success_response(data: Any = None, message: str = "ok") -> dict:
    """Envelope de sucesso padrão."""
    return {"data": data, "error": None, "message": message}

def error_response(error: str, message: str, status_code: int = 400) -> dict:
    """Envelope de erro padrão."""
    return {"data": None, "error": error, "message": message}
```

### 2. Padronizar TODOS os routers
Cada endpoint deve retornar:

```python
from app.schemas.base import success_response

@router.get("/endpoint")
async def my_endpoint():
    data = ...
    return success_response(data)
```

Para listas:
```python
return success_response([item.model_dump() for item in items])
```

Para listas paginadas:
```python
return {
    "data": [item.model_dump() for item in items],
    "error": None,
    "message": "ok",
    "pagination": {"page": page, "per_page": per_page, "total": total, "pages": pages}
}
```

Para erros (via HTTPException):
```python
raise HTTPException(
    status_code=409,
    detail={"data": None, "error": "EMAIL_EXISTS", "message": "E-mail já cadastrado"}
)
```

### 3. Atualizar exception handler no `main.py`
```python
@app.exception_handler(HTTPException)
async def http_exception_handler(request, exc):
    detail = exc.detail
    if isinstance(detail, dict) and "error" in detail:
        return JSONResponse(status_code=exc.status_code, content=detail)
    return JSONResponse(
        status_code=exc.status_code,
        content={"data": None, "error": "ERROR", "message": str(detail)}
    )

@app.exception_handler(Exception)
async def global_exception_handler(request, exc):
    return JSONResponse(
        status_code=500,
        content={"data": None, "error": "INTERNAL_ERROR", "message": "Erro interno do servidor"}
    )
```

### 4. Lista de códigos de erro padronizados
Usar EXATAMENTE estes códigos em todos os routers:

| HTTP | Código | Uso |
|------|--------|-----|
| 401 | INVALID_CREDENTIALS | Login falhou |
| 401 | TOKEN_EXPIRED | JWT expirou |
| 401 | ESPM_AUTH_FAILED | Credenciais ESPM inválidas |
| 403 | ACCESS_DENIED | Sem permissão |
| 404 | NOT_FOUND | Recurso não encontrado |
| 404 | USER_NOT_FOUND | Usuário não encontrado |
| 404 | INVALID_REFERRAL | Código de referral inválido |
| 409 | EMAIL_EXISTS | Email duplicado |
| 422 | VALIDATION_ERROR | Campos inválidos |
| 429 | QUESTION_LIMIT | Limite de perguntas atingido |
| 429 | SYNC_COOLDOWN | Sync em cooldown |
| 500 | INTERNAL_ERROR | Erro genérico |
| 502 | AI_ERROR | Erro OpenAI |
| 503 | ESPM_UNAVAILABLE | Portal ESPM indisponível |
| 504 | ESPM_TIMEOUT | Portal ESPM timeout |

## Verificação
1. TODOS os endpoints retornam { data, error, message }
2. Erros usam os códigos padronizados da tabela acima
3. Exception handler global captura erros não tratados
4. Nenhum endpoint retorna formato diferente do envelope

---

# Prompt 10 — Integração, Config e Validação Final

## Contexto
Último prompt. Verificar que tudo funciona junto, adicionar variáveis de config faltantes, limpar imports, e validar o app inteiro.

## Arquivos a MODIFICAR
- `coffee-backend/app/config.py` — adicionar variáveis novas
- `coffee-backend/app/main.py` — verificar todos os routers registrados
- `coffee-backend/requirements.txt` — verificar dependências
- `coffee-backend/Dockerfile` — verificar

## Tarefa

### 1. Atualizar `config.py`
Adicionar variáveis necessárias:
```python
class Settings(BaseSettings):
    # Existentes (manter)
    DATABASE_URL: str
    SUPABASE_URL: str
    SUPABASE_KEY: str
    OPENAI_API_KEY: str
    JWT_SECRET: str
    JWT_ALGORITHM: str = "HS256"
    JWT_EXPIRATION_HOURS: int = 168
    GOOGLE_APPLICATION_CREDENTIALS: str = "firebase-service-account.json"
    FIREBASE_PROJECT_ID: str = ""
    ENVIRONMENT: str = "development"
    
    # Novas
    SUPABASE_STORAGE_BUCKET: str = "materiais"
    SUPABASE_MEDIA_BUCKET: str = "gravacao-media"
    APPLE_SHARED_SECRET: str = ""  # pra verificação StoreKit
    TRIAL_DAYS: int = 7
    REFERRAL_BONUS_DAYS: int = 7
    QUESTION_LIMIT_TRIAL: int = 10
    QUESTION_LIMIT_PREMIUM: int = -1  # ilimitado
    SYNC_COOLDOWN_HOURS: int = 4
    
    # Removidas
    # ESPM_PORTAL_URL — não usado pelo backend (só pelo scraper)
    # ESPM_USERNAME/PASSWORD — não usado pelo backend
    # secret_key — renomeado pra JWT_SECRET
```

### 2. Verificar `main.py`
Deve ter EXATAMENTE estes routers registrados:
```python
from app.routers import (
    auth, chat, devices, disciplinas, gravacoes,
    health, materiais, notificacoes, profile,
    referral, repositorios, settings, subscription,
)
from app.modules.espm import router as espm_router

# Registrar todos
app.include_router(health.router)
app.include_router(auth.router)
app.include_router(espm_router.router)
app.include_router(disciplinas.router)
app.include_router(repositorios.router)
app.include_router(gravacoes.router)
app.include_router(materiais.router)
app.include_router(chat.router)
app.include_router(profile.router)
app.include_router(subscription.router)
app.include_router(referral.router)
app.include_router(settings.router)
app.include_router(devices.router)
app.include_router(notificacoes.router)
```

### 3. Verificar `requirements.txt`
Deve incluir:
```
fastapi>=0.109.0
uvicorn[standard]>=0.27.0
asyncpg>=0.29.0
pydantic>=2.5.0
pydantic-settings>=2.1.0
python-jose[cryptography]>=3.3.0
passlib[bcrypt]>=1.7.4
openai>=1.10.0
httpx>=0.26.0
python-multipart>=0.0.6
structlog>=24.1.0
google-auth>=2.27.0
Pillow>=10.0.0
PyPDF2>=3.0.0
python-pptx>=0.6.21
```

### 4. Checklist de validação final

Verificar que cada um dos 40 endpoints existe e retorna envelope padrão:

**Auth (5):**
- [ ] POST /api/v1/auth/signup
- [ ] POST /api/v1/auth/login
- [ ] POST /api/v1/auth/logout
- [ ] POST /api/v1/auth/forgot-password
- [ ] POST /api/v1/auth/refresh

**ESPM (3):**
- [ ] POST /api/v1/espm/connect
- [ ] GET /api/v1/espm/status
- [ ] POST /api/v1/espm/sync

**Disciplinas (2):**
- [ ] GET /api/v1/disciplinas
- [ ] GET /api/v1/disciplinas/{id}

**Repositórios (3):**
- [ ] GET /api/v1/repositorios
- [ ] POST /api/v1/repositorios
- [ ] DELETE /api/v1/repositorios/{id}

**Gravações (6):**
- [ ] POST /api/v1/gravacoes
- [ ] GET /api/v1/gravacoes
- [ ] GET /api/v1/gravacoes/{id}
- [ ] POST /api/v1/gravacoes/{id}/media
- [ ] PATCH /api/v1/gravacoes/{id}
- [ ] DELETE /api/v1/gravacoes/{id}

**Materiais (5):**
- [ ] GET /api/v1/disciplinas/{id}/materiais
- [ ] POST /api/v1/disciplinas/{id}/materiais
- [ ] PATCH /api/v1/materiais/{id}/toggle-ai
- [ ] POST /api/v1/disciplinas/{id}/sync
- [ ] GET /api/v1/materiais/{id}

**Chat (4):**
- [ ] GET /api/v1/chats
- [ ] POST /api/v1/chats
- [ ] GET /api/v1/chats/{id}/messages
- [ ] POST /api/v1/chats/{id}/messages

**Profile (2):**
- [ ] GET /api/v1/profile
- [ ] PATCH /api/v1/profile

**Subscription (2):**
- [ ] POST /api/v1/subscription/verify
- [ ] GET /api/v1/subscription/status

**Referral (2):**
- [ ] GET /api/v1/referral
- [ ] POST /api/v1/referral/validate

**Settings (2):**
- [ ] GET /api/v1/settings
- [ ] PATCH /api/v1/settings

**Devices + Notifications (4):**
- [ ] POST /api/v1/devices
- [ ] DELETE /api/v1/devices/{token}
- [ ] GET /api/v1/notificacoes
- [ ] PATCH /api/v1/notificacoes/{id}/read

### 5. Teste de fluxo ponta a ponta (smoke test)
Verificar mentalmente que o fluxo completo funciona:

```
1. POST /auth/signup (com referral_code) → user criado, referrer ganha +7 dias
2. POST /espm/connect → disciplinas importadas
3. GET /disciplinas → lista com ai_active, gravacoes_count
4. POST /gravacoes (transcription texto) → status=processing
   └─ Background: embeddings gerados + resumo gerado → status=ready
5. GET /gravacoes/{id} → detalhe com resumo, transcrição, media
6. POST /chats (source_type=disciplina) → chat criado
7. POST /chats/{id}/messages (text) → SSE stream
   └─ RAG busca embeddings de transcrição + materiais → resposta com fontes
8. GET /profile → usage com perguntas_hoje incrementado
```

Se algum passo quebraria logicamente, revisar o código dos prompts anteriores.
