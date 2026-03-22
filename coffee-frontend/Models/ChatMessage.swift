import Foundation

// MARK: - Chat Models (from API Contract: GET /chats, POST /chats/{id}/messages)

struct Chat: Codable, Identifiable {
    let id: String
    let sourceType: String
    let sourceId: String
    let sourceName: String
    let sourceIcon: String
    var lastMessage: String?
    var messageCount: Int
    let updatedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case sourceType = "source_type"
        case sourceId = "source_id"
        case sourceName = "source_name"
        case sourceIcon = "source_icon"
        case lastMessage = "last_message"
        case messageCount = "message_count"
        case updatedAt = "updated_at"
    }
}

struct ChatMessageItem: Codable, Identifiable {
    let id: String
    let sender: MessageSender
    let text: String
    let label: String?
    let mode: AIMode?
    let sources: [ChatSource]?
    let createdAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, sender, text, label, mode, sources
        case createdAt = "created_at"
    }
}

enum MessageSender: String, Codable {
    case user
    case ai
}

// MARK: - AI Modes (Rápido, Professor, Amigo)

enum AIMode: String, Codable, CaseIterable {
    case rapido
    case professor
    case amigo
    // Legacy modes (for existing messages in DB)
    case espresso
    case lungo
    case coldBrew = "cold_brew"

    // Only show new modes in picker
    static var pickerCases: [AIMode] { [.rapido, .professor, .amigo] }

    var displayName: String {
        switch self {
        case .rapido, .espresso: return "Rapido"
        case .professor, .lungo: return "Professor"
        case .amigo, .coldBrew: return "Amigo"
        }
    }

    var icon: String {
        switch self {
        case .rapido, .espresso: return "bolt.fill"
        case .professor, .lungo: return "graduationcap.fill"
        case .amigo, .coldBrew: return "person.2.fill"
        }
    }

    var subtitle: String {
        switch self {
        case .rapido, .espresso: return "Direto ao ponto"
        case .professor, .lungo: return "Explicacao clara e estruturada"
        case .amigo, .coldBrew: return "Como um amigo explicando"
        }
    }
}

// MARK: - Chat Source Citation

struct ChatSource: Codable, Identifiable {
    var id: String { gravacaoId ?? materialId ?? UUID().uuidString }
    let type: String            // "transcription" | "material"
    let gravacaoId: String?
    let materialId: String?
    let title: String
    let date: String?
    let excerpt: String
    let similarity: Double

    enum CodingKeys: String, CodingKey {
        case type, title, date, excerpt, similarity
        case gravacaoId = "gravacao_id"
        case materialId = "material_id"
    }
}

// MARK: - Send Message Request (POST /chats/{id}/messages)
// chatId goes in the URL path, NOT in the body

struct SendMessageRequest: Codable {
    let text: String
    let mode: AIMode
    let gravacaoId: String?     // null = todas as gravações da source

    enum CodingKeys: String, CodingKey {
        case text, mode
        case gravacaoId = "gravacao_id"
    }
}

// MARK: - Create Chat Request (POST /chats)

struct CreateChatRequest: Codable {
    let sourceType: String
    let sourceId: String

    enum CodingKeys: String, CodingKey {
        case sourceType = "source_type"
        case sourceId = "source_id"
    }
}

// MARK: - SSE Stream Done Payload

struct SSEDonePayload: Codable {
    let done: Bool
    let messageId: String?
    let chatId: String?
    let sources: [ChatSource]?
    let label: String?
    let usagePercent: Double?
    let budgetUsd: Double?
    let usedUsd: Double?
    // Legacy
    let questionsRemaining: QuestionsRemaining?

    enum CodingKeys: String, CodingKey {
        case done, sources, label
        case messageId = "message_id"
        case chatId = "chat_id"
        case usagePercent = "usage_percent"
        case budgetUsd = "budget_usd"
        case usedUsd = "used_usd"
        case questionsRemaining = "questions_remaining"
    }
}
