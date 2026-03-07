# Prompt 02 — Reescrever Gravações

## Contexto
O router `gravacoes.py` atual assume upload de áudio pro servidor + transcrição via Whisper API. No plano novo, o iOS faz transcrição on-device e envia apenas texto. O endpoint `POST /{id}/upload` inteiro deve ser eliminado. A gravação agora recebe transcrição como texto, gera embeddings automaticamente, e dispara resumo em background. Também precisa suportar `source_type/source_id` em vez de `disciplina_id`, upload de fotos (media), e mover gravação.

## Pré-requisitos
Prompts 00 e 01 executados.

## Arquivos a REESCREVER
- `coffee-backend/app/routers/gravacoes.py` (reescrever completamente)
- `coffee-backend/app/schemas/gravacoes.py` (reescrever completamente)

## Tarefa

### 1. Reescrever `schemas/gravacoes.py`

```python
from datetime import date, datetime
from typing import Optional
from uuid import UUID
from pydantic import BaseModel, Field

class CriarGravacaoRequest(BaseModel):
    source_type: str = Field(pattern="^(disciplina|repositorio)$")
    source_id: UUID
    transcription: str = Field(min_length=10)
    duration_seconds: int = Field(gt=0)
    date: Optional[date] = None  # default: today

class MoverGravacaoRequest(BaseModel):
    source_type: str = Field(pattern="^(disciplina|repositorio)$")
    source_id: UUID

class MediaUploadResponse(BaseModel):
    id: UUID
    type: str
    label: Optional[str]
    timestamp_seconds: int
    timestamp_label: str
    url: str
    created_at: datetime

class GravacaoSummarySection(BaseModel):
    title: str
    bullets: list[str]

class GravacaoMediaItem(BaseModel):
    id: UUID
    type: str
    label: Optional[str]
    timestamp_seconds: int
    timestamp_label: str
    url: str

class GravacaoMaterialItem(BaseModel):
    id: UUID
    nome: str
    tipo: str
    size_label: str
    url: Optional[str]

class GravacaoListItem(BaseModel):
    id: UUID
    source_type: str
    source_id: UUID
    date: date
    date_label: str
    duration_seconds: int
    duration_label: str
    status: str
    short_summary: Optional[str]
    media_count: int
    materials_count: int

class GravacaoDetail(BaseModel):
    id: UUID
    source_type: str
    source_id: UUID
    date: date
    date_label: str
    duration_seconds: int
    duration_label: str
    status: str
    short_summary: Optional[str]
    full_summary: Optional[list[GravacaoSummarySection]]
    transcription: Optional[str]
    media: list[GravacaoMediaItem]
    materials: list[GravacaoMaterialItem]
    created_at: datetime

class GravacaoCreatedResponse(BaseModel):
    id: UUID
    source_type: str
    source_id: UUID
    date: date
    date_label: str
    duration_seconds: int
    duration_label: str
    status: str
    created_at: datetime
```

### 2. Reescrever `routers/gravacoes.py`

O novo router deve ter 6 endpoints:

**POST /gravacoes** — Salvar nova gravação
- Recebe: source_type, source_id, transcription (texto completo), duration_seconds, date
- Valida ownership (se disciplina, checa user_disciplinas; se repositorio, checa repositorios.user_id)
- Salva com status='processing'
- Dispara em background: generate_transcription_embeddings + generate_summary_for_gravacao
- Retorna a gravação com status='processing'
- IMPORTANTE: precisa resolver disciplina_id pra embeddings. Se source_type='disciplina', disciplina_id=source_id. Se 'repositorio', disciplina_id=NULL (embeddings buscam por fonte_id diretamente)

**GET /gravacoes?source_type=X&source_id=Y** — Listar
- Query params: source_type, source_id, page, per_page
- Retorna lista com: date_label (formatado "Terça, 25 de fevereiro"), duration_label ("1h 20min"), short_summary, media_count, materials_count
- Ordenar por date DESC

**GET /gravacoes/{id}** — Detalhe completo
- Retorna: tudo do list + full_summary (parsed do JSONB), transcription (texto completo), media[] (JOIN gravacao_media), materials[] (materiais da mesma disciplina, se source_type='disciplina')
- full_summary: parsear JSONB pra lista de {title, bullets}

**POST /gravacoes/{id}/media** — Upload foto
- multipart/form-data: file (JPEG/PNG), label (opcional), timestamp_seconds
- Upload pro Supabase Storage via httpx (mesmo padrão do scraper/storage.py)
- Salva em gravacao_media
- Retorna MediaUploadResponse

**PATCH /gravacoes/{id}** — Mover gravação
- Recebe: source_type, source_id (novo destino)
- Valida ownership do novo destino
- Atualiza source_type e source_id

**DELETE /gravacoes/{id}** — Excluir
- Remove gravação + cascades (gravacao_media, embeddings associados)
- Chamar remove_embeddings do embedding_service

### Helpers necessários no router:

```python
def _format_date_label(d: date) -> str:
    """'2026-02-25' → 'Terça, 25 de fevereiro'"""
    import locale
    locale.setlocale(locale.LC_TIME, 'pt_BR.UTF-8')
    return d.strftime("%A, %d de %B").capitalize()

def _format_duration(seconds: int) -> str:
    """4800 → '1h 20min'"""
    h = seconds // 3600
    m = (seconds % 3600) // 60
    if h > 0:
        return f"{h}h {m}min" if m > 0 else f"{h}h"
    return f"{m}min"

def _format_timestamp(seconds: int) -> str:
    """872 → '14:32'"""
    m = seconds // 60
    s = seconds % 60
    return f"{m}:{s:02d}"

def _format_size(size_bytes: int) -> str:
    """2516582 → '2.4 MB'"""
    if size_bytes >= 1_000_000:
        return f"{size_bytes / 1_000_000:.1f} MB"
    return f"{size_bytes / 1_000:.0f} KB"
```

### Envelope de resposta
TODOS os responses devem seguir: `{"data": ..., "error": null, "message": "ok"}`

## Verificação
1. POST /gravacoes aceita transcription (texto), NÃO aceita file upload de áudio
2. POST /gravacoes dispara embedding + resumo em background (via BackgroundTasks do FastAPI)
3. GET /gravacoes retorna date_label e duration_label formatados
4. GET /gravacoes/{id} retorna full_summary parseado, media[], materials[]
5. POST /gravacoes/{id}/media faz upload pro Supabase Storage
6. PATCH /gravacoes/{id} move gravação entre disciplinas e repositórios
7. DELETE /gravacoes/{id} remove embeddings associados
8. Todos os responses seguem envelope padrão
9. NÃO existe endpoint POST /{id}/upload
