import Foundation

// MARK: - Profile Service
// GET /profile, PATCH /profile

enum ProfileService {

    // MARK: - Get Profile (with usage stats + gift codes)

    static func getProfile() async throws -> UserProfile {
        if APIClient.useMocks {
            return MockData.userProfile
        }
        return try await APIClient.shared.request(path: APIEndpoints.profile)
    }

    // MARK: - Update Profile

    static func updateProfile(nome: String) async throws -> UserProfile {
        if APIClient.useMocks {
            try await Task.sleep(for: .seconds(0.5))
            return MockData.userProfile
        }

        let body = UpdateProfileRequest(nome: nome)
        return try await APIClient.shared.request(
            path: APIEndpoints.profile,
            method: .PATCH,
            body: body
        )
    }
}
