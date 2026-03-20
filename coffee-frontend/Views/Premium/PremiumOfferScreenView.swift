import SwiftUI

// MARK: - Premium Offer Screen (Three-Plan Paywall)
// Three plan cards: Curto (brown) + c/ Leite (beige) + Black (black)
// Comparison table below with green checkmarks and red X icons
// Promo code section + "Testar 7 dias grátis" CTA (Black trial only)

struct PremiumOfferScreenView: View {
    @Environment(\.router) private var router
    @Environment(\.subscriptionService) private var subscription

    @State private var selectedPlanId: String = "black"
    @State private var isStartingTrial = false
    @State private var isPurchasing = false
    @State private var promoCode = ""
    @State private var codeStatus: CodeStatus? = nil
    @State private var showPromo = false

    enum CodeStatus { case valid, invalid }

    // Plan colors
    private let curtoColor = Color(hex: "6F4E37")      // Brown
    private let leiteColor = Color(hex: "C4A882")       // Beige
    private let blackColor = Color(hex: "1A1008")       // Near-black

    var body: some View {
        VStack(spacing: 0) {
            heroSection

            VStack(spacing: 0) {
                ScrollView {
                    VStack(spacing: 24) {
                        // 3 plan cards
                        planCardsSection
                            .padding(.top, 24)

                        // Comparison table
                        comparisonTable
                            .padding(.horizontal, 16)

                        // Promo code
                        promoCodeSection
                            .padding(.horizontal, 16)

                        Spacer().frame(height: 8)
                    }
                }

                // Bottom CTA
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

            Text("Teste grátis por 7 dias com todas as funcionalidades")
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

    // MARK: - Plan Cards Section (3 horizontal cards)

    private var planCardsSection: some View {
        HStack(spacing: 10) {
            planCard(
                planId: "cafe_curto",
                name: "Curto",
                price: "29,90",
                originalPrice: "50,00",
                color: curtoColor
            )

            planCard(
                planId: "cafe_com_leite",
                name: "c/ Leite",
                price: "49,90",
                originalPrice: "75,00",
                color: leiteColor
            )

            planCard(
                planId: "black",
                name: "Black",
                price: "69,90",
                originalPrice: "100,00",
                color: blackColor,
                badge: "Completo"
            )
        }
        .padding(.horizontal, 16)
    }

    private func planCard(planId: String, name: String, price: String, originalPrice: String, color: Color, badge: String? = nil) -> some View {
        let isSelected = selectedPlanId == planId

        return Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                selectedPlanId = planId
            }
        } label: {
            VStack(spacing: 0) {
                // Badge
                if let badge {
                    HStack(spacing: 3) {
                        Image(systemName: "star.fill")
                            .font(.system(size: 7))
                        Text(badge)
                            .font(.system(size: 8, weight: .bold))
                            .textCase(.uppercase)
                    }
                    .foregroundStyle(color)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(.white)
                    .clipShape(Capsule())
                    .padding(.top, 8)
                } else {
                    Spacer().frame(height: 22)
                }

                // Name at top
                Text(name)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.top, 8)

                Spacer()

                // Price center
                VStack(spacing: 2) {
                    // Original price (strikethrough)
                    Text("R$\(originalPrice)")
                        .font(.system(size: 11))
                        .strikethrough()
                        .foregroundStyle(.white.opacity(0.5))

                    Text("R$\(price)")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(.white)

                    Text("/mês")
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.7))
                }

                Spacer()

                // Promo label
                Text("Lançamento")
                    .font(.system(size: 8, weight: .bold))
                    .textCase(.uppercase)
                    .tracking(0.5)
                    .foregroundStyle(.white.opacity(0.5))
                    .padding(.bottom, 10)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 150)
            .background(color)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(isSelected ? Color.white : .clear, lineWidth: 3)
            )
            .shadow(
                color: isSelected ? color.opacity(0.4) : .clear,
                radius: 10, y: 4
            )
            .scaleEffect(isSelected ? 1.03 : 1.0)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Comparison Table

    private var comparisonTable: some View {
        VStack(spacing: 0) {
            // Header row
            HStack(spacing: 0) {
                Text("Funcionalidade")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.coffeeTextSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, 16)

                Text("Curto")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(curtoColor)
                    .frame(width: 52)

                Text("Leite")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(leiteColor)
                    .frame(width: 52)

                Text("Black")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(blackColor)
                    .frame(width: 52)
                    .padding(.trailing, 8)
            }
            .padding(.vertical, 12)
            .background(Color.coffeeTextSecondary.opacity(0.04))

            Divider()

            // Feature rows
            featureRow("Gravar aulas", curto: .limit("20h"), leite: .limit("40h"), black: .unlimited)
            Divider().padding(.leading, 16)
            featureRow("Resumo com IA", curto: .check, leite: .check, black: .check)
            Divider().padding(.leading, 16)
            featureRow("Slides automáticos", curto: .check, leite: .check, black: .check)
            Divider().padding(.leading, 16)
            featureRow("Barista IA", curto: .no, leite: .check, black: .checkWith10X)
            Divider().padding(.leading, 16)
            featureRow("Compartilhar", curto: .no, leite: .no, black: .check)
            Divider().padding(.leading, 16)
            featureRow("Calendário ESPM", curto: .no, leite: .no, black: .check)
            Divider().padding(.leading, 16)
            featureRow("Mapa mental", curto: .no, leite: .no, black: .check)
        }
        .background(Color.coffeeCardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.coffeeSeparator, lineWidth: 0.5)
        )
    }

    enum FeatureValue {
        case check
        case no
        case limit(String)
        case unlimited
        case checkWith10X
    }

    private func featureRow(_ label: String, curto: FeatureValue, leite: FeatureValue, black: FeatureValue) -> some View {
        HStack(spacing: 0) {
            Text(label)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color.coffeeTextPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 16)

            featureIcon(curto)
                .frame(width: 52)
            featureIcon(leite)
                .frame(width: 52)
            featureIcon(black)
                .frame(width: 52)
                .padding(.trailing, 8)
        }
        .padding(.vertical, 11)
    }

    @ViewBuilder
    private func featureIcon(_ value: FeatureValue) -> some View {
        switch value {
        case .check:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 16))
                .foregroundStyle(.green)

        case .no:
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 16))
                .foregroundStyle(.red.opacity(0.5))

        case .limit(let text):
            Text(text)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(Color.coffeePrimary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.coffeePrimary.opacity(0.1))
                .clipShape(Capsule())

        case .unlimited:
            Image(systemName: "infinity")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(.green)

        case .checkWith10X:
            // Green check with "10X" badge at top-right like a notification
            ZStack(alignment: .topTrailing) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(.green)

                Text("10X")
                    .font(.system(size: 7, weight: .black))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 3)
                    .padding(.vertical, 1)
                    .background(Color.coffeePrimary)
                    .clipShape(Capsule())
                    .offset(x: 8, y: -6)
            }
        }
    }

    // MARK: - Promo Code Section

    @ViewBuilder
    private var promoCodeSection: some View {
        if codeStatus == .valid {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text("Código aplicado!")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.green)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(Color.green.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
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
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(Color.coffeeTextSecondary)
                    }
                }

                HStack(spacing: 10) {
                    TextField("Digite o código", text: $promoCode)
                        .font(.system(size: 15))
                        .textInputAutocapitalization(.characters)
                        .tint(Color.coffeePrimary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 11)
                        .background(Color.coffeeInputBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                    Button("Aplicar") {
                        handleApplyCode()
                    }
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 11)
                    .background(Color.coffeePrimary)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .opacity(promoCode.trimmingCharacters(in: .whitespaces).isEmpty ? 0.35 : 1)
                }

                if codeStatus == .invalid {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.circle.fill")
                            .font(.system(size: 13))
                        Text("Código inválido. Tente novamente.")
                            .font(.system(size: 13, weight: .medium))
                    }
                    .foregroundStyle(.red)
                }
            }
            .padding(16)
            .background(Color.coffeeTextSecondary.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .transition(.opacity.combined(with: .move(edge: .bottom)))

        } else {
            Button {
                withAnimation { showPromo = true }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "ticket.fill")
                        .font(.system(size: 14))
                    Text("Tem um código promocional?")
                        .font(.system(size: 14, weight: .semibold))
                }
                .foregroundStyle(Color.coffeePrimary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Color.coffeePrimary.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Bottom CTA

    private var bottomCTA: some View {
        let isBlackSelected = selectedPlanId == "black"

        return VStack(spacing: 12) {
            if isBlackSelected {
                // Black selected — show trial CTA
                Button {
                    handleStartTrial()
                } label: {
                    HStack(spacing: 10) {
                        if isStartingTrial {
                            ProgressView().tint(.white)
                        } else {
                            Image(systemName: "gift.fill")
                                .font(.system(size: 16))
                        }
                        Text("Testar 7 dias grátis")
                            .font(.system(size: 17, weight: .bold))
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(
                        LinearGradient(
                            colors: [Color.coffeePrimary, Color(hex: "5A3E2B")],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .shadow(color: Color.coffeePrimary.opacity(0.3), radius: 8, y: 4)
                }
                .buttonStyle(.plain)
                .disabled(isStartingTrial)

                Text("Acesso completo ao plano Black. Sem cartão.")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.coffeeTextSecondary)
            } else {
                // Curto or Leite selected — show subscribe CTA
                let planName = selectedPlanId == "cafe_curto" ? "Curto" : "c/ Leite"
                let planPrice = selectedPlanId == "cafe_curto" ? "R$29,90" : "R$49,90"

                Button {
                    handlePurchase()
                } label: {
                    HStack(spacing: 10) {
                        if isPurchasing {
                            ProgressView().tint(.white)
                        } else {
                            Image(systemName: "cup.and.saucer.fill")
                                .font(.system(size: 16))
                        }
                        Text("Assinar \(planName) · \(planPrice)/mês")
                            .font(.system(size: 16, weight: .bold))
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(
                        LinearGradient(
                            colors: [Color.coffeePrimary, Color(hex: "5A3E2B")],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .shadow(color: Color.coffeePrimary.opacity(0.3), radius: 8, y: 4)
                }
                .buttonStyle(.plain)
                .disabled(isPurchasing)

                // Hint to try Black
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        selectedPlanId = "black"
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "gift.fill")
                            .font(.system(size: 12))
                        Text("Ou teste o Black grátis por 7 dias")
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .foregroundStyle(Color.coffeePrimary)
                }
                .buttonStyle(.plain)
            }

            // Restore purchases
            Button("Restaurar compras") {
                Task {
                    await subscription.restorePurchases()
                    if subscription.isPremium {
                        if let user = router.currentUser {
                            router.login(user: user)
                        }
                    }
                }
            }
            .font(.system(size: 13))
            .foregroundStyle(Color.coffeeTextSecondary)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 48)
        .padding(.top, 16)
    }

    // MARK: - Actions

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

    private func handlePurchase() {
        guard let plan = subscription.availablePlans.first(where: { $0.planId == selectedPlanId }) else { return }
        isPurchasing = true
        Task {
            let _ = try? await subscription.purchase(plan: plan)
            isPurchasing = false
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
            withAnimation { codeStatus = .valid }
        } else {
            withAnimation { codeStatus = .invalid }
        }
    }
}

#Preview {
    PremiumOfferScreenView()
        .environment(\.router, NavigationRouter())
        .environment(\.subscriptionService, SubscriptionService())
}
