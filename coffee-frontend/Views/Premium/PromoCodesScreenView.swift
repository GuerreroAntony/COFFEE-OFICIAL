import SwiftUI

// MARK: - Promo Codes Screen
// Shows user's gift codes (to share) + field to redeem a promo code
// Reuses: SubscriptionService.getGiftCodes(), redeemGiftCode(), GiftCode model

struct PromoCodesScreenView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.subscriptionService) private var subscriptionService

    // Gift codes
    @State private var giftCodes: [GiftCode] = []
    @State private var isLoading = true
    @State private var shareMessage: String? = nil

    // Redeem
    @State private var inputCode = ""
    @State private var isRedeeming = false
    @State private var redeemSuccess: Bool? = nil
    @State private var redeemMessage = ""

    // Copy feedback
    @State private var copiedCode: String? = nil

    var body: some View {
        VStack(spacing: 0) {
            CoffeeSheetHeader(title: "Códigos Promocionais", onClose: { dismiss() })

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // MARK: - My Codes Section
                    myCodesSection

                    // Divider
                    Rectangle()
                        .fill(Color.coffeeSeparator)
                        .frame(height: 0.5)
                        .padding(.horizontal, 16)

                    // MARK: - Redeem Section
                    redeemSection
                }
                .padding(.top, 8)
                .padding(.bottom, 40)
            }
        }
        .background(Color.coffeeBackground)
        .onAppear {
            loadGiftCodes()
        }
    }

    // MARK: - My Codes Section

    private var myCodesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            CoffeeSectionHeader(title: "Meus Códigos")
                .padding(.horizontal, 20)

            Text("Compartilhe seus códigos com amigos para que ganhem 7 dias de Premium grátis.")
                .font(.system(size: 14))
                .foregroundStyle(Color.coffeeTextSecondary)
                .padding(.horizontal, 20)

            if isLoading {
                HStack {
                    Spacer()
                    ProgressView()
                        .tint(Color.coffeePrimary)
                    Spacer()
                }
                .padding(.vertical, 24)
            } else if giftCodes.isEmpty {
                CoffeeEmptyState(
                    icon: CoffeeIcon.gift,
                    title: "Nenhum código",
                    message: "Ao assinar o plano Premium, você receberá códigos para compartilhar com amigos."
                )
                .padding(.top, 8)
            } else {
                CoffeeCellGroup {
                    ForEach(Array(giftCodes.enumerated()), id: \.element.id) { index, code in
                        giftCodeRow(code)

                        if index < giftCodes.count - 1 {
                            Divider().padding(.leading, 16)
                        }
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }

    // MARK: - Gift Code Row

    private func giftCodeRow(_ giftCode: GiftCode) -> some View {
        HStack(spacing: 12) {
            // Code info
            VStack(alignment: .leading, spacing: 4) {
                Text(giftCode.code)
                    .font(.system(size: 17, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Color.coffeeTextPrimary)

                if giftCode.redeemed {
                    HStack(spacing: 4) {
                        Text("Usado")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Color.coffeeTextSecondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Color.coffeeTextSecondary.opacity(0.1))
                            .clipShape(Capsule())

                        if let by = giftCode.redeemedBy {
                            Text("por \(by)")
                                .font(.system(size: 12))
                                .foregroundStyle(Color.coffeeTextSecondary)
                        }
                    }
                } else {
                    Text("Disponível")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.coffeeSuccess)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.coffeeSuccess.opacity(0.12))
                        .clipShape(Capsule())
                }
            }

            Spacer()

            // Action buttons
            HStack(spacing: 8) {
                // Copy button
                Button {
                    UIPasteboard.general.string = giftCode.code
                    withAnimation {
                        copiedCode = giftCode.code
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        withAnimation {
                            if copiedCode == giftCode.code {
                                copiedCode = nil
                            }
                        }
                    }
                } label: {
                    Image(systemName: copiedCode == giftCode.code ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 16))
                        .foregroundStyle(copiedCode == giftCode.code ? Color.coffeeSuccess : Color.coffeePrimary)
                        .frame(width: 36, height: 36)
                        .background(Color.coffeeInputBackground)
                        .clipShape(Circle())
                }

                // Share button (only for unredeemed)
                if !giftCode.redeemed {
                    Button {
                        shareCode(giftCode.code)
                    } label: {
                        Image(systemName: CoffeeIcon.share)
                            .font(.system(size: 16))
                            .foregroundStyle(Color.coffeePrimary)
                            .frame(width: 36, height: 36)
                            .background(Color.coffeeInputBackground)
                            .clipShape(Circle())
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    // MARK: - Redeem Section

    private var redeemSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            CoffeeSectionHeader(title: "Resgatar Código")
                .padding(.horizontal, 20)

            Text("Digite um código promocional para ganhar 7 dias de Premium grátis.")
                .font(.system(size: 14))
                .foregroundStyle(Color.coffeeTextSecondary)
                .padding(.horizontal, 20)

            // Input field
            HStack(spacing: 12) {
                TextField("Digite o código", text: $inputCode)
                    .font(.system(size: 16, design: .monospaced))
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                    .background(Color.coffeeInputBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(Color.coffeeSeparator, lineWidth: 0.5)
                    )
                    .onChange(of: inputCode) { _, _ in
                        // Reset feedback when typing
                        if redeemSuccess != nil {
                            redeemSuccess = nil
                            redeemMessage = ""
                        }
                    }
            }
            .padding(.horizontal, 16)

            // Redeem button
            CoffeeButton(
                "Resgatar",
                icon: CoffeeIcon.gift,
                isLoading: isRedeeming,
                isDisabled: inputCode.trimmingCharacters(in: .whitespaces).isEmpty || isRedeeming
            ) {
                redeemCode()
            }
            .padding(.horizontal, 16)

            // Feedback message
            if let success = redeemSuccess {
                HStack(spacing: 8) {
                    Image(systemName: success ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(success ? Color.coffeeSuccess : Color.coffeeDanger)

                    Text(redeemMessage)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(success ? Color.coffeeSuccess : Color.coffeeDanger)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    (success ? Color.coffeeSuccess : Color.coffeeDanger).opacity(0.08)
                )
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .padding(.horizontal, 16)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    // MARK: - Actions

    private func loadGiftCodes() {
        Task {
            do {
                let response = try await subscriptionService.getGiftCodes()
                giftCodes = response.codes
                shareMessage = response.shareMessage
            } catch {
                // Silently fail — show empty state
            }
            isLoading = false
        }
    }

    private func redeemCode() {
        let code = inputCode.trimmingCharacters(in: .whitespaces)
        guard !code.isEmpty else { return }

        isRedeeming = true
        Task {
            do {
                let response = try await subscriptionService.redeemGiftCode(code)
                withAnimation {
                    if response.redeemed {
                        redeemSuccess = true
                        redeemMessage = "\(response.daysAdded ?? 7) dias adicionados ao seu plano!"
                        inputCode = ""
                    } else {
                        redeemSuccess = false
                        redeemMessage = "Código inválido ou já utilizado."
                    }
                }
            } catch {
                withAnimation {
                    redeemSuccess = false
                    redeemMessage = "Código inválido ou já utilizado."
                }
            }
            isRedeeming = false
        }
    }

    private func shareCode(_ code: String) {
        let message = shareMessage ?? "Usa meu código \(code) no Coffee e ganha 7 dias grátis!"
        let activityVC = UIActivityViewController(
            activityItems: [message],
            applicationActivities: nil
        )

        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = windowScene.windows.first,
              var topVC = window.rootViewController else { return }

        while let presented = topVC.presentedViewController {
            topVC = presented
        }

        if let popover = activityVC.popoverPresentationController {
            popover.sourceView = topVC.view
            popover.sourceRect = CGRect(x: topVC.view.bounds.midX, y: topVC.view.bounds.midY, width: 0, height: 0)
        }

        topVC.present(activityVC, animated: true)
    }
}

// MARK: - Preview

#Preview {
    PromoCodesScreenView()
        .environment(\.subscriptionService, SubscriptionService())
}
