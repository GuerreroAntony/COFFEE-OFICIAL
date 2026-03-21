import SwiftUI

// MARK: - Calendar Month Grid View
// Full month grid showing all days with colored dots for events
// Tapping a day selects it and shows events in the list below

struct CalendarMonthGridView: View {
    @Binding var selectedDate: Date
    let events: [CalendarEvent]
    let onDateSelected: (Date) -> Void

    @State private var monthOffset: Int = 0

    private let calendar = Calendar.current
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 0), count: 7)

    private let weekdaySymbols: [String] = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "pt_BR")
        return f.shortWeekdaySymbols.map { $0.prefix(3).uppercased() }
    }()

    // MARK: - Date calculations

    private var displayMonth: Date {
        calendar.date(byAdding: .month, value: monthOffset, to: Date()) ?? Date()
    }

    private var monthYearLabel: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "pt_BR")
        f.dateFormat = "MMMM yyyy"
        return f.string(from: displayMonth).capitalized
    }

    /// All days to show in the grid (including leading/trailing days from adjacent months)
    private var gridDates: [Date?] {
        guard let monthInterval = calendar.dateInterval(of: .month, for: displayMonth),
              let firstWeekday = calendar.dateComponents([.weekday], from: monthInterval.start).weekday
        else { return [] }

        // Sunday = 1 in Calendar. We want Sunday-based grid.
        let leadingEmpty = firstWeekday - 1

        let daysInMonth = calendar.range(of: .day, in: .month, for: displayMonth)?.count ?? 30

        var dates: [Date?] = Array(repeating: nil, count: leadingEmpty)

        for day in 0..<daysInMonth {
            if let date = calendar.date(byAdding: .day, value: day, to: monthInterval.start) {
                dates.append(date)
            }
        }

        // Pad to complete the last row
        let remainder = dates.count % 7
        if remainder > 0 {
            dates.append(contentsOf: Array(repeating: nil as Date?, count: 7 - remainder))
        }

        return dates
    }

    // MARK: - Event helpers

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

    private func isCurrentMonth(_ date: Date) -> Bool {
        calendar.isDate(date, equalTo: displayMonth, toGranularity: .month)
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            // Month/Year header + navigation
            HStack {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { monthOffset -= 1 }
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
                    withAnimation(.easeInOut(duration: 0.2)) { monthOffset += 1 }
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.coffeePrimary)
                        .frame(width: 32, height: 32)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 12)

            // Weekday headers
            HStack(spacing: 0) {
                ForEach(weekdaySymbols, id: \.self) { symbol in
                    Text(symbol)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Color.coffeeTextSecondary)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 8)

            // Day grid
            LazyVGrid(columns: columns, spacing: 4) {
                ForEach(Array(gridDates.enumerated()), id: \.offset) { _, date in
                    if let date {
                        dayCell(date)
                    } else {
                        Color.clear
                            .frame(height: 44)
                    }
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
                        withAnimation(.easeInOut(duration: 0.25)) { monthOffset += 1 }
                    } else if value.translation.width > 50 {
                        withAnimation(.easeInOut(duration: 0.25)) { monthOffset -= 1 }
                    }
                }
        )
        .onChange(of: selectedDate) { _, newDate in
            // If user selects a date outside current month view, jump to that month
            if !calendar.isDate(newDate, equalTo: displayMonth, toGranularity: .month) {
                let components = calendar.dateComponents([.month, .year], from: newDate)
                let currentComponents = calendar.dateComponents([.month, .year], from: Date())
                let monthDiff = (components.year! - currentComponents.year!) * 12 + (components.month! - currentComponents.month!)
                withAnimation(.easeInOut(duration: 0.2)) {
                    monthOffset = monthDiff
                }
            }
        }
    }

    // MARK: - Day Cell

    @ViewBuilder
    private func dayCell(_ date: Date) -> some View {
        let isSelected = calendar.isDate(date, inSameDayAs: selectedDate)
        let isToday = calendar.isDateInToday(date)
        let dots = dotColors(for: date)
        let eventCount = eventsFor(date: date).count

        Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                onDateSelected(date)
            }
        } label: {
            VStack(spacing: 2) {
                // Day number
                ZStack {
                    if isSelected {
                        Circle()
                            .fill(Color.coffeePrimary)
                            .frame(width: 30, height: 30)
                    } else if isToday {
                        Circle()
                            .stroke(Color.coffeePrimary, lineWidth: 1.5)
                            .frame(width: 30, height: 30)
                    }

                    Text("\(calendar.component(.day, from: date))")
                        .font(.system(size: 14, weight: isSelected || isToday ? .bold : .regular))
                        .foregroundStyle(
                            isSelected ? .white :
                            (isToday ? Color.coffeePrimary : Color.coffeeTextPrimary)
                        )
                }

                // Event dots (max 3)
                HStack(spacing: 2) {
                    if dots.isEmpty && eventCount == 0 {
                        // Invisible spacer to keep consistent height
                        Circle()
                            .fill(Color.clear)
                            .frame(width: 4, height: 4)
                    } else {
                        ForEach(Array(dots.enumerated()), id: \.offset) { _, color in
                            Circle()
                                .fill(color)
                                .frame(width: 4, height: 4)
                        }
                    }
                }
                .frame(height: 4)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 44)
        }
        .buttonStyle(.plain)
    }
}
