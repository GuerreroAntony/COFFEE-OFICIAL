import SwiftUI

// MARK: - Premium Offer Screen (Two-Plan Paywall)
// Two plan cards: Café com Leite + Black
// Trial as surprise CTA ("7 dias grátis") linked to Café com Leite
// Persuasive but not cheap — intentional, assertive copy

struct PremiumOfferScreenView: View {
    @Environment(\.router) private var router
    @Environment(\.subscriptionService) private var subscription

    @State private var selectedPlanId: String = "black"
    @State private var isStartingTrial = false
    @State private var isPurchasing = false
    @State private var promoCode = ""
    @State private var codeStatus: CodeStatus? = nil
    @State private var trialDays = 7
    @State private var showPromo = false

    enum CodeStatus { case valid, invalid }

    var body: some View {
        VStack(spacing: 0) {
            // Hero gradient area
            heroSection

            // Content + CTA
            VStack(spacing: 0) {
                ScrollView {
                    VStack(spacing: 20) {
                        // Plan cards
                        planCardsSection
                            .padding(.top, 24)

                        // Selected plan features
                        selectedPlanFeatures
                            .padding(.horizontal, 20)

                        // Promo code
                        promoCodeSection
                            .padding(.horizontal, 20)
                    }
                }

                // Bottom CTA area
                bottomCTA
            }
            .background(Color.coffeeBackground)
            .clipShape(
                UnevenRoundedRectangle(
                    topLeadingRadius: 28,
                    topTrailingRadius: 28,
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

    // MARK: - Hero Section

    private var heroSection: some View {
        VStack(spacing: 0) {
            Spacer().frame(height: 52)

            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(.white.opacity(0.15))
                    .frame(width: 56, height: 56)

                Image(systemName: "cup.and.saucer.fill")
                    .font(.system(size: 26))
                    .foregroundStyle(.white)
            }
            .padding(.bottom, 12)

            Text("Escolha seu café")
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(.white)
                .padding(.bottom, 4)

            Text("Dois planos, um propósito: suas notas perfeitas")
                .font(.system(size: 14))
                .foregroundStyle(.white.opacity(0.7))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            Spacer().frame(height: 24)
        }
        .frame(maxWidth: .infinity)
        .background(
            LinearGradient(
                colors: [Color.coffeePrimary, Color(hex: "4A3425")],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }

    // MARK: - Plan Cards Section

    private var planCardsSection: some View {
        HStack(spacing: 12) {
            if let cafe = subscription.cafeComLeitePlan {
                planCard(cafe)
            }
            if let black = subscription.blackPlan {
                planCard(black)
            }
        }
        .padding(.horizontal, 16)
    }

    // MARK: - Single Plan Card

    private func planCard(_ plan: SubscriptionPlan) -> some View {
        let isSelected = selectedPlanId == plan.planId
        let isBlack = plan.planId == "black"

        return Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                selectedPlanId = plan.planId
            }
        } label: {
            VStack(spacing: 0) {
                // Badge ribbon
                if plan.isHighlighted {
                    HStack(spacing: 4) {
                        Image(systemName: "star.fill")
                            .font(.system(size: 9))
                        Text("Mais Popular")
                            .font(.system(size: 10, weight: .bold))
                            .textCase(.uppercase)
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .frame(maxWidth: .infinity)
                    .background(isBlack ? Color(hex: "1A1008") : Color.coffeePrimary)
                } else if let badge = plan.badge {
                    Text(badge)
                        .font(.system(size: 10, weight: .bold))
                        .textCase(.uppercase)
                        .foregroundStyle(Color.coffeePrimary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .frame(maxWidth: .infinity)
                        .background(Color.coffeePrimary.opacity(0.1))
                }

                VStack(spacing: 10) {
                    // Plan icon
                    ZStack {
                        Circle()
                            .fill(isBlack
                                ? Color(hex: "1A1008").opacity(0.1)
                                : Color.coffeePrimary.opacity(0.1)
                            )
                            .frame(width: 44, height: 44)

                        Image(systemName: isBlack ? "flame.fill" : "cup.and.saucer.fill")
                            .font(.system(size: 20))
                            .foregroundStyle(isBlack ? Color(hex: "1A1008") : Color.coffeePrimary)
                    }

                    // Plan name
                    Text(plan.name)
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(Color.coffeeTextPrimary)

                    // Pricing
                    VStack(spacing: 2) {
                        if let original = plan.originalPrice {
                            Text("R$\(String(format: "%.2f", original))")
                                .font(.system(size: 12))
                                .strikethrough()
                                .foregroundStyle(Color.coffeeTextSecondary.opacity(0.6))
                        }

                        HStack(spacing: 0) {
                            Text("R$\(String(format: "%.2f", plan.price))")
                                .font(.system(size: 20, weight: .bold))
                                .foregroundStyle(isBlack ? Color(hex: "1A1008") : Color.coffeePrimary)
                            Text("/mês")
                                .font(.system(size: 12))
                                .foregroundStyle(Color.coffeeTextSecondary)
                        }
                    }

                    // Key differentiator
                    Text(isBlack ? "Espresso ilimitado" : "Todas as funções")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(isBlack ? Color(hex: "1A1008").opacity(0.7) : Color.coffeePrimary.opacity(0.7))
                }
                .padding(.vertical, 16)
                .padding(.horizontal, 12)
            }
            .frame(maxWidth: .infinity)
            .background(Color.coffeeCardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(
                        isSelected
                            ? (isBlack ? Color(hex: "1A1008") : Color.coffeePrimary)
                            : Color.coffeeSeparator,
                        lineWidth: isSelected ? 2.5 : 1
                    )
            )
            .shadow(
                color: isSelected ? (isBlack ? Color(hex: "1A1008").opacity(0.15) : Color.coffeePrimary.opacity(0.15)) : .clear,
                radius: 8, y: 4
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Selected Plan Features

    private var selectedPlanFeatures: some View {
        let plan = subscription.availablePlans.first { $0.planId == selectedPlanId }
            ?? subscription.availablePlans[0]

        return VStack(spacing: 0) {
            HStack {
                Text("O que você recebe")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.coffeeTextPrimary)
                Spacer()
            }
            .padding(.bottom, 12)

            VStack(spacing: 0) {
                ForEach(Array(plan.features.enumerated()), id: \.offset) { index, feature in
                    HStack(spacing: 12) {
                        Image(systemName: feature.included ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .font(.system(size: 16))
                            .foregroundStyle(feature.included ? .green : Color.coffeeTextSecondary.opacity(0.3))

                        Text(feature.text)
                            .font(.system(size: 14))
                            .foregroundStyle(Color.coffeeTextPrimary)

                        Spacer()

                        if let detail = feature.detail {
                            Text(detail)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(
                                    detail == "Ilimitado"
                                        ? Color(hex: "1A1008")
                                        : Color.coffeeTextSecondary
                                )
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(
                                    detail == "Ilimitado"
                                        ? Color(hex: "1A1008").opacity(0.08)
                                        : Color.coffeeTextSecondary.opacity(0.08)
                                )
                                .clipShape(Capsule())
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)

                    if index < plan.features.count - 1 {
                        Divider().padding(.leading, 44)
                    }
                }
            }
            .background(Color.coffeeCardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }

    // MARK: - Bottom CTA

    private var bottomCTA: some View {
        let isBlack = selectedPlanId == "black"
        let plan = subscription.availablePlans.first { $0.planId == selectedPlanId }
            ?? subscription.availablePlans[0]

        return VStack(spacing: 12) {
            // Main CTA — subscribe to selected plan
            CoffeeButton(
                "Assinar \(plan.name)",
                icon: isBlack ? "flame.fill" : "cup.and.saucer.fill",
                isLoading: isPurchasing
            ) {
                handlePurchase(plan)
            }

            // Trial CTA — surprise "7 dias grátis" linked to Café com Leite
            if !subscription.hasUsedTrial {
                Button {
                    handleStartTrial()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "gift.fill")
                            .font(.system(size: 13))
                        Text("Ou experimente \(trialDays) dias grátis")
                            .font(.system(size: 14, weight: .semibold))
                    }
                    .foregroundStyle(Color.coffeePrimary)
                }
                .buttonStyle(.plain)
                .disabled(isStartingTrial)
                .opacity(isStartingTrial ? 0.5 : 1)

                Text("Sem cartão. Limites do Café com Leite.")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.coffeeTextTertiary)
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 48)
        .padding(.top, 16)
    }

    // MARK: - Promo Code Section

    @ViewBuilder
    private var promoCodeSection: some View {
        if codeStatus == .valid {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text("Código aplicado! Trial de \(trialDays) dias.")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.green)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .transition(.opacity)

        } else if showPromo {
            VStack(spacing: 12) {
                HStack {
                    Text("Código promocional")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color.coffeeTextPrimary)
                    Spacer()
                    Button {
                        withAnimation { showPromo = false }
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 16))
                            .foregroundStyle(Color.coffeeTextSecondary)
                    }
                }

                HStack(spacing: 10) {
                    TextField("Digite o código", text: $promoCode)
                        .font(.system(size: 16))
                        .textInputAutocapitalization(.characters)
                        .tint(Color.coffeePrimary)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .background(Color.coffeeCardBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                    Button("Aplicar") {
                        handleApplyCode()
                    }
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .background(Color.coffeePrimary)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .opacity(promoCode.trimmingCharacters(in: .whitespaces).isEmpty ? 0.35 : 1)
                }

                if codeStatus == .invalid {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.circle.fill")
                            .font(.system(size: 13))
                            .foregroundStyle(.red)
                        Text("Código inválido. Tente novamente.")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.red)
                    }
                }
            }
            .padding(20)
            .background(Color.coffeeTextSecondary.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .transition(.opacity.combined(with: .move(edge: .bottom)))

        } else {
            Button {
                withAnimation { showPromo = true }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "ticket.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(Color.coffeePrimary)
                    Text("Tem um código? Ganhe +7 dias")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color.coffeePrimary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Color.coffeeTextSecondary.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Actions

    private func handlePurchase(_ plan: SubscriptionPlan) {
        isPurchasing = true
        Task {
            let _ = try? await subscription.purchase(plan: plan)
            isPurchasing = false
            if let user = router.currentUser {
                router.login(user: user)
            }
        }
    }

    private func handleStartTrial() {
        isStartingTrial = true
        Task {
            await subscription.startFreeTrial()
            isStartingTrial = false
            if let user = router.currentUser {
                router.login(user: user)
            }
        }
    }

    private func handleApplyCode() {
        let code = promoCode.trimmingCharacters(in: .whitespaces).uppercased()
        guard !code.isEmpty else { return }

        let validCodes = ["COFFEE2026", "ESPM", "BARISTA", "AMIGO"]
        if validCodes.contains(code) {
            withAnimation {
                codeStatus = .valid
                trialDays = 14
            }
        } else {
            withAnimation {
                codeStatus = .invalid
            }
        }
    }
}

#Preview {
    PremiumOfferScreenView()
        .environment(\.router, NavigationRouter())
        .environment(\.subscriptionService, SubscriptionService())
}
