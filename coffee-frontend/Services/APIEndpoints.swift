import Foundation

// MARK: - API Endpoints
// All 52 endpoints from Coffee API Contract v3.1
// Source of truth for URL paths — services reference these constants

enum APIEndpoints {

    // MARK: - 1. Auth (6 endpoints)

    /// POST - Create account
    static let signup = "/auth/signup"

    /// POST - Login
    static let login = "/auth/login"

    /// POST - Logout + remove FCM token
    static let logout = "/auth/logout"

    /// POST - Password recovery
    static let forgotPassword = "/auth/forgot-password"

    /// POST - Reset password with code
    static let resetPassword = "/auth/reset-password"

    /// POST - Renew JWT
    static let refreshToken = "/auth/refresh"

    /// GET - Current user
    static let me = "/auth/me"

    // MARK: - 2. ESPM Connection (4 endpoints)

    /// POST - Connect/Reconnect ESPM
    static let espmConnect = "/espm/connect"

    /// POST - Re-sync disciplines
    static let espmSync = "/espm/sync"

    /// GET - Connection status
    static let espmStatus = "/espm/status"

    /// POST - Disconnect ESPM
    static let espmDisconnect = "/espm/disconnect"

    // MARK: - 3. Disciplinas (2 endpoints)

    /// GET - List disciplines
    static let disciplinas = "/disciplinas"

    /// GET - Discipline detail
    static func disciplina(id: String) -> String { "/disciplinas/\(id)" }
    /// PATCH - Update discipline appearance (icon + color)
    static func disciplinaAppearance(id: String) -> String { "/disciplinas/\(id)/appearance" }

    // MARK: - 4. Repositórios (4 endpoints)

    /// GET - List repos
    static let repositorios = "/repositorios"

    /// POST - Create repo (same path as list)
    // Use `repositorios` with POST

    /// PATCH - Rename repo
    static func repositorio(id: String) -> String { "/repositorios/\(id)" }

    /// DELETE - Delete repo (same path as rename)
    // Use `repositorio(id:)` with DELETE

    // MARK: - 5. Gravações (8 endpoints)

    /// POST/GET - Save recording / List recordings
    static let gravacoes = "/gravacoes"

    /// POST - Upload audio for cloud transcription (multipart/form-data)
    static let gravacaoUploadAudio = "/gravacoes/upload-audio"

    /// GET/PATCH/DELETE - Recording detail / Move / Delete
    static func gravacao(id: String) -> String { "/gravacoes/\(id)" }

    /// POST - Upload photo (multipart/form-data)
    static func gravacaoMedia(id: String) -> String { "/gravacoes/\(id)/media" }

    /// GET - Download summary PDF
    static func gravacaoPdfResumo(id: String) -> String { "/gravacoes/\(id)/pdf/resumo" }

    /// GET - Download mind map PDF
    static func gravacaoPdfMindmap(id: String) -> String { "/gravacoes/\(id)/pdf/mindmap" }

    // MARK: - 6. Materiais (5 endpoints)

    /// GET - List materials for discipline
    static func materiais(disciplinaId: String) -> String { "/disciplinas/\(disciplinaId)/materiais" }

    /// POST - Upload material (multipart/form-data)
    // Use `materiais(disciplinaId:)` with POST

    /// GET - Material detail
    static func material(id: String) -> String { "/materiais/\(id)" }

    /// PATCH - Toggle AI feed
    static func materialToggleAI(id: String) -> String { "/materiais/\(id)/toggle-ai" }

    /// PATCH - Enable AI for all materials of a discipline
    static func materiaisEnableAllAI(disciplinaId: String) -> String { "/disciplinas/\(disciplinaId)/materiais/enable-all-ai" }

    /// POST - Manual Canvas sync for discipline
    static func disciplinaSync(id: String) -> String { "/disciplinas/\(id)/sync" }

    // MARK: - 7. Chat — Barista (4 endpoints)

    /// GET/POST - List conversations / Create conversation
    static let chats = "/chats"

