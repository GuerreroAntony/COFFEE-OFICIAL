# Coffee API Contract v3.1

> Source of truth for parallel iOS + backend development.
> Base URL: `https://api-coffee.up.railway.app/api/v1`
> Auth: Bearer JWT | Dates: ISO 8601 UTC | IDs: UUID v4

---

## Changelog v3.0 → v3.1

| # | Item | Decisão |
|---|------|---------|
| 1 | Modelo Cold Brew | Claude Opus 4 (confirmado) |
| 2 | Toggle ai_enabled materiais | Habilitado por padrão — aluno pode desabilitar individualmente |
| 3 | Estado expirado pós-trial | Read-only: vê gravações, não grava nem usa Barista |
| 4 | Reconexão ESPM | Mesmo endpoint POST /espm/connect, documentado explicitamente |
| 5 | Polling gravação | Timeout 3 min — depois mostra "Processando..." sem travar UI |
| 6 | Compartilhamento misto | Envia pra quem existe, avisa quem não foi encontrado |
| 7 | Erro plano expirado | 403 SUBSCRIPTION_REQUIRED → iOS redireciona pro paywall |
| 8 | Deep link notificações | Padrão: `coffee://compartilhamentos/{id}` |
| 9 | Gift code para premium | Botão oculto — só trial pode resgatar |
| 10 | Cooldown sync | 429 retorna `next_sync_available_at` |

---

## Conventions

### Response Envelope

```json
// Success
{ "data": { ... }, "error": null, "message": "ok" }

// Error
{ "data": null, "error": "ERROR_CODE", "message": "Human-readable message" }
```

### Subscription Guard

Endpoints que requerem assinatura ativa retornam este erro quando o plano está expirado:

```json
// 403 SUBSCRIPTION_REQUIRED
{ "data": null, "error": "SUBSCRIPTION_REQUIRED", "message": "Assine para continuar usando o Coffee." }
```

**Endpoints bloqueados para plano `expired`:**
- `POST /gravacoes` — não pode gravar
- `POST /chats/{id}/messages` — não pode usar Barista
- `GET /gravacoes/{id}` — pode (read-only)
- `GET /gravacoes` — pode (read-only)

> iOS ao receber `403 SUBSCRIPTION_REQUIRED` deve redirecionar para a tela de assinatura (paywall).

### Pagination

Endpoints com listas aceitam:

| Param | Type | Default | Description |
|-------|------|---------|-------------|
| page | int | 1 | Page number |
| per_page | int | 20 | Items per page (max 50) |

Response inclui:
```json
"pagination": { "page": 1, "per_page": 20, "total": 42, "pages": 3 }
```

### Auth Header

```
Authorization: Bearer <jwt_token>
```

JWT expira em 7 dias (168h). iOS armazena no Keychain.
Todos os endpoints exceto `/auth/signup`, `/auth/login` e `/auth/forgot-password` requerem JWT.

### Field Conventions

- `snake_case` para todos os campos
- ISO 8601 com timezone: `2026-03-06T14:30:00Z`
- Booleans: `true`/`false`
- Arrays vazios: `[]` (nunca null)
- Strings vazias: `""` (nunca null, exceto campos nullable)

---

## 1. Auth

### POST /auth/signup

Criar conta.

**Request:**
```json
{
  "nome": "Gabriel Lima",
  "email": "gabriel@email.com",
  "password": "12345678",
  "gift_code": "ABC12345"    // opcional — +7 dias se válido
}
```

**Response 201:**
```json
{
  "data": {
    "user": {
      "id": "uuid",
      "nome": "Gabriel Lima",
      "email": "gabriel@email.com",
      "plano": "trial",
      "trial_end": "2026-03-13T00:00:00Z",
      "subscription_active": false,
      "espm_connected": false,
      "created_at": "2026-03-06T..."
    },
    "token": "eyJhbG..."
  }
}
```

**Errors:**
- `409 EMAIL_EXISTS`
- `422 VALIDATION_ERROR` — senha < 8 chars, email inválido
- `404 INVALID_CODE` — gift code não encontrado ou já usado

**Backend notes:**
- `trial_end` = now + 7 dias
- Se `gift_code` válido: `trial_end` = now + 14 dias, marca código como usado
- Cria `user_settings` com defaults

---

### POST /auth/login

**Request:**
```json
{ "email": "gabriel@email.com", "password": "12345678" }
```

**Response 200:** Mesma estrutura do signup (user + token).

**Errors:**
- `401 INVALID_CREDENTIALS`
- `404 USER_NOT_FOUND`

---

### POST /auth/logout

Remove FCM token e blacklista JWT.

**Request:**
```json
{ "device_token": "fcm_token_string"   // opcional — se omitido, remove todos }
```

**Response 200:**
```json
{ "data": null, "error": null, "message": "Logged out" }
```

---

### POST /auth/forgot-password

**Request:**
```json
{ "email": "gabriel@email.com" }
```

**Response 200:**
```json
{ "data": null, "error": null, "message": "Se o email existir, enviaremos instrucoes de recuperacao." }
```

> Sempre retorna 200 — não revela se email existe.

---

### POST /auth/refresh

Renova JWT. Requer token válido no Authorization header.

**Response 200:**
```json
{ "data": { "token": "eyJhbG...novo" } }
```

**Errors:** `401 TOKEN_EXPIRED`

---

### GET /auth/me

