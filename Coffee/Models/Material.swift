import Foundation

struct Material: Codable, Identifiable {
    let id: UUID
    let disciplinaId: UUID
    let tipo: String
    let nome: String
    let urlStorage: String?
    let fonte: String
    let aiEnabled: Bool
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case disciplinaId = "disciplina_id"
        case tipo
        case nome
        case urlStorage   = "url_storage"
        case fonte
        case aiEnabled    = "ai_enabled"
        case createdAt    = "created_at"
    }
}
