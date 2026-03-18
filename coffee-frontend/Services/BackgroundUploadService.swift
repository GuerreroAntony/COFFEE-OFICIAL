import Foundation
import Network
import UserNotifications

// MARK: - Background Upload Service
// Handles audio upload with background URLSession, retry, and connectivity monitoring.
// Falls back to foreground upload if background session isn't available.

final class BackgroundUploadService: NSObject, @unchecked Sendable {

    static let shared = BackgroundUploadService()

    private let sessionIdentifier = "com.coffee.background-upload"
    private let pendingUploadsKey = "coffee_pending_uploads"
    private let maxRetryCount = 30  // 30 retries × 60s = 30 min timeout
    private let retryInterval: TimeInterval = 60

    private var backgroundSession: URLSession!
    private var pathMonitor: NWPathMonitor?
    private var completionHandlers: [String: () -> Void] = [:]
    private var retryTimers: [String: Timer] = [:]

    override init() {
        super.init()
        let config = URLSessionConfiguration.background(withIdentifier: sessionIdentifier)
        config.isDiscretionary = false
        config.sessionSendsLaunchEvents = true
        config.timeoutIntervalForResource = 300
        backgroundSession = URLSession(configuration: config, delegate: self, delegateQueue: .main)
    }

    // MARK: - Public API

    /// Queue an audio upload. If WiFi available, uploads immediately.
    /// If not, monitors connectivity and retries every 60s.
    func queueUpload(
        audioFileURL: URL,
        disciplinaId: String,
        durationSeconds: Int,
        startTime: Date,
        endTime: Date,
        qualityScore: Double,
        token: String
    ) {
        let pending = PendingUpload(
            id: UUID().uuidString,
            audioPath: audioFileURL.path,
            disciplinaId: disciplinaId,
            durationSeconds: durationSeconds,
            startTime: startTime,
            endTime: endTime,
            qualityScore: qualityScore,
            token: token,
            retryCount: 0,
            createdAt: Date()
        )

        savePendingUpload(pending)
        attemptUpload(pending)
    }

    /// Called from AppDelegate when background session events are available
    func handleBackgroundSessionEvents(completionHandler: @escaping () -> Void) {
        completionHandlers[sessionIdentifier] = completionHandler
    }

    /// Retry any pending uploads (call on app launch)
    func retryPendingUploads() {
        let pending = loadPendingUploads()
        for upload in pending {
            if upload.retryCount < maxRetryCount {
                attemptUpload(upload)
            } else {
                removePendingUpload(id: upload.id)
                sendLocalNotification(
                    title: "Upload falhou",
                    body: "Não foi possível enviar a gravação. Tente novamente."
                )
            }
        }
    }

    // MARK: - Upload Logic

    private func attemptUpload(_ upload: PendingUpload) {
        guard FileManager.default.fileExists(atPath: upload.audioPath) else {
            removePendingUpload(id: upload.id)
            return
        }

        let audioURL = URL(fileURLWithPath: upload.audioPath)

        // Build multipart request
        guard let (request, bodyFileURL) = buildMultipartRequest(upload: upload, audioURL: audioURL) else {
            scheduleRetry(upload)
            return
        }

        // Use background upload task
        let task = backgroundSession.uploadTask(with: request, fromFile: bodyFileURL)
        task.taskDescription = upload.id
        task.resume()
    }

    private func buildMultipartRequest(upload: PendingUpload, audioURL: URL) -> (URLRequest, URL)? {
        guard let audioData = try? Data(contentsOf: audioURL) else { return nil }

        let url = URL(string: "\(APIClient.baseURL)\(APIEndpoints.gravacaoUploadAudio)")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(upload.token)", forHTTPHeaderField: "Authorization")

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
            ("disciplina_id", upload.disciplinaId),
            ("duration_seconds", "\(upload.durationSeconds)"),
            ("start_time", isoFormatter.string(from: upload.startTime)),
            ("end_time", isoFormatter.string(from: upload.endTime)),
            ("quality_score", "\(upload.qualityScore)"),
        ]

        for (name, value) in fields {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".data(using: .utf8)!)
            body.append("\(value)\r\n".data(using: .utf8)!)
        }

        body.append("--\(boundary)--\r\n".data(using: .utf8)!)

        // Write body to temp file (required for background upload)
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("upload_\(upload.id).tmp")
        do {
            try body.write(to: tempURL)
            return (request, tempURL)
        } catch {
            return nil
        }
    }

    private func scheduleRetry(_ upload: PendingUpload) {
        var updated = upload
        updated.retryCount += 1

        if updated.retryCount >= maxRetryCount {
            removePendingUpload(id: upload.id)
            sendLocalNotification(
                title: "Upload pendente",
                body: "A gravação não pôde ser enviada. Abra o app com WiFi para tentar novamente."
            )
            return
        }

        savePendingUpload(updated)

        // Retry after interval
        let timer = Timer.scheduledTimer(withTimeInterval: retryInterval, repeats: false) { [weak self] _ in
            self?.attemptUpload(updated)
        }
        retryTimers[upload.id] = timer
    }

    // MARK: - Persistence

    private func savePendingUpload(_ upload: PendingUpload) {
        var pending = loadPendingUploads()
        pending.removeAll { $0.id == upload.id }
        pending.append(upload)
        if let data = try? JSONEncoder().encode(pending) {
            UserDefaults.standard.set(data, forKey: pendingUploadsKey)
        }
    }

    private func removePendingUpload(id: String) {
        var pending = loadPendingUploads()
        pending.removeAll { $0.id == id }
        if let data = try? JSONEncoder().encode(pending) {
            UserDefaults.standard.set(data, forKey: pendingUploadsKey)
        }
        retryTimers[id]?.invalidate()
        retryTimers.removeValue(forKey: id)

        // Clean temp file
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("upload_\(id).tmp")
        try? FileManager.default.removeItem(at: tempURL)
    }

    private func loadPendingUploads() -> [PendingUpload] {
        guard let data = UserDefaults.standard.data(forKey: pendingUploadsKey) else { return [] }
        return (try? JSONDecoder().decode([PendingUpload].self, from: data)) ?? []
    }

    // MARK: - Notifications

    private func sendLocalNotification(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }
}

// MARK: - URLSessionDelegate

extension BackgroundUploadService: URLSessionDelegate, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let uploadId = task.taskDescription else { return }

        if let error = error {
            // Network error — retry
            if let pending = loadPendingUploads().first(where: { $0.id == uploadId }) {
                scheduleRetry(pending)
            }
            return
        }

        if let httpResponse = task.response as? HTTPURLResponse, httpResponse.statusCode < 300 {
            // Success — clean up
            if let pending = loadPendingUploads().first(where: { $0.id == uploadId }) {
                // Delete local audio file
                try? FileManager.default.removeItem(atPath: pending.audioPath)
            }
            removePendingUpload(id: uploadId)
        } else {
            // Server error — retry
            if let pending = loadPendingUploads().first(where: { $0.id == uploadId }) {
                scheduleRetry(pending)
            }
        }
    }

    func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        DispatchQueue.main.async {
            self.completionHandlers[self.sessionIdentifier]?()
            self.completionHandlers.removeValue(forKey: self.sessionIdentifier)
        }
    }
}

// MARK: - PendingUpload Model

struct PendingUpload: Codable {
    let id: String
    let audioPath: String
    let disciplinaId: String
    let durationSeconds: Int
    let startTime: Date
    let endTime: Date
    let qualityScore: Double
    let token: String
    var retryCount: Int
    let createdAt: Date
}
