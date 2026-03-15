import SwiftUI
import WebKit

// MARK: - Canvas WebView Controller
// UIViewControllerRepresentable wrapping WKWebView for Canvas SSO + token generation
// Flow: canvas.espm.br/profile/settings → Microsoft SSO → JS generates token → Swift receives it

struct CanvasWebViewController: UIViewControllerRepresentable {
    let onTokenReceived: (String) -> Void
    let onError: (String) -> Void
    let onCanvasReady: () -> Void

    func makeUIViewController(context: Context) -> CanvasWebViewHostController {
        let controller = CanvasWebViewHostController()
        controller.onTokenReceived = onTokenReceived
        controller.onError = onError
        controller.onCanvasReady = onCanvasReady
        return controller
    }

    func updateUIViewController(_ uiViewController: CanvasWebViewHostController, context: Context) {}
}

// MARK: - Host Controller (UIKit)

final class CanvasWebViewHostController: UIViewController, WKNavigationDelegate, WKScriptMessageHandler {

    var onTokenReceived: ((String) -> Void)?
    var onError: ((String) -> Void)?
    var onCanvasReady: (() -> Void)?

    private var webView: WKWebView!
    private var hasInjectedScript = false
    private var timeoutTask: Task<Void, Never>?

    // MARK: - Canvas URL

