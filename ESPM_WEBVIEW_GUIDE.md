# Guia Completo: WebView ESPM Connect para iOS

> **Para:** Dev frontend iOS + Claude Code
> **De:** Backend Coffee
> **Última atualização:** 14/03/2026
> **Status backend:** PRONTO — 100% implementado e testado em produção

---

## 1. O QUE É ISSO

O app Coffee precisa conectar a conta ESPM do aluno para acessar disciplinas e materiais do Canvas. Isso é feito gerando um **Canvas API token** — uma chave que dura 120 dias e permite acessar a API REST do Canvas.

**O problema:** Canvas não tem OAuth público. A única forma de gerar o token é pela UI do Canvas (`/profile/settings`), que exige login via Microsoft SSO.

**A solução:** Abrir um WKWebView dentro do app → aluno faz login normalmente → JavaScript automatiza a geração do token → app extrai e envia pro backend.

**O aluno NÃO vê nenhum token.** Pra ele, é só fazer login.

---

## 2. FLUXO DO ALUNO (UX)

```
Passo 1: Toca "Conectar ESPM"
Passo 2: WebView aparece com tela de login Microsoft
         (igual a quando acessa o portal no computador)
Passo 3: Digita email @acad.espm.br + senha
Passo 4: Tela de login some, aparece spinner:
         "Configurando sua conta..."  (3-5 segundos)
Passo 5: Sucesso → "Conectado! 7 disciplinas encontradas"
         WebView fecha automaticamente
```

---

## 3. FLUXO TÉCNICO DETALHADO

```
┌─────────────────────────────────────────────────────────┐
│                    iOS App (SwiftUI)                     │
│                                                          │
│  ESPMConnectView                                        │
│    ├── WKWebView carrega canvas.espm.br/profile/settings│
│    │     ↓ Canvas redireciona pro Microsoft SSO         │
│    │     ↓ Aluno digita email + senha                   │
│    │     ↓ Microsoft autentica (IP residencial = sem MFA)│
│    │     ↓ Redireciona de volta pro Canvas              │
│    │                                                     │
│    ├── WKNavigationDelegate detecta URL = canvas.espm.br│
│    │     ↓ Injeta JavaScript de geração de token         │
│    │     ↓ JS clica botões, preenche campos, extrai token│
│    │     ↓ JS chama: window.webkit.messageHandlers       │
│    │       .coffeeToken.postMessage({token: "11552~..."})│
│    │                                                     │
│    ├── Swift recebe o token via WKScriptMessageHandler   │
│    │     ↓ Mostra overlay "Configurando..."              │
│    │     ↓ POST /api/v1/espm/connect                     │
│    │       { matricula: "x@acad.espm.br",                │
│    │         canvas_token: "11552~AL9k..." }             │
│    │                                                     │
│    └── Backend responde com disciplinas                  │
│          ↓ Mostra sucesso + lista de disciplinas         │
│          ↓ Fecha WebView                                 │
└─────────────────────────────────────────────────────────┘
```

---

## 4. API DO BACKEND (já implementada, testada em produção)

### Base URL
```
https://coffee-oficial-production.up.railway.app/api/v1
```

### Headers obrigatórios
```
Authorization: Bearer <jwt_token>
Content-Type: application/json
```

### POST /espm/connect

**Request:**
```json
{
    "matricula": "leonardo.millan@acad.espm.br",
    "canvas_token": "11552~AL9kKCLCC66Whze4HvhrGUWtf4BQ2v2vE8x3mNtuRarxC2xFFC976Kcc3z4PTzRP"
}
```

**Response 200 (sucesso):**
```json
{
    "data": {
        "status": "connected",
        "disciplinas_found": 7,
        "disciplinas": [
            {
                "id": "7934c473-5b56-4779-bd02-936ea1ce4671",
                "nome": "Argumentação Oral e Escrita",
                "turma": "AD1N",
                "semestre": "2026/1"
            },
            {
                "id": "755474e5-3d36-4c21-839f-1fb0e18f0f12",
                "nome": "Autenticidade e Inteligência Emocional",
                "turma": "AD1N",
                "semestre": "2026/1"
            }
        ]
    },
    "error": null,
    "message": "ok"
}
```

**Response 401 (token inválido/expirado):**
```json
{
    "data": null,
    "error": "ESPM_AUTH_FAILED",
    "message": "Token Canvas inválido ou expirado."
}
```

