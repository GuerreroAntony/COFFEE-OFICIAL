import SwiftUI

struct SignupView: View {
    @EnvironmentObject var authViewModel: AuthViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var nome = ""
    @State private var email = ""
    @State private var senha = ""
    @State private var confirmarSenha = ""
    @State private var localError: String?

    var body: some View {
        ZStack {
            CoffeeTheme.Colors.background.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Spacer().frame(height: CoffeeTheme.Spacing.xl)

                    // Title + subtitle
                    Text("criar conta")
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundColor(CoffeeTheme.Colors.espresso)

                    Text("etapa 1 de 2 — sua conta coffee")
                        .font(.system(size: 14))
                        .foregroundColor(CoffeeTheme.Colors.almond)
                        .padding(.top, CoffeeTheme.Spacing.xs)

                    Spacer().frame(height: CoffeeTheme.Spacing.xxl)

                    // Fields
                    VStack(spacing: CoffeeTheme.Spacing.lg) {
                        CoffeeTextField(placeholder: "nome completo", text: $nome, icon: "person")
                            .textInputAutocapitalization(.words)

                        CoffeeTextField(placeholder: "email acadêmico", text: $email, icon: "envelope")
                            .keyboardType(.emailAddress)
                            .textInputAutocapitalization(.never)

                        CoffeeTextField(placeholder: "senha", text: $senha, isSecure: true, icon: "lock")

                        CoffeeTextField(placeholder: "confirmar senha", text: $confirmarSenha, isSecure: true, icon: "lock.shield")
                    }

                    Spacer().frame(height: CoffeeTheme.Spacing.xxl)

                    // Error
                    let error = localError ?? authViewModel.errorMessage
                    if let error {
                        Text(error)
                            .font(.system(size: 13))
                            .foregroundColor(.red)
                            .multilineTextAlignment(.leading)
                            .padding(.bottom, CoffeeTheme.Spacing.sm)
                    }

                    // Cadastrar button
                    CoffeeButton(title: "Cadastrar", isLoading: authViewModel.isLoading) {
                        guard senha == confirmarSenha else {
                            localError = "As senhas não coincidem"
                            return
                        }
                        localError = nil
                        Task { await authViewModel.signup(nome: nome, email: email, senha: senha) }
                    }

                    Spacer().frame(height: CoffeeTheme.Spacing.xxl)
                }
                .padding(.horizontal, CoffeeTheme.Spacing.lg)
            }
        }
        .navigationBarBackButtonHidden(false)
        .simultaneousGesture(TapGesture().onEnded {
            UIApplication.shared.sendAction(
                #selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil
            )
        })
    }
}
