import Foundation

// MARK: - Auth Service
// Handles authentication, registration, and token management
// POST /auth/signup, POST /auth/login, POST /auth/logout,
// POST /auth/forgot-password, POST /auth/refresh, GET /auth/me

enum AuthService {

    // MARK: - Login

    static func login(email: String, password: String) async throws -> AuthResponse {
        if APIClient.useMocks {
            try await Task.sleep(for: .seconds(1))
            let response = MockData.authResponse
            KeychainManager.saveTokens(access: response.token, userId: response.user.id)
            return response
        }

        let body = LoginRequest(email: email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(), password: password)
        let auth: AuthResponse = try await APIClient.shared.request(
            path: APIEndpoints.login,
            method: .POST,
            body: body,
            authenticated: false
        )

        KeychainManager.saveTokens(access: auth.token, userId: auth.user.id)
        return auth
    }

    // MARK: - Signup

    static func signup(nome: String, email: String, password: String, giftCode: String? = nil) async throws -> AuthResponse {
        if APIClient.useMocks {
            try await Task.sleep(for: .seconds(1.5))
            let response = MockData.authResponse
            KeychainManager.saveTokens(access: response.token, userId: response.user.id)
            return response
        }

        let body = SignupRequest(nome: nome, email: email, password: password, giftCode: giftCode)
        let auth: AuthResponse = try await APIClient.shared.request(
            path: APIEndpoints.signup,
            method: .POST,
            body: body,
            authenticated: false
        )

        KeychainManager.saveTokens(access: auth.token, userId: auth.user.id)
        return auth
    }

    // MARK: - Logout

    static func logout(deviceToken: String? = nil) async {
        if !APIClient.useMocks {
            let body = LogoutRequest(deviceToken: deviceToken)
            let _: EmptyData? = try? await APIClient.shared.request(
                path: APIEndpoints.logout,
                method: .POST,
                body: body
            )
        }
        KeychainManager.clearAll()
    }

    // MARK: - Forgot Password

    static func forgotPassword(email: String) async throws {
        if APIClient.useMocks {
            try await Task.sleep(for: .seconds(1))
            return
        }

        let body = ForgotPasswordRequest(email: email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
        try await APIClient.shared.requestVoid(
            path: APIEndpoints.forgotPassword,
            method: .POST,
            body: body,
            authenticated: false
        )
    }

    // MARK: - Reset Password

    static func resetPassword(email: String, code: String, newPassword: String) async throws {
        if APIClient.useMocks {
            try await Task.sleep(for: .seconds(1))
            return
        }

        let body = ResetPasswordRequest(email: email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(), code: code, newPassword: newPassword)
        try await APIClient.shared.requestVoid(
            path: APIEndpoints.resetPassword,
            method: .POST,
            body: body,
            authenticated: false
        )
    }

    // MARK: - Refresh Token

    static func refreshToken() async throws -> String {
        if APIClient.useMocks {
            return "mock_refreshed_token_\(UUID().uuidString)"
        }

        struct RefreshResponse: Decodable { let token: String }

        let result: RefreshResponse = try await APIClient.shared.request(
            path: APIEndpoints.refreshToken,
            method: .POST
        )

        KeychainManager.save(key: .accessToken, value: result.token)
        return result.token
    }

    // MARK: - Get Current User

    static func getMe() async throws -> User {
        if APIClient.useMocks {
            return MockData.currentUser
        }
        return try await APIClient.shared.request(path: APIEndpoints.me)
    }

    // MARK: - Get Profile (with usage stats)

    static func getProfile() async throws -> UserProfile {
        if APIClient.useMocks {
            return MockData.userProfile
        }
        return try await APIClient.shared.request(path: APIEndpoints.profile)
    }
}
