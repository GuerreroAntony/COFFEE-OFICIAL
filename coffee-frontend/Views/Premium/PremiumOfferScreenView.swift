import SwiftUI

// MARK: - Premium Offer Screen
// Gradient hero + benefits list + promo code + CTA
// Matches PremiumOffer.jsx

struct PremiumOfferScreenView: View {
    @Environment(\.router) private var router
    @Environment(\.subscriptionService) private var subscription

    @State private var isStartingTrial = false
    @State private var promoCode = ""
    @State private var codeStatus: CodeStatus? = nil
    @State private var trialDays = 7
    @State private var showPromo = false

    enum CodeStatus { case valid, invalid }

    private let benefits: [(icon: String, text: String, sub: String, color: Color, bg: Color)] = [
        ("infinity", "Aulas ilimitadas", "Sem limite mensal", .green, .green.opacity(0.1)),
        (CoffeeIcon.sparkles, "IA sem limites", "Perguntas ilimitadas ao Barista", Color.coffeePrimary, Color.coffeePrimary.opacity(0.08)),
        ("doc.text.fill", "IA nos materiais", "Resumos e análises automáticas", .blue, .blue.opacity(0.1)),
        ("doc.richtext", "Exportar PDF", "Baixe seus resumos e notas", .orange, .orange.opacity(0.1)),
    ]

    private var isExpanded: Bool {
        showPromo && codeStatus != .valid
    }

    var body: some View {
        VStack(spacing: 0) {
            // Hero gradient area
            VStack(spacing: 0) {
                Spacer().frame(height: 56)

                ZStack {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(.white.opacity(0.15))
                        .frame(width: 56, height: 56)

                    Image(systemName: CoffeeIcon.sparkles)
                        .font(.system(size: 28))
                        .foregroundStyle(.white)
                }
                .padding(.bottom, 12)

                Text("Desbloqueie tudo")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.bottom, 4)

                HStack(spacing: 4) {
                    Text("\(trialDays) dias grátis")
                        .fontWeight(.bold)
                        .foregroundStyle(.white)
                    Text("· Cancele quando quiser")
                        .foregroundStyle(.white.opacity(0.7))
                }
                .font(.system(size: 14))

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

            // White card area
            VStack(spacing: 0) {
                ScrollView {
                    VStack(spacing: 0) {
                        // Benefits
                        VStack(spacing: isExpanded ? 22 : 28) {
                            ForEach(Array(benefits.enumerated()), id: \.offset) { _, item in
                                benefitRow(item)
                            }
                        }
                        .padding(.top, 28)
                        .padding(.horizontal, 24)
                        .animation(.easeInOut(duration: 0.3), value: isExpanded)

                        // Promo code area
                        promoCodeSection
                            .padding(.horizontal, 24)
                            .padding(.top, 20)
                    }
                }

                // Bottom CTA
                VStack(spacing: 16) {
                    HStack(spacing: 6) {
                        Text("Após o trial:")
                            .foregroundStyle(Color.coffeeTextSecondary)
                        Text("R$59,90")
                            .strikethrough()
                            .foregroundStyle(Color.coffeeTextSecondary)
                        Text("R$29,90/mês")
                            .fontWeight(.bold)
                            .foregroundStyle(Color.coffeeTextPrimary)
                    }
                    .font(.system(size: 13))

                    Text("Sem cartão de crédito necessário")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.coffeeTextSecondary)

                    CoffeeButton("Começar \(trialDays) dias grátis", icon: "crown.fill", isLoading: isStartingTrial) {
                        handleStartTrial()
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 48)
                .padding(.top, 16)
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

    // MARK: - Benefit Row

    private func benefitRow(_ item: (icon: String, text: String, sub: String, color: Color, bg: Color)) -> some View {
        HStack(spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(item.bg)
                    .frame(width: isExpanded ? 40 : 48, height: isExpanded ? 40 : 48)

                Image(systemName: item.icon)
                    .font(.system(size: isExpanded ? 18 : 22))
                    .foregroundStyle(item.color)
            }
            .animation(.easeInOut(duration: 0.3), value: isExpanded)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.text)
                    .font(.system(size: isExpanded ? 15 : 17, weight: .semibold))
                    .foregroundStyle(Color.coffeeTextPrimary)

                Text(item.sub)
                    .font(.system(size: isExpanded ? 12 : 14))
                    .foregroundStyle(Color.coffeeTextSecondary)
            }
            .animation(.easeInOut(duration: 0.3), value: isExpanded)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Promo Code Section

    @ViewBuilder
    private var promoCodeSection: some View {
        if codeStatus == .valid {
            // Success
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
            // Expanded promo input
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
            // Collapsed button
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

        if MockData.validPromoCodes.contains(code) {
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
