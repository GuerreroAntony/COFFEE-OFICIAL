import Foundation

// MARK: - Material Service
// GET /disciplinas/{id}/materiais, POST /disciplinas/{id}/materiais,
// GET /materiais/{id}, PATCH /materiais/{id}/toggle-ai

enum MaterialService {

    // MARK: - List Materials for Discipline

    static func getMaterials(disciplinaId: String) async throws -> [Material] {
        if APIClient.useMocks {
            return MockData.materials(for: disciplinaId)
        }
        return try await APIClient.shared.request(
            path: APIEndpoints.materiais(disciplinaId: disciplinaId)
        )
    }

    // MARK: - Get Material Detail

    static func getMaterial(id: String) async throws -> Material {
        if APIClient.useMocks {
            return MockData.allMaterials.first { $0.id == id } ?? MockData.allMaterials[0]
        }
        return try await APIClient.shared.request(
            path: APIEndpoints.material(id: id)
        )
    }

    // MARK: - Upload Material (multipart/form-data)

    static func uploadMaterial(
        disciplinaId: String,
        fileData: Data,
        fileName: String,
        mimeType: String,
        aiEnabled: Bool = true
    ) async throws -> Material {
        if APIClient.useMocks {
            try await Task.sleep(for: .seconds(2))
            return Material(
                id: UUID().uuidString,
                disciplinaId: disciplinaId,
                tipo: fileName.hasSuffix(".pdf") ? "pdf" : "outro",
                nome: fileName,
                urlStorage: nil,
                fonte: "manual",
                aiEnabled: aiEnabled,
                sizeBytes: fileData.count,
                sizeLabel: ByteCountFormatter.string(fromByteCount: Int64(fileData.count), countStyle: .file),
                createdAt: Date()
            )
        }

        let url = URL(string: "\(APIClient.baseURL)\(APIEndpoints.materiais(disciplinaId: disciplinaId))")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        if let token = KeychainManager.accessToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let boundary = UUID().uuidString
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()
        // File field
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(fileName)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: \(mimeType)\r\n\r\n".data(using: .utf8)!)
        body.append(fileData)
        body.append("\r\n".data(using: .utf8)!)
        // ai_enabled field
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"ai_enabled\"\r\n\r\n".data(using: .utf8)!)
        body.append("\(aiEnabled)\r\n".data(using: .utf8)!)
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)

        request.httpBody = body

        let (data, _) = try await URLSession.shared.data(for: request)
        let response = try JSONDecoder.coffeeDecoder.decode(APIResponse<Material>.self, from: data)
        guard let material = response.data else {
            throw APIError.unknown(response.message ?? "Upload failed")
        }
        return material
    }

    // MARK: - Sync Materials from Canvas

    static func syncMaterials(disciplinaId: String) async throws -> SyncResponse {
        if APIClient.useMocks {
            try await Task.sleep(for: .seconds(2))
            return SyncResponse(status: "triggered", lastSyncedAt: Date())
        }
        return try await APIClient.shared.request(
            path: APIEndpoints.disciplinaSync(id: disciplinaId),
            method: .POST
        )
    }

    // MARK: - Enable All AI

    /// Enables AI for all materials of a discipline. Returns the count of updated materials.
    static func enableAllAI(disciplinaId: String) async throws -> Int {
        if APIClient.useMocks {
            try await Task.sleep(for: .seconds(0.5))
            return 3
        }

        struct EnableAllAIResponse: Codable {
            let updatedCount: Int
        }

        let response: EnableAllAIResponse = try await APIClient.shared.request(
            path: APIEndpoints.materiaisEnableAllAI(disciplinaId: disciplinaId),
            method: .PATCH
        )
        return response.updatedCount
    }

    // MARK: - Toggle AI Feed

    struct ToggleAIResult: Codable {
        let id: String
        let aiEnabled: Bool
        enum CodingKeys: String, CodingKey {
            case id
            case aiEnabled = "ai_enabled"
        }
    }

    static func toggleAI(materialId: String) async throws -> ToggleAIResult {
        if APIClient.useMocks {
            try await Task.sleep(for: .seconds(0.3))
            return ToggleAIResult(id: materialId, aiEnabled: true)
        }

        return try await APIClient.shared.request(
            path: APIEndpoints.materialToggleAI(id: materialId),
            method: .PATCH
        )
    }
}
