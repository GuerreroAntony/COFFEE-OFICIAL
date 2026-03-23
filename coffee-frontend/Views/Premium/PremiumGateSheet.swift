import SwiftUI

// MARK: - Premium Gate Sheet
// Modal paywall — three plan cards with comparison table
// Shown when user taps upgrade from locked tabs or profile
// 7 dias grátis only available when Black is selected

struct PremiumGateSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.router) private var router
    @Environment(\.subscriptionService) private var subscription

    @State private var selectedPlanId: String = "black"
    @State private var isPurchasing = false
    @State private var isStartingTrial = false
    @State private var promoCode = ""
    @State private var showPromo = false
    @State private var codeStatus: CodeStatus? = nil

    enum CodeStatus { case valid, invalid }

    private let curtoColor = Color(hex: "6F4E37")
    private let leiteColor = Color(hex: "C4A882")
    private let blackColor = Color(hex: "1A1008")

    var body: some View {
        VStack(spacing: 0) {
            // Hero gradient
            ZStack(alignment: .topTrailing) {
                VStack(spacing: 16) {
                    Spacer().frame(height: 20)

                    Image("coffee-logo")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 72, height: 72)
                        .foregroundStyle(.white)

                    Text("Escolha seu café")
                        .font(.system(size: 26, weight: .bold))
                        .foregroundStyle(.white)

                    Text("Teste grátis por 7 dias com todas as funcionalidades")
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
                    VStack(spacing: 20) {
                        planCards
                            .padding(.top, 24)

                        comparisonTable
                            .padding(.horizontal, 16)

                        promoSection
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

    // MARK: - Plan Cards

    private var planCards: some View {
        HStack(spacing: 10) {
            miniCard(planId: "cafe_curto", name: "Curto", price: "29,90", originalPrice: "50,00", color: curtoColor)
            miniCard(planId: "cafe_com_leite", name: "c/ Leite", price: "49,90", originalPrice: "75,00", color: leiteColor)
            miniCard(planId: "black", name: "Black", price: "69,90", originalPrice: "100,00", color: blackColor, badge: "Completo")
        }
        .padding(.horizontal, 16)
    }

    private func miniCard(planId: String, name: String, price: String, originalPrice: String, color: Color, badge: String? = nil) -> some View {
        let isSelected = selectedPlanId == planId

        return Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                selectedPlanId = planId
            }
        } label: {
            VStack(spacing: 0) {
                if let badge {
                    HStack(spacing: 3) {
                        Image(systemName: "star.fill").font(.system(size: 7))
                        Text(badge).font(.system(size: 8, weight: .bold)).textCase(.uppercase)
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
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.top, 6)

                Spacer()

                // Price center
                VStack(spacing: 1) {
                    Text("R$\(originalPrice)")
                        .font(.system(size: 10))
                        .strikethrough()
                        .foregroundStyle(.white.opacity(0.5))

                    Text("R$\(price)")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.white)

                    Text("/mês")
                        .font(.system(size: 9))
                        .foregroundStyle(.white.opacity(0.7))
                }

                Spacer()

                Text("Lançamento")
                    .font(.system(size: 7, weight: .bold))
                    .textCase(.uppercase)
                    .tracking(0.5)
                    .foregroundStyle(.white.opacity(0.5))
                    .padding(.bottom, 8)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 140)
            .background(color)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(isSelected ? Color.white : .clear, lineWidth: 3)
            )
            .shadow(color: isSelected ? color.opacity(0.4) : .clear, radius: 8, y: 4)
            .scaleEffect(isSelected ? 1.03 : 1.0)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Comparison Table

    private var comparisonTable: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                Text("Funcionalidade")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.coffeeTextSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, 14)

                Text("Curto").font(.system(size: 10, weight: .bold)).foregroundStyle(curtoColor).frame(width: 48)
                Text("Leite").font(.system(size: 10, weight: .bold)).foregroundStyle(leiteColor).frame(width: 48)
                Text("Black").font(.system(size: 10, weight: .bold)).foregroundStyle(blackColor).frame(width: 48).padding(.trailing, 6)
            }
            .padding(.vertical, 10)
            .background(Color.coffeeTextSecondary.opacity(0.04))

            Divider()

            compRow("Gravar aulas", c: .limit("20h"), l: .limit("40h"), b: .unlimited)
            Divider().padding(.leading, 14)
            compRow("Resumo com IA", c: .yes, l: .yes, b: .yes)
            Divider().padding(.leading, 14)
            compRow("Slides automáticos", c: .yes, l: .yes, b: .yes)
            Divider().padding(.leading, 14)
            compRow("Barista IA", c: .no, l: .yes, b: .yesWith10X)
            Divider().padding(.leading, 14)
            compRow("Compartilhar", c: .no, l: .no, b: .yes)
            Divider().padding(.leading, 14)
            compRow("Calendário ESPM", c: .no, l: .no, b: .yes)
            Divider().padding(.leading, 14)
            compRow("Mapa mental", c: .no, l: .no, b: .yes)
        }
        .background(Color.coffeeCardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.coffeeSeparator, lineWidth: 0.5)
        )
    }

    private enum Val { case yes, no, limit(String), unlimited, yesWith10X }

    private func compRow(_ label: String, c: Val, l: Val, b: Val) -> some View {
        HStack(spacing: 0) {
            Text(label)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color.coffeeTextPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 14)

            valView(c).frame(width: 48)
            valView(l).frame(width: 48)
            valView(b).frame(width: 48).padding(.trailing, 6)
        }
        .padding(.vertical, 9)
    }

    @ViewBuilder
    private func valView(_ v: Val) -> some View {
        switch v {
        case .yes:
            Image(systemName: "checkmark.circle.fill").font(.system(size: 15)).foregroundStyle(.green)
        case .no:
            Image(systemName: "xmark.circle.fill").font(.system(size: 15)).foregroundStyle(.red.opacity(0.45))
        case .limit(let t):
            Text(t).font(.system(size: 9, weight: .bold)).foregroundStyle(Color.coffeePrimary)
                .padding(.horizontal, 5).padding(.vertical, 2)
                .background(Color.coffeePrimary.opacity(0.1)).clipShape(Capsule())
        case .unlimited:
            Image(systemName: "infinity").font(.system(size: 13, weight: .bold)).foregroundStyle(.green)
        case .yesWith10X:
            ZStack(alignment: .topTrailing) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 15))
                    .foregroundStyle(.green)

                Text("10X")
                    .font(.system(size: 6, weight: .black))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 3)
                    .padding(.vertical, 1)
                    .background(Color.coffeePrimary)
                    .clipShape(Capsule())
                    .offset(x: 8, y: -5)
            }
        }
    }

    // MARK: - Promo Section

    @ViewBuilder
    private var promoSection: some View {
        if codeStatus == .valid {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                Text("Código aplicado!").font(.system(size: 14, weight: .semibold)).foregroundStyle(.green)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(Color.green.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

        } else if showPromo {
            VStack(spacing: 12) {
                HStack {
                    Text("Código promocional")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.coffeeTextPrimary)
                    Spacer()
                    Button { withAnimation { showPromo = false } } label: {
                        Image(systemName: "xmark").font(.system(size: 14)).foregroundStyle(Color.coffeeTextSecondary)
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

                    Button("Aplicar") { handleApplyCode() }
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 11)
                        .background(Color.coffeePrimary)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .opacity(promoCode.trimmingCharacters(in: .whitespaces).isEmpty ? 0.35 : 1)
                }

                if codeStatus == .invalid {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.circle.fill").font(.system(size: 13))
                        Text("Código inválido.").font(.system(size: 13, weight: .medium))
                    }
                    .foregroundStyle(.red)
                }
            }
            .padding(14)
            .background(Color.coffeeTextSecondary.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

        } else {
            Button {
                withAnimation { showPromo = true }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "ticket.fill").font(.system(size: 14))
                    Text("Tem um código promocional?").font(.system(size: 14, weight: .semibold))
                }
                .foregroundStyle(Color.coffeePrimary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(Color.coffeePrimary.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Bottom CTA

    private var bottomCTA: some View {
        let isBlackSelected = selectedPlanId == "black"

        return VStack(spacing: 10) {
            if isBlackSelected {
                // Black — trial CTA
                Button {
                    handleFreeTrial()
                } label: {
                    HStack(spacing: 10) {
                        if isStartingTrial {
                            ProgressView().tint(.white)
                        } else {
                            Image(systemName: "gift.fill").font(.system(size: 16))
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

                Text("Acesso completo ao plano Black.")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.coffeeTextSecondary)
            } else {
                // Curto / Leite — subscribe CTA
                let planName = selectedPlanId == "cafe_curto" ? "Curto" : "c/ Leite"
                let planPrice = selectedPlanId == "cafe_curto" ? "R$29,90" : "R$49,90"

                Button {
                    handlePurchase()
                } label: {
                    HStack(spacing: 10) {
                        if isPurchasing {
                            ProgressView().tint(.white)
                        } else {
                            Image(systemName: "cup.and.saucer.fill").font(.system(size: 16))
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

                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { selectedPlanId = "black" }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "gift.fill").font(.system(size: 12))
                        Text("Ou teste o Black grátis por 7 dias")
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .foregroundStyle(Color.coffeePrimary)
                }
                .buttonStyle(.plain)
            }

            // Restaurar compras removido
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 40)
        .padding(.top, 16)
    }

    // MARK: - Actions

    private func handleFreeTrial() {
        isStartingTrial = true
        Task {
            let _ = try? await subscription.startFreeTrial()
            isStartingTrial = false
            if subscription.isPremium { dismiss() }
        }
    }

    private func handlePurchase() {
        guard let plan = subscription.availablePlans.first(where: { $0.planId == selectedPlanId }) else { return }
        isPurchasing = true
        Task {
            let _ = try? await subscription.purchase(plan: plan)
            isPurchasing = false
            if subscription.isPremium { dismiss() }
        }
    }

    private func handleApplyCode() {
        let code = promoCode.trimmingCharacters(in: .whitespaces).uppercased()
        guard !code.isEmpty else { return }
        Task {
            do {
                let response = try await subscription.validateGiftCode(code)
                withAnimation {
                    codeStatus = response.valid ? .valid : .invalid
                }
            } catch {
                withAnimation { codeStatus = .invalid }
            }
        }
    }
}

#Preview {
    PremiumGateSheet()
        .environment(\.router, NavigationRouter())
        .environment(\.subscriptionService, SubscriptionService())
}
