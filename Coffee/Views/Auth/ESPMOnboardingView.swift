import SwiftUI

struct ESPMOnboardingView: View {
    @EnvironmentObject var authViewModel: AuthViewModel
    @StateObject private var viewModel = ESPMViewModel()
    @State private var login = ""
    @State private var password = ""

    var body: some View {
        ZStack {
            CoffeeTheme.Colors.background.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Spacer().frame(height: CoffeeTheme.Spacing.xxl)

                    // Header
                    VStack(alignment: .leading, spacing: CoffeeTheme.Spacing.xs) {
                        Image(systemName: "graduationcap.fill")
                            .font(.system(size: 28))
                            .foregroundColor(CoffeeTheme.Colors.coffee)

                        Spacer().frame(height: CoffeeTheme.Spacing.sm)

                        Text("etapa 2 de 2")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(CoffeeTheme.Colors.almond)

                        Text("conectar portal ESPM")
                            .font(.system(size: 26, weight: .semibold))
                            .foregroundColor(CoffeeTheme.Colors.espresso)

                        Text("suas disciplinas e horários serão importados automaticamente do portal.")
                            .font(.system(size: 14))
                            .foregroundColor(CoffeeTheme.Colors.almond)
                            .padding(.top, CoffeeTheme.Spacing.xs)
                    }

                    Spacer().frame(height: CoffeeTheme.Spacing.xxl)

                    // Fields
                    VStack(spacing: CoffeeTheme.Spacing.lg) {
                        CoffeeTextField(
                            placeholder: "email ESPM",
                            text: $login,
                            icon: "envelope"
                        )
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                        CoffeeTextField(
                            placeholder: "senha do portal",
                            text: $password,
                            isSecure: true,
                            icon: "lock"
                        )
                    }

                    Spacer().frame(height: CoffeeTheme.Spacing.lg)

                    if let error = viewModel.errorMessage {
                        Text(error)
                            .font(.system(size: 13))
                            .foregroundColor(.red)
                            .padding(.bottom, CoffeeTheme.Spacing.sm)
                    }

                    CoffeeButton(title: "conectar", isLoading: viewModel.isLoading) {
                        Task { await viewModel.connect(login: login, password: password) }
                    }

                    Spacer().frame(height: CoffeeTheme.Spacing.xxl)
                }
                .padding(.horizontal, CoffeeTheme.Spacing.lg)
            }
        }
        .onTapGesture {
            UIApplication.shared.sendAction(
                #selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil
            )
        }
        .onChange(of: viewModel.isConnected) { _, connected in
            if connected {
                authViewModel.completeESPMOnboarding()
            }
        }
    }
}
