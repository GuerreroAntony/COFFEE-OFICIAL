import SwiftUI
import UserNotifications

// MARK: - Calendar View Mode

enum CalendarViewMode: String {
    case week
    case month
}

// MARK: - Calendario Screen View
// Full-screen calendar with week/month views + event list for selected day
// Presented as .fullScreenCover from DisciplinasScreenView

struct CalendarioScreenView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.router) private var router

    @State private var events: [CalendarEvent] = []
    @State private var selectedDate = Date()
    @State private var isLoading = true
    @State private var isSyncing = false
    @State private var syncRotation: Double = 0
    @State private var showAddEvent = false
    @State private var disciplines: [Discipline] = []
    @State private var lastSyncMessage: String? = nil
    @State private var viewMode: CalendarViewMode = .week

    private let calendar = Calendar.current

    private var eventsForSelectedDay: [CalendarEvent] {
        let dayStart = calendar.startOfDay(for: selectedDate)
        guard let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) else { return [] }
        return events
            .filter { $0.startAt >= dayStart && $0.startAt < dayEnd }
            .sorted { $0.startAt < $1.startAt }
    }

    private var overdueEvents: [CalendarEvent] {
        let today = calendar.startOfDay(for: Date())
        return events.filter {
            $0.startAt < today && $0.isOverdue && !($0.submitted == true)
        }
    }

    private var selectedDateLabel: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "pt_BR")
        if calendar.isDateInToday(selectedDate) {
            return "Hoje"
        } else if calendar.isDateInTomorrow(selectedDate) {
            return "Amanhã"
        } else if calendar.isDateInYesterday(selectedDate) {
            return "Ontem"
        }
        f.dateFormat = "EEEE, d 'de' MMMM"
        return f.string(from: selectedDate).capitalized
    }

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                // Nav bar
                navBar

                // Calendar view (week strip or month grid)
                if viewMode == .week {
                    CalendarWeekStripView(
                        selectedDate: $selectedDate,
                        events: events,
                        onDateSelected: { date in
                            selectedDate = date
                        }
                    )
                } else {
                    CalendarMonthGridView(
                        selectedDate: $selectedDate,
                        events: events,
                        onDateSelected: { date in
                            selectedDate = date
                        }
                    )
                }

                Divider()

            // Sync message toast
            if let msg = lastSyncMessage {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.system(size: 14))
                    Text(msg)
                        .font(.system(size: 13))
                        .foregroundStyle(Color.coffeeTextSecondary)
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Color.green.opacity(0.06))
                .transition(.move(edge: .top).combined(with: .opacity))
            }

            // Event list
            ScrollView {
                VStack(spacing: 12) {
                    // Overdue section (only show on today)
                    if calendar.isDateInToday(selectedDate) && !overdueEvents.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 6) {
                                Circle()
                                    .fill(.red)
                                    .frame(width: 8, height: 8)
                                Text("Atrasados (\(overdueEvents.count))")
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundStyle(.red)
                            }
                            .padding(.horizontal, 4)

                            ForEach(overdueEvents) { event in
                                CalendarEventRow(event: event) {
                                    openCanvasUrl(event)
                                }
                            }
                        }
                        .padding(.bottom, 8)
                    }

                    // Day label
                    HStack {
                        Text(selectedDateLabel)
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(Color.coffeeTextPrimary)

                        if !eventsForSelectedDay.isEmpty {
                            Text("· \(eventsForSelectedDay.count) evento\(eventsForSelectedDay.count == 1 ? "" : "s")")
                                .font(.system(size: 14))
                                .foregroundStyle(Color.coffeeTextSecondary)
                        }

                        Spacer()
                    }
                    .padding(.horizontal, 4)

                    // Events for day
                    if isLoading {
                        EventCardSkeleton(count: 4)
                            .padding(.top, 16)
                    } else if eventsForSelectedDay.isEmpty {
                        VStack(spacing: 12) {
                            Image(systemName: "calendar")
                                .font(.system(size: 40))
                                .foregroundStyle(Color.coffeeTextSecondary.opacity(0.3))

                            Text("Nenhum evento neste dia")
                                .font(.system(size: 15))
                                .foregroundStyle(Color.coffeeTextSecondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, 60)
                    } else {
                        ForEach(eventsForSelectedDay) { event in
                            CalendarEventRow(event: event) {
                                openCanvasUrl(event)
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 120)
            }
            .background(Color.coffeeBackground)
        }
        .background(Color.coffeeBackground)
        .overlay(alignment: .bottomTrailing) {
            // FAB - Add event
            Button {
                showAddEvent = true
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 56, height: 56)
                    .background(Color.coffeePrimary)
                    .clipShape(Circle())
                    .shadow(color: Color.coffeePrimary.opacity(0.3), radius: 8, x: 0, y: 4)
            }
            .padding(.trailing, 20)
            .padding(.bottom, 30)
        }
        .sheet(isPresented: $showAddEvent) {
            AddEventSheet(
                disciplines: disciplines,
                onSave: { title, startAt, endAt, allDay, eventType, desc, discId in
                    Task {
                        await createEvent(
                            title: title,
                            startAt: startAt,
                            endAt: endAt,
                            allDay: allDay,
                            eventType: eventType,
                            description: desc,
                            disciplinaId: discId
                        )
                    }
                },
                onClose: { showAddEvent = false }
            )
            .presentationDetents([.large])
        }
        .task {
            await loadData()
        }
            
            // Loading overlay (initial load only)
            if isLoading && events.isEmpty {
                VStack(spacing: 16) {
                    ProgressView()
                        .scaleEffect(1.2)
                        .tint(Color.coffeePrimary)
                    
                    Text("Carregando calendário...")
                        .font(.system(size: 15))
                        .foregroundStyle(Color.coffeeTextSecondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.coffeeBackground)
            }
        }
    }

    // MARK: - Nav Bar

    private var navBar: some View {
        VStack(spacing: 0) {
            // Row 1: Back + Title + Sync
            ZStack {
                Text("Calendário ESPM")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Color.coffeeTextPrimary)

                HStack {
                    // Back button
                    Button {
                        dismiss()
                    } label: {
                        HStack(spacing: 2) {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 22, weight: .medium))
                            Text("Voltar")
                                .font(.system(size: 17))
                        }
                        .foregroundStyle(Color.coffeePrimary)
                    }

                    Spacer()

                    // Sync button
                    Button {
                        Task { await syncCanvas() }
                    } label: {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(isSyncing ? Color.coffeeTextSecondary : Color.coffeePrimary)
                            .rotationEffect(.degrees(syncRotation))
                            .frame(width: 32, height: 32)
                            .background(Color.coffeeInputBackground)
                            .clipShape(Circle())
                    }
                    .disabled(isSyncing)
                }
            }
            .padding(.horizontal, 16)
            .frame(height: 48)

            // Row 2: Segmented control + Hoje
            HStack(spacing: 12) {
                // Segmented: Semana | Mês
                HStack(spacing: 0) {
                    viewModeSegment("Semana", mode: .week)
                    viewModeSegment("Mês", mode: .month)
                }
                .background(Color.coffeeInputBackground)
                .clipShape(Capsule())

                Spacer()

                // Today button
                if !calendar.isDateInToday(selectedDate) {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            selectedDate = Date()
                        }
                    } label: {
                        Text("Hoje")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Color.coffeePrimary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.coffeePrimary.opacity(0.1))
                            .clipShape(Capsule())
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 10)
        }
        .background(Color.coffeeCardBackground)
    }

    // MARK: - Segmented Control Helper

    private func viewModeSegment(_ label: String, mode: CalendarViewMode) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.25)) {
                viewMode = mode
            }
        } label: {
            Text(label)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(viewMode == mode ? .white : Color.coffeeTextSecondary)
                .padding(.horizontal, 16)
                .padding(.vertical, 7)
                .background(
                    viewMode == mode ? Color.coffeePrimary : Color.clear
                )
                .clipShape(Capsule())
        }
    }

    // MARK: - Actions

    private func loadData() async {
        let cache = CacheManager.shared

        // Show cached events instantly
        if let cached: [CalendarEvent] = cache.get("calendar_events") {
            events = cached
            isLoading = false
        } else {
            isLoading = true
        }

        // Request notification permission
        requestNotificationPermission()

        // Load disciplines + events in PARALLEL
        async let d = try? DisciplineService.getDisciplines()
        async let e: () = fetchEvents()
        disciplines = await d ?? []
        await e

        // Cache fresh events
        cache.set("calendar_events", data: events)
        isLoading = false

        // Schedule local notifications for upcoming events
        scheduleLocalNotifications()
    }

    private func fetchEvents() async {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        let start = f.string(from: Date().addingTimeInterval(-30 * 24 * 3600))
        let end = f.string(from: Date().addingTimeInterval(120 * 24 * 3600))

        do {
            events = try await CalendarService.getEvents(start: start, end: end)
        } catch {
            print("[Calendario] Error loading events: \(error)")
        }
    }

    // MARK: - Local Notifications

    private func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if let error {
                print("[Calendario] Notification permission error: \(error)")
            }
        }
    }

    private func scheduleLocalNotifications() {
        let center = UNUserNotificationCenter.current()

        // Remove old calendar notifications before re-scheduling
        center.removePendingNotificationRequests(withIdentifiers:
            events.map { "cal_1h_\($0.id)" } + events.map { "cal_1d_\($0.id)" }
        )

        let now = Date()
        let futureEvents = events.filter { $0.startAt > now && !$0.completed }

        for event in futureEvents.prefix(60) { // iOS limit: ~64 pending notifications
            let typeLabels: [String: String] = [
                "assignment": "Atividade",
                "quiz": "Quiz",
                "exam": "Prova",
                "deadline": "Prazo",
                "event": "Evento",
                "reminder": "Lembrete"
            ]
            let typeLabel = typeLabels[event.eventType] ?? "Evento"
            let timeStr = event.startAt.formatted(date: .omitted, time: .shortened)
            let discName = event.displayName

            // 1h before
            let oneHourBefore = event.startAt.addingTimeInterval(-3600)
            if oneHourBefore > now {
                let content = UNMutableNotificationContent()
                content.title = "Em 1 hora: \(event.title)"
                content.body = "\(typeLabel) às \(timeStr)"
                if !discName.isEmpty {
                    content.body += " · \(discName)"
                }
                content.sound = .default

                let trigger = UNTimeIntervalNotificationTrigger(
                    timeInterval: oneHourBefore.timeIntervalSince(now),
                    repeats: false
                )
                let request = UNNotificationRequest(
                    identifier: "cal_1h_\(event.id)",
                    content: content,
                    trigger: trigger
                )
                center.add(request)
            }

            // 24h before
            let oneDayBefore = event.startAt.addingTimeInterval(-86400)
            if oneDayBefore > now {
                let content = UNMutableNotificationContent()
                content.title = "Amanhã: \(event.title)"
                content.body = "\(typeLabel) às \(timeStr)"
                if !discName.isEmpty {
                    content.body += " · \(discName)"
                }
                content.sound = .default

                let trigger = UNTimeIntervalNotificationTrigger(
                    timeInterval: oneDayBefore.timeIntervalSince(now),
                    repeats: false
                )
                let request = UNNotificationRequest(
                    identifier: "cal_1d_\(event.id)",
                    content: content,
                    trigger: trigger
                )
                center.add(request)
            }
        }

        let scheduled = futureEvents.prefix(60).count
        if scheduled > 0 {
            print("[Calendario] Scheduled local notifications for \(scheduled) events")
        }
    }

    private func syncCanvas() async {
        isSyncing = true
        withAnimation(.linear(duration: 1).repeatForever(autoreverses: false)) {
            syncRotation = 360
        }

        do {
            let result = try await CalendarService.syncCanvas()
            if result.status == "cooldown" {
                lastSyncMessage = "Próxima sync em \(result.remainingMinutes ?? 0) min"
            } else {
                // Wait a moment then refresh
                try? await Task.sleep(for: .seconds(2))
                await fetchEvents()
                scheduleLocalNotifications()
                lastSyncMessage = "Sincronizado com Canvas"
            }
        } catch {
            lastSyncMessage = "Erro ao sincronizar"
            print("[Calendario] Sync error: \(error)")
        }

        withAnimation { syncRotation = 0 }
        isSyncing = false

        // Auto-dismiss toast after 3s
        Task {
            try? await Task.sleep(for: .seconds(3))
            withAnimation { lastSyncMessage = nil }
        }
    }

    private func createEvent(
        title: String,
        startAt: Date,
        endAt: Date?,
        allDay: Bool,
        eventType: String,
        description: String?,
        disciplinaId: String?
    ) async {
        do {
            let newEvent = try await CalendarService.createEvent(
                title: title,
                startAt: startAt,
                endAt: endAt,
                allDay: allDay,
                eventType: eventType,
                description: description,
                disciplinaId: disciplinaId
            )
            events.append(newEvent)
            showAddEvent = false

            // Select the day of the new event
            selectedDate = newEvent.startAt

            // Re-schedule notifications with new event included
            scheduleLocalNotifications()
        } catch {
            print("[Calendario] Error creating event: \(error)")
        }
    }

    private func openCanvasUrl(_ event: CalendarEvent) {
        guard let urlStr = event.canvasUrl,
              let url = URL(string: urlStr) else { return }
        UIApplication.shared.open(url)
    }
}

// MARK: - Preview

#Preview {
    CalendarioScreenView()
        .environment(\.router, NavigationRouter())
}
