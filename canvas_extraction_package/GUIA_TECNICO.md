# Guia Técnico Completo: Extração de Materiais do Canvas ESPM

> **Objetivo deste documento:** Ensinar a uma IA (ou desenvolvedor) exatamente como autenticar, navegar e extrair cursos + materiais (PDFs) do Canvas LMS da ESPM (canvas.espm.br) usando Playwright em Python.

---

## Índice

1. [Visão Geral da Arquitetura](#1-visão-geral-da-arquitetura)
2. [Stack Tecnológica](#2-stack-tecnológica)
3. [Fluxo de Autenticação SSO (Microsoft B2C)](#3-fluxo-de-autenticação-sso-microsoft-b2c)
4. [Extração de Cursos](#4-extração-de-cursos)
5. [Extração de Materiais por Curso](#5-extração-de-materiais-por-curso)
6. [Lógica de Download de Arquivos](#6-lógica-de-download-de-arquivos)
7. [Seletores CSS e Padrões de DOM](#7-seletores-css-e-padrões-de-dom)
8. [Tratamento de Erros e Resiliência](#8-tratamento-de-erros-e-resiliência)
9. [Resultado de Teste Real](#9-resultado-de-teste-real)
10. [Referência de Código](#10-referência-de-código)

---

## 1. Visão Geral da Arquitetura

```
┌──────────────────────────────────────────────────────────────┐
│  Entrada: email + senha do aluno ESPM                        │
│                                                              │
│  1. Abrir browser headless (Playwright/Chromium)             │
│  2. Navegar para canvas.espm.br                              │
│  3. SSO redireciona para Microsoft B2C login                 │
│  4. Preencher credenciais no formulário B2C                  │
│  5. Lidar com "Stay signed in?" e modais NEXUS               │
│  6. Agora autenticado no Canvas — scrape cursos              │
│  7. Para cada curso → acessar /modules → baixar "Aula X"    │
│                                                              │
│  Saída: lista de cursos + lista de PDFs baixados por curso   │
└──────────────────────────────────────────────────────────────┘
```

O Canvas ESPM **não tem** login próprio. Ele usa o **Portal ESPM** como Identity Provider, que por sua vez usa **Microsoft Entra ID (B2C)** para autenticação. Isso significa que ao acessar `canvas.espm.br`, o usuário é redirecionado para uma página intermediária ESPM e depois para `login.microsoftonline.com`.

---

## 2. Stack Tecnológica

### Dependências obrigatórias

```
playwright>=1.49.0       # Automação de browser (Chromium)
python-dotenv>=1.0.0     # Carregar .env
```

### Instalação

```bash
pip install playwright python-dotenv
playwright install chromium
```

### Por que Playwright e não requests/Selenium?

- **Portal e Canvas são SPAs** (React/Angular) — requests puro não renderiza o JS necessário
- **SSO da Microsoft** tem redirects complexos e proteções anti-bot
- **Playwright** é mais rápido e confiável que Selenium para SPAs
- Suporte nativo a `expect_download()` para downloads de arquivo

---

## 3. Fluxo de Autenticação SSO (Microsoft B2C)

Este é o passo mais crítico e frágil do processo. Aqui está a sequência exata:

### 3.1. Configuração do Browser

```python
browser = await playwright.chromium.launch(
    headless=True,
    args=[
        "--no-sandbox",
        "--disable-dev-shm-usage",
        "--disable-blink-features=AutomationControlled",  # anti-detecção
        "--disable-infobars",
    ],
)
context = await browser.new_context(
    user_agent=(
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) "
        "AppleWebKit/537.36 (KHTML, like Gecko) "
        "Chrome/131.0.0.0 Safari/537.36"
    ),
    viewport={"width": 1280, "height": 720},
    extra_http_headers={
        "Accept-Language": "pt-BR,pt;q=0.9,en-US;q=0.8",
        "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
    },
)
page = await context.new_page()
```

**Detalhe crítico**: O `--disable-blink-features=AutomationControlled` é essencial para que o Microsoft B2C não detecte o browser como bot.

### 3.2. Passo a Passo do Login

```
ETAPA 1: page.goto("https://canvas.espm.br", wait_until="networkidle")
         → O Canvas redireciona automaticamente para a tela de login ESPM

ETAPA 2: Procurar e clicar no botão "Conectar com sua conta ESPM"
         → Este botão está na página intermediária ESPM
         → Seletor: iterar sobre <button> e procurar texto contendo "Conectar"
         → NÃO usar wait_for_navigation após o clique — a página navega para
           login.microsoftonline.com e precisamos deixar acontecer

ETAPA 3: Aguardar formulário Microsoft B2C
         → page.wait_for_selector("#i0116", state="visible", timeout=20000)
         → "#i0116" é o campo de email da Microsoft
         → ATENÇÃO: pode estar em um iframe! Se não encontrar no documento
           principal, itere sobre page.frames

ETAPA 4: Preencher email
         → page.fill("#i0116", email_do_aluno)
         → Clicar em "Avançar": page.click("#idSIButton9")
         → Aguardar 2 segundos

ETAPA 5: Preencher senha
         → page.fill("#i0118", senha_do_aluno)
         → Clicar em "Entrar": page.click("#idSIButton9")
         → Aguardar page.wait_for_load_state("domcontentloaded", timeout=30000)
         → MAIS 5 segundos de wait_for_timeout (redirects são lentos)

ETAPA 6: Lidar com "Continuar conectado?" / "Stay signed in?"
         → O botão "#idSIButton9" aparece NOVAMENTE para "Sim"
         → Verificar se existe e clicar
         → Aguardar mais 3+3 segundos para redirects

ETAPA 7: Fechar modal NEXUS (popup de avisos do Portal)
         → Executar JavaScript para remover ".MuiDialog-container" do DOM
         → Isso é necessário porque o Portal pode mostrar um popup que
           bloqueia toda a interface

ETAPA 8: Verificar se chegou ao Canvas
         → Checar se a URL contém "canvas.espm.br" e NÃO contém "login"
         → Se ainda não está no Canvas, navegar diretamente:
           page.goto("https://canvas.espm.br", wait_until="domcontentloaded")
```

### 3.3. Código Completo de Login

```python
async def login_via_sso(page, email: str, password: str) -> bool:
    """
    Autentica no Canvas ESPM via SSO Microsoft B2C.
    Retorna True se login bem-sucedido.
    """
    # Navegar para o Canvas (redireciona para login ESPM)
    await page.goto("https://canvas.espm.br", wait_until="networkidle", timeout=30000)

    # Verificar se já está autenticado
    if "canvas.espm.br" in page.url.lower() and "login" not in page.url.lower():
        return True  # Sessão ainda válida

    # Clicar no botão "Conectar com sua conta ESPM"
    try:
        buttons = await page.query_selector_all("button")
        for btn in buttons:
            text = await btn.text_content()
            if "Conectar" in (text or "").strip():
                await btn.click()
                break
    except Exception:
        pass  # Se não encontrar, assume que já está na tela B2C

    # Aguardar campo de email Microsoft B2C
    await page.wait_for_selector("#i0116", state="visible", timeout=20000)

    # Preencher email
    await page.fill("#i0116", email)
    submit_btn = await page.query_selector("#idSIButton9")
    if submit_btn:
        await submit_btn.click()
        await page.wait_for_timeout(2000)

    # Preencher senha
    await page.fill("#i0118", password)
    sign_in_btn = await page.query_selector("#idSIButton9")
    if sign_in_btn:
        await sign_in_btn.click()

    # Aguardar redirecionamento
    try:
        await page.wait_for_load_state("domcontentloaded", timeout=30000)
    except Exception:
        pass
    await page.wait_for_timeout(5000)

    # Lidar com "Stay signed in?"
    try:
        stay_btn = await page.query_selector("#idSIButton9")
        if stay_btn:
            await stay_btn.click()
            await page.wait_for_timeout(3000)
            try:
                await page.wait_for_load_state("domcontentloaded", timeout=15000)
            except Exception:
                pass
            await page.wait_for_timeout(3000)
    except Exception:
        pass

    # Fechar modal NEXUS do Portal (se aparecer durante o redirect)
    try:
        await page.evaluate("""
            () => {
                const backdrop = document.querySelector('.MuiDialog-container');
                if (backdrop) backdrop.click();
                document.querySelectorAll('.MuiDialog-root').forEach(el => el.remove());
            }
        """)
        await page.wait_for_timeout(2000)
    except Exception:
        pass

    # Se não estiver no Canvas, navegar explicitamente
    if "canvas.espm.br" not in page.url.lower() or "login" in page.url.lower():
        await page.goto(
            "https://canvas.espm.br",
            wait_until="domcontentloaded",
            timeout=30000,
        )
        await page.wait_for_timeout(5000)

    # Verificação final
    url = page.url.lower()
    return "canvas.espm.br" in url and "login" not in url
```

---

## 4. Extração de Cursos

Após autenticado, o Canvas mostra um dashboard. Para obter todos os cursos:

### 4.1. Navegar para a Lista de Cursos

```python
await page.goto("https://canvas.espm.br/courses", wait_until="networkidle", timeout=15000)
```

### 4.2. Extrair Dados via JavaScript

O Canvas renderiza cursos de várias formas (tabela, dashboard cards, etc). O JavaScript abaixo cobre todos os formatos conhecidos:

```javascript
() => {
    const courses = [];
    const rows = document.querySelectorAll(
        'tr.course-list-table-row, .course-list-course-title-column a, ' +
        '.ic-DashboardCard, [data-course-id]'
    );
    rows.forEach(row => {
        const nameEl = row.querySelector(
            '.course-list-course-title-column a, .ic-DashboardCard__header_title, ' +
            'a[href*="/courses/"], h3, span.name'
        ) || row;
        const name = nameEl?.textContent?.trim();
        const href = (nameEl?.getAttribute('href') || row.getAttribute('href') || '');
        const match = href.match(/\/courses\/(\d+)/);
        const courseId = match ? parseInt(match[1]) : null;

        if (name && courseId) {
            courses.push({
                canvas_course_id: courseId,
                name: name,
            });
        }
    });
    return courses;
}
```

### 4.3. Deduplicação

Os seletores CSS acima podem capturar o mesmo curso mais de uma vez (um card pode ter vários links). **Sempre deduplicar por `canvas_course_id`**:

```python
seen_ids = set()
unique_courses = []
for course in courses:
    if course["canvas_course_id"] not in seen_ids:
        seen_ids.add(course["canvas_course_id"])
        unique_courses.append(course)
```

### Resultado Esperado (exemplo real)

| ID    | Nome                                                |
|-------|-----------------------------------------------------|
| 48852 | AD1N - Argumentação Oral e Escrita                  |
| 49119 | AD1N - Autenticidade e Inteligência Emocional       |
| 49137 | AD1N - Branding Profissional e Reputação            |
| 49075 | AD1N - Business Lab 1                               |
| 48517 | AD1N - Empreendedorismo                             |
| 48547 | AD1N - Gestão da Inovação e Novos Modelos de Negócios |
| 49165 | AD1N - Marketing em Administração                   |

---

## 5. Extração de Materiais por Curso

Para cada curso, acessamos a página de **Módulos** e buscamos links cujo texto contenha "Aula" seguido de um número.

### 5.1. Acessar Página de Módulos

```python
await page.goto(
    f"https://canvas.espm.br/courses/{course_id}/modules",
    wait_until="domcontentloaded",
    timeout=30000,
)
await page.wait_for_timeout(3000)  # Esperar módulos renderizarem
```

### 5.2. Encontrar Links de Aulas via JavaScript

```javascript
() => {
    const results = [];
    const links = document.querySelectorAll(
        '.context_module_item .item_name a, .ig-title a, a.ig-title'
    );
    const pattern = /Aula\s*\d+/i;
    links.forEach(a => {
        const text = a.textContent?.trim();
        if (text && pattern.test(text)) {
            results.push({
                text: text,
                href: a.getAttribute('href') || '',
            });
        }
    });
    return results;
}
```

**Regex**: `/Aula\s*\d+/i` — encontra "Aula 01", "AULA 3", "Aula01", etc.

**Nota**: Nem todo curso usa a nomenclatura "Aula X". Alguns usam "Semana X - Aula X" (que também é capturado pela regex). Cursos que usam nomenclatura completamente diferente (como "Módulo 1") **não serão capturados** com essa regex — adaptações podem ser necessárias.

### 5.3. Navegar e Baixar Cada Material

Para cada link encontrado:

```python
for link_info in aula_links:
    href = link_info["href"]
    full_url = href if href.startswith("http") else f"https://canvas.espm.br{href}"

    # 1. Navegar para a página do documento
    await page.goto(full_url, wait_until="domcontentloaded", timeout=20000)
    await page.wait_for_timeout(2000)

    # 2. Encontrar o link de download na página
    download_link = await page.query_selector(
        'a[download], a[href*="/download"], a:has-text("Download"), '
        'a:has-text("download"), a.file-download'
    )

    # 3. Usar Playwright expect_download() para capturar o arquivo
    if download_link:
        async with page.expect_download(timeout=30000) as download_info:
            await download_link.click()
        download = await download_info.value
        await download.save_as(f"./downloads/{download.suggested_filename}")
```

---

## 6. Lógica de Download de Arquivos

### Por que não usar requests para baixar?

O Canvas protege seus downloads com tokens de sessão. O Playwright mantém a sessão autenticada no browser, então precisa **usar o browser para baixar**:

```python
# ✅ CORRETO: usar Playwright expect_download
async with page.expect_download(timeout=30000) as download_info:
    await download_link.click()
download = await download_info.value
suggested = download.suggested_filename or "arquivo.pdf"
await download.save_as(f"./downloads/{course_id}/{suggested}")

# ❌ ERRADO: não tente usar requests
# requests.get(url) → vai dar 401 ou sessão inválida
```

### Metadados do Arquivo

```python
import re

# Extrair file_id da URL (quando disponível)
fid_match = re.search(r"/files/(\d+)", download_url)
file_id = int(fid_match.group(1)) if fid_match else hash(nome) % 10**9

# Tipo de arquivo pela extensão
ext = pathlib.Path(suggested).suffix.lstrip(".").lower()
# Resulta em: "pdf", "pptx", "docx", etc.
```

---

## 7. Seletores CSS e Padrões de DOM

### Seletores do Microsoft B2C Login

| Elemento | Seletor | Descrição |
|----------|---------|-----------|
| Campo Email | `#i0116` | Input de email do B2C |
| Campo Senha | `#i0118` | Input de senha do B2C |
| Botão Avançar/Entrar | `#idSIButton9` | Botão "Next" / "Sign in" / "Stay signed in" |
| Botão "Stay signed in" | `#idSIButton9` ou `#Accept` | Mesmo ID, contexto diferente |

### Seletores do Canvas ESPM

| Elemento | Seletor | Descrição |
|----------|---------|-----------|
| Linhas de curso | `tr.course-list-table-row` | Tabela de cursos |
| Cards de curso | `.ic-DashboardCard` | Dashboard cards |
| Título do curso | `.course-list-course-title-column a` | Link com nome do curso |
| Link de módulo | `.context_module_item .item_name a` | Item de módulo |
| Título alternativo | `.ig-title a` ou `a.ig-title` | Título do item |
| Link de download | `a[download]` | Link com atributo download |
| Download alternativo | `a[href*="/download"]` | Link com /download na URL |
| Download texto | `a:has-text("Download")` | Link com texto "Download" |

### Seletores do Portal ESPM (para fechar modais)

| Elemento | Seletor | Descrição |
|----------|---------|-----------|
| Modal NEXUS | `.MuiDialog-container` | Container do modal MUI |
| Backdrop modal | `.MuiBackdrop-root` | Fundo escuro do modal |
| Dialog root | `.MuiDialog-root` | Raiz do dialog MUI |

---

## 8. Tratamento de Erros e Resiliência

### Timeouts Generosos

O SSO da Microsoft é **lento**. Use timeouts generosos:

```python
# Login — usar timeouts longos
await page.goto(url, timeout=30000)          # 30s para navegação
await page.wait_for_selector(sel, timeout=20000)  # 20s para elementos
await page.wait_for_timeout(5000)            # 5s para redirects lentos

# Download — pode ser arquivo grande
async with page.expect_download(timeout=30000) as dl:
    await download_link.click()
```

### Try/Catch em Cada Etapa

```python
# Cada download individual não deve matar o processo inteiro
for link_info in aula_links:
    try:
        # ... navegar e baixar ...
    except Exception as e:
        logger.warning(f"Falha ao baixar '{link_info['text']}': {e}")
        continue  # Próximo material
```

### Retry com Backoff

```python
for attempt in range(1, max_retries + 1):
    try:
        # ... login + scrape ...
        break
    except Exception:
        if attempt == max_retries:
            raise
        await asyncio.sleep(3)  # Esperar antes de tentar de novo
        # Reinicializar browser para estado limpo
```

### Anti-Bot

```python
# Args obrigatórias no launch:
"--disable-blink-features=AutomationControlled"  # Esconder automation flag
"--no-sandbox"                                    # Compatibilidade
"--disable-dev-shm-usage"                         # Evitar crash em containers
"--disable-infobars"                              # Remover barra "Chrome is being controlled"

# User-Agent realista obrigatório:
user_agent="Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) ..."

# Headers de idioma:
extra_http_headers={"Accept-Language": "pt-BR,pt;q=0.9,en-US;q=0.8"}
```

---

## 9. Resultado de Teste Real

Teste realizado em 2026-03-05 com o perfil `murilo.rubens@acad.espm.br`:

| Disciplina | Materiais | Exemplos |
|---|---|---|
| Argumentação Oral e Escrita | **4 PDFs** | Aula 01..04 - Caline Migliato.pdf |
| Autenticidade e Inteligência Emocional | **10 PDFs** | Aula 01..05 + artigos + dinâmicas |
| Branding Profissional e Reputação | **0** | Sem links "Aula X" nos módulos |
| Business Lab 1 | **3 PDFs** | Semana 01..03 - Aula 01..03.pdf |
| Empreendedorismo | **3 PDFs** | Aula 1..3 (Nubank, Netflix cases) |
| Gestão da Inovação e NMN | **4 PDFs** | AULA 1..4 - ICNMN.pdf |
| Marketing em Administração | **0** | Sem links "Aula X" nos módulos |

**Total: 7 disciplinas, 24 PDFs, ~5 minutos de execução.**

---

## 10. Referência de Código

O pacote contém os seguintes arquivos:

| Arquivo | Função |
|---------|--------|
| `canvas_scraper.py` | Scraper completo e auto-contido (~350 linhas) |
| `run_extraction.py` | Script de execução — basta rodar |
| `requirements.txt` | Dependências mínimas |
| `.env.example` | Template de configuração |
| `GUIA_TECNICO.md` | Este documento |

### Estrutura de Dados de Saída

```python
# Curso
{
    "canvas_course_id": 48852,       # ID numérico do Canvas
    "name": "AD1N - Argumentação Oral e Escrita",
}

# Material
{
    "canvas_file_id": 6307367,       # ID numérico do arquivo no Canvas
    "file_name": "Aula 01 - Argumentação Oral e Escrita.pdf",
    "file_url": "./downloads/48852/Aula 01....pdf",  # Path local
    "file_type": "pdf",              # Extensão do arquivo
    "course_id": 48852,              # A qual curso pertence
}
```

### URLs Importantes

| URL | Finalidade |
|-----|-----------|
| `https://canvas.espm.br` | Página principal (redireciona para SSO) |
| `https://canvas.espm.br/courses` | Lista de todos os cursos |
| `https://canvas.espm.br/courses/{ID}/modules` | Módulos de um curso específico |
| `https://canvas.espm.br/profile/settings` | Configurações (para gerar API token) |

---

## Cuidados Finais para a IA

1. **Nunca hardcode senhas** — sempre ler de variáveis de ambiente ou `.env`
2. **Tempos de espera são essenciais** — o SSO é lento, não pule os `wait_for_timeout`
3. **O botão `#idSIButton9` aparece 3 vezes** — Avançar, Entrar, Stay Signed In
4. **Downloads devem usar `expect_download()`** — não tente baixar via HTTP direto
5. **Deduplicar cursos** — os seletores CSS podem capturar duplicatas
6. **Regex `/Aula\s*\d+/i`** — é o padrão usado pela maioria dos professores ESPM
7. **Cursos sem materiais são normais** — alguns professores não usam a nomenclatura "Aula X"
8. **Fechar modal NEXUS via JavaScript** — ele bloqueia a interface se não for removido
9. **headless=True funciona perfeitamente** — testado e confirmado
10. **Retry é importante** — o B2C da Microsoft às vezes falha por timeout
