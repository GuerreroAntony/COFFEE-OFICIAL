import Foundation

// MARK: - Compartilhamento Models (from API Contract: GET /compartilhamentos/received)

struct SharedItem: Codable, Identifiable {
    let id: String
    let sender: SharedSender
    let gravacao: SharedGravacao
    let sourceDiscipline: String
    let sharedContent: [String]      // ["resumo", "mapa"]
    let message: String?
    var status: ShareStatus
    var isNew: Bool
    let createdAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, sender, gravacao, message, status
        case sourceDiscipline = "source_discipline"
        case sharedContent = "shared_content"
        case isNew = "is_new"
        case createdAt = "created_at"
    }
}

struct SharedSender: Codable {
    let nome: String
    let initials: String
}

struct SharedGravacao: Codable {
    let date: String
    let dateLabel: String
    let durationLabel: String
    let shortSummary: String?
    let hasMindMap: Bool

    enum CodingKeys: String, CodingKey {
        case date
        case dateLabel = "date_label"
        case durationLabel = "duration_label"
        case shortSummary = "short_summary"
        case hasMindMap = "has_mind_map"
    }
}

enum ShareStatus: String, Codable {
    case pending
    case accepted
    case rejected
}

// MARK: - Share Request

struct ShareRequest: Codable {
    let gravacaoId: String
    let recipientEmails: [String]
    let sharedContent: [String]
    let message: String?

    enum CodingKeys: String, CodingKey {
        case message
        case gravacaoId = "gravacao_id"
        case recipientEmails = "recipient_emails"
        case sharedContent = "shared_content"
    }
}

// MARK: - Accept Share Request

struct AcceptShareRequest: Codable {
    let destinationType: String
    let destinationId: String

    enum CodingKeys: String, CodingKey {
        case destinationType = "destination_type"
        case destinationId = "destination_id"
    }
}

// MARK: - Share Response (POST /compartilhamentos response)

struct ShareResponse: Codable {
    let sharedCount: Int
    let notFoundEmails: [String]
    let results: [ShareResultItem]

    enum CodingKeys: String, CodingKey {
        case results
        case sharedCount = "shared_count"
        case notFoundEmails = "not_found_emails"
    }
}

struct ShareResultItem: Codable {
    let email: String
    let status: String  // "sent" | "not_found"
}

// MARK: - Accept Share Response

struct AcceptShareResponse: Codable {
    let gravacaoId: String
    let destinationType: String
    let destinationId: String
    let status: String

    enum CodingKeys: String, CodingKey {
        case status
        case gravacaoId = "gravacao_id"
        case destinationType = "destination_type"
        case destinationId = "destination_id"
    }
}
