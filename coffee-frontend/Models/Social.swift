import Foundation

// MARK: - Friend

struct Friend: Codable, Identifiable {
    let id: String
    let userId: String
    let nome: String
    let email: String
    let initials: String
    let status: FriendStatus
    let createdAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, nome, email, initials, status
        case userId = "user_id"
        case createdAt = "created_at"
    }
}

enum FriendStatus: String, Codable {
    case pendingSent = "pending_sent"
    case pendingReceived = "pending_received"
    case accepted
}

// MARK: - Group

struct SocialGroup: Codable, Identifiable {
    let id: String
    let nome: String
    let isAuto: Bool
    let disciplinaId: String?
    let memberCount: Int
    let members: [GroupMember]?
    let createdAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, nome, members
        case isAuto = "is_auto"
        case disciplinaId = "disciplina_id"
        case memberCount = "member_count"
        case createdAt = "created_at"
    }
}

struct GroupMember: Codable, Identifiable {
    var id: String { userId }
    let userId: String
    let nome: String
    let initials: String
    let role: String

    enum CodingKeys: String, CodingKey {
        case nome, initials, role
        case userId = "user_id"
    }
}

// MARK: - User Search Result

struct UserSearchResult: Codable, Identifiable {
    let id: String
    let nome: String
    let email: String
    let initials: String
    let isFriend: Bool
    let friendshipStatus: String?

    enum CodingKeys: String, CodingKey {
        case id, nome, email, initials
        case isFriend = "is_friend"
        case friendshipStatus = "friendship_status"
    }
}

// MARK: - Share Targets

struct ShareTargets: Codable {
    let friends: [Friend]
    let groups: [SocialGroup]
}

// MARK: - Requests

struct SendFriendRequestBody: Codable {
    let addresseeEmail: String?
    let addresseeId: String?
    enum CodingKeys: String, CodingKey {
        case addresseeEmail = "addressee_email"
        case addresseeId = "addressee_id"
    }
}

struct CreateGroupRequest: Codable {
    let nome: String
    let memberIds: [String]
    enum CodingKeys: String, CodingKey {
        case nome
        case memberIds = "member_ids"
    }
}

struct AddMemberRequestBody: Codable {
    let userId: String
    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
    }
}