    private let canvasURL = URL(string: "https://canvas.espm.br/profile/settings")!

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        setupWebView()
        loadCanvas()
    }

    deinit {
        timeoutTask?.cancel()
        webView?.configuration.userContentController.removeScriptMessageHandler(forName: "coffeeToken")
    }

    // MARK: - Setup

    private func setupWebView() {
        let config = WKWebViewConfiguration()
        let contentController = WKUserContentController()

        // Register message handler for receiving token from JS
        contentController.add(LeakAvoider(delegate: self), name: "coffeeToken")
        config.userContentController = contentController

        // Use default data store to persist SSO cookies
        config.websiteDataStore = .default()
        config.preferences.javaScriptCanOpenWindowsAutomatically = false

        webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = self
        webView.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(webView)
        NSLayoutConstraint.activate([
            webView.topAnchor.constraint(equalTo: view.topAnchor),
            webView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            webView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    private func loadCanvas() {
        hasInjectedScript = false
        timeoutTask?.cancel()
        webView.load(URLRequest(url: canvasURL))
    }

    // MARK: - Reload (for retry)

    func reload() {
        hasInjectedScript = false
        timeoutTask?.cancel()

        // Clear site data for fresh start
        let dataStore = webView.configuration.websiteDataStore
        dataStore.fetchDataRecords(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes()) { records in
            let canvasRecords = records.filter { $0.displayName.contains("espm") }
            dataStore.removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), for: canvasRecords) { [weak self] in
                self?.loadCanvas()
            }
        }
    }

    // MARK: - WKNavigationDelegate

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard let url = webView.url?.absoluteString else { return }
        print("[CanvasWebView] didFinish: \(url)")

        // Ignore SSO / login pages — reset flag so we can inject when back on Canvas
        if url.contains("microsoftonline.com") || url.contains("microsoft.com") || url.contains("instructure.com") {
            print("[CanvasWebView] SSO page — waiting for login...")
            hasInjectedScript = false
            return
        }

        // Canvas login page — reset and wait
        if url.contains("canvas.espm.br") && url.contains("/login") {
            print("[CanvasWebView] Canvas login redirect — waiting...")
            hasInjectedScript = false
            return
        }

        // Login completed — Canvas settings page loaded
        if url.contains("canvas.espm.br") && !hasInjectedScript {
            hasInjectedScript = true
            print("[CanvasWebView] Canvas page loaded! Will inject JS in 4s...")

            // Notify parent to show loading overlay (hides automation from user)
            DispatchQueue.main.async { [weak self] in
                self?.onCanvasReady?()
            }

            // Start timeout timer (60 seconds)
            startTimeout()

            // Wait 4 seconds for Canvas React components to load, then inject JS
            DispatchQueue.main.asyncAfter(deadline: .now() + 4.0) { [weak self] in
                guard let self else { return }
                // Double-check we're still on Canvas settings (not redirected to login)
                guard let currentURL = self.webView.url?.absoluteString,
                      currentURL.contains("canvas.espm.br"),
                      !currentURL.contains("/login") else {
                    print("[CanvasWebView] Page navigated away before injection, resetting...")
                    self.hasInjectedScript = false
                    return
                }
                self.injectTokenGenerator()
            }
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        handleWebError(error)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        // Ignore cancelled navigations (happens during redirects)
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled {
            return
        }
        handleWebError(error)
    }

    private func handleWebError(_ error: Error) {
        let urlError = error as? URLError
        let message: String

        switch urlError?.code {
        case .timedOut:
            message = "O login demorou muito. Tente novamente."
        case .notConnectedToInternet, .networkConnectionLost:
            message = "Sem conexão com a internet."
        default:
            message = "Não foi possível carregar o Canvas. Verifique sua conexão."
        }

        DispatchQueue.main.async { [weak self] in
            self?.timeoutTask?.cancel()
            self?.onError?(message)
        }
    }

    // MARK: - Timeout

    private func startTimeout() {
        timeoutTask?.cancel()
        timeoutTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(60))
            guard !Task.isCancelled else { return }
            onError?("Conexão lenta. Verifique sua internet e tente novamente.")
        }
    }

    // MARK: - WKScriptMessageHandler

    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        guard message.name == "coffeeToken",
              let body = message.body as? [String: Any] else { return }

        timeoutTask?.cancel()

        let success = body["success"] as? Bool ?? false

        if success, let token = body["token"] as? String, token.contains("~"), token.count > 20 {
            DispatchQueue.main.async { [weak self] in
                self?.onTokenReceived?(token)
            }
        } else {
            let errorMsg = body["error"] as? String ?? "Erro desconhecido"
            print("[CanvasWebView] ❌ JS ERROR: \(errorMsg)")
            let userMessage: String

            if errorMsg.contains("LINK_NOT_FOUND") || errorMsg.contains("FIELD_NOT_FOUND") || errorMsg.contains("BUTTON_NOT_FOUND") {
                userMessage = "Erro ao configurar. Tente novamente."
            } else if errorMsg.contains("TOKEN_NOT_FOUND") {
                userMessage = "Erro ao gerar token. Tente novamente."
            } else if errorMsg.contains("DAY_NOT_FOUND") {
                userMessage = "Erro ao configurar. Tente novamente."
            } else {
                userMessage = "Erro inesperado. Tente novamente."
            }

            DispatchQueue.main.async { [weak self] in
                self?.onError?(userMessage)
            }
        }
    }

    // MARK: - JavaScript Injection

    private func injectTokenGenerator() {
        print("[CanvasWebView] Injecting JS token generator...")
        // First, dump current page info
        webView.evaluateJavaScript("document.title + ' | URL: ' + window.location.href") { result, _ in
            print("[CanvasWebView] Page before inject: \(result ?? "nil")")
        }
        webView.evaluateJavaScript(Self.tokenGeneratorScript) { _, error in
            if let error = error {
                print("[CanvasWebView] JS injection error: \(error)")
            }
        }
    }

    // MARK: - Token Generator JavaScript
    // Provided by backend team — automates Canvas token generation

    static let tokenGeneratorScript = """
    (async function coffeeTokenGenerator() {
        const sleep = ms => new Promise(r => setTimeout(r, ms));
        const log = msg => console.log('[CoffeeJS] ' + msg);
        const report = (success, data) => {
            log('REPORT: success=' + success + ' data=' + JSON.stringify(data));
            window.webkit.messageHandlers.coffeeToken.postMessage(
                Object.assign({ success }, data)
            );
        };

        try {
            log('Starting on: ' + window.location.href);
            log('Page title: ' + document.title);
            log('Body text length: ' + (document.body?.innerText?.length || 0));

            // 0. Close NEXUS modal (Canvas announcements popup)
            const closeBtn = document.querySelector("button[aria-label='Close']");
            if (closeBtn) {
                log('Found NEXUS close button, clicking...');
                closeBtn.click();
                await sleep(800);
            } else {
                log('No NEXUS modal found (ok)');
            }

            // 1. Click "Novo token de acesso"
            let tokenLink = null;
            const allLinks = document.querySelectorAll('a, button');
            log('Found ' + allLinks.length + ' links/buttons on page');
            const linkTexts = [];
            for (const el of allLinks) {
                const txt = (el.textContent || '').trim().substring(0, 60);
                if (txt) linkTexts.push(txt);
                if (txt.includes('Novo token de acesso') || txt.includes('New Access Token')) {
                    tokenLink = el;
                    break;
                }
            }
            log('Link/button texts (first 20): ' + JSON.stringify(linkTexts.slice(0, 20)));
            if (!tokenLink) {
                throw new Error('LINK_NOT_FOUND: "Novo token de acesso" not found. Page has ' + allLinks.length + ' links/buttons');
            }
            tokenLink.click();
            await sleep(1200);

            // 2. Fill "Objetivo" field
            const purposeField = document.querySelector("input[name='purpose']");
            if (!purposeField) {
                throw new Error('FIELD_NOT_FOUND: input[name=purpose]');
            }
            const nativeInputValueSetter = Object.getOwnPropertyDescriptor(
                window.HTMLInputElement.prototype, 'value'
            ).set;
            nativeInputValueSetter.call(purposeField, 'coffee-app');
            purposeField.dispatchEvent(new Event('input', { bubbles: true }));
            purposeField.dispatchEvent(new Event('change', { bubbles: true }));
            await sleep(400);

            // 3. Open date picker
            const dateInput = document.querySelector("input[id^='Selectable']");
            if (!dateInput) {
                throw new Error('FIELD_NOT_FOUND: date picker (input[id^=Selectable])');
            }
            dateInput.click();
            await sleep(600);

            // 4. Advance 4 months in calendar
            for (let i = 0; i < 4; i++) {
                const nextMonthBtn = Array.from(document.querySelectorAll('button'))
                    .find(b => (b.textContent || '').includes('Pr\\u00f3ximo m\\u00eas'));
                if (nextMonthBtn) {
                    nextMonthBtn.click();
                    await sleep(300);
                }
            }

            // 5. Select safe day (today - 3, minimum 1)
            const safeDay = Math.max(new Date().getDate() - 3, 1);
            const dayButtons = document.querySelectorAll("button[role='option']");
            let dayClicked = false;
            for (const btn of dayButtons) {
                const text = btn.textContent || '';
                if (text.startsWith(safeDay + ' ')) {
                    btn.click();
                    dayClicked = true;
                    break;
                }
            }
            if (!dayClicked) {
                throw new Error('DAY_NOT_FOUND: day ' + safeDay + ' not found in calendar');
            }
            await sleep(500);

            // 6. Click "Gerar token"
            const submitBtn = Array.from(
                document.querySelectorAll("button[type='submit']")
            ).find(b => (b.textContent || '').includes('Gerar token'));
            if (!submitBtn) {
                throw new Error('BUTTON_NOT_FOUND: "Gerar token"');
            }
            submitBtn.click();

            // 7. Wait and extract token
            let token = null;
            for (let attempt = 0; attempt < 15; attempt++) {
                await sleep(500);
                const tokenEl = document.querySelector('[data-testid="visible_token"]');
                if (tokenEl) {
                    token = tokenEl.textContent.trim();
                    if (token && token.includes('~') && token.length > 20) {
                        break;
                    }
                    token = null;
                }
            }
            if (!token) {
                throw new Error('TOKEN_NOT_FOUND: [data-testid=visible_token] not found in 7.5s');
            }

            // 8. Success — send token to Swift
            report(true, { token: token });

        } catch (err) {
            report(false, { error: err.message || String(err) });
        }
    })();
    """
}

// MARK: - Leak Avoider
// Prevents WKUserContentController retain cycle

private class LeakAvoider: NSObject, WKScriptMessageHandler {
    weak var delegate: WKScriptMessageHandler?

    init(delegate: WKScriptMessageHandler) {
        self.delegate = delegate
        super.init()
    }

    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        delegate?.userContentController(userContentController, didReceive: message)
    }
}