**Response 200:**
```json
{
  "data": {
    "id": "uuid",
    "nome": "Gabriel Lima",
    "email": "gabriel@email.com",
    "plano": "trial",
    "trial_end": "2026-03-13T00:00:00Z",
    "subscription_active": false,
    "espm_connected": true,
    "created_at": "2026-03-06T..."
  }
}
```

---

## 2. ESPM Connection

### POST /espm/connect

Conexão ESPM — **primeira vez OU reconexão após `POST /espm/disconnect`**. Playwright gera Canvas token + extrai cursos.

> Este endpoint serve tanto para conexão inicial quanto para reconexão. O iOS deve reutilizá-lo nos dois casos.

**Request:**
```json
{
  "matricula": "aluno@acad.espm.br",
  "password": "senha_espm"
}
```

**Response 200:**
```json
{
  "data": {
    "status": "connected",
    "disciplinas_found": 5,
    "disciplinas": [
      { "id": "uuid", "nome": "Gestao de Marketing", "turma": "AD1N", "semestre": "2026/1" }
    ]
  }
}
```

**Errors:**
- `401 ESPM_AUTH_FAILED` — credenciais inválidas
- `504 ESPM_TIMEOUT` — Canvas não respondeu
- `503 ESPM_UNAVAILABLE` — Canvas fora do ar

**Backend notes:**
- Playwright: login SSO → navega `/profile/settings` → gera token
- Salva token criptografado (Fernet) em `users.canvas_token`
- Salva `canvas_token_expires_at`
- Canvas API `GET /courses` → extrai disciplinas
- Upsert disciplinas + vincula via `user_disciplinas`
- Salva `espm_login = matricula`

**iOS notes:**
- Exibir progresso em 3 steps: Autenticando → Extraindo disciplinas → Sincronizando

---

### POST /espm/sync

Re-sincroniza disciplinas. Usa token Canvas existente (regenera se expirado).

**Request e Response:** mesmo formato de `/espm/connect`.

---

### GET /espm/status

**Response 200:**
```json
{
  "data": {
    "connected": true,
    "matricula": "aluno@acad.espm.br",
    "disciplinas_count": 5,
    "token_expires_at": "2026-07-10T00:00:00Z"
  }
}
```

---

## 3. Disciplinas

Read-only. Criadas automaticamente pela conexão ESPM.

### GET /disciplinas

**Response 200:**
```json
{
  "data": [
    {
      "id": "uuid",
      "nome": "Gestao de Marketing",
      "turma": "AD1N",
      "semestre": "2026/1",
      "canvas_course_id": 49137,
      "gravacoes_count": 12,
      "materiais_count": 8,
      "last_synced_at": "2026-03-06T03:00:00Z",
      "ai_active": true
    }
  ]
}
```

> `ai_active` = true quando há ao menos 1 transcrição com embedding OU 1 material com `ai_enabled=true`.
> Sem professor, horário, sala — Canvas API não fornece.

---

### GET /disciplinas/{id}

**Response 200:** Mesmo objeto do list item.

**Errors:**
- `403 ACCESS_DENIED` — usuário não está matriculado
- `404 NOT_FOUND`

---

## 4. Repositórios

Pastas livres criadas pelo usuário.

### GET /repositorios

**Response 200:**
```json
{
  "data": [
    {
      "id": "uuid",
      "nome": "Resumos para P1",
      "icone": "description",
      "gravacoes_count": 4,
      "ai_active": true,
      "created_at": "2026-03-01T..."
    }
  ]
}
```

---

### POST /repositorios

**Request:**
```json
{ "nome": "Resumos para P1", "icone": "description" }
```
> `icone`: Material Icon name. Default: `"folder"`.

**Response 201:** Retorna repositório criado.

---

### PATCH /repositorios/{id}

**Request:**
```json
{ "nome": "Novo nome" }
```

**Response 200:** Retorna repositório atualizado.

**Errors:** `403 ACCESS_DENIED`, `404 NOT_FOUND`

---

### DELETE /repositorios/{id}

Deleta repositório. Gravações dentro ficam órfãs (`source_id = null`).

**Response 204:** Sem body.

---

## 5. Gravações

### POST /gravacoes

Salva nova gravação com transcrição on-device.

**Request:**
```json
{
  "source_type": "disciplina",
  "source_id": "uuid",
  "transcription": "Bom dia a todos, vamos comecar...",
  "duration_seconds": 4800,
  "date": "2026-02-25"   // opcional, default: hoje
}
```

**Response 201:**
```json
{
  "data": {
    "id": "uuid",
    "source_type": "disciplina",
    "source_id": "uuid",
    "date": "2026-02-25",
    "date_label": "Terca, 25 de fevereiro",
    "duration_seconds": 4800,
    "duration_label": "1h 20min",
    "status": "processing",
    "created_at": "2026-03-06T..."
  }
}
```

**Backend pipeline (background task):**
1. Salva gravacao com `status='processing'`
2. Gera embeddings (`text-embedding-3-small`, pgvector)
3. Gera resumo (`GPT-4o-mini` → `short_summary` + `full_summary`)
4. Gera mapa mental (`GPT-4o-mini` → `mind_map` JSONB)
5. Atualiza `status → 'ready'`

> Se qualquer step falhar: `status → 'error'`, `mind_map` fica `null` (graceful).

**iOS notes:**
- Poll `GET /gravacoes/{id}` a cada 5s
- Timeout de **3 minutos** — após timeout, mostra "Processando..." sem bloquear UI e atualiza quando o aluno voltar

---

### GET /gravacoes

Lista gravações por source.

**Query params:**

