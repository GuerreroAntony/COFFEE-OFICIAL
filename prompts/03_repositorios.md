# Prompt 03 — Repositórios (CRUD Novo)

## Contexto
Repositórios são pastas livres criadas pelo aluno pra organizar gravações fora da grade (monitorias, grupos de estudo). Não existe nada no backend atual — é 100% novo.

## Pré-requisitos
Prompt 00 executado (tabela repositorios existe).

## Arquivos a CRIAR
- `coffee-backend/app/routers/repositorios.py`
- `coffee-backend/app/schemas/repositorios.py`

## Arquivos a MODIFICAR
- `coffee-backend/app/main.py` — adicionar import e include_router

## Tarefa

### 1. Criar `schemas/repositorios.py`

```python
from datetime import datetime
from typing import Optional
from uuid import UUID
from pydantic import BaseModel, Field

class CriarRepositorioRequest(BaseModel):
    nome: str = Field(min_length=1, max_length=50)
    icone: str = Field(default="folder", max_length=50)

class RepositorioResponse(BaseModel):
    id: UUID
    nome: str
    icone: str
    gravacoes_count: int
    ai_active: bool
    created_at: datetime
```

### 2. Criar `routers/repositorios.py`

3 endpoints:

**GET /repositorios** — Listar repositórios do aluno
- JOIN com gravacoes pra contar gravações
- ai_active = true se há pelo menos 1 gravação com status='ready' neste repositório (ou seja, pelo menos 1 transcrição embedada)
- Ordenar por created_at DESC

**POST /repositorios** — Criar repositório
- Campos: nome, icone (default 'folder')
- Retorna repositório criado

**DELETE /repositorios/{id}** — Excluir
- Verifica ownership (repositorios.user_id = current_user)
- SET NULL nas gravações órfãs (UPDATE gravacoes SET source_id = NULL WHERE source_type = 'repositorio' AND source_id = $1)
- Na verdade, como source_id é NOT NULL no schema, precisamos pensar: ao deletar repo, as gravações devem ser desvinculadas ou deletadas? 
  - Decisão: deletar o repositório e deixar as gravações com source_id apontando pra UUID que não existe mais. O frontend pode filtrar isso ou oferecer "reatribuir gravações".
  - Alternativa: mudar source_id pra nullable no schema. MELHOR: sim, tornar nullable.

**ATENÇÃO:** Precisa ajustar o schema do Prompt 00 — `gravacoes.source_id` deve ser `UUID` (nullable) em vez de `UUID NOT NULL`. Isso permite que ao deletar um repositório, as gravações fiquem com source_id = NULL.

### 3. Modificar `main.py`
Adicionar:
```python
from app.routers import repositorios
app.include_router(repositorios.router)
```

### Envelope de resposta
Todos os responses: `{"data": ..., "error": null, "message": "ok"}`

## Verificação
1. GET /repositorios retorna lista com gravacoes_count e ai_active
2. POST /repositorios cria com nome e icone
3. DELETE /repositorios/{id} remove repositório e seta source_id=NULL nas gravações órfãs
4. Ownership verificado em todos os endpoints
5. Router registrado no main.py
