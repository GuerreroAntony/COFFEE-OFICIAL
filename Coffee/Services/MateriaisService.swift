import Foundation

struct MaterialListResponse: Decodable {
    let materiais: [Material]
}

struct ToggleAIResponse: Decodable {
    let id: UUID
    let aiEnabled: Bool

    enum CodingKeys: String, CodingKey {
        case id
        case aiEnabled = "ai_enabled"
    }
}

struct SyncStatusResponse: Decodable {
    let status: String
    let lastScrapedAt: Date?

    enum CodingKeys: String, CodingKey {
        case status
        case lastScrapedAt = "last_scraped_at"
    }
}

final class MateriaisService {
    static let shared = MateriaisService()
    private init() {}

    private let net = NetworkService.shared

    func listar(disciplinaId: UUID) async throws -> [Material] {
        let resp: MaterialListResponse = try await net.request(.GET, "/materiais/disciplina/\(disciplinaId)")
        return resp.materiais
    }

    func get(materialId: UUID) async throws -> Material {
        return try await net.request(.GET, "/materiais/\(materialId)")
    }

    func toggleAI(materialId: UUID) async throws -> ToggleAIResponse {
        return try await net.request(.PATCH, "/materiais/\(materialId)/toggle-ai")
    }

    func triggerSync(disciplinaId: UUID) async throws -> SyncStatusResponse {
        return try await net.request(.POST, "/materiais/disciplina/\(disciplinaId)/sync")
    }
}