**Response 503 (servidor indisponível):**
```json
{
    "data": null,
    "error": "ESPM_UNAVAILABLE",
    "message": "Erro ao validar token Canvas."
}
```

### GET /espm/status

**Response 200:**
```json
{
    "data": {
        "connected": true,
        "matricula": "leonardo.millan@acad.espm.br",
        "disciplinas_count": 7,
        "token_expires_at": "2026-07-12T04:56:26.147052+00:00"
    },
    "error": null,
    "message": "ok"
}
```

**Response 200 (não conectado):**
```json
{
    "data": {
        "connected": false,
        "matricula": null,
        "disciplinas_count": 0,
        "token_expires_at": null
    },
    "error": null,
    "message": "ok"
}
```

### POST /espm/disconnect

**Response 200:**
```json
{
    "data": null,
    "error": null,
    "message": "ESPM desconectado"
}
```

### POST /espm/sync

Mesma response que `/connect`. Usa o token salvo no backend pra re-sincronizar disciplinas sem precisar de novo login.

---

## 5. COMPONENTES iOS A IMPLEMENTAR

### 5.1 `CanvasWebViewController` (peça central)

**Tipo:** `UIViewControllerRepresentable` (para usar WKWebView em SwiftUI)

**Responsabilidades:**
- Criar e configurar WKWebView
- Registrar `WKScriptMessageHandler` para receber token do JS
- Implementar `WKNavigationDelegate` para detectar quando login completou
- Injetar JavaScript de geração de token após login
- Reportar token, email, e erros via callbacks pro SwiftUI

**Configuração do WKWebView:**
```swift
let config = WKWebViewConfiguration()
let controller = WKUserContentController()

// Registra handler para receber mensagens do JavaScript
controller.add(self, name: "coffeeToken")
config.userContentController = controller

// Preferências
config.preferences.javaScriptCanOpenWindowsAutomatically = false

let webView = WKWebView(frame: .zero, configuration: config)
webView.navigationDelegate = self
webView.customUserAgent = nil  // usa o user-agent nativo do iOS (importante: NÃO mudar)

// Carrega Canvas
webView.load(URLRequest(url: URL(string: "https://canvas.espm.br/profile/settings")!))
```

**Detecção de login completado:**
```swift
// WKNavigationDelegate
func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
    guard let url = webView.url?.absoluteString else { return }

    // Ignora páginas Microsoft (login em andamento)
    if url.contains("microsoftonline.com") || url.contains("microsoft.com") { return }

    // Login completou → Canvas carregou
    if url.contains("canvas.espm.br") && !url.contains("/login") {

        // Extrair email do aluno da página (se possível)
        extractStudentEmail(from: webView)

        // Espera 2 segundos (Canvas carregando componentes React)
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
            self?.injectTokenGenerator(into: webView)
        }
    }
}
```

**Recebendo o token do JavaScript:**
```swift
// WKScriptMessageHandler
func userContentController(
    _ userContentController: WKUserContentController,
    didReceive message: WKScriptMessage
) {
    guard message.name == "coffeeToken",
          let body = message.body as? [String: Any] else { return }

    let success = body["success"] as? Bool ?? false

    if success, let token = body["token"] as? String {
        // TOKEN EXTRAÍDO COM SUCESSO
        onTokenGenerated?(token)
    } else {
        let error = body["error"] as? String ?? "Erro desconhecido"
        onError?(error)
    }
}
```

### 5.2 `ESPMConnectViewModel`

```swift
enum ESPMConnectState {
    case webLogin       // WebView visível, aluno fazendo login
    case generating     // Overlay "Configurando...", JS rodando
    case sending        // Enviando pro backend
    case success        // Conectado, mostra disciplinas
    case error(String)  // Erro, mostra mensagem + botão retry
}

@MainActor
class ESPMConnectViewModel: ObservableObject {
    @Published var state: ESPMConnectState = .webLogin
    @Published var matricula: String = ""
    @Published var disciplinas: [Disciplina] = []

    func onLoginDetected(email: String) {
        matricula = email
        state = .generating
    }

    func onTokenGenerated(_ token: String) {
        state = .sending
        Task {
            do {
                let response = try await ESPMService.shared.connect(
                    matricula: matricula,
                    canvasToken: token
                )
                disciplinas = response.disciplinas
                state = .success
            } catch {
                state = .error("Não foi possível conectar. Tente novamente.")
            }
        }
    }

    func onTokenError(_ error: String) {
        state = .error("Erro ao gerar token: \(error)")
    }

    func retry() {
        state = .webLogin
        // WebView recarrega canvas.espm.br
    }
}
```

