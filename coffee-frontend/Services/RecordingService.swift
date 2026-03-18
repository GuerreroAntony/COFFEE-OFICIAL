import Foundation

// MARK: - Recording Service
// POST /gravacoes, GET /gravacoes, GET /gravacoes/{id},
// POST /gravacoes/{id}/media, PATCH /gravacoes/{id}, DELETE /gravacoes/{id},
// GET /gravacoes/{id}/pdf/resumo, GET /gravacoes/{id}/pdf/mindmap

enum RecordingService {

    // MARK: - List Recordings

    /// List recordings by source (both params required per contract)
    static func getRecordings(sourceType: String, sourceId: String) async throws -> [Recording] {
        if APIClient.useMocks {
            return MockData.recordings(for: sourceId)
        }

        let path = "\(APIEndpoints.gravacoes)?source_type=\(sourceType)&source_id=\(sourceId)"
        return try await APIClient.shared.request(path: path)
    }

    // MARK: - Get Recording Detail

    static func getRecordingDetail(id: String) async throws -> RecordingDetail {
        if APIClient.useMocks {
            return MockData.recordingDetail(for: id)
        }
        return try await APIClient.shared.request(
            path: APIEndpoints.gravacao(id: id)
        )
    }

    // MARK: - Create Recording

    static func createRecording(
        sourceType: String,
        sourceId: String,
        transcription: String,
        durationSeconds: Int,
        date: String? = nil
    ) async throws -> Recording {
        if APIClient.useMocks {
            try await Task.sleep(for: .seconds(2))
            return Recording(
                id: UUID().uuidString,
                sourceType: sourceType,
                sourceId: sourceId,
                date: date ?? ISO8601DateFormatter().string(from: Date()),
                dateLabel: "Hoje",
                durationSeconds: durationSeconds,
                durationLabel: "\(durationSeconds / 3600)h \((durationSeconds % 3600) / 60)min",
                status: .processing,
                shortSummary: nil,
                mediaCount: 0,
                materialsCount: 0,
                hasMindMap: false,
                receivedFrom: nil,
                createdAt: Date()
            )
        }

        let body = CreateRecordingRequest(
            sourceType: sourceType,
            sourceId: sourceId,
            transcription: transcription,
            durationSeconds: durationSeconds,
            date: date
        )
        return try await APIClient.shared.request(
            path: APIEndpoints.gravacoes,
            method: .POST,
            body: body
        )
    }

    // MARK: - Upload Audio Recording (Cloud Transcription)

    /// Upload audio file for cloud transcription via GPT-4o Transcribe.
    /// Used for discipline recordings. Backend processes asynchronously.
    static func uploadAudioRecording(
        audioFileURL: URL,
        disciplinaId: String,
        durationSeconds: Int,
        startTime: Date,
        endTime: Date,
        qualityScore: Double = 0.0
    ) async throws -> Recording {
        if APIClient.useMocks {
            try await Task.sleep(for: .seconds(2))
            return Recording(
                id: UUID().uuidString,
                sourceType: "disciplina",
                sourceId: disciplinaId,
                date: ISO8601DateFormatter().string(from: startTime),
                dateLabel: "Hoje",
                durationSeconds: durationSeconds,
                durationLabel: "\(durationSeconds / 60)min",
                status: .processing,
                shortSummary: nil,
                mediaCount: 0,
                materialsCount: 0,
                hasMindMap: false,
                receivedFrom: nil,
                createdAt: Date()
            )
        }

        let audioData = try Data(contentsOf: audioFileURL)
        print("[RecordingService] Audio file: \(audioFileURL.lastPathComponent), size: \(audioData.count) bytes (\(audioData.count / 1024) KB)")

        let url = URL(string: "\(APIClient.baseURL)\(APIEndpoints.gravacaoUploadAudio)")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        if let token = KeychainManager.accessToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let boundary = UUID().uuidString
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        var body = Data()

        // Audio file
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"recording.m4a\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: audio/mp4\r\n\r\n".data(using: .utf8)!)
        body.append(audioData)
        body.append("\r\n".data(using: .utf8)!)

        // Form fields
        let fields: [(String, String)] = [
            ("disciplina_id", disciplinaId),
            ("duration_seconds", "\(durationSeconds)"),
            ("start_time", isoFormatter.string(from: startTime)),
            ("end_time", isoFormatter.string(from: endTime)),
            ("quality_score", "\(qualityScore)"),
        ]

