# Canvas ESPM Scraper — Documentacao Tecnica Completa

> Documento de referencia para integracao deste modulo em outros projetos (ex: Coffee).
> Escrito para ser consumido por outro agente Claude Code ou desenvolvedor.

---

## 1. Visao Geral

Este modulo automatiza duas tarefas:

1. **Gerar um access token da API do Canvas ESPM** — via browser automation (Playwright), fazendo login SSO Microsoft e navegando pela UI do Canvas para criar o token.
2. **Baixar todos os materiais (PDFs/PPTXs) do aluno** — usando a API REST do Canvas com o token gerado.

### Arquitetura

```
canvas_login.py              # Login SSO Microsoft via Playwright
       |
       v
generate_canvas_token.py     # Navega UI do Canvas, gera token, salva JSON
       |
       v
canvas_access.py             # Classe CanvasScraper — usa token para baixar materiais
```

### Fluxo de execucao

```
[1] CanvasScraper.__init__()
    |
    +--> Existe canvas_token.json com token valido?
    |       SIM --> usa o token
    |       NAO --> chama generate_canvas_token.py
    |                   |
    |                   +--> canvas_login.py (login SSO)
    |                   +--> navega /profile/settings
    |                   +--> cria token via UI
    |                   +--> salva canvas_token.json
    |
[2] CanvasScraper.run()
    |
    +--> GET /api/v1/users/self/profile
    +--> GET /api/v1/courses (com paginacao)
    +--> Para cada curso:
    |       GET /api/v1/courses/{id}/modules
    |       GET /api/v1/courses/{id}/modules/{mod_id}/items
    |       Filtra por extensao (.pdf, .pptx) e nomes ignorados
    |       Download paralelo (4 threads) dos arquivos novos
    |
    +--> Salva resumo_export.json
```

---

## 2. Arquivos

### `canvas_login.py`

**Responsabilidade**: Login no Canvas ESPM via Microsoft B2C SSO usando Playwright.

**Funcao principal**:
```python
async def canvas_login(
    email: str,
    password: str,
    base_url: str = "https://canvas.espm.br",
    target_path: str = "/profile/settings",
    headless: bool = True,
) -> tuple:  # retorna (pw, browser, page)
```

**Retorno**: Tupla `(playwright_instance, browser, page)`. O chamador e responsavel por fechar com `await browser.close()` e `await pw.stop()`.

**Fluxo detalhado**:
1. Navega direto para `base_url + target_path` (ex: `https://canvas.espm.br/profile/settings`)
   - IMPORTANTE: Ir direto para a URL alvo faz o SSO redirecionar de volta apos login, economizando uma navegacao extra
   - Usa `wait_until="domcontentloaded"` em vez de `"networkidle"` para performance
2. Clica no botao "Conectar com sua conta ESPM" (botao SSO)
3. Preenche email no campo `#i0116` e clica Next (`#idSIButton9`)
4. **Aguarda campo de senha** `#i0118` ficar visivel + sleep de 0.4s (animacao do campo Microsoft)
   - CRITICO: Sem esse delay, o Playwright preenche a senha antes do campo estar interagivel e o login falha
   - O campo precisa de `.click()` antes do `.fill()` para garantir foco
5. Clica Sign In (`#idSIButton9`)
6. Tenta clicar "Stay signed in?" (mesmo botao `#idSIButton9`) — try/except pois pode nao aparecer
7. Aguarda URL voltar para `canvas.espm.br/**`
8. Tenta fechar modal NEXUS (`button[aria-label='Close']`) — try/except

**Seletores DOM do Microsoft B2C SSO**:
| Seletor | Elemento |
|---------|----------|
| `#i0116` | Campo email |
| `#i0118` | Campo senha |
| `#idSIButton9` | Botao Next / Sign In / Stay signed in (mesmo ID nos 3 passos) |

**Pode rodar standalone**:
```bash
CANVAS_EMAIL="email@espm.br" CANVAS_PASSWORD="senha" python3 canvas_login.py
```

---

### `generate_canvas_token.py`

**Responsabilidade**: Gerar um access token da API do Canvas via automacao da UI.

