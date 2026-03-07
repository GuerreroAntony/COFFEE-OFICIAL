import Foundation

struct User: Codable, Identifiable {
    let id: UUID
    let nome: String
    let email: String
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case nome
        case email
        case createdAt = "created_at"
    }
}
