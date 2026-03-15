import Foundation

// MARK: - Recording Model (from API Contract: GET /gravacoes, GET /gravacoes/{id})

struct Recording: Codable, Identifiable {
    let id: String
    let sourceType: String
    let sourceId: String
    let date: String
    let dateLabel: String
    let durationSeconds: Int
    let durationLabel: String
    var status: RecordingStatus
    var shortSummary: String?
    var mediaCount: Int?
    var materialsCount: Int?
    var hasMindMap: Bool?
    var receivedFrom: String?
    let createdAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, date, status
        case sourceType = "source_type"
        case sourceId = "source_id"
        case dateLabel = "date_label"
        case durationSeconds = "duration_seconds"
        case durationLabel = "duration_label"
        case shortSummary = "short_summary"
        case mediaCount = "media_count"
        case materialsCount = "materials_count"
        case hasMindMap = "has_mind_map"
        case receivedFrom = "received_from"
        case createdAt = "created_at"
    }
}

enum RecordingStatus: String, Codable {
    case processing
    case ready
    case error
}

// MARK: - Recording Detail (full object)

struct RecordingDetail: Codable, Identifiable {
    let id: String
    let sourceType: String
    let sourceId: String
    let date: String
    let dateLabel: String
    let durationSeconds: Int
    let durationLabel: String
    var status: RecordingStatus
    var shortSummary: String?
    var fullSummary: [SummarySection]?
    var transcription: String?
    var mindMap: MindMap?
    var media: [RecordingMedia]?
    var materials: [Material]?
    var receivedFrom: String?
    let createdAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, date, status, transcription, media, materials
        case sourceType = "source_type"
        case sourceId = "source_id"
        case dateLabel = "date_label"
        case durationSeconds = "duration_seconds"
        case durationLabel = "duration_label"
        case shortSummary = "short_summary"
        case fullSummary = "full_summary"
        case mindMap = "mind_map"
        case receivedFrom = "received_from"
        case createdAt = "created_at"
    }
}

// MARK: - Summary

struct SummarySection: Codable, Identifiable {
    var id: String { title }
    let title: String
    let bullets: [String]
}

// MARK: - Mind Map (4 branches x 3 children, always)

struct MindMap: Codable {
    let topic: String
    let branches: [MindMapBranch]
}

struct MindMapBranch: Codable, Identifiable {
    var id: String { topic }
    let topic: String
    let color: Int      // 0=red, 1=orange, 2=green, 3=purple
    let children: [String]
}

// MARK: - Media

struct RecordingMedia: Codable, Identifiable {
    let id: String
    let type: String
    let label: String?
    let timestampSeconds: Int
    let timestampLabel: String
    let url: String?

    enum CodingKeys: String, CodingKey {
        case id, type, label, url
        case timestampSeconds = "timestamp_seconds"
        case timestampLabel = "timestamp_label"
    }
}

// MARK: - Material

struct Material: Codable, Identifiable {
    let id: String
    let disciplinaId: String?
    let tipo: String           // pdf, slide, foto, outro
    let nome: String
    let urlStorage: String?
    let fonte: String?         // canvas | manual
    var aiEnabled: Bool
    let sizeBytes: Int?
    let sizeLabel: String?
    let createdAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, tipo, nome, fonte
        case disciplinaId = "disciplina_id"
        case urlStorage = "url_storage"
        case aiEnabled = "ai_enabled"
        case sizeBytes = "size_bytes"
        case sizeLabel = "size_label"
        case createdAt = "created_at"
    }
}

// MARK: - Create Recording Request

struct CreateRecordingRequest: Codable {
    let sourceType: String
    let sourceId: String
    let transcription: String?
    var durationSeconds: Int = 0
    var date: String? = nil

    enum CodingKeys: String, CodingKey {
        case transcription, date
        case sourceType = "source_type"
        case sourceId = "source_id"
        case durationSeconds = "duration_seconds"
    }
}
