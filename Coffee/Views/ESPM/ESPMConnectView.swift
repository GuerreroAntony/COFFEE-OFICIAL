import SwiftUI

struct ESPMConnectView: View {
    let onSuccess: () -> Void

    @StateObject private var viewModel = ESPMViewModel()
    @State private var login = ""
    @State private var password = ""
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            CoffeeTheme.Colors.background.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: CoffeeTheme.Spacing.lg) {
                    VStack(alignment: .leading, spacing: CoffeeTheme.Spacing.xs) {
                        Text("conectar portal ESPM")
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundColor(CoffeeTheme.Colors.espresso)

                        Text("entre com suas credenciais do portal ESPM")
                            .font(.system(size: 14))
                            .foregroundColor(CoffeeTheme.Colors.almond)
                    }

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

                    if let error = viewModel.errorMessage {
                        Text(error)
                            .font(.system(size: 13))
                            .foregroundColor(.red)
                    }

                    CoffeeButton(title: "conectar", isLoading: viewModel.isLoading) {
                        Task {
                            await viewModel.connect(login: login, password: password)
                        }
                    }
                }
                .padding(.horizontal, CoffeeTheme.Spacing.lg)
                .padding(.top, CoffeeTheme.Spacing.xl)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: viewModel.isConnected) { _, connected in
            if connected {
                onSuccess()
                dismiss()
            }
        }
    }
}
