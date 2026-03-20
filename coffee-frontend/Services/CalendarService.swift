import Foundation

// MARK: - Calendar Service
// GET /calendario/events, POST /calendario/events, PATCH, DELETE, POST /sync, GET /upcoming

enum CalendarService {

    // MARK: - List Events

    static func getEvents(start: String? = nil, end: String? = nil) async throws -> [CalendarEvent] {
        var path = APIEndpoints.calendarioEvents
        var params: [String] = []
        if let start { params.append("start=\(start)") }
        if let end { params.append("end=\(end)") }
        if !params.isEmpty { path += "?\(params.joined(separator: "&"))" }
        return try await APIClient.shared.request(path: path)
    }

    // MARK: - Create Event

    static func createEvent(
        title: String,
        startAt: Date,
        endAt: Date? = nil,
        allDay: Bool = false,
        eventType: String = "event",
        description: String? = nil,
        location: String? = nil,
        disciplinaId: String? = nil
    ) async throws -> CalendarEvent {
        let body = CreateCalendarEventRequest(
            title: title,
            startAt: startAt,
            endAt: endAt,
            dueAt: nil,
            allDay: allDay,
            eventType: eventType,
            description: description,
            location: location,
            disciplinaId: disciplinaId
        )
        return try await APIClient.shared.request(
            path: APIEndpoints.calendarioEvents,
            method: .POST,
            body: body
        )
    }

    // MARK: - Delete Event

    static func deleteEvent(id: String) async throws {
        let _: EmptyResponse = try await APIClient.shared.request(
            path: APIEndpoints.calendarioEvent(id: id),
            method: .DELETE
        )
    }

    // MARK: - Sync Canvas

    static func syncCanvas() async throws -> CalendarSyncResponse {
        return try await APIClient.shared.request(
            path: APIEndpoints.calendarioSync,
            method: .POST
        )
    }

    // MARK: - Upcoming

    static func getUpcoming() async throws -> UpcomingResponse {
        return try await APIClient.shared.request(
            path: APIEndpoints.calendarioUpcoming
        )
    }
}

// MARK: - Helpers

struct CalendarSyncResponse: Codable {
    let status: String
    let remainingMinutes: Int?
    let synced: Int?
    let skipped: Int?

    enum CodingKeys: String, CodingKey {
        case status
        case remainingMinutes = "remaining_minutes"
        case synced, skipped
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        status = try container.decode(String.self, forKey: .status)
        remainingMinutes = try container.decodeIfPresent(Int.self, forKey: .remainingMinutes)
        synced = try container.decodeIfPresent(Int.self, forKey: .synced)
        skipped = try container.decodeIfPresent(Int.self, forKey: .skipped)
    }
}

struct EmptyResponse: Codable {}