**Funcao principal**:
```python
async def generate_token(
    email: str,
    password: str,
    purpose: str = "scrapper-auto",
    base_url: str = "https://canvas.espm.br",
    output_file: str = "canvas_token.json",
    headless: bool = True,
) -> dict:
```

**Retorno**: Dict com `token`, `purpose`, `created_at`, `expires_at`, `canvas_url`.

**Fluxo detalhado**:
1. Chama `canvas_login()` que ja navega direto para `/profile/settings`
2. Clica em "Novo token de acesso" (abre modal)
3. Preenche campo objetivo: `input[name='purpose']`
4. Clica no campo de data `input[id^='Selectable']` para abrir calendario
5. Avanca 4 meses clicando em `button:has-text('Proximo mes')` com 0.15s entre cliques
6. Seleciona dia = dia atual - 3 (margem de seguranca)
   - IMPORTANTE: Os botoes de dia tem `role='option'` mas o inner_text nao e so o numero
   - Formato real: `"9 julho 2026\n09"` — por isso usa `text.startswith(f"{safe_day} ")`
   - Se o dia nao existir no mes, continua sem data (o Canvas aceita)
7. Clica "Gerar token" (`button[type='submit']:has-text('Gerar token')`)
8. Extrai token do elemento `[data-testid="visible_token"]`
   - CRITICO: O token completo so aparece UMA VEZ neste modal, imediatamente apos criacao
   - Se tentar ver depois em "detalhes", o Canvas mostra truncado
   - Formato do token: `11552~FBrraTFrDDtPayhaz8HGk9ha...` (prefixo numerico + ~ + 64 chars alfanumericos)
9. Salva em `canvas_token.json`

**Constantes**:
- `MONTHS_TO_ADVANCE = 4` — quantos meses avancar no calendario
- `DAYS_AHEAD = 120` — dias de validade alvo (informativo, a data real depende do calendario)

**Seletores DOM do Canvas Settings**:
| Seletor | Elemento |
|---------|----------|
| `text=Novo token de acesso` | Link que abre o modal |
| `input[name='purpose']` | Campo "Objetivo" |
| `input[id^='Selectable']` | Campo data (abre calendario) |
| `button:has-text('Proximo mes')` | Seta avancar mes |
| `button[role='option']` | Botoes dos dias do calendario |
| `button[type='submit']:has-text('Gerar token')` | Botao submit |
| `[data-testid="visible_token"]` | Span com o token completo |

**Arquivo de saida** (`canvas_token.json`):
```json
{
  "token": "11552~FBrraTFrDDtPayhaz8HGk9haFWy9UzALWK7864rVJ7U8JxRkn3NuW3fV9UPKAZB4",
  "purpose": "scrapper-auto",
  "created_at": "2026-03-12T01:04:10",
  "expires_at": "2026-07-10T01:03:40",
  "canvas_url": "https://canvas.espm.br"
}
```

**Pode rodar standalone**:
```bash
CANVAS_EMAIL="email@espm.br" CANVAS_PASSWORD="senha" python3 generate_canvas_token.py
```

---

### `canvas_access.py`

**Responsabilidade**: Baixar todos os materiais do aluno usando a API REST do Canvas.

**Classe principal**: `CanvasScraper`

```python
class CanvasScraper:
    def __init__(
        self,
        token: str = None,         # se fornecido, usa direto (pula auto-geracao)
        canvas_url: str = "https://canvas.espm.br",
        export_dir: str = None,    # default: ./canvas_export/
        token_file: str = None,    # default: ./canvas_token.json
        email: str = None,         # para auto-geracao de token
        password: str = None,      # para auto-geracao de token
    )
```

**Formas de uso (em ordem de prioridade)**:

```python
# 1. Token direto (mais simples para integracao)
scraper = CanvasScraper(token="11552~abc...")
scraper.run()

# 2. Token do arquivo JSON (gerado previamente)
scraper = CanvasScraper(token_file="/caminho/canvas_token.json")
scraper.run()

# 3. Auto-geracao (precisa de Playwright instalado)
scraper = CanvasScraper(email="email@espm.br", password="senha")
scraper.run()

# 4. Via env vars (quando nem email/password sao passados)
# CANVAS_EMAIL e CANVAS_PASSWORD devem estar definidos
scraper = CanvasScraper()
scraper.run()
```