| Param | Type | Required | Description |
|-------|------|----------|-------------|
| source_type | string | sim | `"disciplina"` ou `"repositorio"` |
| source_id | uuid | sim | Source ID |
| page | int | não | Default 1 |
| per_page | int | não | Default 20 |

**Response 200:**
```json
{
  "data": [
    {
      "id": "uuid",
      "source_type": "disciplina",
      "source_id": "uuid",
      "date": "2026-02-25",
      "date_label": "Terca, 25 de fevereiro",
      "duration_seconds": 4800,
      "duration_label": "1h 20min",
      "status": "ready",
      "short_summary": "A aula abordou o mix de marketing...",
      "media_count": 3,
      "materials_count": 2,
      "has_mind_map": true,
      "received_from": null
    }
  ],
  "pagination": { "page": 1, "per_page": 20, "total": 12, "pages": 1 }
}
```

> `received_from`: `null` se gravação própria, nome do remetente se recebida via compartilhamento.

---

### GET /gravacoes/{id}

Detalhe completo da gravação.

**Response 200:**
```json
{
  "data": {
    "id": "uuid",
    "source_type": "disciplina",
    "source_id": "uuid",
    "date": "2026-02-25",
    "date_label": "Terca, 25 de fevereiro",
    "duration_seconds": 4800,
    "duration_label": "1h 20min",
    "status": "ready",
    "short_summary": "A aula abordou o mix de marketing...",
    "full_summary": [
      {
        "title": "Mix de Marketing (4Ps)",
        "bullets": ["Modelo classico: Produto, Preco, Praca e Promocao", "Cada P influencia..."]
      }
    ],
    "transcription": "Bom dia a todos, vamos comecar...",
    "mind_map": {
      "topic": "Mix de Marketing",
      "branches": [
        { "topic": "Produto",  "color": 0, "children": ["Qualidade e Design", "Ciclo de Vida", "Marca e Embalagem"] },
        { "topic": "Preco",    "color": 1, "children": ["Precificacao", "Elasticidade", "Preco Psicologico"] },
        { "topic": "Praca",    "color": 2, "children": ["Canais de Distrib.", "Logistica", "E-commerce"] },
        { "topic": "Promocao", "color": 3, "children": ["Publicidade", "Marketing Digital", "Relacoes Publicas"] }
      ]
    },
    "media": [
      {
        "id": "uuid",
        "type": "photo",
        "label": "Quadro - 4Ps do Marketing",
        "timestamp_seconds": 872,
        "timestamp_label": "14:32",
        "url": "https://...supabase.co/storage/..."
      }
    ],
    "materials": [
      {
        "id": "uuid",
        "nome": "Cap. 3 - Mix de Marketing.pdf",
        "tipo": "pdf",
        "size_label": "2.4 MB",
        "url": "https://...supabase.co/storage/..."
      }
    ],
    "received_from": null,
    "created_at": "2026-03-06T..."
  }
}
```

**Mind map schema (invariantes):**
- Sempre exatamente 4 branches
- Sempre exatamente 3 children por branch
- `color`: 0=red, 1=orange, 2=green, 3=purple
- `topic` root: máx 30 chars | branch: máx 20 chars | children: máx 22 chars
- `null` se geração falhou ou ainda processando

---

### POST /gravacoes/{id}/media

Upload de foto tirada durante ou após a gravação.

**Content-Type: multipart/form-data**

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| file | file | sim | JPEG/PNG (máx 10MB) |
| label | string | não | Descrição |
| timestamp_seconds | int | sim | Momento na gravação (0 se adicionada depois) |

**Response 201:**
```json
{
  "data": {
    "id": "uuid",
    "type": "photo",
    "label": "Quadro - 4Ps",
    "timestamp_seconds": 872,
    "timestamp_label": "14:32",
    "url": "https://...supabase.co/storage/...",
    "created_at": "2026-03-06T..."
  }
}
```

---

### PATCH /gravacoes/{id}

Move gravação para outro source.

**Request:**
```json
{ "source_type": "repositorio", "source_id": "uuid" }
```

**Response 200:** Retorna gravação atualizada (formato do list item).

---

### DELETE /gravacoes/{id}

Deleta gravação e todos os dados associados (transcrição, resumo, mapa, mídia, embeddings).

**Response 204:** Sem body.

---

### GET /gravacoes/{id}/pdf/resumo

Download do resumo em PDF.

**Response 200:** `Content-Type: application/pdf`. iOS faz download direto.

**Errors:** `404 NOT_FOUND` — gravação não encontrada ou sem resumo ainda.

---

### GET /gravacoes/{id}/pdf/mindmap

Download do mapa mental em PDF.

**Response 200:** `Content-Type: application/pdf`.

**Errors:** `404 NOT_FOUND` — gravação não encontrada ou `mind_map` é null.

---

## 6. Materiais

### GET /disciplinas/{id}/materiais

**Response 200:**
```json
{
  "data": [
    {
      "id": "uuid",
      "disciplina_id": "uuid",
      "tipo": "pdf",
      "nome": "Cap. 3 - Mix de Marketing.pdf",
      "url_storage": "https://...supabase.co/...",
      "fonte": "canvas",
      "ai_enabled": true,
      "size_bytes": 2516582,
      "size_label": "2.4 MB",
      "created_at": "2026-02-25T..."
    }
  ]
}
```

> `fonte`: `"canvas"` (auto-sincronizado) ou `"manual"` (upload do aluno).
> `tipo`: `"pdf"`, `"slide"` (pptx), `"foto"`, `"outro"`.
> `ai_enabled`: `true` por padrão. Aluno pode desabilitar individualmente via toggle.