### 5.3 `ESPMConnectView`

```swift
struct ESPMConnectView: View {
    @StateObject private var viewModel = ESPMConnectViewModel()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                // Camada 1: WebView (sempre presente, mas fica atrás do overlay)
                CanvasWebViewController(
                    onTokenGenerated: viewModel.onTokenGenerated,
                    onLoginDetected: viewModel.onLoginDetected,
                    onError: viewModel.onTokenError
                )
                .opacity(viewModel.state == .webLogin ? 1 : 0)

                // Camada 2: Overlays conforme estado
                switch viewModel.state {
                case .generating, .sending:
                    GeneratingOverlay()
                case .success:
                    SuccessOverlay(
                        disciplinas: viewModel.disciplinas,
                        onContinue: { dismiss() }
                    )
                case .error(let msg):
                    ErrorOverlay(
                        message: msg,
                        onRetry: { viewModel.retry() }
                    )
                default:
                    EmptyView()
                }
            }
            .navigationTitle("Conectar ESPM")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
            }
        }
    }
}
```

### 5.4 `ESPMService`

```swift
class ESPMService {
    static let shared = ESPMService()

    func connect(matricula: String, canvasToken: String) async throws -> ESPMConnectResponse {
        let body: [String: Any] = [
            "matricula": matricula,
            "canvas_token": canvasToken
        ]
        return try await NetworkService.shared.post("/espm/connect", body: body)
    }

    func status() async throws -> ESPMStatusResponse {
        return try await NetworkService.shared.get("/espm/status")
    }

    func sync() async throws -> ESPMConnectResponse {
        return try await NetworkService.shared.post("/espm/sync", body: [:])
    }

    func disconnect() async throws {
        let _: EmptyResponse = try await NetworkService.shared.post("/espm/disconnect", body: [:])
    }
}
```

---

## 6. JAVASCRIPT DE INJEÇÃO (copiar exatamente)

Este é o script que gera o token automaticamente após o login. **Cada seletor e timing foi extraído do Playwright que funciona em produção.** Copiar como string literal no Swift.