        for (name, value) in fields {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".data(using: .utf8)!)
            body.append("\(value)\r\n".data(using: .utf8)!)
        }

        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        request.httpBody = body

        // Use longer timeout for audio upload (files can be 20+ MB)
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 120
        config.timeoutIntervalForResource = 300
        let session = URLSession(configuration: config)

        let (data, _) = try await session.data(for: request)
        let response = try JSONDecoder.coffeeDecoder.decode(APIResponse<Recording>.self, from: data)
        guard let recording = response.data else {
            throw APIError.unknown(response.message ?? "Upload failed")
        }
        return recording
    }

    // MARK: - Move Recording

    static func moveRecording(id: String, sourceType: String, sourceId: String) async throws -> Recording {
        if APIClient.useMocks {
            try await Task.sleep(for: .seconds(0.5))
            return MockData.recordings.first ?? MockData.recordings(for: sourceId).first!
        }

        let body = MoveRecordingRequest(sourceType: sourceType, sourceId: sourceId)
        return try await APIClient.shared.request(
            path: APIEndpoints.gravacao(id: id),
            method: .PATCH,
            body: body
        )
    }

    // MARK: - Delete Recording

    static func deleteRecording(id: String) async throws {
        if APIClient.useMocks {
            try await Task.sleep(for: .seconds(0.5))
            return
        }

        let _: EmptyData = try await APIClient.shared.request(
            path: APIEndpoints.gravacao(id: id),
            method: .DELETE
        )
    }

    // MARK: - Upload Media (Photo)

    /// Upload photo taken during or after recording
    /// Uses multipart/form-data — implemented separately from JSON API
    static func uploadMedia(
        recordingId: String,
        imageData: Data,
        label: String?,
        timestampSeconds: Int
    ) async throws -> RecordingMedia {
        if APIClient.useMocks {
            try await Task.sleep(for: .seconds(1))
            return RecordingMedia(
                id: UUID().uuidString,
                type: "photo",
                label: label,
                timestampSeconds: timestampSeconds,
                timestampLabel: "\(timestampSeconds / 60):\(String(format: "%02d", timestampSeconds % 60))",
                url: nil
            )
        }

        // Multipart upload — uses URLSession directly
        let url = URL(string: "\(APIClient.baseURL)\(APIEndpoints.gravacaoMedia(id: recordingId))")!
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
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"photo.jpg\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: image/jpeg\r\n\r\n".data(using: .utf8)!)
        body.append(imageData)
        body.append("\r\n".data(using: .utf8)!)
        // timestamp_seconds field
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"timestamp_seconds\"\r\n\r\n".data(using: .utf8)!)
        body.append("\(timestampSeconds)\r\n".data(using: .utf8)!)
        // label field (optional)
        if let label {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"label\"\r\n\r\n".data(using: .utf8)!)
            body.append("\(label)\r\n".data(using: .utf8)!)
        }
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)

        request.httpBody = body

        let (data, _) = try await URLSession.shared.data(for: request)
        let response = try JSONDecoder.coffeeDecoder.decode(APIResponse<RecordingMedia>.self, from: data)
        guard let media = response.data else {
            throw APIError.unknown(response.message ?? "Upload failed")
        }
        return media
    }

    // MARK: - PDF Downloads

    /// Get summary PDF URL for download
    static func getSummaryPDFURL(recordingId: String) -> URL? {
        URL(string: "\(APIClient.baseURL)\(APIEndpoints.gravacaoPdfResumo(id: recordingId))")
    }

    /// Get mind map PDF URL for download
    static func getMindMapPDFURL(recordingId: String) -> URL? {
        URL(string: "\(APIClient.baseURL)\(APIEndpoints.gravacaoPdfMindmap(id: recordingId))")
    }

    // MARK: - Poll Recording Status

    /// Poll recording status every 5s until ready or timeout (3 min)
    static func pollRecordingStatus(id: String) -> AsyncThrowingStream<RecordingDetail, Error> {
        AsyncThrowingStream { continuation in
            Task {
                let maxAttempts = 36  // 3 min / 5s = 36 attempts
                for attempt in 0..<maxAttempts {
                    if attempt > 0 {
                        try await Task.sleep(for: .seconds(5))
                    }

                    let detail = try await getRecordingDetail(id: id)
                    continuation.yield(detail)

                    if detail.status == .ready || detail.status == .error {
                        continuation.finish()
                        return
                    }
                }
                // Timeout — finish gracefully, UI shows "Processando..."
                continuation.finish()
            }
        }
    }
}
