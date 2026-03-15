import Foundation

// MARK: - Repository Model (from API Contract: GET /repositorios)

struct Repository: Codable, Identifiable, Hashable {
    let id: String
    var nome: String
    var icone: String       // Material Icon name, default: "folder"
    var gravacoesCount: Int
    var aiActive: Bool
    let createdAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, nome, icone
        case gravacoesCount = "gravacoes_count"
        case aiActive = "ai_active"
        case createdAt = "created_at"
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: Repository, rhs: Repository) -> Bool {
        lhs.id == rhs.id
    }
}

struct CreateRepositoryRequest: Codable {
    let nome: String
    var icone: String = "folder"
}
