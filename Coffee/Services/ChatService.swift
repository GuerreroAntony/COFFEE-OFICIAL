import Foundation

enum ChatStreamEvent {
    case token(String)
    case done(fontes: [FonteCitacao], messageId: UUID, chatId: UUID)
}

private struct TokenEvent: Decodable {
    let token: String
}

private struct DoneEvent: Decodable {
    let done: Bool
    let fontes: [FonteCitacao]
    let messageId: UUID
    let chatId: UUID

    enum CodingKeys: String, CodingKey {
        case done
        case fontes
        case messageId = "message_id"
        case chatId = "chat_id"
    }
}

private struct ChatSendBody: Encodable {
    let mensagem: String
    let chatId: UUID?
    let disciplinaId: UUID?
    let modo: String
    let personality: PersonalityConfig?

    enum CodingKeys: String, CodingKey {
        case mensagem
        case chatId = "chat_id"
        case disciplinaId = "disciplina_id"
        case modo
        case personality
    }
}

private struct HistoryResponseBody: Decodable {
    let messages: [HistoryMessage]
}

private struct HistoryMessage: Decodable {
    let id: UUID
    let chatId: UUID
    let role: String
    let conteudo: String
    let fontes: [FonteCitacao]?
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case chatId = "chat_id"
        case role
        case conteudo
        case fontes
        case createdAt = "created_at"
    }
}

private struct ChatsListBody: Decodable {
    let chats: [ChatSummary]
}

final class ChatService {
    static let shared = ChatService()
    private init() {}

    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let str = try container.decode(String.self)
            let formatters: [DateFormatter] = [
                {
                    let f = DateFormatter()
                    f.locale = Locale(identifier: "en_US_POSIX")
                    f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSSSSXXXXX"
                    return f
                }(),
                {
                    let f = DateFormatter()
                    f.locale = Locale(identifier: "en_US_POSIX")
                    f.dateFormat = "yyyy-MM-dd'T'HH:mm:ssXXXXX"
                    return f
                }()
            ]
            for fmt in formatters {
                if let date = fmt.date(from: str) { return date }
            }
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Cannot decode date: \(str)"
            )
        }
        return d
    }()

    func sendMessage(
        mensagem: String,
        chatId: UUID?,
        disciplinaId: UUID?,
        modo: String,
        personality: PersonalityConfig?
    ) -> AsyncThrowingStream<ChatStreamEvent, Error> {
        let body = ChatSendBody(
            mensagem: mensagem,
            chatId: chatId,
            disciplinaId: disciplinaId,
            modo: modo,
            personality: personality
        )

        return AsyncThrowingStream { continuation in
            Task {
                do {
                    for try await jsonStr in NetworkService.shared.stream(.POST, "/chat/send", body: body) {
                        guard let data = jsonStr.data(using: .utf8) else { continue }
                        if let tokenEvent = try? self.decoder.decode(TokenEvent.self, from: data) {
                            continuation.yield(.token(tokenEvent.token))
                        } else if let doneEvent = try? self.decoder.decode(DoneEvent.self, from: data) {
                            continuation.yield(.done(
                                fontes: doneEvent.fontes,
                                messageId: doneEvent.messageId,
                                chatId: doneEvent.chatId
                            ))
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    func fetchHistory(chatId: UUID) async throws -> [ChatMessage] {
        let body: HistoryResponseBody = try await NetworkService.shared.request(
            .GET, "/chat/history/\(chatId)"
        )
        return body.messages.map { m in
            ChatMessage(
                id: m.id,
                role: m.role,
                conteudo: m.conteudo,
                fontes: m.fontes ?? [],
                createdAt: m.createdAt
            )
        }
    }

    func fetchChats(disciplinaId: UUID?) async throws -> [ChatSummary] {
        let path: String
        if let did = disciplinaId {
            path = "/chat/list?disciplina_id=\(did)"
        } else {
            path = "/chat/list"
        }
        let body: ChatsListBody = try await NetworkService.shared.request(.GET, path)
        return body.chats
    }
}