    /// GET - List messages in chat
    static func chatMessages(chatId: String) -> String { "/chats/\(chatId)/messages" }

    /// POST - Send question (SSE streaming) — same path as list messages
    // Use `chatMessages(chatId:)` with POST

    // MARK: - 8. Compartilhamentos (4 endpoints)

    /// POST - Share recording
    static let compartilhamentos = "/compartilhamentos"

    /// GET - Received shares inbox
    static let compartilhamentosReceived = "/compartilhamentos/received"

    /// POST - Accept share
    static func compartilhamentoAccept(id: String) -> String { "/compartilhamentos/\(id)/accept" }

    /// POST - Reject share
    static func compartilhamentoReject(id: String) -> String { "/compartilhamentos/\(id)/reject" }

    // MARK: - 9. Profile (2 endpoints)

    /// GET/PATCH - User profile
    static let profile = "/profile"

    // MARK: - 10. Subscription (2 endpoints)

    /// POST - Verify Apple receipt
    static let subscriptionVerify = "/subscription/verify"

    /// GET - Subscription status
    static let subscriptionStatus = "/subscription/status"

    // MARK: - 11. Gift Codes (3 endpoints)

    /// GET - List gift codes
    static let giftCodes = "/gift-codes"

    /// POST - Validate code
    static let giftCodesValidate = "/gift-codes/validate"

    /// POST - Redeem code
    static let giftCodesRedeem = "/gift-codes/redeem"

    // MARK: - 12. Devices & Notifications (4 endpoints)

    /// POST - Register FCM token
    static let devices = "/devices"

    /// DELETE - Remove FCM token
    static func device(token: String) -> String { "/devices/\(token)" }

    /// GET - List notifications (last 50)
    static let notificacoes = "/notificacoes"

    /// PATCH - Mark notification as read
    static func notificacaoRead(id: String) -> String { "/notificacoes/\(id)/read" }

    // MARK: - 13. Calendário (6 endpoints)

    /// GET/POST - List events / Create event
    static let calendarioEvents = "/calendario/events"

    /// PATCH/DELETE - Update / Delete event
    static func calendarioEvent(id: String) -> String { "/calendario/events/\(id)" }

    /// POST - Sync Canvas planner items
    static let calendarioSync = "/calendario/sync"

    /// GET - Upcoming events (overdue, today, tomorrow, this_week)
    static let calendarioUpcoming = "/calendario/upcoming"

    // MARK: - 14. Settings & Account (4 endpoints)

    /// GET - Get settings
    static let settings = "/settings"

    /// DELETE - Delete account (LGPD)
    static let account = "/account"

    /// POST - Contact form
    static let supportContact = "/support/contact"

    /// GET - Health check
    static let health = "/health"

    // MARK: - 15. Social (12 endpoints)

    /// GET - List friends
    static let socialFriends = "/social/friends"

    /// GET - List pending friend requests
    static let socialFriendRequests = "/social/friends/requests"

    /// POST - Send friend request
    static let socialFriendRequest = "/social/friends/request"

    /// POST - Accept friend request
    static func socialFriendAccept(id: String) -> String { "/social/friends/\(id)/accept" }

    /// POST - Reject friend request
    static func socialFriendReject(id: String) -> String { "/social/friends/\(id)/reject" }

    /// DELETE - Remove friend
    static func socialFriendRemove(id: String) -> String { "/social/friends/\(id)" }

    /// GET - Search users
    static let socialSearch = "/social/search"

    /// GET/POST - List groups / Create group
    static let socialGroups = "/social/groups"

    /// GET/DELETE - Group detail / Delete group
    static func socialGroup(id: String) -> String { "/social/groups/\(id)" }

    /// POST - Add member to group
    static func socialGroupMembers(id: String) -> String { "/social/groups/\(id)/members" }

    /// DELETE - Remove member from group
    static func socialGroupMember(groupId: String, userId: String) -> String { "/social/groups/\(groupId)/members/\(userId)" }

    /// GET - Share targets (friends + groups)
    static let socialShareTargets = "/social/share-targets"
}