---

### POST /disciplinas/{id}/materiais

Upload manual pelo aluno.

**Content-Type: multipart/form-data**

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| file | file | sim | PDF, PPTX, DOCX, imagens (máx 20MB) |
| ai_enabled | bool | não | Alimentar IA? Default: `true` |

**Response 201:** Retorna material criado.

**Backend notes:**
- Extrai texto (PyPDF2/python-pptx)
- Upload para Supabase Storage bucket `"materiais"`
- Se `ai_enabled`: gera embeddings em background

---

### GET /materiais/{id}

**Response 200:** Mesmo objeto do list item.

---

### PATCH /materiais/{id}/toggle-ai

Toggle do flag `ai_enabled`. Gera ou remove embeddings correspondentemente.

**Response 200:**
```json
{ "data": { "id": "uuid", "ai_enabled": false } }
```

**Backend notes:**
- `ai_enabled true → false`: remove embeddings do pgvector
- `ai_enabled false → true`: gera embeddings em background

---

### POST /disciplinas/{id}/sync

Dispara sync manual do Canvas para uma disciplina.

**Response 200:**
```json
{
  "data": {
    "status": "triggered",
    "last_synced_at": "2026-03-06T03:00:00Z"
  }
}
```

**Errors:**
```json
// 429 SYNC_COOLDOWN
{
  "data": null,
  "error": "SYNC_COOLDOWN",
  "message": "Sync disponivel em breve.",
  "next_sync_available_at": "2026-03-06T04:00:00Z"
}
```

> `next_sync_available_at`: iOS usa este campo para exibir countdown do cooldown de 1 hora.

**Backend notes:**
- Usa token Canvas do usuário para chamar Canvas REST API
- `GET /courses/{canvas_course_id}/modules` → items → filtra arquivos
- Download novos → extrai texto → upload storage → salva DB → embeddings
- Atualiza `disciplinas.last_scraped_at`

---

## 7. Chat — Barista (AI)

### GET /chats

**Response 200:**
```json
{
  "data": [
    {
      "id": "uuid",
      "source_type": "disciplina",
      "source_id": "uuid",
      "source_name": "Gestao de Marketing",
      "source_icon": "school",
      "last_message": "Os 4Ps discutidos na aula de 25/02...",
      "message_count": 5,
      "updated_at": "2026-03-06T14:32:00Z"
    }
  ]
}
```

---

### POST /chats

**Request:**
```json
{ "source_type": "disciplina", "source_id": "uuid" }
```

**Response 201:** Retorna chat criado (`message_count=0`).

> Trocar disciplina/repositório requer criar novo chat.

---

### GET /chats/{id}/messages

**Response 200:**
```json
{
  "data": [
    {
      "id": "uuid",
      "sender": "user",
      "text": "Quais os principais conceitos?",
      "created_at": "2026-03-06T14:30:00Z"
    },
    {
      "id": "uuid",
      "sender": "ai",
      "label": "Barista de Gestao de Marketing",
      "text": "Os 4Ps discutidos na aula de 25/02...",
      "mode": "lungo",
      "sources": [
        {
          "type": "transcription",
          "gravacao_id": "uuid",
          "title": "Aula 25/02",
          "date": "25 fev 2026",
          "excerpt": "...os quatro pilares do marketing...",
          "similarity": 0.89
        },
        {
          "type": "material",
          "material_id": "uuid",
          "title": "Cap. 3 - Mix de Marketing.pdf",
          "excerpt": "...modelo classico de Kotler...",
          "similarity": 0.82
        }
      ],
      "created_at": "2026-03-06T14:30:05Z"
    }
  ]
}
```

---

### POST /chats/{id}/messages

Envia pergunta ao Barista. Resposta via SSE streaming.

**Request:**
```json
{
  "text": "Quais os principais conceitos da aula de ontem?",
  "mode": "lungo",
  "gravacao_id": null
}
```

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| text | string | sim | Pergunta (1-5000 chars) |
| mode | string | sim | `"espresso"`, `"lungo"`, `"cold_brew"` |
| gravacao_id | uuid | não | Gravação específica (null = todas da source) |

**Response: SSE stream (text/event-stream)**
```
data: {"token": "Os "}
data: {"token": "4Ps "}
...
data: {"done": true, "message_id": "uuid", "chat_id": "uuid", "sources": [...], "questions_remaining": {"espresso": -1, "lungo": 27, "cold_brew": 14}}
```

**Errors:**
- `429 QUESTION_LIMIT` — limite mensal atingido para o modo
- `403 SUBSCRIPTION_REQUIRED` — plano expirado
- `404 CHAT_NOT_FOUND`

**Mode → Model mapping:**

| Mode | Model | Limite mensal |
|------|-------|---------------|
| espresso | GPT-4o-mini | Ilimitado |
| lungo | GPT-4o | 30/mês |
| cold_brew | Claude Opus 4 | 15/mês |

> Limites iguais para trial e premium. Reset a cada 30 dias da data de criação do usuário.

**Response headers:**
```
X-Questions-Remaining-Espresso: -1
X-Questions-Remaining-Lungo: 27
X-Questions-Remaining-ColdBrew: 14
```

**RAG pipeline:**
1. Embed pergunta (`text-embedding-3-small`)
2. Busca pgvector filtrado por `source_id` + `ai_enabled`
3. Se `gravacao_id` especificado: filtra também por `fonte_id`
4. Top 8 chunks como contexto
5. Stream response do modelo selecionado
6. Salva mensagem + fontes no DB

