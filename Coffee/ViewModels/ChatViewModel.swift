import Foundation

@MainActor
final class ChatViewModel: ObservableObject {
    @Published var messages: [ChatMessage] = []
    @Published var currentStreamText = ""
    @Published var isStreaming = false
    @Published var errorMessage: String?
    @Published var personality = PersonalityConfig()

    var chatId: UUID?
    var disciplinaId: UUID?
    var modo: String = "disciplina"

    func sendMessage(_ text: String) async {
        let userMsg = ChatMessage(
            id: UUID(),
            role: "user",
            conteudo: text,
            fontes: [],
            createdAt: Date()
        )
        messages.append(userMsg)
        isStreaming = true
        currentStreamText = ""
        errorMessage = nil

        var accumulated = ""
        var finalFontes: [FonteCitacao] = []
        var finalMsgId: UUID = UUID()
        var finalChatId: UUID? = chatId

        do {
            for try await event in ChatService.shared.sendMessage(
                mensagem: text,
                chatId: chatId,
                disciplinaId: disciplinaId,
                modo: modo,
                personality: personality
            ) {
                switch event {
                case .token(let delta):
                    accumulated += delta
                    currentStreamText = accumulated
                case .done(let fontes, let msgId, let cid):
                    finalFontes = fontes
                    finalMsgId = msgId
                    finalChatId = cid
                }
            }

            let aiMsg = ChatMessage(
                id: finalMsgId,
                role: "assistant",
                conteudo: accumulated,
                fontes: finalFontes,
                createdAt: Date()
            )
            messages.append(aiMsg)
            currentStreamText = ""
            chatId = finalChatId
        } catch let e as CoffeeAPIError {
            errorMessage = e.errorDescription
            currentStreamText = ""
        } catch {
            errorMessage = error.localizedDescription
            currentStreamText = ""
        }

        isStreaming = false
    }
}
