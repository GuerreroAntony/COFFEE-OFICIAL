import SwiftUI

struct LoginView: View {
    @EnvironmentObject var authViewModel: AuthViewModel
    @State private var email = ""
    @State private var senha = ""
    @State private var showSignup = false

    var body: some View {
        NavigationStack {
            ZStack {
                CoffeeTheme.Colors.background.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 0) {
                        Spacer().frame(height: CoffeeTheme.Spacing.xxl)

                        // Icon + Title
                        VStack(spacing: CoffeeTheme.Spacing.sm) {
                            Image(systemName: "cup.and.saucer.fill")
                                .font(.system(size: 32))
                                .foregroundColor(CoffeeTheme.Colors.espresso)

                            Text("coffee")
                                .font(.system(size: 24, weight: .light))
                                .tracking(3)
                                .foregroundColor(CoffeeTheme.Colors.espresso)
                        }

                        Spacer().frame(height: CoffeeTheme.Spacing.xxl)

                        // Fields
                        VStack(spacing: CoffeeTheme.Spacing.lg) {
                            CoffeeTextField(
                                placeholder: "email",
                                text: $email,
                                icon: "envelope"
                            )
                            .keyboardType(.emailAddress)
                            .textInputAutocapitalization(.never)

                            CoffeeTextField(
                                placeholder: "senha",
                                text: $senha,
                                isSecure: true,
                                icon: "lock"
                            )
                        }

                        Spacer().frame(height: CoffeeTheme.Spacing.xxl)

                        // Entrar button
                        CoffeeButton(
                            title: "Entrar",
                            isLoading: authViewModel.isLoading
                        ) {
                            Task { await authViewModel.login(email: email, senha: senha) }
                        }

                        Spacer().frame(height: CoffeeTheme.Spacing.md)

                        // Criar conta link
                        Button { showSignup = true } label: {
                            Text("Criar conta")
                                .font(.system(size: 14))
                                .foregroundColor(CoffeeTheme.Colors.caramel)
                        }

                        // Error message
                        if let error = authViewModel.errorMessage {
                            Text(error)
                                .font(.system(size: 13))
                                .foregroundColor(.red)
                                .multilineTextAlignment(.center)
                                .padding(.top, CoffeeTheme.Spacing.sm)
                        }

                        Spacer().frame(height: CoffeeTheme.Spacing.xxl)
                    }
                    .padding(.horizontal, CoffeeTheme.Spacing.lg)
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .simultaneousGesture(TapGesture().onEnded {
                UIApplication.shared.sendAction(
                    #selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil
                )
            })
            .navigationDestination(isPresented: $showSignup) {
                SignupView()
            }
        }
    }
}
