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
    @State private var showForgotPassword = false
    @State private var forgotEmail = ""
    @State private var forgotLoading = false
    @State private var forgotSuccess = false
    @State private var forgotError: String? = nil
    @State private var showResetPassword = false

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
                Button("Esqueci minha senha") {
                    forgotEmail = email
                    forgotError = nil
                    forgotSuccess = false
                    showForgotPassword = true
                }
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
        .alert("Recuperar senha", isPresented: $showForgotPassword) {
            TextField("Seu e-mail", text: $forgotEmail)
                .textInputAutocapitalization(.never)
                .keyboardType(.emailAddress)
            Button("Cancelar", role: .cancel) { }
            Button("Enviar") {
                Task { await handleForgotPassword() }
            }
        } message: {
            Text("Digite seu e-mail e enviaremos um link para redefinir sua senha.")
        }
        .alert("Código enviado", isPresented: $forgotSuccess) {
            Button("Digitar código") { showResetPassword = true }
        } message: {
            Text("Enviamos um código de 6 dígitos para \(forgotEmail). Verifique sua caixa de entrada e spam.")
        }
        .sheet(isPresented: $showResetPassword) {
            ResetPasswordView(email: forgotEmail) {
                showResetPassword = false
            }
        }
        .alert("Erro", isPresented: Binding(get: { forgotError != nil }, set: { if !$0 { forgotError = nil } })) {
            Button("OK") { forgotError = nil }
        } message: {
            Text(forgotError ?? "")
        }
    }

    private func handleForgotPassword() async {
        let trimmed = forgotEmail.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            forgotError = "Digite seu e-mail."
            return
        }
        do {
            try await AuthService.forgotPassword(email: trimmed)
            forgotSuccess = true
        } catch {
            forgotError = "Não foi possível enviar o e-mail. Verifique o endereço e tente novamente."
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

// MARK: - Reset Password View

struct ResetPasswordView: View {
    let email: String
    var onSuccess: () -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var code = ""
    @State private var newPassword = ""
    @State private var confirmPassword = ""
    @State private var showPassword = false
    @State private var isLoading = false
    @State private var errorMessage: String? = nil
    @State private var isSuccess = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Spacer()

                VStack(spacing: 16) {
                    Image(systemName: "lock.rotation")
                        .font(.system(size: 48))
                        .foregroundStyle(Color.coffeePrimary)

                    Text("Redefinir senha")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(Color.coffeeTextPrimary)

                    Text("Enviamos um código de 6 dígitos para\n\(email)")
                        .font(.system(size: 15))
                        .foregroundStyle(Color.coffeeTextSecondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.bottom, 32)

                VStack(spacing: 0) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("CÓDIGO")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Color.coffeeTextSecondary)

                        TextField("000000", text: $code)
                            .font(.system(size: 24, weight: .medium, design: .monospaced))
                            .foregroundStyle(Color.coffeeTextPrimary)
                            .keyboardType(.numberPad)
                            .textContentType(.oneTimeCode)
                            .tint(Color.coffeePrimary)
                            .onChange(of: code) { _, newValue in
                                code = String(newValue.prefix(6)).filter { $0.isNumber }
                            }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .overlay(alignment: .bottom) {
                        Rectangle().fill(Color.coffeeSeparator).frame(height: 0.5)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("NOVA SENHA")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Color.coffeeTextSecondary)

                        HStack {
                            Group {
                                if showPassword {
                                    TextField("Mínimo 6 caracteres", text: $newPassword)
                                } else {
                                    SecureField("Mínimo 6 caracteres", text: $newPassword)
                                }
                            }
                            .font(.coffeeBody)
                            .textContentType(.newPassword)
                            .tint(Color.coffeePrimary)

                            Button { showPassword.toggle() } label: {
                                Image(systemName: showPassword ? "eye.slash" : "eye")
                                    .font(.system(size: 18))
                                    .foregroundStyle(Color.coffeeTextSecondary)
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .overlay(alignment: .bottom) {
                        Rectangle().fill(Color.coffeeSeparator).frame(height: 0.5)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("CONFIRMAR SENHA")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Color.coffeeTextSecondary)

                        Group {
                            if showPassword {
                                TextField("Repita a senha", text: $confirmPassword)
                            } else {
                                SecureField("Repita a senha", text: $confirmPassword)
                            }
                        }
                        .font(.coffeeBody)
                        .textContentType(.newPassword)
                        .tint(Color.coffeePrimary)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }
                .background(Color.coffeeCardBackground)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .padding(.horizontal, 24)

                if let errorMessage {
                    Text(errorMessage)
                        .font(.system(size: 14))
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 28)
                        .padding(.top, 12)
                }

                Spacer().frame(height: 24)

                CoffeeButton("Redefinir senha", isLoading: isLoading) {
                    handleReset()
                }
                .padding(.horizontal, 24)

                Spacer()
            }
            .background(Color.coffeeBackground)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(Color.coffeeTextSecondary)
                    }
                }
            }
            .alert("Senha redefinida!", isPresented: $isSuccess) {
                Button("OK") {
                    onSuccess()
                    dismiss()
                }
            } message: {
                Text("Sua senha foi alterada com sucesso. Faça login com a nova senha.")
            }
            .onTapGesture {
                UIApplication.shared.sendAction(
                    #selector(UIResponder.resignFirstResponder),
                    to: nil, from: nil, for: nil
                )
            }
        }
    }

    private func handleReset() {
        errorMessage = nil
        let trimmedCode = code.trimmingCharacters(in: .whitespaces)
        guard trimmedCode.count == 6 else {
            errorMessage = "Digite o código de 6 dígitos."
            return
        }
        guard newPassword.count >= 6 else {
            errorMessage = "A senha deve ter no mínimo 6 caracteres."
            return
        }
        guard newPassword == confirmPassword else {
            errorMessage = "As senhas não conferem."
            return
        }
        isLoading = true
        Task {
            do {
                try await AuthService.resetPassword(email: email, code: trimmedCode, newPassword: newPassword)
                isSuccess = true
            } catch {
                errorMessage = "Código inválido ou expirado. Tente novamente."
            }
            isLoading = false
        }
    }
}

#Preview {
    LoginScreenView()
        .environment(\.router, NavigationRouter())
}
