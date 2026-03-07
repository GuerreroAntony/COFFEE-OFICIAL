import SwiftUI
import AVFoundation

struct OnboardingView: View {
    @EnvironmentObject var authViewModel: AuthViewModel
    @StateObject private var pushService = PushNotificationService.shared

    @State private var currentPage = 0
    @State private var micGranted = false
    @State private var notifGranted = false

    var body: some View {
        ZStack {
            CoffeeTheme.Colors.background
                .ignoresSafeArea()

            VStack(spacing: CoffeeTheme.Spacing.xl) {
                Spacer()

                if currentPage == 0 {
                    micPermissionPage
                } else {
                    notificationPermissionPage
                }

                Spacer()

                // Page indicator
                HStack(spacing: CoffeeTheme.Spacing.sm) {
                    Circle()
                        .fill(currentPage == 0 ? CoffeeTheme.Colors.coffee : CoffeeTheme.Colors.vanilla)
                        .frame(width: 8, height: 8)
                    Circle()
                        .fill(currentPage == 1 ? CoffeeTheme.Colors.coffee : CoffeeTheme.Colors.vanilla)
                        .frame(width: 8, height: 8)
                }
                .padding(.bottom, CoffeeTheme.Spacing.lg)
            }
            .padding(.horizontal, CoffeeTheme.Spacing.lg)
        }
    }

    // MARK: - Page 1: Microphone

    private var micPermissionPage: some View {
        VStack(spacing: CoffeeTheme.Spacing.lg) {
            Image(systemName: "mic.fill")
                .font(.system(size: 64))
                .foregroundColor(CoffeeTheme.Colors.caramel)

            Text("Gravar Aulas")
                .font(.system(size: CoffeeTheme.Typography.titleSize, weight: .bold))
                .foregroundColor(CoffeeTheme.Colors.espresso)

            Text("O Coffee precisa do microfone para gravar suas aulas e gerar resumos automaticamente.")
                .font(.system(size: CoffeeTheme.Typography.bodySize))
                .foregroundColor(CoffeeTheme.Colors.mocca)
                .multilineTextAlignment(.center)
                .padding(.horizontal, CoffeeTheme.Spacing.md)

            CoffeeButton(title: micGranted ? "Microfone Permitido" : "Permitir Microfone") {
                Task {
                    let granted = await requestMicPermission()
                    micGranted = granted
                    // Auto-advance after a brief moment
                    try? await Task.sleep(nanoseconds: 500_000_000)
                    withAnimation { currentPage = 1 }
                }
            }
            .disabled(micGranted)
            .padding(.top, CoffeeTheme.Spacing.md)

            Button("Pular") {
                withAnimation { currentPage = 1 }
            }
            .font(.system(size: CoffeeTheme.Typography.captionSize))
            .foregroundColor(CoffeeTheme.Colors.almond)
        }
    }

    // MARK: - Page 2: Notifications

    private var notificationPermissionPage: some View {
        VStack(spacing: CoffeeTheme.Spacing.lg) {
            Image(systemName: "bell.fill")
                .font(.system(size: 64))
                .foregroundColor(CoffeeTheme.Colors.caramel)

            Text("Fique Atualizado")
                .font(.system(size: CoffeeTheme.Typography.titleSize, weight: .bold))
                .foregroundColor(CoffeeTheme.Colors.espresso)

            Text("Receba notificacoes quando novos materiais forem adicionados nas suas disciplinas.")
                .font(.system(size: CoffeeTheme.Typography.bodySize))
                .foregroundColor(CoffeeTheme.Colors.mocca)
                .multilineTextAlignment(.center)
                .padding(.horizontal, CoffeeTheme.Spacing.md)

            CoffeeButton(title: notifGranted ? "Notificacoes Ativadas" : "Ativar Notificacoes") {
                Task {
                    let granted = await pushService.requestPermission()
                    notifGranted = granted
                    try? await Task.sleep(nanoseconds: 500_000_000)
                    authViewModel.completeOnboarding()
                }
            }
            .disabled(notifGranted)
            .padding(.top, CoffeeTheme.Spacing.md)

            Button("Pular") {
                authViewModel.completeOnboarding()
            }
            .font(.system(size: CoffeeTheme.Typography.captionSize))
            .foregroundColor(CoffeeTheme.Colors.almond)
        }
    }

    // MARK: - Helpers

    private func requestMicPermission() async -> Bool {
        await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
    }
}
