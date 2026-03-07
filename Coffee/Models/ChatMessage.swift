import Foundation

struct FonteCitacao: Codable, Identifiable {
    let fonteId: UUID
    let fonteType: String
    let disciplinaNome: String
    let metadata: [String: String]
    let similarity: Double

    var id: UUID { fonteId }

    enum CodingKeys: String, CodingKey {
        case fonteId = "fonte_id"
        case fonteType = "fonte_tipo"
        case disciplinaNome = "disciplina_nome"
        case metadata
        case similarity
    }
}

struct ChatMessage: Identifiable {
    let id: UUID
    let role: String        // "user" | "assistant"
    var conteudo: String
    var fontes: [FonteCitacao]
    let createdAt: Date
}

struct ChatSummary: Codable, Identifiable {
    let id: UUID
    let disciplinaId: UUID?
    let disciplinaNome: String?
    let modo: String
    let lastMessagePreview: String?
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case disciplinaId = "disciplina_id"
        case disciplinaNome = "disciplina_nome"
        case modo
        case lastMessagePreview = "last_message_preview"
        case createdAt = "created_at"
    }
}