**Logica de resolucao do token** (em `__init__`):
1. Se `token` foi passado → usa direto
2. Se nao → chama `_load_or_generate_token()`:
   a. Tenta ler `canvas_token.json`
   b. Se existe e `expires_at > now` → usa
   c. Se expirou ou nao existe → gera novo via `generate_canvas_token.py`
   d. Para gerar, precisa de email/password (parametro ou env var)

**Metodos publicos**:
- `run()` — executa scraping completo, retorna dict com resultado
- `api_get(endpoint, params)` — GET paginado na API Canvas (pode ser util para integracao)

**API do Canvas utilizada**:
| Endpoint | Descricao |
|----------|-----------|
| `GET /api/v1/users/self/profile` | Dados do aluno |
| `GET /api/v1/courses?include[]=term&per_page=100` | Lista cursos com semestre |
| `GET /api/v1/courses/{id}/modules` | Modulos de um curso |
| `GET /api/v1/courses/{id}/modules/{mod_id}/items` | Itens de um modulo |
| `GET {file_url}` | Metadados do arquivo (contem URL real de download) |

**Paginacao**: A API do Canvas retorna header `Link` com `rel="next"`. O metodo `api_get` segue automaticamente todas as paginas.

**Filtros aplicados nos arquivos**:
- Extensoes aceitas: `.pdf`, `.pptx`
- Nomes ignorados (case-insensitive): contrato, pea, combinados, programa, codigo/codigo, calendario/calendario, grade
- Arquivos ja existentes no disco sao pulados (idempotente)

**Downloads paralelos**: Usa `ThreadPoolExecutor` com 4 workers. Dentro de cada modulo, acumula lista de pendentes e baixa em batch.

**Estrutura de saida**:
```
canvas_export/
  Argumentacao Oral e Escrita/
    Aula 01 - Argumentacao Oral e Escrita.pdf
    Aula 02 - ...pdf
  Business Lab 1/
    Semana 01 - Aula 01.pdf
    ...
  resumo_export.json
```

**resumo_export.json**:
```json
{
  "aluno": "LEONARDO DI GIGLIO MILLAN",
  "total_cursos": 7,
  "cursos": [
    {
      "id": 49137,
      "disciplina": "Branding Profissional e Reputacao",
      "codigo": "GADMSSPA-AD1N-2837",
      "turma": "AD1N",
      "semestre": "2026/1",
      "arquivos": ["Encontro 1 e 2_ADM.pdf", "..."]
    }
  ]
}
```

---

## 3. Dependencias

```
playwright          # automacao de browser (login SSO + geracao token)
requests            # chamadas API REST do Canvas
```

**Instalacao**:
```bash
pip3 install playwright requests
python3 -m playwright install chromium
```

NOTA: Playwright so e necessario para **geracao de token**. Se o token for fornecido diretamente via `CanvasScraper(token="...")`, Playwright nao e importado nem necessario.

---

## 4. Variaveis de Ambiente

| Variavel | Obrigatorio | Default | Descricao |
|----------|-------------|---------|-----------|
| `CANVAS_EMAIL` | Sim* | — | Email @espm.br para login SSO |
| `CANVAS_PASSWORD` | Sim* | — | Senha Microsoft |
| `CANVAS_BASE_URL` | Nao | `https://canvas.espm.br` | URL da instancia Canvas |
| `TOKEN_PURPOSE` | Nao | `scrapper-auto` | Nome/objetivo do token |
| `TOKEN_OUTPUT_FILE` | Nao | `canvas_token.json` | Arquivo de saida do token |
| `HEADLESS` | Nao | `true` | `false` para ver o browser |

*Obrigatorio apenas se nao houver `canvas_token.json` valido e nao for passado `token` diretamente.

---

## 5. Performance Medida

