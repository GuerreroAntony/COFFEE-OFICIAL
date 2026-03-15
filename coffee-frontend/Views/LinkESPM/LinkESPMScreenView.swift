import SwiftUI

// MARK: - Link ESPM Screen
// Real connection flow: terms → WKWebView SSO → token generation → backend → success
// Supports both onboarding (full-screen) and settings reconnect (sheet) contexts

struct LinkESPMScreenView: View {
    @Environment(\.router) private var router
    @Environment(\.dismiss) private var dismiss

    enum Phase: Equatable {
        case terms
        case webLogin
        case connecting
        case success(Int)
        case error(String)
    }

    @State private var phase: Phase = .terms
    @State private var accepted = false
    @State private var connectStep = 0  // 0=token, 1=sending, 2=importing
    @State private var showAutomationOverlay = false

    /// True when presented as full-screen auth flow (onboarding), false when sheet (settings)
    private var isOnboarding: Bool {
        router.authState == .linkESPM
    }

    var body: some View {
        Group {
            switch phase {
            case .terms:
                termsView
            case .webLogin:
                webLoginView
            case .connecting:
                connectingView
            case .success(let count):
                successView(count: count)
            case .error(let message):
                errorView(message: message)
            }
        }
        .background(Color.coffeeBackground)
    }

    // MARK: - Terms View

    private var termsView: some View {
        VStack(spacing: 0) {
            CoffeeNavBar(
                title: "Conexão Acadêmica",
                onBack: isOnboarding ? { router.goToLogin() } : { dismiss() }
            )

            ScrollView {
                VStack(spacing: 16) {
                    // Header card
                    VStack(alignment: .leading, spacing: 8) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(Color.coffeePrimary.opacity(0.08))
                                .frame(width: 48, height: 48)

                            Image(systemName: "doc.text.fill")
                                .font(.system(size: 24))
                                .foregroundStyle(Color.coffeePrimary)
                        }

                        Text("Antes de continuar")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundStyle(Color.coffeeTextPrimary)

                        Text("Leia e aceite os termos para que possamos acessar sua grade e materiais do Canvas ESPM.")
                            .font(.system(size: 14))
                            .foregroundStyle(Color.coffeeTextSecondary)
                            .lineSpacing(3)
                    }
                    .padding(20)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.coffeeCardBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

                    // Terms sections
                    VStack(spacing: 0) {
                        termSection(icon: CoffeeIcon.mic, title: "Gravação de Aulas",
                            body: "O COFFEE capta o áudio da aula em tempo real apenas para gerar a transcrição. Nenhum arquivo de áudio é armazenado.")
                        Divider()
                        termSection(icon: CoffeeIcon.school, title: "Dados Acadêmicos",
                            body: "Ao conectar sua conta ESPM, acessamos apenas sua grade horária e materiais do Canvas. Suas credenciais ESPM não são armazenadas — utilizamos apenas um token temporário de acesso.")
                        Divider()
                        termSection(icon: CoffeeIcon.sparkles, title: "Inteligência Artificial",
                            body: "As transcrições são processadas por modelos de IA para gerar resumos e mapas mentais. Os dados são anonimizados.")
                        Divider()
                        termSection(icon: "c.circle", title: "Propriedade Intelectual",
                            body: "As transcrições, resumos e materiais gerados pertencem ao usuário. Você pode exportar ou deletar a qualquer momento.")
                        Divider()
                        termSection(icon: CoffeeIcon.lock, title: "Privacidade e LGPD",
                            body: "Seguimos a Lei Geral de Proteção de Dados (LGPD). Seus dados podem ser excluídos a qualquer momento em Perfil > Excluir conta, ou via suportecoffeeapp@gmail.com.")
                    }
                    .background(Color.coffeeCardBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

                    // Accept checkbox
                    Button {
                        accepted.toggle()
                    } label: {
                        HStack(alignment: .top, spacing: 12) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 5)
                                    .fill(accepted ? Color.coffeePrimary : Color.coffeeTextSecondary.opacity(0.15))
                                    .frame(width: 20, height: 20)

                                if accepted {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 12, weight: .bold))
                                        .foregroundStyle(.white)
                                }
                            }
                            .padding(.top, 2)

