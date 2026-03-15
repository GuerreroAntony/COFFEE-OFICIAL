import SwiftUI

// MARK: - Signup Screen
// Matches SignupScreen from AuthScreens.jsx
// Nav bar + avatar + form fields + password strength

struct SignupScreenView: View {
    @Environment(\.router) private var router

    @State private var nome = ""
    @State private var email = ""
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var showPassword = false
    @State private var isLoading = false
    @State private var errorMessage: String? = nil

    private var passwordStrength: (label: String, color: Color, progress: CGFloat) {
        let length = password.count
        if length == 0 { return ("", .clear, 0) }
        if length < 4 { return ("Fraca", .coffeeDanger, 0.25) }
        if length < 8 { return ("Média", .coffeeWarning, 0.65) }
        return ("Forte", .coffeeSuccess, 1.0)
    }

    private var canSubmit: Bool {
        !nome.isEmpty && !email.isEmpty && password.count >= 8 && password == confirmPassword
    }

    var body: some View {
        VStack(spacing: 0) {
            // Nav bar
            CoffeeNavBar(
                title: "Criar conta",
                backTitle: "Entrar",
                onBack: { router.goToLogin() }
            )

            ScrollView {
                VStack(spacing: 0) {
                    // Avatar
                    VStack(spacing: 12) {
                        ZStack {
                            Circle()
                                .fill(Color.coffeePrimary)
                                .frame(width: 80, height: 80)
                                .shadow(color: Color.coffeePrimary.opacity(0.3), radius: 8, y: 4)

                            Image("logo-wide")
                                .resizable()
                                .renderingMode(.template)
                                .aspectRatio(contentMode: .fit)
                                .frame(maxWidth: 50)
                                .foregroundStyle(.white)
                        }

                        Text("Junte-se à comunidade COFFEE")
                            .font(.coffeeFootnote)
                            .foregroundStyle(Color.coffeeTextSecondary)
                    }
                    .padding(.top, 32)
                    .padding(.bottom, 32)

                    // Form fields (inline label style)
                    VStack(spacing: 0) {
                        formRow(label: "Nome", placeholder: "Seu nome", text: $nome, showSeparator: true)
                        formRow(label: "E-mail", placeholder: "exemplo@email.com", text: $email, keyboardType: .emailAddress, showSeparator: true)
                        passwordRow(label: "Senha", placeholder: "Mínimo 8 caracteres", text: $password, showSeparator: true)
                        formRow(label: "Confirmar", placeholder: "Repita a senha", text: $confirmPassword, isSecure: true, showSeparator: false)
                    }
                    .background(Color.coffeeCardBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .padding(.horizontal, 24)

                    // Password strength
                    if !password.isEmpty {
                        VStack(spacing: 4) {
                            HStack {
                                Text("Força da senha")
                                    .font(.system(size: 12))
                                    .foregroundStyle(Color.coffeeTextSecondary)
                                Spacer()
                                Text(passwordStrength.label)
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(passwordStrength.color)
                            }

                            GeometryReader { geometry in
                                ZStack(alignment: .leading) {
                                    Capsule()
                                        .fill(Color.coffeeBackground)
                                        .frame(height: 4)

                                    Capsule()
                                        .fill(passwordStrength.color)
                                        .frame(width: geometry.size.width * passwordStrength.progress, height: 4)
                                        .animation(.easeInOut(duration: 0.3), value: passwordStrength.progress)
                                }
                            }
                            .frame(height: 4)
                        }
                        .padding(.horizontal, 28)
                        .padding(.top, 12)
                    }

                    // Error message
                    if let errorMessage {
                        Text(errorMessage)
                            .font(.system(size: 14))
                            .foregroundStyle(.red)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 28)
                            .padding(.top, 8)
                    }

                    // Submit button
                    CoffeeButton("Criar conta", isLoading: isLoading, isDisabled: !canSubmit) {
                        errorMessage = nil
                        isLoading = true
                        Task {
                            do {
                                let auth = try await AuthService.signup(
                                    nome: nome,
                                    email: email,
                                    password: password
                                )
                                router.currentUser = auth.user
                                router.goToLinkESPM()
                            } catch let error as APIError {
                                errorMessage = error.localizedDescription
                            } catch {
                                errorMessage = "Erro ao criar conta. Tente novamente."
                            }
                            isLoading = false
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 24)
                    .padding(.bottom, 40)
                }
            }
        }
        .background(Color.coffeeBackground)
        .onTapGesture {
            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        }
    }

    // MARK: - Form Row

    @ViewBuilder
    private func formRow(
        label: String,
        placeholder: String,
        text: Binding<String>,
        keyboardType: UIKeyboardType = .default,
        isSecure: Bool = false,
        showSeparator: Bool
    ) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 15))
                .foregroundStyle(Color.coffeeTextPrimary)
                .frame(width: 90, alignment: .leading)

            if isSecure {
                SecureField(placeholder, text: text)
                    .font(.coffeeBody)
                    .tint(Color.coffeePrimary)
            } else {
                TextField(placeholder, text: text)
                    .font(.coffeeBody)
                    .keyboardType(keyboardType)
                    .textInputAutocapitalization(keyboardType == .emailAddress ? .never : .words)
                    .autocorrectionDisabled(keyboardType == .emailAddress)
                    .tint(Color.coffeePrimary)
            }
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 44)
        .overlay(alignment: .bottom) {
            if showSeparator {
                Rectangle()
                    .fill(Color.coffeeSeparator)
                    .frame(height: 0.5)
            }
        }
    }

    // MARK: - Password Row with toggle

    @ViewBuilder
    private func passwordRow(
        label: String,
        placeholder: String,
        text: Binding<String>,
        showSeparator: Bool
    ) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 15))
                .foregroundStyle(Color.coffeeTextPrimary)
                .frame(width: 90, alignment: .leading)

            if showPassword {
                TextField(placeholder, text: text)
                    .font(.coffeeBody)
                    .tint(Color.coffeePrimary)
            } else {
                SecureField(placeholder, text: text)
                    .font(.coffeeBody)
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
        .padding(.horizontal, 16)
        .frame(minHeight: 44)
        .overlay(alignment: .bottom) {
            if showSeparator {
                Rectangle()
                    .fill(Color.coffeeSeparator)
                    .frame(height: 0.5)
            }
        }
    }
}

#Preview {
    SignupScreenView()
        .environment(\.router, NavigationRouter())
}
