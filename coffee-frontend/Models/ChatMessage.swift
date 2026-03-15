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

// MARK: - AI Modes (Espresso, Lungo, Cold Brew)

enum AIMode: String, Codable, CaseIterable {
    case espresso
    case lungo
    case coldBrew = "cold_brew"

    var displayName: String {
        switch self {
        case .espresso: return "Espresso"
        case .lungo: return "Lungo"
        case .coldBrew: return "Cold Brew"
        }
    }

    var icon: String {
        switch self {
        case .espresso: return CoffeeIcon.bolt
        case .lungo: return CoffeeIcon.sparkles
        case .coldBrew: return CoffeeIcon.brain
        }
    }

    var subtitle: String {
        switch self {
        case .espresso: return "Rapido e direto ao ponto"
        case .lungo: return "Equilibrado e claro"
        case .coldBrew: return "Profundo e detalhado"
        }
    }

    var monthlyLimit: String {
        switch self {
        case .espresso: return "Ilimitado"
        case .lungo: return "30/mes"
        case .coldBrew: return "15/mes"
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
    let questionsRemaining: QuestionsRemaining?

    enum CodingKeys: String, CodingKey {
        case done, sources, label
        case messageId = "message_id"
        case chatId = "chat_id"
        case questionsRemaining = "questions_remaining"
    }
}