---

## 8. Compartilhamentos (Sharing)

### POST /compartilhamentos

**Request:**
```json
{
  "gravacao_id": "uuid",
  "recipient_emails": ["ana@acad.espm.br", "lucas@acad.espm.br"],
  "shared_content": ["resumo", "mapa"],
  "message": "Olha o resumo da aula que voce perdeu!"
}
```

**Response 201:**
```json
{
  "data": {
    "shared_count": 1,
    "not_found_emails": ["lucas@acad.espm.br"],
    "results": [
      { "email": "ana@acad.espm.br", "status": "sent" },
      { "email": "lucas@acad.espm.br", "status": "not_found" }
    ]
  }
}
```

> Envia para quem existe no Coffee. `not_found_emails` lista os que não foram encontrados.
> `404 RECIPIENT_NOT_FOUND` apenas se **todos** os emails forem inválidos.
> iOS deve exibir aviso para emails não encontrados.

**Backend notes:**
- Busca destinatários por `users.espm_login`
- Cria uma linha de `compartilhamentos` por destinatário
- Sempre envia pacote completo: resumo + mapa + fotos + transcrição
- `shared_content` armazenado apenas para exibição
- Envia push notification para destinatários

---

### GET /compartilhamentos/received

**Response 200:**
```json
{
  "data": [
    {
      "id": "uuid",
      "sender": { "nome": "Ana Beatriz", "initials": "AB" },
      "gravacao": {
        "date": "2026-02-25",
        "date_label": "Terca, 25 de fevereiro",
        "duration_label": "1h 20min",
        "short_summary": "A aula abordou...",
        "has_mind_map": true
      },
      "source_discipline": "Gestao de Marketing",
      "shared_content": ["resumo", "mapa"],
      "message": "Olha o resumo da aula!",
      "status": "pending",
      "is_new": true,
      "created_at": "2026-03-06T14:30:00Z"
    }
  ]
}
```

---

### POST /compartilhamentos/{id}/accept

**Request:**
```json
{ "destination_type": "disciplina", "destination_id": "uuid" }
```

**Response 200:**
```json
{
  "data": {
    "gravacao_id": "uuid",
    "destination_type": "disciplina",
    "destination_id": "uuid",
    "status": "accepted"
  }
}
```

**Backend notes:**
1. Cria nova gravação para o destinatário (cópia): transcrição, resumo, mapa, data, duração
2. `received_from` = nome do remetente
3. Copia mídia (fotos) da gravação original
4. Gera embeddings para pgvector do destinatário
5. Atualiza `compartilhamento status = 'accepted'`
6. Atualiza `gravacao status = 'ready'` após embeddings

---

### POST /compartilhamentos/{id}/reject

**Response 200:**
```json
{ "data": { "status": "rejected" } }
```

> Backend: atualiza status = 'rejected'. Nenhum dado copiado.

---

## 9. Profile

### GET /profile

**Response 200:**
```json
{
  "data": {
    "id": "uuid",
    "nome": "Gabriel Lima",
    "email": "gabriel@email.com",
    "plano": "trial",
    "trial_end": "2026-03-13T00:00:00Z",
    "subscription_active": false,
    "espm_connected": true,
    "espm_login": "gabriel.lima@acad.espm.br",
    "usage": {
      "gravacoes_total": 20,
      "horas_gravadas": 12.5,
      "questions_remaining": { "espresso": -1, "lungo": 27, "cold_brew": 14 },
      "questions_reset_at": "2026-04-06T00:00:00Z"
    },
    "gift_codes": [
      { "code": "ABC12345", "redeemed": false },
      { "code": "XYZ67890", "redeemed": true, "redeemed_by": "Ana" }
    ],
    "created_at": "2026-03-06T..."
  }
}
```

> `questions_remaining`: `-1` = ilimitado (espresso).
> `gift_codes`: presente apenas para assinantes premium.

---

### PATCH /profile

**Request:**
```json
{ "nome": "Gabriel Lima Santos" }
```

**Response 200:** Retorna perfil completo.

---

## 10. Subscription

### POST /subscription/verify

Valida receipt Apple após compra StoreKit 2.

**Request:**
```json
{ "receipt_data": "base64...", "transaction_id": "apple_txn_id" }
```

**Response 200:**
```json
{
  "data": {
    "plano": "premium",
    "subscription_active": true,
    "expires_at": "2026-04-06T00:00:00Z",
    "gift_codes": [
      { "code": "ABC12345", "redeemed": false },
      { "code": "XYZ67890", "redeemed": false }
    ]
  }
}
```

**Backend notes:**
- Valida receipt com Apple
- Atualiza `plano = 'premium'`
- Cria registro de assinatura
- Auto-gera 2 gift codes para o assinante
- Preço: R$59,90/mês (cheio) ou R$29,90/mês (promo lançamento)

---

### GET /subscription/status

**Response 200:** Mesmo formato do verify response.

---

## 11. Gift Codes

> Apenas usuários em **trial** podem resgatar gift codes. Botão oculto para assinantes premium.

### GET /gift-codes

**Response 200:**
```json
{
  "data": {
    "codes": [
      { "code": "ABC12345", "redeemed": false, "created_at": "2026-03-06T..." },
      { "code": "XYZ67890", "redeemed": true, "redeemed_by": "Ana", "redeemed_at": "2026-03-08T..." }
    ],
    "share_message": "Usa meu codigo ABC12345 no Coffee e ganha 7 dias gratis!"
  }
}
```

