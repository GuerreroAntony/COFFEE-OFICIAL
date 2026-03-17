import SwiftUI

// MARK: - Premium Gate Sheet
// Modal paywall — two plan cards (Café com Leite + Black)
// Shown when user taps upgrade from locked tabs or profile

struct PremiumGateSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.router) private var router
    @Environment(\.subscriptionService) private var subscription

    @State private var selectedPlanId: String = "black"
    @State private var isPurchasing = false
    @State private var isStartingTrial = false

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
                        Image(systemName: "cup.and.saucer.fill")
                            .font(.system(size: 32))
                            .foregroundStyle(.white)
                    }

                    Text("Escolha seu café")
                        .font(.system(size: 26, weight: .bold))
                        .foregroundStyle(.white)

                    Text("Desbloqueie todas as funcionalidades do Coffee")
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

            // Plans + CTA
            VStack(spacing: 0) {
                ScrollView {
                    VStack(spacing: 16) {
                        // Plan cards side by side
                        planCardsCompact
                            .padding(.top, 24)

                        // Quick feature comparison
                        quickComparison
                            .padding(.horizontal, 20)
                    }
                }

                // Bottom CTA
                VStack(spacing: 10) {
                    let plan = subscription.availablePlans.first { $0.planId == selectedPlanId }
                        ?? subscription.availablePlans[0]
                    let isBlack = selectedPlanId == "black"

                    CoffeeButton(
                        "Assinar \(plan.name)",
                        icon: isBlack ? "flame.fill" : "cup.and.saucer.fill",
                        isLoading: isPurchasing
                    ) {
                        handlePurchase(plan)
                    }

                    if !subscription.hasUsedTrial {
                        Button {
                            handleFreeTrial()
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "gift.fill")
                                    .font(.system(size: 13))
                                Text("Ou experimente 7 dias grátis")
                                    .font(.system(size: 14, weight: .semibold))
                            }
                            .foregroundStyle(Color.coffeePrimary)
                        }
                        .buttonStyle(.plain)
                        .disabled(isStartingTrial)

                        Text("Sem cartão. Limites do Café com Leite.")
                            .font(.system(size: 11))
                            .foregroundStyle(Color.coffeeTextTertiary)
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
    }

    // MARK: - Compact Plan Cards

    private var planCardsCompact: some View {
        HStack(spacing: 10) {
            ForEach(subscription.availablePlans, id: \.id) { plan in
                compactCard(plan)
            }
        }
        .padding(.horizontal, 16)
    }

    private func compactCard(_ plan: SubscriptionPlan) -> some View {
        let isSelected = selectedPlanId == plan.planId
        let isBlack = plan.planId == "black"
        let accent = isBlack ? Color(hex: "1A1008") : Color.coffeePrimary

        return Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                selectedPlanId = plan.planId
            }
        } label: {
            VStack(spacing: 8) {
                // Badge
                if plan.isHighlighted {
                    HStack(spacing: 3) {
                        Image(systemName: "star.fill")
                            .font(.system(size: 8))
                        Text("Mais Popular")
                            .font(.system(size: 9, weight: .bold))
                            .textCase(.uppercase)
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(accent)
                    .clipShape(Capsule())
                } else {
                    Spacer().frame(height: 16)
                }

                // Icon
                Image(systemName: isBlack ? "flame.fill" : "cup.and.saucer.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(accent)

                // Name
                Text(plan.name)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Color.coffeeTextPrimary)

                // Price
                VStack(spacing: 1) {
                    if let original = plan.originalPrice {
                        Text("R$\(String(format: "%.2f", original))")
                            .font(.system(size: 11))
                            .strikethrough()
                            .foregroundStyle(Color.coffeeTextSecondary.opacity(0.5))
                    }
                    HStack(spacing: 0) {
                        Text("R$\(String(format: "%.2f", plan.price))")
                            .font(.system(size: 17, weight: .bold))
                            .foregroundStyle(accent)
                        Text("/mês")
                            .font(.system(size: 10))
                            .foregroundStyle(Color.coffeeTextSecondary)
                    }
                }
            }
            .padding(.vertical, 14)
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity)
            .background(Color.coffeeCardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(isSelected ? accent : Color.coffeeSeparator, lineWidth: isSelected ? 2.5 : 1)
            )
            .shadow(color: isSelected ? accent.opacity(0.12) : .clear, radius: 6, y: 3)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Quick Comparison

    private var quickComparison: some View {
        VStack(spacing: 0) {
            comparisonRow("Espresso", cafe: "75/mês", black: "Ilimitado")
            Divider().padding(.leading, 16)
            comparisonRow("Lungo", cafe: "30/mês", black: "100/mês")
            Divider().padding(.leading, 16)
            comparisonRow("Cold Brew", cafe: "15/mês", black: "25/mês")
            Divider().padding(.leading, 16)
            comparisonRow("Gift codes", cafe: "2", black: "3")
        }
        .background(Color.coffeeCardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func comparisonRow(_ label: String, cafe: String, black: String) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color.coffeeTextPrimary)
                .frame(width: 80, alignment: .leading)

            Spacer()

            Text(cafe)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color.coffeeTextSecondary)
                .frame(width: 70)

            Text(black)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(
                    black == "Ilimitado" ? Color(hex: "1A1008") : Color.coffeeTextPrimary
                )
                .frame(width: 70)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    // MARK: - Actions

    private func handlePurchase(_ plan: SubscriptionPlan) {
        isPurchasing = true
        Task {
            let _ = try? await subscription.purchase(plan: plan)
            isPurchasing = false
            if subscription.isPremium {
                dismiss()
            }
        }
    }

    private func handleFreeTrial() {
        isStartingTrial = true
        Task {
            await subscription.startFreeTrial()
            isStartingTrial = false
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
