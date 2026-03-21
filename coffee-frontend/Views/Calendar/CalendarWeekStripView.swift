import SwiftUI

// MARK: - Calendar Week Strip
// Horizontal 7-day strip with colored dots indicating event status
// Swipe left/right to navigate weeks

struct CalendarWeekStripView: View {
    @Binding var selectedDate: Date
    let events: [CalendarEvent]
    let onDateSelected: (Date) -> Void

    @State private var weekOffset: Int = 0

    private let calendar = Calendar.current
    private let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "pt_BR")
        f.dateFormat = "EEE"
        return f
    }()

    private var currentWeekDates: [Date] {
        let today = calendar.startOfDay(for: Date())
        guard let weekStart = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: today)) else {
            return []
        }
        guard let offsetWeekStart = calendar.date(byAdding: .weekOfYear, value: weekOffset, to: weekStart) else {
            return []
        }
        return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: offsetWeekStart) }
    }

    private func eventsFor(date: Date) -> [CalendarEvent] {
        let dayStart = calendar.startOfDay(for: date)
        guard let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) else { return [] }
        return events.filter { $0.startAt >= dayStart && $0.startAt < dayEnd }
    }

    private func dotColors(for date: Date) -> [Color] {
        let dayEvents = eventsFor(date: date)
        var colors: [Color] = []
        for event in dayEvents.prefix(3) {
            if event.missing == true || event.isOverdue {
                colors.append(.red)
            } else if event.graded == true || event.submitted == true {
                colors.append(.green)
            } else if event.source == "manual" {
                colors.append(Color.coffeeTextSecondary)
            } else {
                colors.append(Color.coffeePrimary)
            }
        }
        return colors
    }

    private var monthYearLabel: String {
        guard let first = currentWeekDates.first else { return "" }
        let f = DateFormatter()
        f.locale = Locale(identifier: "pt_BR")
        f.dateFormat = "MMMM yyyy"
        return f.string(from: first).capitalized
    }

    var body: some View {
        VStack(spacing: 0) {
            // Month/Year + navigation arrows
            HStack {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { weekOffset -= 1 }
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.coffeePrimary)
                        .frame(width: 32, height: 32)
                }

                Spacer()

                Text(monthYearLabel)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.coffeeTextPrimary)

                Spacer()

                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { weekOffset += 1 }
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.coffeePrimary)
                        .frame(width: 32, height: 32)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 12)

            // Week days
            HStack(spacing: 0) {
                ForEach(currentWeekDates, id: \.self) { date in
                    let isSelected = calendar.isDate(date, inSameDayAs: selectedDate)
                    let isToday = calendar.isDateInToday(date)
                    let dots = dotColors(for: date)

                    Button {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            onDateSelected(date)
                        }
                    } label: {
                        VStack(spacing: 6) {
                            // Day name
                            Text(dayFormatter.string(from: date).prefix(3).uppercased())
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(isSelected ? Color.coffeePrimary : Color.coffeeTextSecondary)

                            // Day number
                            ZStack {
                                if isSelected {
                                    Circle()
                                        .fill(Color.coffeePrimary)
                                        .frame(width: 36, height: 36)
                                } else if isToday {
                                    Circle()
                                        .stroke(Color.coffeePrimary, lineWidth: 1.5)
                                        .frame(width: 36, height: 36)
                                }

                                Text("\(calendar.component(.day, from: date))")
                                    .font(.system(size: 16, weight: isSelected ? .bold : .medium))
                                    .foregroundStyle(isSelected ? .white : (isToday ? Color.coffeePrimary : Color.coffeeTextPrimary))
                            }

                            // Event dots
                            HStack(spacing: 3) {
                                ForEach(Array(dots.enumerated()), id: \.offset) { _, color in
                                    Circle()
                                        .fill(color)
                                        .frame(width: 5, height: 5)
                                }
                            }
                            .frame(height: 5)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 12)
        }
        .padding(.top, 12)
        .background(Color.coffeeCardBackground)
        .gesture(
            DragGesture(minimumDistance: 50)
                .onEnded { value in
                    if value.translation.width < -50 {
                        withAnimation(.easeInOut(duration: 0.25)) { weekOffset += 1 }
                    } else if value.translation.width > 50 {
                        withAnimation(.easeInOut(duration: 0.25)) { weekOffset -= 1 }
                    }
                }
        )
    }
}