---

### POST /gift-codes/validate

**Request:**
```json
{ "code": "ABC12345" }
```

**Response 200:**
```json
{ "data": { "valid": true, "owner_name": "Gabriel" } }
// ou
{ "data": { "valid": false } }
```

---

### POST /gift-codes/redeem

**Request:**
```json
{ "code": "ABC12345" }
```

**Response 200:**
```json
{ "data": { "redeemed": true, "days_added": 7, "new_trial_end": "2026-03-20T00:00:00Z" } }
```

**Errors:**
- `404 INVALID_CODE`
- `409 CODE_ALREADY_USED`
- `409 ALREADY_REDEEMED`
- `403 SUBSCRIPTION_REQUIRED` — usuário premium não pode resgatar

---

## 12. Devices & Notifications

### POST /devices

**Request:**
```json
{ "token": "fcm_token_string", "platform": "ios" }
```

**Response 201:** `{ "data": { "success": true } }`

---

### DELETE /devices/{token}

**Response 200:** `{ "data": { "success": true } }`

---

### GET /notificacoes

Lista últimas 50 notificações.

**Response 200:**
```json
{
  "data": [
    {
      "id": "uuid",
      "tipo": "compartilhamento",
      "titulo": "Ana Beatriz compartilhou uma aula",
      "corpo": "Gestao de Marketing - Aula 25/02",
      "data_payload": {
        "compartilhamento_id": "uuid",
        "deep_link": "coffee://compartilhamentos/{uuid}"
      },
      "lida": false,
      "created_at": "2026-03-06T14:30:00Z"
    }
  ]
}
```

> `deep_link` padrão: `coffee://compartilhamentos/{id}` — iOS navega direto para aba Recebidos.

---

### PATCH /notificacoes/{id}/read

**Response 200:** Retorna notificação atualizada.

---

## 13. Settings & Account

### GET /settings

**Response 200:**
```json
{ "data": { "espm_connected": true, "espm_login": "gabriel.lima@acad.espm.br" } }
```

---

### POST /espm/disconnect

Desconecta conta ESPM. App trava na tela de conexão ESPM.

**Response 200:**
```json
{ "data": null, "message": "ESPM desconectado" }
```

**Backend notes:**
- Limpa `espm_login`, `canvas_token`, `canvas_token_expires_at`
- **NÃO** deleta disciplinas ou gravações (dados persistem)
- App fica inutilizável até reconexão via `POST /espm/connect`

---

### DELETE /account

Deleta todos os dados do usuário (LGPD).

**Request:**
```json
{ "confirm": true }
```

**Response 200:**
```json
{ "data": null, "message": "Conta excluida com sucesso" }
```

**Backend notes:**
- Deleção cascateada: user → gravacoes → media → embeddings → chats → mensagens → compartilhamentos → subscriptions → gift_codes → device_tokens → notificacoes → user_disciplinas
- Remove arquivos do Supabase Storage (bucket media)
- Blacklista JWT atual
- **Irreversível**

---

### POST /support/contact

**Request:**
```json
{ "subject": "Problema com transcricao", "message": "A transcricao ficou cortada..." }
```

**Response 200:**
```json
{ "data": null, "message": "Mensagem enviada com sucesso" }
```

**Backend notes:**
- Envia email para `suportecoffeeapp@gmail.com` com info do usuário + subject + message

---

### GET /health

**Response 200:**
```json
{ "status": "ok", "timestamp": "2026-03-06T..." }
```

---

## Appendix A — Complete Endpoint Table

| # | Method | Path | Description |
|---|--------|------|-------------|
| 1 | POST | /auth/signup | Create account |
| 2 | POST | /auth/login | Login |
| 3 | POST | /auth/logout | Logout + remove FCM |
| 4 | POST | /auth/forgot-password | Password recovery |
| 5 | POST | /auth/refresh | Renew JWT |
| 6 | GET | /auth/me | Current user |
| 7 | POST | /espm/connect | Connect/Reconnect ESPM |
| 8 | POST | /espm/sync | Re-sync disciplines |
| 9 | GET | /espm/status | Connection status |
| 10 | POST | /espm/disconnect | Disconnect ESPM |
| 11 | GET | /disciplinas | List disciplines |
| 12 | GET | /disciplinas/{id} | Discipline detail |
| 13 | GET | /repositorios | List repos |
| 14 | POST | /repositorios | Create repo |
| 15 | PATCH | /repositorios/{id} | Rename repo |
| 16 | DELETE | /repositorios/{id} | Delete repo |
| 17 | POST | /gravacoes | Save recording |
| 18 | GET | /gravacoes | List recordings |
| 19 | GET | /gravacoes/{id} | Recording detail |
| 20 | POST | /gravacoes/{id}/media | Upload photo |
| 21 | PATCH | /gravacoes/{id} | Move recording |
| 22 | DELETE | /gravacoes/{id} | Delete recording |
| 23 | GET | /gravacoes/{id}/pdf/resumo | Download summary PDF |
| 24 | GET | /gravacoes/{id}/pdf/mindmap | Download mind map PDF |
| 25 | GET | /disciplinas/{id}/materiais | List materials |
| 26 | POST | /disciplinas/{id}/materiais | Upload material |
| 27 | GET | /materiais/{id} | Material detail |
| 28 | PATCH | /materiais/{id}/toggle-ai | Toggle AI feed |
| 29 | POST | /disciplinas/{id}/sync | Manual Canvas sync |
| 30 | GET | /chats | List conversations |
| 31 | POST | /chats | Create conversation |
| 32 | GET | /chats/{id}/messages | List messages |
| 33 | POST | /chats/{id}/messages | Send question (SSE) |
| 34 | POST | /compartilhamentos | Share recording |
| 35 | GET | /compartilhamentos/received | Inbox |
| 36 | POST | /compartilhamentos/{id}/accept | Accept share |
| 37 | POST | /compartilhamentos/{id}/reject | Reject share |
| 38 | GET | /profile | User profile |
| 39 | PATCH | /profile | Update profile |
| 40 | POST | /subscription/verify | Verify Apple receipt |
| 41 | GET | /subscription/status | Subscription status |
| 42 | GET | /gift-codes | List gift codes |
| 43 | POST | /gift-codes/validate | Validate code |
| 44 | POST | /gift-codes/redeem | Redeem code |
| 45 | POST | /devices | Register FCM |
| 46 | DELETE | /devices/{token} | Remove FCM |
| 47 | GET | /notificacoes | List notifications |
| 48 | PATCH | /notificacoes/{id}/read | Mark read |
| 49 | GET | /settings | Get settings |
| 50 | DELETE | /account | Delete account (LGPD) |
| 51 | POST | /support/contact | Contact form |
| 52 | GET | /health | Health check |

