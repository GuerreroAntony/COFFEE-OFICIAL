import SwiftUI

// MARK: - Content View
// Root view — handles auth routing + tab navigation
// Equivalent to App.jsx renderContent() + tab bar

struct ContentView: View {
    @State private var router = NavigationRouter()
    @State private var subscriptionService = SubscriptionService()
    @State private var showForceUpdate = false

    var body: some View {
        ZStack(alignment: .bottom) {
            // Main content
            Group {
                switch router.authState {
                case .splash:
                    SplashScreenView()
                        .transition(.opacity)

                case .onboarding:
                    OnboardingScreenView()
                        .transition(.move(edge: .trailing))

                case .login:
                    LoginScreenView()
                        .transition(.move(edge: .trailing))

                case .signup:
                    SignupScreenView()
                        .transition(.move(edge: .trailing))

                case .linkESPM:
                    LinkESPMScreenView()
                        .transition(.move(edge: .trailing))

                case .premiumOffer:
                    PremiumOfferScreenView()
                        .transition(.move(edge: .trailing))

                case .authenticated:
                    authenticatedContent
                }
            }
            .animation(.easeInOut(duration: 0.35), value: router.authState)

            // Tab Bar (only visible when appropriate)
            if router.showTabBar {
                CoffeeTabBarFinal()
                    .transition(.move(edge: .bottom))
            }

            // Force Update overlay — blocks EVERYTHING
            if showForceUpdate {
                ForceUpdateView()
                    .transition(.opacity)
                    .zIndex(999)
            }
        }
        .environment(\.router, router)
        .environment(\.subscriptionService, subscriptionService)
        .task {
            await checkAuthState()
        }
        .onReceive(NotificationCenter.default.publisher(for: .forceUpdateRequired)) { _ in
            withAnimation(.easeInOut(duration: 0.3)) {
                showForceUpdate = true
            }
        }
    }

    // MARK: - Auto-Login

    private func checkAuthState() async {
        guard KeychainManager.isLoggedIn else { return }

        do {
            let user = try await AuthService.getMe()
            subscriptionService.syncWithUser(user)
            router.login(user: user)
        } catch {
            // Token expired or invalid — clear and go to login
            KeychainManager.clearAll()
            router.goToLogin()
        }
    }

    // MARK: - Authenticated Content

    @ViewBuilder
    private var authenticatedContent: some View {
        ZStack {
            DisciplinasScreenView()
                .opacity(router.activeTab == .home ? 1 : 0)
                .allowsHitTesting(router.activeTab == .home)

            Group {
                if subscriptionService.isPremium {
                    RecordingFlowView()
                } else {
                    PremiumLockedTabView(feature: .recording)
                }
            }
            .opacity(router.activeTab == .record ? 1 : 0)
            .allowsHitTesting(router.activeTab == .record)

            Group {
                if subscriptionService.isPremium {
                    AIChatScreenView()
                } else {
                    PremiumLockedTabView(feature: .aiChat)
                }
            }
            .opacity(router.activeTab == .ai ? 1 : 0)
            .allowsHitTesting(router.activeTab == .ai)
        }
        // Course detail push
        .fullScreenCover(item: $router.selectedCourse) { course in
            CourseDetailScreenView(discipline: course)
        }
        // Repository detail push
        .fullScreenCover(item: $router.selectedRepository) { repo in
            RepositoryDetailScreenView(repository: repo)
        }
        // Profile sheet
        .sheet(isPresented: $router.showProfile) {
            ProfileScreenView()
        }
        // Settings sheet
        .sheet(isPresented: $router.showSettings) {
            SettingsScreenView()
        }
        // Link ESPM sheet (from settings)
        .sheet(isPresented: $router.showLinkESPM) {
            LinkESPMScreenView()
        }
        // Payment sheet
        .sheet(isPresented: $router.showPayment) {
            if let plan = router.selectedPlan {
                PaymentSheetView(plan: plan)
            }
        }
        // Premium gate sheet
        .sheet(isPresented: $router.showPremiumGate) {
            PremiumGateSheet()
        }
        // Promo codes sheet
        .sheet(isPresented: $router.showPromoCodes) {
            PromoCodesScreenView()
        }
    }
}

