import SwiftUI

// MARK: - Content View
// Root view — handles auth routing + tab navigation
// Equivalent to App.jsx renderContent() + tab bar

struct ContentView: View {
    @State private var router = NavigationRouter()
    @State private var subscriptionService = SubscriptionService()

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
        }
        .environment(\.router, router)
        .environment(\.subscriptionService, subscriptionService)
        .task {
            await checkAuthState()
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
            switch router.activeTab {
            case .home:
                DisciplinasScreenView()

            case .record:
                if subscriptionService.isPremium {
                    RecordingFlowView()
                } else {
                    PremiumLockedTabView(feature: .recording)
                }

            case .ai:
                if subscriptionService.isPremium {
                    AIChatScreenView()
                } else {
                    PremiumLockedTabView(feature: .aiChat)
                }
            }
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

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Plan header
                    VStack(spacing: 12) {
                        ZStack {
                            Circle()
                                .fill(Color.coffeePrimary.opacity(0.1))
                                .frame(width: 64, height: 64)
                            Image(systemName: "crown.fill")
                                .font(.system(size: 28))
                                .foregroundStyle(Color.coffeePrimary)
                        }

                        Text(plan.name)
                            .font(.system(size: 22, weight: .bold))
                            .foregroundStyle(Color.coffeeTextPrimary)

                        HStack(spacing: 4) {
                            Text("R$\(String(format: "%.2f", plan.price))")
                                .font(.system(size: 28, weight: .bold))
                                .foregroundStyle(Color.coffeePrimary)
                            Text("/mês")
                                .font(.system(size: 15))
                                .foregroundStyle(Color.coffeeTextSecondary)
                        }
                    }
                    .padding(.top, 16)

                    // Features
                    CoffeeCellGroup {
                        ForEach(Array(plan.features.enumerated()), id: \.offset) { index, feature in
                            HStack(spacing: 12) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                                Text(feature)
                                    .font(.system(size: 15))
                                    .foregroundStyle(Color.coffeeTextPrimary)
                                Spacer()
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

                    CoffeeButton("Assinar com Apple Pay", isLoading: isPurchasing) {
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