**Total: 52 endpoints**

---

## Appendix B — Error Codes

| HTTP | Code | Description |
|------|------|-------------|
| 401 | INVALID_CREDENTIALS | Wrong email or password |
| 401 | TOKEN_EXPIRED | JWT expired — redirect to login |
| 401 | ESPM_AUTH_FAILED | ESPM credentials invalid |
| 403 | ACCESS_DENIED | User doesn't own resource |
| 403 | SUBSCRIPTION_REQUIRED | Plano expirado — iOS redireciona pro paywall |
| 404 | NOT_FOUND | Resource not found |
| 404 | USER_NOT_FOUND | Email not registered |
| 404 | INVALID_CODE | Gift code not found |
| 404 | RECIPIENT_NOT_FOUND | ALL share recipients not in Coffee |
| 409 | EMAIL_EXISTS | Email already registered |
| 409 | CODE_ALREADY_USED | Gift code already redeemed |
| 409 | ALREADY_REDEEMED | User already redeemed a code |
| 422 | VALIDATION_ERROR | Invalid request fields |
| 429 | QUESTION_LIMIT | Monthly question limit for mode |
| 429 | SYNC_COOLDOWN | Manual sync cooldown (1h) — retorna next_sync_available_at |
| 500 | INTERNAL_ERROR | Server error |
| 502 | AI_ERROR | OpenAI/Anthropic API error |
| 503 | ESPM_UNAVAILABLE | Canvas down |
| 504 | ESPM_TIMEOUT | Canvas timeout |

---

## Appendix C — Database Schema

### users
```sql
id UUID PK
nome VARCHAR(255)
email VARCHAR(255) UNIQUE
password_hash VARCHAR(255)
plano VARCHAR(20) DEFAULT 'trial'         -- trial | premium | expired
trial_end TIMESTAMPTZ
espm_login VARCHAR(255)                    -- email ESPM vinculado
encrypted_espm_password BYTEA
canvas_token TEXT                          -- encrypted Canvas API token
canvas_token_expires_at TIMESTAMPTZ
created_at TIMESTAMPTZ
updated_at TIMESTAMPTZ
```

### disciplinas
```sql
id UUID PK
nome VARCHAR(255)
turma VARCHAR(20)
semestre VARCHAR(20)
canvas_course_id INTEGER
last_scraped_at TIMESTAMPTZ
created_at TIMESTAMPTZ
UNIQUE(nome, semestre)
```

### user_disciplinas
```sql
id UUID PK
user_id UUID FK→users
disciplina_id UUID FK→disciplinas
created_at TIMESTAMPTZ
UNIQUE(user_id, disciplina_id)
```

### repositorios
```sql
id UUID PK
user_id UUID FK→users
nome VARCHAR(50)
icone VARCHAR(50) DEFAULT 'folder'
created_at TIMESTAMPTZ
```

### gravacoes
```sql
id UUID PK
user_id UUID FK→users
source_type VARCHAR(20)                    -- disciplina | repositorio
source_id UUID
date DATE DEFAULT CURRENT_DATE
duration_seconds INTEGER DEFAULT 0
status VARCHAR(20) DEFAULT 'processing'    -- processing | ready | error
transcription TEXT
short_summary TEXT
full_summary JSONB
mind_map JSONB                             -- 4x3 mind map JSON
received_from VARCHAR(255)                 -- null ou nome do remetente
created_at TIMESTAMPTZ
```

### gravacao_media
```sql
id UUID PK
gravacao_id UUID FK→gravacoes
type VARCHAR(20) DEFAULT 'photo'
label VARCHAR(255)
timestamp_seconds INTEGER
url_storage TEXT
created_at TIMESTAMPTZ
```

### materiais
```sql
id UUID PK
disciplina_id UUID FK→disciplinas
tipo VARCHAR(20)                           -- pdf | slide | foto | outro
nome VARCHAR(255)
url_storage TEXT
texto_extraido TEXT
fonte VARCHAR(20) DEFAULT 'canvas'         -- canvas | manual
canvas_file_id INTEGER UNIQUE
hash_arquivo VARCHAR(64)
ai_enabled BOOLEAN DEFAULT true            -- habilitado por padrão, aluno pode desabilitar
size_bytes BIGINT
created_at TIMESTAMPTZ
```

