import SwiftUI

// MARK: - Force Update View
// Blocking full-screen view shown when the app version is outdated.
// No dismiss button — user MUST update to continue using the app.

struct ForceUpdateView: View {
    private let storeURL = "https://apps.apple.com/app/coffee-espm/id6744076580"

    var body: some View {
        ZStack {
            Color.coffeeBackground
                .ignoresSafeArea()

            VStack(spacing: 32) {
                Spacer()

                // Icon
                ZStack {
                    Circle()
                        .fill(Color.coffeePrimary.opacity(0.1))
                        .frame(width: 120, height: 120)

                    Image(systemName: "arrow.down.app.fill")
                        .font(.system(size: 52))
                        .foregroundStyle(Color.coffeePrimary)
                }

                // Title
                VStack(spacing: 12) {
                    Text("Nova versao disponivel")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(Color.coffeeTextPrimary)
                        .multilineTextAlignment(.center)

                    Text("Atualize o Coffee para continuar\nusando o app com todas as novidades.")
                        .font(.system(size: 16))
                        .foregroundStyle(Color.coffeeTextSecondary)
                        .multilineTextAlignment(.center)
                        .lineSpacing(4)
                }
                .padding(.horizontal, 32)

                Spacer()

                // Update button
                Button {
                    openAppStore()
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 20))
                        Text("Atualizar na App Store")
                            .font(.system(size: 17, weight: .semibold))
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 54)
                    .background(Color.coffeePrimary)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .padding(.horizontal, 24)

                // Version info
                Text("Versao atual: \(currentVersion)")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.coffeeTextSecondary.opacity(0.6))
                    .padding(.bottom, 32)
            }
        }
        .interactiveDismissDisabled()
    }

    // MARK: - Helpers

    private var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
    }

    private func openAppStore() {
        guard let url = URL(string: storeURL) else { return }
        UIApplication.shared.open(url)
    }
}

#Preview {
    ForceUpdateView()
}
