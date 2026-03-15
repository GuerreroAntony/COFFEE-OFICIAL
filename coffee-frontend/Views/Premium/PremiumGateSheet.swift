import SwiftUI

// MARK: - Premium Gate Sheet
// Modal paywall shown when user taps "Desbloquear Premium"
// Visual style matches PremiumOfferScreenView (gradient hero + benefits + CTA)

struct PremiumGateSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.router) private var router
    @Environment(\.subscriptionService) private var subscription

    @State private var isPurchasing = false
    @State private var showPayment = false

    private let benefits: [(icon: String, text: String, sub: String, color: Color)] = [
        ("infinity", "Aulas ilimitadas", "Sem limite mensal de gravações", .green),
        (CoffeeIcon.sparkles, "IA sem limites", "Perguntas ilimitadas ao Barista", Color.coffeePrimary),
        ("doc.text.fill", "IA nos materiais", "Resumos e análises automáticas", .blue),
        ("doc.richtext", "Exportar PDF", "Baixe seus resumos e notas", .orange),
    ]

    var body: some View {
        VStack(spacing: 0) {
            // Hero gradient
            ZStack(alignment: .topTrailing) {
                VStack(spacing: 16) {
                    Spacer().frame(height: 20)

                    ZStack {
                        Circle()
                            .fill(.white.opacity(0.15))
                            .frame(width: 72, height: 72)
                        Image(systemName: "crown.fill")
                            .font(.system(size: 32))
                            .foregroundStyle(.white)
                    }

                    Text("Desbloqueie tudo")
                        .font(.system(size: 26, weight: .bold))
                        .foregroundStyle(.white)

                    Text("Acesse todas as funcionalidades do COFFEE")
                        .font(.system(size: 15))
                        .foregroundStyle(.white.opacity(0.7))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)

                    Spacer().frame(height: 16)
                }
                .frame(maxWidth: .infinity)
                .background(
                    LinearGradient(
                        colors: [Color.coffeePrimary, Color(hex: "4A3425")],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

                // Close button
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.7))
                        .frame(width: 32, height: 32)
                        .background(.white.opacity(0.15))
                        .clipShape(Circle())
                }
                .padding(.top, 16)
                .padding(.trailing, 16)
            }

            // Benefits + CTA
            VStack(spacing: 0) {
                ScrollView {
                    VStack(spacing: 20) {
                        ForEach(Array(benefits.enumerated()), id: \.offset) { _, item in
                            benefitRow(item)
                        }
                    }
                    .padding(.top, 28)
                    .padding(.horizontal, 24)
                }

                // Bottom CTA
                VStack(spacing: 14) {
                    // Price with strikethrough
                    HStack(spacing: 6) {
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

                    if subscription.hasUsedTrial {
                        // Already used trial — go to payment
                        CoffeeButton(
                            "Assinar Premium",
                            icon: "crown.fill"
                        ) {
                            showPayment = true
                        }
                    } else {
                        // First time — free trial (no card)
                        CoffeeButton(
                            "Começar 7 dias grátis",
                            icon: "crown.fill",
                            isLoading: isPurchasing
                        ) {
                            handleFreeTrial()
                        }

                        Text("Sem cartão de crédito necessário")
                            .font(.system(size: 12))
                            .foregroundStyle(Color.coffeeTextSecondary)
                    }

                    Button("Restaurar compras") {
                        Task {
                            await subscription.restorePurchases()
                            if subscription.isPremium {
                                dismiss()
                            }
                        }
                    }
                    .font(.system(size: 13))
                    .foregroundStyle(Color.coffeeTextSecondary)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 40)
                .padding(.top, 16)
            }
            .background(Color.coffeeBackground)
            .clipShape(
                UnevenRoundedRectangle(
                    topLeadingRadius: 24,
                    topTrailingRadius: 24,
                    style: .continuous
                )
            )
            .padding(.top, -12)
        }
        .background(Color.coffeeBackground.ignoresSafeArea(edges: .bottom))
        .background(
            LinearGradient(
                colors: [Color.coffeePrimary, Color(hex: "4A3425")],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
        )
        .sheet(isPresented: $showPayment) {
            if let plan = subscription.availablePlans.first {
                PaymentSheetView(plan: plan)
            }
        }
    }

    // MARK: - Benefit Row

    private func benefitRow(_ item: (icon: String, text: String, sub: String, color: Color)) -> some View {
        HStack(spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(item.color.opacity(0.1))
                    .frame(width: 48, height: 48)

                Image(systemName: item.icon)
                    .font(.system(size: 22))
                    .foregroundStyle(item.color)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(item.text)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Color.coffeeTextPrimary)

                Text(item.sub)
                    .font(.system(size: 14))
                    .foregroundStyle(Color.coffeeTextSecondary)
            }

            Spacer()

            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 20))
                .foregroundStyle(.green)
        }
    }

    // MARK: - Free Trial

    private func handleFreeTrial() {
        isPurchasing = true
        Task {
            await subscription.startFreeTrial()
            isPurchasing = false
            if subscription.isPremium {
                dismiss()
            }
        }
    }
}

// MARK: - Preview

#Preview {
    PremiumGateSheet()
        .environment(\.router, NavigationRouter())
        .environment(\.subscriptionService, SubscriptionService())
}
