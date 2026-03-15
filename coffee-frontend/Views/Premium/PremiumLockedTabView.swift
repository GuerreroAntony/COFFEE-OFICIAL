import SwiftUI

// MARK: - Premium Locked Tab View
// Shown in place of a premium-only tab (Record, AI) when user is not subscribed
// Displays lock icon + feature description + CTA to open paywall

struct PremiumLockedTabView: View {
    let feature: PremiumFeature
    @Environment(\.router) private var router
    @Environment(\.subscriptionService) private var subscription

    @State private var showPremiumGate = false

    var body: some View {
        VStack(spacing: 0) {
            // Nav bar with back button
            CoffeeNavBar(
                title: feature.navTitle,
                backTitle: "Voltar",
                onBack: {
                    router.switchTab(.home)
                }
            )

            VStack(spacing: 28) {
                Spacer()

                // Lock icon with themed background
                ZStack {
                    Circle()
                        .fill(Color.coffeePrimary.opacity(0.08))
                        .frame(width: 120, height: 120)

                    Circle()
                        .fill(Color.coffeePrimary.opacity(0.15))
                        .frame(width: 80, height: 80)

                    Image(systemName: "lock.fill")
                        .font(.system(size: 36))
                        .foregroundStyle(Color.coffeePrimary)
                }

                // Title + description
                VStack(spacing: 10) {
                    Text(feature.title)
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(Color.coffeeTextPrimary)

                    Text(feature.description)
                        .font(.system(size: 16))
                        .foregroundStyle(Color.coffeeTextSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                        .lineSpacing(4)
                }

                // Feature icon
                Image(systemName: feature.icon)
                    .font(.system(size: 28))
                    .foregroundStyle(Color.coffeePrimary.opacity(0.4))

                Spacer()

                // Price info with strikethrough
                HStack(spacing: 6) {
                    if !subscription.hasUsedTrial {
                        Text("Após o trial:")
                            .font(.system(size: 13))
                            .foregroundStyle(Color.coffeeTextSecondary)
                    }
                    Text("R$59,90")
                        .font(.system(size: 14, weight: .medium))
                        .strikethrough()
                        .foregroundStyle(Color.coffeeTextSecondary)
                    Text("R$29,90/mês")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(Color.coffeeTextPrimary)
                    Text("· Cancele quando quiser")
                        .font(.system(size: 13))
                        .foregroundStyle(Color.coffeeTextSecondary)
                }

                // CTA — opens PremiumGateSheet (handles trial vs payment)
                CoffeeButton(
                    subscription.hasUsedTrial ? "Assinar Premium" : "Começar 7 dias grátis",
                    icon: "crown.fill"
                ) {
                    showPremiumGate = true
                }
                .padding(.horizontal, 24)

                if !subscription.hasUsedTrial {
                    Text("Sem cartão de crédito necessário")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.coffeeTextSecondary)
                }

                // Restore purchases
                Button("Restaurar compras") {
                    Task {
                        await subscription.restorePurchases()
                    }
                }
                .font(.system(size: 14))
                .foregroundStyle(Color.coffeeTextSecondary)

                Spacer().frame(height: 40)
            }
        }
        .background(Color.coffeeBackground)
        .sheet(isPresented: $showPremiumGate) {
            PremiumGateSheet()
        }
    }
}

// MARK: - Premium Feature

enum PremiumFeature {
    case recording
    case aiChat

    var navTitle: String {
        switch self {
        case .recording: return "Gravar"
        case .aiChat: return "Barista IA"
        }
    }

    var title: String {
        switch self {
        case .recording: return "Grave suas aulas"
        case .aiChat: return "Converse com o Barista"
        }
    }

    var description: String {
        switch self {
        case .recording: return "Grave aulas ilimitadas e receba transcrições e resumos automáticos com IA."
        case .aiChat: return "Tire dúvidas, peça resumos e explore o conteúdo das suas aulas com IA."
        }
    }

    var icon: String {
        switch self {
        case .recording: return "mic.fill"
        case .aiChat: return CoffeeIcon.sparkles
        }
    }
}

// MARK: - Preview

#Preview("Recording Locked") {
    PremiumLockedTabView(feature: .recording)
        .environment(\.router, NavigationRouter())
        .environment(\.subscriptionService, SubscriptionService())
}

#Preview("AI Locked") {
    PremiumLockedTabView(feature: .aiChat)
        .environment(\.router, NavigationRouter())
        .environment(\.subscriptionService, SubscriptionService())
}
