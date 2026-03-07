import Foundation
import UserNotifications

final class ClassReminderService {
    static let shared = ClassReminderService()
    private init() {}

    private let identifierPrefix = "class-reminder-"
    private let reminderMinutesBefore = 15

    // Portuguese day name → Calendar weekday (Sunday=1, Monday=2, ..., Saturday=7)
    private let dayMapping: [String: Int] = [
        "segunda": 2,
        "terca": 3,
        "terça": 3,
        "quarta": 4,
        "quinta": 5,
        "sexta": 6,
        "sabado": 7,
        "sábado": 7,
        "domingo": 1,
    ]

    /// Schedule recurring weekly reminders 15 min before each class slot.
    func scheduleReminders(disciplinas: [Disciplina]) {
        let center = UNUserNotificationCenter.current()

        // Cancel existing reminders first, then schedule fresh
        cancelAllReminders {
            for disciplina in disciplinas {
                guard let horarios = disciplina.horarios else { continue }

                for (index, slot) in horarios.enumerated() {
                    guard let weekday = self.dayMapping[slot.day.lowercased()] else {
                        print("ClassReminder: unknown day '\(slot.day)'")
                        continue
                    }

                    guard let (hour, minute) = self.parseTime(slot.timeStart) else {
                        print("ClassReminder: invalid time '\(slot.timeStart)'")
                        continue
                    }

                    // Subtract 15 minutes
                    var reminderMinute = minute - self.reminderMinutesBefore
                    var reminderHour = hour
                    if reminderMinute < 0 {
                        reminderMinute += 60
                        reminderHour -= 1
                    }
                    if reminderHour < 0 {
                        reminderHour += 24
                    }

                    var dateComponents = DateComponents()
                    dateComponents.weekday = weekday
                    dateComponents.hour = reminderHour
                    dateComponents.minute = reminderMinute

                    let trigger = UNCalendarNotificationTrigger(
                        dateMatching: dateComponents,
                        repeats: true
                    )

                    let content = UNMutableNotificationContent()
                    content.title = "Aula em 15 minutos"
                    content.body = disciplina.nome
                    content.sound = .default

                    let identifier = "\(self.identifierPrefix)\(disciplina.id.uuidString)-\(index)"
                    let request = UNNotificationRequest(
                        identifier: identifier,
                        content: content,
                        trigger: trigger
                    )

                    center.add(request) { error in
                        if let error {
                            print("ClassReminder: failed to schedule for '\(disciplina.nome)': \(error)")
                        }
                    }
                }
            }

            print("ClassReminder: scheduled reminders for \(disciplinas.count) disciplinas")
        }
    }

    /// Cancel all class reminder notifications.
    func cancelAllReminders(completion: (() -> Void)? = nil) {
        let center = UNUserNotificationCenter.current()
        center.getPendingNotificationRequests { requests in
            let ids = requests
                .filter { $0.identifier.hasPrefix(self.identifierPrefix) }
                .map(\.identifier)

            if !ids.isEmpty {
                center.removePendingNotificationRequests(withIdentifiers: ids)
                print("ClassReminder: cancelled \(ids.count) pending reminders")
            }

            completion?()
        }
    }

    // MARK: - Helpers

    private func parseTime(_ time: String) -> (hour: Int, minute: Int)? {
        let parts = time.split(separator: ":")
        guard parts.count == 2,
              let hour = Int(parts[0]),
              let minute = Int(parts[1]) else {
            return nil
        }
        return (hour, minute)
    }
}
