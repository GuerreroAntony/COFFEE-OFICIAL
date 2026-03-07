import Foundation

struct SignupRequest: Encodable {
    let nome: String
    let email: String
    let senha: String
}

struct LoginRequest: Encodable {
    let email: String
    let senha: String
}

struct AuthResponse: Decodable {
    let user: User
    let token: String
}

final class AuthService {
    static let shared = AuthService()
    private init() {}

    func signup(nome: String, email: String, senha: String) async throws -> User {
        let body = SignupRequest(nome: nome, email: email, senha: senha)
        let response: AuthResponse = try await NetworkService.shared.request(
            .POST, "/auth/signup", body: body, authenticated: false
        )
        KeychainService.shared.saveToken(response.token)
        return response.user
    }

    func login(email: String, senha: String) async throws -> User {
        let body = LoginRequest(email: email, senha: senha)
        let response: AuthResponse = try await NetworkService.shared.request(
            .POST, "/auth/login", body: body, authenticated: false
        )
        KeychainService.shared.saveToken(response.token)
        return response.user
    }

    func logout() {
        KeychainService.shared.deleteToken()
    }

    func checkAuth() async -> User? {
        guard KeychainService.shared.getToken() != nil else { return nil }
        return try? await NetworkService.shared.request(.GET, "/auth/me", authenticated: true)
    }
}