### chats
```sql
id UUID PK
user_id UUID FK→users
source_type VARCHAR(20)                    -- disciplina | repositorio
source_id UUID
created_at TIMESTAMPTZ
updated_at TIMESTAMPTZ
```

### mensagens
```sql
id UUID PK
chat_id UUID FK→chats
role VARCHAR(10)                           -- user | assistant
conteudo TEXT
fontes JSONB DEFAULT '[]'
mode VARCHAR(20)                           -- espresso | lungo | cold_brew
created_at TIMESTAMPTZ
```

### embeddings
```sql
id UUID PK
disciplina_id UUID FK→disciplinas          -- null para gravacoes de repositorio
fonte_tipo VARCHAR(20)                     -- transcricao | material
fonte_id UUID
chunk_index INTEGER
texto_chunk TEXT
embedding VECTOR(1536)
metadata JSONB DEFAULT '{}'
created_at TIMESTAMPTZ
```

### compartilhamentos
```sql
id UUID PK
sender_id UUID FK→users
recipient_id UUID FK→users
gravacao_id UUID FK→gravacoes              -- gravacao original
shared_content JSONB                       -- ["resumo", "mapa"]
message TEXT
status VARCHAR(20) DEFAULT 'pending'       -- pending | accepted | rejected
destination_type VARCHAR(20)               -- preenchido no accept
destination_id UUID                        -- preenchido no accept
created_gravacao_id UUID                   -- cópia criada para o destinatário
created_at TIMESTAMPTZ
```

### gift_codes
```sql
id UUID PK
owner_id UUID FK→users                     -- assinante que gerou
code VARCHAR(20) UNIQUE
redeemed_by UUID FK→users                  -- quem usou
redeemed_at TIMESTAMPTZ
created_at TIMESTAMPTZ
```

### subscriptions
```sql
id UUID PK
user_id UUID FK→users
plano VARCHAR(20) DEFAULT 'premium'
status VARCHAR(20)                         -- active | expired | cancelled
trial_end TIMESTAMPTZ
expires_at TIMESTAMPTZ
apple_transaction_id VARCHAR(255)
created_at TIMESTAMPTZ
```

### device_tokens
```sql
id UUID PK
user_id UUID FK→users
fcm_token TEXT UNIQUE
platform VARCHAR(10) DEFAULT 'ios'
active BOOLEAN DEFAULT true
created_at TIMESTAMPTZ
updated_at TIMESTAMPTZ
```

### notificacoes
```sql
id UUID PK
user_id UUID FK→users
tipo VARCHAR(30)                           -- compartilhamento (único tipo por ora)
titulo VARCHAR(255)
corpo TEXT
data_payload JSONB DEFAULT '{}'            -- inclui deep_link
lida BOOLEAN DEFAULT false
created_at TIMESTAMPTZ
```

### token_blacklist
```sql
id UUID PK
token_hash VARCHAR(64)
expires_at TIMESTAMPTZ
created_at TIMESTAMPTZ
```

---

## Appendix D — Product Decisions

- **Platform:** iOS native (SwiftUI). Gravação + transcrição on-device (WhisperKit/CoreML).
- **Pricing:** R$59,90/mês (cheio), R$29,90/mês (promo lançamento). Só mensal. Trial: 7 dias, sem cartão.
- **AI assistant name:** Barista.
- **AI modes:** Espresso (GPT-4o-mini, ilimitado), Lungo (GPT-4o, 30/mês), Cold Brew (Claude Opus 4, 15/mês). Limites iguais trial e premium. Reset a cada 30 dias da data de criação.
- **Áudio:** Deletado do device após transcrição. Nunca enviado ao servidor. Só texto persiste.
- **ESPM:** Conexão obrigatória. Token Canvas gerado via Playwright (120 dias). Renovação automática. Sem professor, horário, sala.
- **Estado expirado:** Read-only — aluno vê gravações antigas, não grava nem usa Barista.
- **Sharing:** Via @acad.espm.br. Pacote completo (resumo + mapa + fotos + transcrição). Transcrição invisível para destinatário, alimenta RAG dele.
- **Compartilhamento misto:** Envia para quem existe, avisa quem não foi encontrado.
- **Gift codes:** 2 por assinante (auto-gerados). Cada um dá +7 dias de trial. Não é referral — quem indica não ganha nada. Só trial pode resgatar.
- **Materiais:** `ai_enabled=true` por padrão. Aluno pode desabilitar individualmente. Upload manual. Sync automático diário + manual com cooldown de 1h.
- **Mapa mental:** 4 branches x 3 children. GPT-4o-mini a partir do resumo. JSONB em gravacoes. Null se falhar.
- **PDF downloads:** Backend gera. PDFs separados para resumo e mapa mental.
- **Polling de gravação:** A cada 5s. Timeout de 3 minutos. Após timeout, mostra "Processando..." sem bloquear UI.
- **Deep link de notificação:** `coffee://compartilhamentos/{id}`.
- **Sync cooldown:** 429 retorna `next_sync_available_at` para iOS exibir countdown.
- **Settings:** Mínimas. Status ESPM, sobre, termos, privacidade, fale conosco, logout, excluir conta (LGPD).
- **Notificações:** Push apenas para compartilhamentos recebidos (por ora).
- **Infraestrutura:** Railway (backend) + Supabase (DB + Storage). Container scraper eliminado. Playwright roda no container backend.
- **Canvas sync:** Automático diário + manual por disciplina (cooldown 1h). REST API com token do usuário.

---

*— end of contract v3.1 —*