// MARK: - Payment Sheet View

struct PaymentSheetView: View {
    let plan: SubscriptionPlan
    @Environment(\.dismiss) private var dismiss
    @Environment(\.subscriptionService) private var subscriptionService
    @State private var isPurchasing = false

    private var isBlack: Bool { plan.planId == "black" }
    private var accent: Color { isBlack ? Color(hex: "1A1008") : Color.coffeePrimary }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Plan header
                    VStack(spacing: 12) {
                        ZStack {
                            Circle()
                                .fill(accent.opacity(0.1))
                                .frame(width: 64, height: 64)
                            Image(systemName: isBlack ? "flame.fill" : "cup.and.saucer.fill")
                                .font(.system(size: 28))
                                .foregroundStyle(accent)
                        }

                        Text(plan.name)
                            .font(.system(size: 22, weight: .bold))
                            .foregroundStyle(Color.coffeeTextPrimary)

                        VStack(spacing: 2) {
                            if let original = plan.originalPrice {
                                Text("R$\(String(format: "%.2f", original))")
                                    .font(.system(size: 14))
                                    .strikethrough()
                                    .foregroundStyle(Color.coffeeTextSecondary.opacity(0.6))
                            }
                            HStack(spacing: 4) {
                                Text("R$\(String(format: "%.2f", plan.price))")
                                    .font(.system(size: 28, weight: .bold))
                                    .foregroundStyle(accent)
                                Text("/mês")
                                    .font(.system(size: 15))
                                    .foregroundStyle(Color.coffeeTextSecondary)
                            }
                        }
                    }
                    .padding(.top, 16)

                    // Features
                    CoffeeCellGroup {
                        ForEach(Array(plan.features.enumerated()), id: \.offset) { index, feature in
                            HStack(spacing: 12) {
                                Image(systemName: feature.included ? "checkmark.circle.fill" : "xmark.circle.fill")
                                    .foregroundStyle(feature.included ? .green : Color.coffeeTextSecondary.opacity(0.3))
                                Text(feature.text)
                                    .font(.system(size: 15))
                                    .foregroundStyle(Color.coffeeTextPrimary)
                                Spacer()
                                if let detail = feature.detail {
                                    Text(detail)
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundStyle(Color.coffeeTextSecondary)
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)

                            if index < plan.features.count - 1 {
                                Divider().padding(.leading, 44)
                            }
                        }
                    }
                    .padding(.horizontal, 16)

                    // StoreKit note
                    VStack(spacing: 8) {
                        Image(systemName: "apple.logo")
                            .font(.system(size: 20))
                            .foregroundStyle(Color.coffeeTextSecondary)
                        Text("Pagamento processado pela Apple via App Store")
                            .font(.system(size: 13))
                            .foregroundStyle(Color.coffeeTextSecondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.horizontal, 24)

                    CoffeeButton("Assinar \(plan.name)", isLoading: isPurchasing) {
                        isPurchasing = true
                        Task {
                            let _ = try? await subscriptionService.purchase(plan: plan)
                            isPurchasing = false
                            dismiss()
                        }
                    }
                    .padding(.horizontal, 20)

                    Text("Cancele a qualquer momento nas Configurações do iPhone.")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.coffeeTextSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                }
            }
            .background(Color.coffeeBackground)
            .navigationTitle("Assinatura")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Fechar") { dismiss() }
                        .foregroundStyle(Color.coffeePrimary)
                }
            }
        }
    }
}

// MARK: - AuthState Equatable

extension NavigationRouter.AuthState: Equatable {}

// MARK: - Preview

#Preview {
    ContentView()
}
