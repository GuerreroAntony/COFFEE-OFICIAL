import Foundation

struct ESPMLoginRequest: Encodable {
    let login: String
    let password: String
}

struct ESPMLoginResponse: Decodable {
    let userId: UUID
    let sessionValid: Bool
    let disciplinesSynced: Int

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case sessionValid = "session_valid"
        case disciplinesSynced = "disciplines_synced"
    }
}

final class ESPMService {
    static let shared = ESPMService()
    private init() {}

    func connectPortal(login: String, password: String) async throws -> ESPMLoginResponse {
        let body = ESPMLoginRequest(login: login, password: password)
        return try await NetworkService.shared.request(.POST, "/espm/login", body: body, timeout: 300)
    }
}
