# COFFEE — Contexto Master para Claude Code

> Este arquivo deve ser incluído como contexto em TODAS as sessões de Claude Code que modifiquem o backend.
> Última atualização: Março 2026

---

## O que é o Coffee

App iOS nativo (SwiftUI) para alunos da ESPM gravarem aulas, transcreverem automaticamente via WhisperKit (on-device), e consultarem um assistente IA ("Barista") que responde fundamentado nas transcrições + materiais do Canvas ESPM via RAG com pgvector.

## Stack Técnica

| Camada | Tecnologia |
|--------|-----------|
| iOS | SwiftUI + WhisperKit/CoreML |
| Backend API | Python 3.11 + FastAPI + asyncpg |
| Banco | PostgreSQL 15 + pgvector (Supabase) |
| Storage | Supabase Storage (materiais, fotos) |
| IA | OpenAI GPT-4o (chat), GPT-4o-mini (resumos), text-embedding-3-small (embeddings) |
| Scraper | Playwright + Canvas ESPM SSO |
| Push | Firebase Cloud Messaging (FCM v1 via OAuth2) |
| Deploy | Railway (backend ~$5/mo + scraper ~$3/mo) + Supabase Pro ($25/mo) |
| Pagamento | App Store StoreKit 2 (R$49,99/mês + 7 dias trial) |

## Estrutura do Monorepo

```
COFFEE-OFICIAL/
├── coffee-backend/          ← FastAPI API (FOCO PRINCIPAL)
│   ├── app/
│   │   ├── main.py
│   │   ├── config.py
│   │   ├── database.py
│   │   ├── dependencies.py
│   │   ├── routers/         ← Endpoints
│   │   ├── schemas/         ← Pydantic models
│   │   ├── services/        ← Business logic
│   │   ├── utils/           ← Security, embeddings
│   │   └── modules/espm/    ← ESPM portal integration
│   ├── sql/                 ← Migrations
│   ├── firebase-service-account.json  ← FCM push credentials
│   ├── Dockerfile
│   └── requirements.txt
├── contrato-api/            ← Spec API v3.1 (referência front↔back)
│   └── coffee-api-contract-v3.1.md
├── CLAUDE.md                ← Este arquivo
└── ESPM_WEBVIEW_GUIDE.md    ← Guia integração ESPM webview
```

## Regras Invioláveis

1. **NUNCA modifique modules/espm/auth/authenticator.py.** SSO B2C funciona.
2. **NUNCA modifique modules/espm/schedule/extractor.py.** Extração funciona.
3. **Sempre use asyncpg via helpers** (fetch_one, fetch_all, execute_query de database.py). NÃO use get_db/Depends injection.
4. **Todos os responses seguem o envelope:** `{ "data": ..., "error": null, "message": "ok" }`
5. **Campos em snake_case.** Datas ISO 8601 UTC. IDs UUID v4.
6. **Embeddings: text-embedding-3-small, 1536 dimensões.**
7. **Chunks: 500 palavras, 100 overlap** (manter idêntico ao scraper).

## Base URL

```
https://coffee-oficial-production.up.railway.app/api/v1
```

## Autenticação

Bearer JWT via header `Authorization: Bearer <token>`. JWT expira em 168h (7 dias). Endpoints públicos: /auth/signup, /auth/login, /auth/forgot-password.

## Conceitos-Chave

### source_type / source_id
Gravações e chats são vinculados a uma FONTE, que pode ser uma disciplina OU um repositório. Isso é representado por dois campos:
- `source_type`: "disciplina" ou "repositorio"
- `source_id`: UUID da disciplina ou do repositório

### ai_enabled
Flag booleano nos materiais. Materiais com ai_enabled=true alimentam o RAG (têm embeddings no pgvector). O scraper seta automaticamente: padrão "Aula XX" = true, resto = false. O aluno pode alterar via toggle. Quando ai_enabled muda, embeddings devem ser gerados ou removidos.

### Pipeline RAG
```
Pergunta do aluno
    ↓ embed (text-embedding-3-small)
Busca similaridade no pgvector
    ↓ filtra por source_id + ai_enabled
Top 8 chunks (transcrições + materiais)
    ↓ injeta como contexto
GPT-4o responde com citação de fontes
```

