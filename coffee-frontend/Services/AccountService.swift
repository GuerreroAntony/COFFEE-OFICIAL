import Foundation

// MARK: - Account Service
// DELETE /account, GET /settings, POST /support/contact, GET /health

enum AccountService {

    // MARK: - Delete Account (LGPD)

    /// Deletes all user data permanently. Irreversible.
    /// Cascaded deletion: user -> gravacoes -> media -> embeddings -> chats ->
    /// mensagens -> compartilhamentos -> subscriptions -> gift_codes ->
    /// device_tokens -> notificacoes -> user_disciplinas
    static func deleteAccount() async throws {
        if APIClient.useMocks {
            try await Task.sleep(for: .seconds(1))
            KeychainManager.clearAll()
            return
        }

        let body = DeleteAccountRequest(confirm: true)
        let _: EmptyData = try await APIClient.shared.request(
            path: APIEndpoints.account,
            method: .DELETE,
            body: body
        )

        KeychainManager.clearAll()
    }

    // MARK: - Get Settings

    static func getSettings() async throws -> SettingsResponse {
        if APIClient.useMocks {
            return SettingsResponse(
                espmConnected: true,
                espmLogin: "gabriel.lima@acad.espm.br"
            )
        }

        return try await APIClient.shared.request(path: APIEndpoints.settings)
    }

    // MARK: - Contact Support

    static func contactSupport(subject: String, message: String) async throws {
        if APIClient.useMocks {
            try await Task.sleep(for: .seconds(1))
            return
        }

        let body = ContactRequest(subject: subject, message: message)
        let _: EmptyData = try await APIClient.shared.request(
            path: APIEndpoints.supportContact,
            method: .POST,
            body: body
        )
    }

    // MARK: - Health Check

    static func healthCheck() async throws -> Bool {
        if APIClient.useMocks { return true }

        struct HealthResponse: Decodable { let status: String }
        let result: HealthResponse = try await APIClient.shared.request(
            path: APIEndpoints.health,
            authenticated: false
        )
        return result.status == "ok"
    }
}