| Operacao | Tempo |
|----------|-------|
| Login SSO + gerar token (headless) | ~19s |
| Scraping completo (7 cursos, 43 arquivos, todos em cache) | ~33s |
| Scraping completo (com downloads novos) | depende da rede |

O gargalo principal e a rede (SSO Microsoft + API Canvas). Os sleeps minimos no codigo sao:
- 0.4s no campo de senha (animacao Microsoft — NAO REMOVER)
- 0.15s entre cliques de mes no calendario (estabilidade do DOM)

---

## 6. Bugs Conhecidos e Armadilhas

### Campo de senha do Microsoft SSO
O campo `#i0118` tem uma animacao de entrada. Se preencher imediatamente apos ficar visivel, o valor e perdido. Solucao: `wait_for(visible)` + `sleep(0.4)` + `click()` + `fill()`.

### Botao #idSIButton9 reutilizado
A Microsoft usa o MESMO ID para 3 botoes diferentes em sequencia: Next (email), Sign In (senha), Yes (stay signed in). O codigo lida com isso usando try/except e timeouts.

### Texto dos dias no calendario Canvas
Os botoes de dia nao contem apenas o numero. O `inner_text()` retorna formato `"9 julho 2026\n09"`. A comparacao usa `startswith(f"{day} ")` para evitar falso match.

### Token so aparece completo uma vez
Apos criar o token, o Canvas mostra o valor completo no modal com `data-testid="visible_token"`. Se navegar para detalhes depois, mostra truncado. O codigo extrai do modal imediatamente.

### Tokens acumulam
Cada execucao que gera token cria um NOVO token no Canvas sem revogar anteriores. Para o futuro, considerar usar a API `DELETE /api/v1/users/self/tokens/{id}` para limpar tokens antigos.

### Modal NEXUS
Apos login, o Canvas pode exibir um modal promocional (NEXUS). O codigo tenta fechar via `button[aria-label='Close']` com timeout de 3s. Se nao aparecer, segue normalmente.

---

## 7. Integracao com outro projeto

### Exemplo minimo (com token existente)
```python
from canvas_access import CanvasScraper

scraper = CanvasScraper(
    token="11552~abc...",
    export_dir="/caminho/do/projeto/materiais",
)
resultado = scraper.run()
# resultado["cursos"] contem lista de cursos com arquivos
```

### Exemplo completo (auto-geracao de token)
```python
from canvas_access import CanvasScraper

scraper = CanvasScraper(
    email="aluno@acad.espm.br",
    password="senha",
    export_dir="/caminho/exports",
    token_file="/caminho/token.json",
)
resultado = scraper.run()
```

### Usando apenas a API (sem download)
```python
from canvas_access import CanvasScraper

scraper = CanvasScraper(token="11552~abc...")
cursos = scraper.api_get("courses", params={"include[]": "term"})
user = scraper.api_get("users/self/profile")
```

### Gerando apenas o token
```python
import asyncio
from generate_canvas_token import generate_token

data = asyncio.run(generate_token(
    email="aluno@acad.espm.br",
    password="senha",
    headless=True,
))
print(data["token"])
```

---

## 8. O que NAO alterar sem testar

1. **O sleep de 0.4s no campo de senha** (`canvas_login.py:44`) — sem ele o login falha
2. **O `startswith` na selecao de dia** (`generate_canvas_token.py:77`) — o inner_text nao e so o numero
3. **O seletor `[data-testid="visible_token"]`** (`generate_canvas_token.py:93`) — unica forma confiavel de pegar o token completo
4. **A ordem click > fill no campo de senha** (`canvas_login.py:45-46`) — precisa focar antes de preencher
5. **O `target_path="/profile/settings"` no login** — ir direto para settings evita navegacao extra e o SSO redireciona de volta

---

## 9. Estrutura final de arquivos

```
canvas-api-test/
  canvas_login.py              # 104 linhas — login SSO
  generate_canvas_token.py     # 148 linhas — geracao de token
  canvas_access.py             # 282 linhas — classe CanvasScraper

  # Gerados em runtime (nao versionados):
  canvas_token.json            # token de API
  canvas_export/               # materiais baixados
    {Disciplina}/
      arquivo.pdf
    resumo_export.json
```