### Pipeline de Gravação (novo)
```
iOS grava áudio → transcrição on-device (WhisperKit)
    ↓ POST /gravacoes (envia TEXTO, não áudio)
Backend salva gravação (status=processing)
    ↓ background tasks paralelas:
    ├── Gerar embeddings da transcrição (pgvector)
    └── Gerar resumo via GPT-4o-mini
    ↓ quando pronto: status=ready
iOS faz polling até status=ready
```

## Tabelas do Banco (v2 — target)

```sql
users          — id, nome, email, password_hash, plano, trial_end, espm_login, encrypted_espm_password, referral_code, created_at
disciplinas    — id, nome, turma, professor, horario, sala, semestre, horarios (JSONB), canvas_course_id, last_scraped_at
user_disciplinas — user_id, disciplina_id (UNIQUE pair)
repositorios   — id, user_id, nome, icone, created_at                          [NOVO]
gravacoes      — id, user_id, source_type, source_id, date, duration_seconds, status, transcription, short_summary, full_summary (JSONB), created_at  [REESTRUTURADO]
gravacao_media — id, gravacao_id, type, label, timestamp_seconds, url_storage   [NOVO]
materiais      — id, disciplina_id, tipo, nome, url_storage, texto_extraido, fonte, canvas_file_id, ai_enabled, size_bytes, created_at
chats          — id, user_id, source_type, source_id, created_at                [ADAPTADO]
mensagens      — id, chat_id, role, conteudo, fontes (JSONB), created_at
embeddings     — id, disciplina_id, fonte_tipo, fonte_id, chunk_index, texto_chunk, embedding VECTOR(1536), metadata (JSONB)
device_tokens  — id, user_id, fcm_token (UNIQUE), platform, active, created_at
notificacoes   — id, user_id, tipo, titulo, corpo, disciplina_id, lida, created_at
referrals      — id, referrer_id, referred_id, code, reward_applied, created_at [NOVO]
subscriptions  — id, user_id, plano, status, trial_end, expires_at, apple_transaction_id [NOVO]
user_settings  — id, user_id, auto_transcription, auto_summaries, push_notifications, class_reminders, audio_quality, summary_language [NOVO]
```

## Endpoints Target (40 endpoints)

### Auth (5)
- POST /auth/signup — Criar conta (com referral_code opcional)
- POST /auth/login — Login
- POST /auth/logout — Logout + remove FCM
- POST /auth/forgot-password — Recuperação de senha
- POST /auth/refresh — Renovar JWT

### ESPM (3)
- POST /espm/connect — Conectar conta ESPM
- GET /espm/status — Status conexão
- POST /espm/sync — Forçar re-sync

### Disciplinas (2)
- GET /disciplinas — Listar
- GET /disciplinas/{id} — Detalhe

### Repositórios (3)
- GET /repositorios — Listar
- POST /repositorios — Criar
- DELETE /repositorios/{id} — Excluir

### Gravações (5)
- POST /gravacoes — Salvar gravação (transcrição texto)
- GET /gravacoes — Listar por fonte
- GET /gravacoes/{id} — Detalhe completo
- POST /gravacoes/{id}/media — Upload foto
- PATCH /gravacoes/{id} — Mover
- DELETE /gravacoes/{id} — Excluir

### Materiais (5)
- GET /disciplinas/{id}/materiais — Listar
- POST /disciplinas/{id}/materiais — Upload manual
- PATCH /materiais/{id}/toggle-ai — Toggle ai_enabled
- POST /disciplinas/{id}/sync — Sync Canvas
- GET /materiais/{id} — Detalhe

### Chat (4)
- GET /chats — Listar conversas
- POST /chats — Criar conversa
- GET /chats/{id}/messages — Listar mensagens
- POST /chats/{id}/messages — Enviar pergunta (SSE)

### Profile (2)
- GET /profile — Dados do perfil
- PATCH /profile — Atualizar

### Subscription (2)
- POST /subscription/verify — Verificar recibo Apple
- GET /subscription/status — Status

### Referral (2)
- GET /referral — Dados do programa
- POST /referral/validate — Validar código

### Settings (2)
- GET /settings — Obter
- PATCH /settings — Atualizar

### Devices + Notifications (4)
- POST /devices — Registrar FCM
- DELETE /devices/{token} — Remover
- GET /notificacoes — Listar
- PATCH /notificacoes/{id}/read — Marcar lida
