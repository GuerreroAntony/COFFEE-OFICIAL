import Foundation

// MARK: - Social Service
// GET /social/friends, GET /social/friends/requests, POST /social/friends/request
// POST /social/friends/{id}/accept, POST /social/friends/{id}/reject, DELETE /social/friends/{id}
// GET /social/search, GET /social/groups, POST /social/groups, GET /social/groups/{id}
// POST /social/groups/{id}/members, DELETE /social/groups/{groupId}/members/{userId}
// DELETE /social/groups/{id}, GET /social/share-targets

enum SocialService {

    // MARK: - Friends

    static func getFriends() async throws -> [Friend] {
        try await APIClient.shared.request(path: APIEndpoints.socialFriends)
    }

    static func getFriendRequests() async throws -> [Friend] {
        try await APIClient.shared.request(path: APIEndpoints.socialFriendRequests)
    }

    private struct FriendRequestResponse: Decodable {
        let id: String?
        let status: String?
        let message: String?
    }

    static func sendFriendRequest(email: String? = nil, userId: String? = nil) async throws {
        let body = SendFriendRequestBody(addresseeEmail: email, addresseeId: userId)
        let _: FriendRequestResponse = try await APIClient.shared.request(
            path: APIEndpoints.socialFriendRequest,
            method: .POST,
            body: body
        )
    }

    static func acceptFriendRequest(id: String) async throws {
        let _: EmptyData = try await APIClient.shared.request(
            path: APIEndpoints.socialFriendAccept(id: id),
            method: .POST
        )
    }

    static func rejectFriendRequest(id: String) async throws {
        let _: EmptyData = try await APIClient.shared.request(
            path: APIEndpoints.socialFriendReject(id: id),
            method: .POST
        )
    }

    static func removeFriend(id: String) async throws {
        let _: EmptyData = try await APIClient.shared.request(
            path: APIEndpoints.socialFriendRemove(id: id),
            method: .DELETE
        )
    }

    static func searchUsers(query: String) async throws -> [UserSearchResult] {
        let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        return try await APIClient.shared.request(
            path: APIEndpoints.socialSearch + "?q=\(encoded)"
        )
    }

    // MARK: - Groups

    static func getGroups() async throws -> [SocialGroup] {
        try await APIClient.shared.request(path: APIEndpoints.socialGroups)
    }

    static func createGroup(nome: String, memberIds: [String]) async throws -> SocialGroup {
        let body = CreateGroupRequest(nome: nome, memberIds: memberIds)
        return try await APIClient.shared.request(
            path: APIEndpoints.socialGroups,
            method: .POST,
            body: body
        )
    }

    static func getGroupDetail(id: String) async throws -> SocialGroup {
        try await APIClient.shared.request(
            path: APIEndpoints.socialGroup(id: id)
        )
    }

    static func addGroupMember(groupId: String, userId: String) async throws {
        let body = AddMemberRequestBody(userId: userId)
        let _: EmptyData = try await APIClient.shared.request(
            path: APIEndpoints.socialGroupMembers(id: groupId),
            method: .POST,
            body: body
        )
    }

    static func removeGroupMember(groupId: String, userId: String) async throws {
        let _: EmptyData = try await APIClient.shared.request(
            path: APIEndpoints.socialGroupMember(groupId: groupId, userId: userId),
            method: .DELETE
        )
    }

    static func deleteGroup(id: String) async throws {
        let _: EmptyData = try await APIClient.shared.request(
            path: APIEndpoints.socialGroup(id: id),
            method: .DELETE
        )
    }

    // MARK: - Share Targets

    static func getShareTargets() async throws -> ShareTargets {
        try await APIClient.shared.request(path: APIEndpoints.socialShareTargets)
    }
}
