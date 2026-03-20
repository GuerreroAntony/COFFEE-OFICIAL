import Foundation

// MARK: - Calendar Event Model (from GET /calendario/events)

struct CalendarEvent: Codable, Identifiable, Hashable {
    let id: String
    let userId: String
    let disciplinaId: String?
    let source: String              // "canvas_assignment", "canvas_quiz", "manual"
    let canvasPlannableId: Int?
    let plannableType: String?
    let title: String
    let description: String?
    let location: String?
    let eventType: String           // "assignment", "quiz", "exam", "deadline", "event", "reminder"
    let startAt: Date
    let endAt: Date?
    let allDay: Bool
    let dueAt: Date?
    let pointsPossible: Double?
    let submitted: Bool?
    let graded: Bool?
    let late: Bool?
    let missing: Bool?
    let canvasUrl: String?
    let courseName: String?
    let completed: Bool
    let disciplinaNome: String?
    let createdAt: Date
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case disciplinaId = "disciplina_id"
        case source
        case canvasPlannableId = "canvas_plannable_id"
        case plannableType = "plannable_type"
        case title, description, location
        case eventType = "event_type"
        case startAt = "start_at"
        case endAt = "end_at"
        case allDay = "all_day"
        case dueAt = "due_at"
        case pointsPossible = "points_possible"
        case submitted, graded, late, missing
        case canvasUrl = "canvas_url"
        case courseName = "course_name"
        case completed
        case disciplinaNome = "disciplina_nome"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    // MARK: - Computed

    var isCanvas: Bool { source != "manual" }

    var isOverdue: Bool {
        guard !completed else { return false }
        if submitted == true { return false }
        return startAt < Date()
    }

    var statusLabel: String {
        if completed { return "Concluído" }
        if graded == true { return "Corrigido" }
        if submitted == true { return "Entregue" }
        if missing == true { return "Faltando" }
        if late == true { return "Atrasado" }
        if isOverdue { return "Atrasado" }
        return "Pendente"
    }

    var displayName: String {
        disciplinaNome ?? courseName ?? ""
    }

    /// Short time label: "14:30" or "Dia todo"
    var timeLabel: String {
        if allDay { return "Dia todo" }
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        f.timeZone = TimeZone(identifier: "America/Sao_Paulo")
        return f.string(from: startAt)
    }

    /// Points label: "10 pts" or nil
    var pointsLabel: String? {
        guard let pts = pointsPossible, pts > 0 else { return nil }
        if pts == pts.rounded() {
            return "\(Int(pts)) pts"
        }
        return String(format: "%.1f pts", pts)
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: CalendarEvent, rhs: CalendarEvent) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Upcoming Response

struct UpcomingResponse: Codable {
    let overdue: [CalendarEvent]
    let today: [CalendarEvent]
    let tomorrow: [CalendarEvent]
    let thisWeek: [CalendarEvent]
    let totalUpcoming: Int

    enum CodingKeys: String, CodingKey {
        case overdue, today, tomorrow
        case thisWeek = "this_week"
        case totalUpcoming = "total_upcoming"
    }
}

// MARK: - Create Event Request

struct CreateCalendarEventRequest: Codable {
    let title: String
    let startAt: Date
    let endAt: Date?
    let dueAt: Date?
    let allDay: Bool
    let eventType: String
    let description: String?
    let location: String?
    let disciplinaId: String?

    enum CodingKeys: String, CodingKey {
        case title
        case startAt = "start_at"
        case endAt = "end_at"
        case dueAt = "due_at"
        case allDay = "all_day"
        case eventType = "event_type"
        case description, location
        case disciplinaId = "disciplina_id"
    }
}