```javascript
(async function coffeeTokenGenerator() {
    const sleep = ms => new Promise(r => setTimeout(r, ms));

    const report = (success, data) => {
        window.webkit.messageHandlers.coffeeToken.postMessage(
            Object.assign({ success }, data)
        );
    };

    try {
        // ── 0. Fechar modal NEXUS (popup de avisos do Canvas) ──
        const closeBtn = document.querySelector("button[aria-label='Close']");
        if (closeBtn) {
            closeBtn.click();
            await sleep(800);
        }

        // ── 1. Clicar "Novo token de acesso" ──
        let tokenLink = null;
        const allLinks = document.querySelectorAll('a, button');
        for (const el of allLinks) {
            if ((el.textContent || '').includes('Novo token de acesso')) {
                tokenLink = el;
                break;
            }
        }
        if (!tokenLink) {
            throw new Error('LINK_NOT_FOUND: "Novo token de acesso" nao existe na pagina');
        }
        tokenLink.click();
        await sleep(1200);  // modal de criacao abre

        // ── 2. Preencher campo "Objetivo" ──
        const purposeField = document.querySelector("input[name='purpose']");
        if (!purposeField) {
            throw new Error('FIELD_NOT_FOUND: input[name=purpose]');
        }
        // Simula digitacao real (React controlled input)
        const nativeInputValueSetter = Object.getOwnPropertyDescriptor(
            window.HTMLInputElement.prototype, 'value'
        ).set;
        nativeInputValueSetter.call(purposeField, 'coffee-app');
        purposeField.dispatchEvent(new Event('input', { bubbles: true }));
        purposeField.dispatchEvent(new Event('change', { bubbles: true }));
        await sleep(400);

        // ── 3. Abrir calendario de expiracao ──
        const dateInput = document.querySelector("input[id^='Selectable']");
        if (!dateInput) {
            throw new Error('FIELD_NOT_FOUND: date picker (input[id^=Selectable])');
        }
        dateInput.click();
        await sleep(600);

        // ── 4. Avancar 4 meses no calendario ──
        for (let i = 0; i < 4; i++) {
            const nextMonthBtn = Array.from(document.querySelectorAll('button'))
                .find(b => (b.textContent || '').includes('Pr\u00f3ximo m\u00eas'));
            if (nextMonthBtn) {
                nextMonthBtn.click();
                await sleep(300);  // animacao do calendario
            }
        }

        // ── 5. Selecionar dia seguro (hoje - 3, minimo 1) ──
        const safeDay = Math.max(new Date().getDate() - 3, 1);
        const dayButtons = document.querySelectorAll("button[role='option']");
        let dayClicked = false;
        for (const btn of dayButtons) {
            const text = btn.textContent || '';
            // Formato do texto: "9 julho 2026\n09"
            // Matching: startsWith("9 ") — espaco evita match errado (19 != 1)
            if (text.startsWith(safeDay + ' ')) {
                btn.click();
                dayClicked = true;
                break;
            }
        }
        if (!dayClicked) {
            throw new Error('DAY_NOT_FOUND: dia ' + safeDay + ' nao encontrado no calendario');
        }
        await sleep(500);

        // ── 6. Clicar "Gerar token" ──
        const submitBtn = Array.from(
            document.querySelectorAll("button[type='submit']")
        ).find(b => (b.textContent || '').includes('Gerar token'));
        if (!submitBtn) {
            throw new Error('BUTTON_NOT_FOUND: "Gerar token"');
        }
        submitBtn.click();

        // ── 7. Aguardar e extrair o token ──
        // IMPORTANTE: O token aparece APENAS UMA VEZ no modal de criacao.
        // Se navegar pra fora e voltar, ele fica truncado e inutilizavel.
        let token = null;
        for (let attempt = 0; attempt < 15; attempt++) {
            await sleep(500);
            const tokenEl = document.querySelector('[data-testid="visible_token"]');
            if (tokenEl) {
                token = tokenEl.textContent.trim();
                if (token && token.includes('~') && token.length > 20) {
                    break;
                }
                token = null;  // ainda nao apareceu completamente
            }
        }

        if (!token) {
            throw new Error('TOKEN_NOT_FOUND: elemento [data-testid=visible_token] nao apareceu em 7.5s');
        }

        // ── 8. Sucesso! Envia token pro Swift ──
        report(true, { token: token });

    } catch (err) {
        report(false, { error: err.message || String(err) });
    }
})();
```

### Notas sobre o JavaScript:

| Detalhe | Explicacao |
|---------|-----------|
| **`nativeInputValueSetter`** | Canvas usa React. Setar `.value` direto nao dispara o onChange do React. Esse trick usa o setter nativo do HTMLInputElement pra contornar. |
| **`startsWith(safeDay + ' ')`** | O texto do botao do dia e "9 julho 2026\n09". O espaco apos o numero evita match errado (ex: "19 " nao matcha "1 "). |
| **Polling do token (15 x 500ms)** | O token leva ~1-2s pra aparecer apos clicar "Gerar". Loop garante que esperamos o suficiente. |
| **`token.includes('~')`** | Formato do token Canvas: `11552~AL9kKCL...`. O `~` e a validacao minima. |

---

## 7. SELETORES CSS/JS — REFERENCIA COMPLETA

### Pagina Microsoft SSO (aluno interage manualmente)
| Elemento | Seletor | Acao |
|----------|---------|------|
| Campo email | `#i0116` | Aluno preenche |
| Botao Next/SignIn | `#idSIButton9` | Aluno clica |
| Campo senha | `#i0118` | Aluno preenche |
| "Stay signed in?" | `#idSIButton9` | Automatico se necessario |

### Pagina Canvas /profile/settings (automatico via JS)
| Elemento | Seletor | Acao do JS |
|----------|---------|------------|
| Modal NEXUS close | `button[aria-label='Close']` | Click (se existir) |
| Link novo token | Texto: `"Novo token de acesso"` | Click |
| Campo objetivo | `input[name='purpose']` | Fill "coffee-app" |
| Date picker | `input[id^='Selectable']` | Click (abre calendario) |
| Proximo mes | Texto: `"Proximo mes"` | Click x 4 |
| Botao do dia | `button[role='option']` | Click no dia correto |
| Gerar token | `button[type='submit']` com texto `"Gerar token"` | Click |
| Token gerado | `[data-testid="visible_token"]` | Read textContent |

---

## 8. TRATAMENTO DE ERROS

