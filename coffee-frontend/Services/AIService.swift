import Foundation

// MARK: - AI Service
// GET /chats, POST /chats, GET /chats/{id}/messages, POST /chats/{id}/messages (SSE)
// Handles Barista IA chat with Server-Sent Events

enum AIService {

    // MARK: - List Conversations

    static func getChats() async throws -> [Chat] {
        if APIClient.useMocks {
            return MockData.chatHistory
        }
        return try await APIClient.shared.request(path: APIEndpoints.chats)
    }

    // MARK: - Create Conversation

    static func createChat(sourceType: String, sourceId: String? = nil) async throws -> Chat {
        if APIClient.useMocks {
            try await Task.sleep(for: .seconds(0.3))
            return Chat(
                id: UUID().uuidString,
                sourceType: sourceType,
                sourceId: sourceId ?? UUID().uuidString,
                sourceName: sourceType == "all" ? "Todas as Disciplinas" : "Nova Conversa",
                sourceIcon: sourceType == "all" ? "books.vertical" : "school",
                lastMessage: nil,
                messageCount: 0,
                updatedAt: Date()
            )
        }

        let body = CreateChatRequest(sourceType: sourceType, sourceId: sourceId)
        return try await APIClient.shared.request(
            path: APIEndpoints.chats,
            method: .POST,
            body: body
        )
    }

    // MARK: - List Messages

    static func getChatMessages(chatId: String) async throws -> [ChatMessageItem] {
        if APIClient.useMocks {
            return [
                ChatMessageItem(id: "m1", sender: .user, text: "O que sao os 4Ps?", label: nil, mode: .lungo, sources: nil, createdAt: Date()),
                MockData.sampleAIResponse,
            ]
        }
        return try await APIClient.shared.request(
            path: APIEndpoints.chatMessages(chatId: chatId)
        )
    }

    // MARK: - Send Message (SSE Streaming)

    /// Send a message to the Barista and receive streaming response
    /// chatId is passed as URL path parameter per API contract
    static func sendMessage(
        chatId: String,
        text: String,
        mode: AIMode,
        gravacaoId: String? = nil
    ) -> AsyncThrowingStream<String, Error> {
        if APIClient.useMocks {
            return mockStreamResponse()
        }

        let body = SendMessageRequest(
            text: text,
            mode: mode,
            gravacaoId: gravacaoId
        )

        return APIClient.shared.streamRequest(
            path: APIEndpoints.chatMessages(chatId: chatId),
            body: body
        )
    }

    // MARK: - Mock Streaming

    private static func mockStreamResponse() -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            Task {
                let words = MockData.sampleAIResponse.text.split(separator: " ")

                for (index, word) in words.enumerated() {
                    try await Task.sleep(for: .milliseconds(50))
                    let separator = index == 0 ? "" : " "
                    continuation.yield(separator + String(word))
                }

                continuation.finish()
            }
        }
    }
}