                            Text("Li e aceito os **Termos de Uso** e a **Política de Privacidade** do COFFEE.")
                                .font(.system(size: 14))
                                .foregroundStyle(Color.coffeeTextPrimary)
                                .lineSpacing(3)
                                .multilineTextAlignment(.leading)
                        }
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.coffeeCardBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(accepted ? Color.coffeePrimary : .clear, lineWidth: 1.5)
                        )
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 120)
            }

            // Bottom buttons
            VStack(spacing: 8) {
                CoffeeButton(
                    "Aceitar e Continuar",
                    isDisabled: !accepted
                ) {
                    handleAcceptTerms()
                }

                if isOnboarding {
                    Button("Pular esta etapa") {
                        router.goToPremiumOffer()
                    }
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Color.coffeeTextSecondary)
                    .padding(.vertical, 8)
                } else {
                    Button("Cancelar") {
                        dismiss()
                    }
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.red)
                    .padding(.vertical, 8)
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 16)
            .background(
                Color.coffeeBackground.opacity(0.95)
                    .background(.ultraThinMaterial)
            )
        }
    }

    // MARK: - Web Login View

    private var webLoginView: some View {
        VStack(spacing: 0) {
            CoffeeNavBar(
                title: "Login ESPM",
                backTitle: "Voltar",
                onBack: {
                    showAutomationOverlay = false
                    withAnimation { phase = .terms }
                }
            )

            if APIClient.useMocks {
                // Mock mode: simulate WebView login
                VStack(spacing: 24) {
                    Spacer()

                    ZStack {
                        Circle()
                            .fill(Color.coffeePrimary.opacity(0.08))
                            .frame(width: 80, height: 80)

                        ProgressView()
                            .scaleEffect(1.3)
                            .tint(Color.coffeePrimary)
                    }

                    VStack(spacing: 8) {
                        Text("Simulando login no Canvas...")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(Color.coffeeTextPrimary)

                        Text("Em modo real, o aluno veria a tela de login Microsoft aqui.")
                            .font(.system(size: 14))
                            .foregroundStyle(Color.coffeeTextSecondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 40)
                    }

                    Spacer()
                }
                .frame(maxWidth: .infinity)
                .onAppear {
                    // Auto-advance after mock delay
                    Task { @MainActor in
                        try? await Task.sleep(for: .seconds(2))
                        handleTokenReceived("mock_11552~canvas_token_for_testing")
                    }
                }
            } else {
                // Real mode: WKWebView + connecting steps overlay
                ZStack {
                    CanvasWebViewController(
                        onTokenReceived: { token in
                            handleTokenReceived(token)
                        },
                        onError: { error in
                            withAnimation {
                                phase = .error(error)
                            }
                        },
                        onCanvasReady: {
                            withAnimation(.easeInOut(duration: 0.3)) {
                                connectStep = 0
                                showAutomationOverlay = true
                            }
                        }
                    )

                    // Connecting steps overlay — shows progress while JS runs behind
                    if showAutomationOverlay {
                        VStack(spacing: 0) {
                            Spacer()

                            VStack(spacing: 32) {
                                // Animated icon
                                ZStack {
                                    Circle()
                                        .fill(Color.coffeePrimary.opacity(0.08))
                                        .frame(width: 100, height: 100)

                                    Circle()
                                        .fill(Color.coffeePrimary.opacity(0.15))
                                        .frame(width: 64, height: 64)

                                    Image(systemName: CoffeeIcon.school)
                                        .font(.system(size: 28))
                                        .foregroundStyle(Color.coffeePrimary)
                                }

                                Text("Configurando sua conta...")
                                    .font(.system(size: 20, weight: .bold))
                                    .foregroundStyle(Color.coffeeTextPrimary)

                                // Progress steps
                                CoffeeCellGroup {
                                    VStack(spacing: 0) {
                                        connectingStep(
                                            label: "Gerando token de acesso...",
                                            isCompleted: connectStep >= 1,
                                            isActive: connectStep == 0,
                                            showSeparator: true
                                        )
                                        connectingStep(
                                            label: "Conectando ao COFFEE...",
                                            isCompleted: connectStep >= 2,
                                            isActive: connectStep == 1,
                                            showSeparator: true
                                        )
                                        connectingStep(
                                            label: "Importando disciplinas...",
                                            isCompleted: connectStep >= 3,
                                            isActive: connectStep == 2,
                                            showSeparator: false
                                        )
                                    }
                                }
                                .padding(.horizontal, 24)
                            }

                            Spacer()
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color.coffeeBackground)
                        .transition(.opacity)
                    }
                }
            }
        }
    }

    // MARK: - Connecting View

    private var connectingView: some View {
        VStack(spacing: 0) {
            CoffeeNavBar(title: "Conexão Acadêmica")

            VStack(spacing: 0) {
                Spacer()

                VStack(spacing: 32) {
                    // Animated icon
                    ZStack {
                        Circle()
                            .fill(Color.coffeePrimary.opacity(0.08))
                            .frame(width: 100, height: 100)

                        Circle()
                            .fill(Color.coffeePrimary.opacity(0.15))
                            .frame(width: 64, height: 64)

                        Image(systemName: CoffeeIcon.school)
                            .font(.system(size: 28))
                            .foregroundStyle(Color.coffeePrimary)
                    }

                    Text("Configurando sua conta...")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(Color.coffeeTextPrimary)

                    // Progress steps
                    CoffeeCellGroup {
                        VStack(spacing: 0) {
                            connectingStep(
                                label: "Token de acesso gerado",
                                isCompleted: connectStep >= 1,
                                isActive: connectStep == 0,
                                showSeparator: true
                            )
                            connectingStep(
                                label: "Conectando ao COFFEE...",
                                isCompleted: connectStep >= 2,
                                isActive: connectStep == 1,
                                showSeparator: true
                            )
                            connectingStep(
                                label: "Importando disciplinas...",
                                isCompleted: false,
                                isActive: connectStep == 2,
                                showSeparator: false
                            )
                        }
                    }
                    .padding(.horizontal, 24)
                }

                Spacer()
            }
        }
    }

    // MARK: - Success View

    private func successView(count: Int) -> some View {
        VStack(spacing: 0) {
            CoffeeNavBar(title: "Conexão Acadêmica")

            VStack(spacing: 0) {
                Spacer()

                VStack(spacing: 24) {
                    // Success icon
                    ZStack {
                        Circle()
                            .fill(Color.green.opacity(0.08))
                            .frame(width: 100, height: 100)

                        Circle()
                            .fill(Color.green.opacity(0.15))
                            .frame(width: 64, height: 64)

                        Image(systemName: "checkmark")
                            .font(.system(size: 28, weight: .bold))
                            .foregroundStyle(.green)
                    }

                    VStack(spacing: 8) {
                        Text("Conexão realizada!")
                            .font(.system(size: 24, weight: .bold))
                            .foregroundStyle(Color.coffeeTextPrimary)

                        Text("\(count) \(count == 1 ? "disciplina encontrada" : "disciplinas encontradas")")
                            .font(.system(size: 16))
                            .foregroundStyle(Color.coffeeTextSecondary)
                    }

                    // Feature hint
                    HStack(spacing: 12) {
                        Image(systemName: CoffeeIcon.sparkles)
                            .font(.system(size: 18))
                            .foregroundStyle(Color.coffeePrimary)

                        Text("Suas disciplinas e materiais já estão disponíveis no app.")
                            .font(.system(size: 14))
                            .foregroundStyle(Color.coffeeTextSecondary)
                            .lineSpacing(3)
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.coffeePrimary.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .padding(.horizontal, 24)
                }

                Spacer()

                CoffeeButton("Continuar") {
                    if isOnboarding {
                        router.goToPremiumOffer()
                    } else {
                        dismiss()
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 48)
            }
        }
    }

    // MARK: - Error View

    private func errorView(message: String) -> some View {
        VStack(spacing: 0) {
            CoffeeNavBar(
                title: "Conexão Acadêmica",
                onBack: { withAnimation { phase = .terms } }
            )

            VStack(spacing: 0) {
                Spacer()

                VStack(spacing: 24) {
                    // Error icon
                    ZStack {
                        Circle()
                            .fill(Color.red.opacity(0.08))
                            .frame(width: 100, height: 100)

                        Circle()
                            .fill(Color.red.opacity(0.15))
                            .frame(width: 64, height: 64)

                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 28))
                            .foregroundStyle(.red)
                    }

                    VStack(spacing: 8) {
                        Text("Erro na conexão")
                            .font(.system(size: 24, weight: .bold))
                            .foregroundStyle(Color.coffeeTextPrimary)

                        Text(message)
                            .font(.system(size: 16))
                            .foregroundStyle(Color.coffeeTextSecondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)
                    }
                }

                Spacer()

                VStack(spacing: 12) {
                    CoffeeButton("Tentar novamente") {
                        withAnimation {
                            phase = .webLogin
                        }
                    }

                    if isOnboarding {
                        Button("Pular esta etapa") {
                            router.goToPremiumOffer()
                        }
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Color.coffeeTextSecondary)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 48)
            }
        }
    }

    // MARK: - Connecting Step Row

    private func connectingStep(label: String, isCompleted: Bool, isActive: Bool, showSeparator: Bool) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(isCompleted ? Color.green.opacity(0.12) : isActive ? Color.coffeePrimary.opacity(0.1) : Color.coffeeTextSecondary.opacity(0.08))
                        .frame(width: 36, height: 36)

                    if isCompleted {
                        Image(systemName: "checkmark")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(.green)
                    } else if isActive {
                        ProgressView()
                            .scaleEffect(0.8)
                            .tint(Color.coffeePrimary)
                    } else {
                        Circle()
                            .fill(Color.coffeeTextSecondary.opacity(0.3))
                            .frame(width: 6, height: 6)
                    }
                }
                .frame(width: 36, height: 36)

                Text(label)
                    .font(.system(size: 15, weight: isActive ? .medium : .regular))
                    .foregroundStyle(isActive || isCompleted ? Color.coffeeTextPrimary : Color.coffeeTextSecondary)

                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)

            if showSeparator {
                Rectangle()
                    .fill(Color.coffeeSeparator)
                    .frame(height: 0.5)
                    .padding(.leading, 66)
            }
        }
    }

    // MARK: - Term Section

    private func termSection(icon: String, title: String, body: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 16))
                    .foregroundStyle(Color.coffeePrimary)
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.coffeeTextPrimary)
            }
            Text(body)
                .font(.system(size: 13))
                .foregroundStyle(Color.coffeeTextSecondary)
                .lineSpacing(3)
        }
        .padding(16)
    }

    // MARK: - Actions

    private func handleAcceptTerms() {
        withAnimation {
            phase = .webLogin
        }
    }

    private func handleTokenReceived(_ token: String) {
        // Token generated — advance to step 1
        withAnimation { connectStep = 1 }

        // Continue through connecting steps
        Task { @MainActor in
            // Step 2: Sending to backend
            do {
                let userEmail = router.currentUser?.email ?? ""
                let response = try await DisciplineService.connectESPM(
                    matricula: userEmail,
                    canvasToken: token
                )

                withAnimation { connectStep = 2 }
                try? await Task.sleep(for: .seconds(0.8))

                withAnimation {
                    showAutomationOverlay = false
                    phase = .success(response.disciplinasFound)
                }
            } catch {
                let message: String
                if let apiError = error as? APIError {
                    message = apiError.localizedDescription
                } else {
                    message = "Erro ao conectar. Tente novamente."
                }
                withAnimation {
                    showAutomationOverlay = false
                    phase = .error(message)
                }
            }
        }
    }
}

// MARK: - Preview

#Preview("Onboarding") {
    LinkESPMScreenView()
        .environment(\.router, NavigationRouter())
}