| Erro | Causa | O que mostrar pro aluno |
|------|-------|------------------------|
| `LINK_NOT_FOUND` | Canvas mudou a UI | "Erro ao configurar. Tente novamente." |
| `FIELD_NOT_FOUND` | Canvas mudou a UI | "Erro ao configurar. Tente novamente." |
| `TOKEN_NOT_FOUND` | Modal nao abriu ou token nao apareceu | "Erro ao gerar token. Tente novamente." |
| `DAY_NOT_FOUND` | Calendario nao carregou | "Erro ao configurar. Tente novamente." |
| Backend 401 | Token gerado e invalido (raro) | "Token invalido. Tente novamente." |
| Backend 503 | Servidor fora | "Servidor indisponivel. Tente mais tarde." |
| WebView timeout | Login SSO travou | "Conexao lenta. Verifique sua internet." |

**Em TODOS os casos de erro:** mostrar botao "Tentar novamente" que recarrega o WebView do zero.

---

## 9. RENOVACAO DO TOKEN (a cada 120 dias)

```swift
// No AppDelegate ou na MainView, checar ao abrir o app:
func checkTokenExpiry() async {
    guard let status = try? await ESPMService.shared.status(),
          status.connected,
          let expiresAt = status.tokenExpiresAt else { return }

    let daysLeft = Calendar.current.dateComponents(
        [.day], from: Date(), to: expiresAt
    ).day ?? 999

    if daysLeft <= 14 {
        // Agendar notificacao local
        scheduleRenewalNotification(daysLeft: daysLeft)
    }
}
```

Quando o aluno toca na notificacao → abre `ESPMConnectView`. Se os cookies do Microsoft ainda estiverem validos no WKWebView, o login e automatico (sem digitar senha). Se expiraram, o aluno digita de novo.

---

## 10. MODELS SWIFT

```swift
// MARK: - ESPM Models

struct ESPMConnectResponse: Codable {
    let status: String           // "connected"
    let disciplinasFound: Int
    let disciplinas: [Disciplina]

    enum CodingKeys: String, CodingKey {
        case status
        case disciplinasFound = "disciplinas_found"
        case disciplinas
    }
}

struct ESPMStatusResponse: Codable {
    let connected: Bool
    let matricula: String?
    let disciplinasCount: Int
    let tokenExpiresAt: String?  // ISO 8601

    enum CodingKeys: String, CodingKey {
        case connected
        case matricula
        case disciplinasCount = "disciplinas_count"
        case tokenExpiresAt = "token_expires_at"
    }
}

struct Disciplina: Codable, Identifiable {
    let id: String
    let nome: String
    let turma: String?
    let semestre: String?
}

// Envelope padrao de todas as respostas do backend
struct APIResponse<T: Codable>: Codable {
    let data: T?
    let error: String?
    let message: String
}
```

---

## 11. INFO.PLIST

Nenhuma permissao especial necessaria para WKWebView. O WebView usa o engine do Safari nativo, sem precisar de entitlements extras.

---

## 12. CHECKLIST DE IMPLEMENTACAO

- [ ] `ESPMService.swift` — chamadas HTTP (connect, status, sync, disconnect)
- [ ] `CanvasWebViewController.swift` — WKWebView + NavigationDelegate + ScriptMessageHandler
- [ ] `ESPMConnectViewModel.swift` — state machine (webLogin → generating → sending → success/error)
- [ ] `ESPMConnectView.swift` — UI com WebView + overlays de loading/sucesso/erro
- [ ] Overlays: `GeneratingOverlay`, `SuccessOverlay`, `ErrorOverlay`
- [ ] Models: `ESPMConnectResponse`, `ESPMStatusResponse`, `Disciplina`
- [ ] JavaScript de injecao (string literal no Swift, copiar da secao 6)
- [ ] Integracao na navegacao principal (botao "Conectar ESPM")
- [ ] Checagem de expiracao no launch do app
- [ ] Notificacao local de renovacao (14 dias antes)
- [ ] Teste end-to-end com conta ESPM real

---

## 13. TESTE

**Backend de producao:** `https://coffee-oficial-production.up.railway.app`

**Fluxo de teste:**
1. Abrir ESPMConnectView
2. Fazer login com email + senha ESPM no WebView
3. Verificar que o overlay "Configurando..." aparece
4. Verificar que a response do backend contem disciplinas
5. Verificar que a tela de sucesso mostra as disciplinas
6. Chamar `GET /espm/status` e confirmar `connected: true`
