import SwiftUI

// MARK: - Login Screen
// Matches LoginScreen from AuthScreens.jsx
// Email + password form in iOS cell group style

struct LoginScreenView: View {
    @Environment(\.router) private var router
    @Environment(\.subscriptionService) private var subscriptionService

    @State private var email = ""
    @State private var password = ""
    @State private var showPassword = false
    @State private var isLoading = false
    @State private var errorMessage: String? = nil
    @State private var highlightSignup = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            // Logo + tagline
            VStack(spacing: 12) {
                Image("logo-wide")
                    .resizable()
                    .renderingMode(.template)
                    .aspectRatio(contentMode: .fit)
                    .frame(height: 110)
                    .foregroundStyle(Color.coffeePrimary)

                Text("mais foco no que importa.")
                    .font(.system(size: 22))
                    .foregroundStyle(Color.coffeeTextSecondary)
            }
            .padding(.bottom, 40)

            // Form
            VStack(spacing: 0) {
                // Email field
                VStack(alignment: .leading, spacing: 4) {
                    Text("E-MAIL")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.coffeeTextSecondary)

                    ZStack(alignment: .leading) {
                        if email.isEmpty {
                            Text("exemplo@email.com")
                                .font(.coffeeBody)
                                .foregroundStyle(Color.coffeeTextSecondary.opacity(0.4))
                        }
                        TextField("", text: $email)
                            .font(.coffeeBody)
                            .foregroundStyle(Color.coffeeTextPrimary)
                            .keyboardType(.emailAddress)
                            .textContentType(.emailAddress)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .tint(Color.coffeePrimary)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .overlay(alignment: .bottom) {
                    Rectangle()
                        .fill(Color.coffeeSeparator)
                        .frame(height: 0.5)
                }

                // Password field
                VStack(alignment: .leading, spacing: 4) {
                    Text("SENHA")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.coffeeTextSecondary)

                    HStack {
                        if showPassword {
                            TextField("••••••••", text: $password)
                                .font(.coffeeBody)
                                .textContentType(.password)
                                .tint(Color.coffeePrimary)
                        } else {
                            SecureField("••••••••", text: $password)
                                .font(.coffeeBody)
                                .textContentType(.password)
                                .tint(Color.coffeePrimary)
                        }

                        Button {
                            showPassword.toggle()
                        } label: {
                            Image(systemName: showPassword ? "eye.slash" : "eye")
                                .font(.system(size: 18))
                                .foregroundStyle(Color.coffeeTextSecondary)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .background(Color.coffeeCardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .padding(.horizontal, 24)

            // Forgot password
            HStack {
                Spacer()
                Button("Esqueci minha senha") { }
                    .font(.system(size: 15))
                    .foregroundStyle(Color.coffeePrimary)
            }
            .padding(.horizontal, 28)
            .padding(.top, 12)
            .padding(.bottom, 20)

            // Error message
            if let errorMessage {
                Text(errorMessage)
                    .font(.system(size: 14))
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 28)
                    .padding(.bottom, 16)
            }

            // Login button
            CoffeeButton("Entrar", isLoading: isLoading) {
                errorMessage = nil
                isLoading = true
                Task {
                    do {
                        let auth = try await AuthService.login(email: email, password: password)
                        subscriptionService.syncWithUser(auth.user)
                        router.login(user: auth.user)
                    } catch let error as APIError {
                        errorMessage = error.localizedDescription
                        flashSignup()
                    } catch {
                        errorMessage = "Erro ao conectar. Tente novamente."
                    }
                    isLoading = false
                }
            }
            .padding(.horizontal, 24)

            Spacer()

            // Create account link
            HStack(spacing: 4) {
                Text("Não tem conta?")
                    .font(.system(size: 15))
                    .foregroundStyle(Color.coffeeTextSecondary)

                Button("Criar conta") {
                    router.goToSignup()
                }
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color.coffeePrimary)
                .scaleEffect(highlightSignup ? 1.15 : 1.0)
                .animation(.easeInOut(duration: 0.25).repeatCount(3, autoreverses: true), value: highlightSignup)
            }
            .padding(.bottom, 40)
        }
        .background(Color.coffeeBackground)
        .onTapGesture {
            hideKeyboard()
        }
    }

    private func flashSignup() {
        highlightSignup = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            highlightSignup = false
        }
    }

    private func hideKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}

#Preview {
    LoginScreenView()
        .environment(\.router, NavigationRouter())
}
