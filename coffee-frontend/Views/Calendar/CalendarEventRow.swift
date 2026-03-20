import SwiftUI

// MARK: - Calendar Event Row
// Single event card with colored bar, title, discipline, time, status badge

struct CalendarEventRow: View {
    let event: CalendarEvent
    var onTap: (() -> Void)? = nil

    private var barColor: Color {
        if event.missing == true || event.isOverdue { return .red }
        if event.late == true { return .orange }
        if event.graded == true || event.submitted == true { return .green }
        if event.source == "manual" { return Color.coffeeTextSecondary }
        return Color.coffeePrimary
    }

    private var statusColor: Color {
        if event.missing == true || event.isOverdue { return .red }
        if event.late == true { return .orange }
        if event.graded == true || event.submitted == true { return .green }
        return Color.coffeeTextSecondary
    }

    private var typeIcon: String {
        switch event.eventType {
        case "quiz": return "questionmark.circle.fill"
        case "assignment": return "doc.text.fill"
        case "exam": return "pencil.line"
        case "deadline": return "clock.fill"
        case "reminder": return "bell.fill"
        default: return "calendar"
        }
    }

    var body: some View {
        Button {
            onTap?()
        } label: {
            HStack(spacing: 0) {
                // Color bar
                RoundedRectangle(cornerRadius: 2)
                    .fill(barColor)
                    .frame(width: 4)
                    .padding(.vertical, 4)

                HStack(spacing: 12) {
                    // Time column
                    VStack(spacing: 2) {
                        Text(event.timeLabel)
                            .font(.system(size: 13, weight: .semibold, design: .monospaced))
                            .foregroundStyle(Color.coffeeTextPrimary)

                        if let pts = event.pointsLabel {
                            Text(pts)
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(Color.coffeeTextSecondary)
                        }
                    }
                    .frame(width: 52)

                    // Content
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            Image(systemName: typeIcon)
                                .font(.system(size: 11))
                                .foregroundStyle(barColor)

                            Text(event.title)
                                .font(.system(size: 15, weight: .medium))
                                .foregroundStyle(Color.coffeeTextPrimary)
                                .lineLimit(1)
                        }

                        if !event.displayName.isEmpty {
                            Text(event.displayName)
                                .font(.system(size: 12))
                                .foregroundStyle(Color.coffeeTextSecondary)
                                .lineLimit(1)
                        }
                    }

                    Spacer()

                    // Status badge
                    if event.isCanvas {
                        Text(event.statusLabel)
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(statusColor)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(statusColor.opacity(0.1))
                            .clipShape(Capsule())
                    }

                    // Canvas deep link indicator
                    if event.canvasUrl != nil {
                        Image(systemName: "arrow.up.right.square")
                            .font(.system(size: 12))
                            .foregroundStyle(Color.coffeeTextSecondary.opacity(0.4))
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 12)
            }
            .background(Color.coffeeCardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.coffeeSeparator, lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
    }
}
