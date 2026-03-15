import SwiftUI

// MARK: - View Extensions

extension View {
    /// Applies Coffee card style (white background, rounded corners)
    func coffeeCard(radius: CGFloat = 12) -> some View {
        self
            .background(Color.coffeeCardBackground)
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
    }

    /// Applies Coffee separator line
    func coffeeSeparator(leadingPadding: CGFloat = 58) -> some View {
        self.overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.coffeeSeparator)
                .frame(height: 0.5)
                .padding(.leading, leadingPadding)
        }
    }

    /// Conditional modifier
    @ViewBuilder
    func `if`<Content: View>(_ condition: Bool, transform: (Self) -> Content) -> some View {
        if condition {
            transform(self)
        } else {
            self
        }
    }

    /// Hide keyboard
    func hideKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }

    /// iOS-style blur background
    func coffeeBlurBackground() -> some View {
        self.background(.ultraThinMaterial)
    }
}

// MARK: - Date Extensions

extension Date {
    /// "Hoje", "Ontem", or formatted date
    var coffeeRelativeLabel: String {
        let calendar = Calendar.current
        if calendar.isDateInToday(self) {
            return "Hoje"
        } else if calendar.isDateInYesterday(self) {
            return "Ontem"
        } else {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "pt_BR")
            formatter.dateFormat = "d MMM"
            return formatter.string(from: self)
        }
    }

    /// "Terça, 25 de fevereiro"
    var coffeeLongLabel: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "pt_BR")
        formatter.dateFormat = "EEEE, d 'de' MMMM"
        return formatter.string(from: self).capitalized
    }

    /// "25 fev 2026"
    var coffeeShortLabel: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "pt_BR")
        formatter.dateFormat = "d MMM yyyy"
        return formatter.string(from: self)
    }
}

// MARK: - TimeInterval Extensions

extension TimeInterval {
    /// "1h 20min" format
    var coffeeDurationLabel: String {
        let hours = Int(self) / 3600
        let minutes = (Int(self) % 3600) / 60

        if hours > 0 {
            return "\(hours)h \(minutes)min"
        } else {
            return "\(minutes)min"
        }
    }

    /// "01:23:45" timer format
    var coffeeTimerLabel: String {
        let hours = Int(self) / 3600
        let minutes = (Int(self) % 3600) / 60
        let seconds = Int(self) % 60

        if hours > 0 {
            return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%02d:%02d", minutes, seconds)
        }
    }
}

// MARK: - String Extensions

extension String {
    /// Get user initials from full name (e.g., "Ana Beatriz" → "AB")
    var initials: String {
        let components = self.split(separator: " ")
        let initials = components.prefix(2).compactMap { $0.first }
        return String(initials).uppercased()
    }
}

// MARK: - JSON Decoder with Coffee Date Strategy

extension JSONDecoder {
    static var coffeeDecoder: JSONDecoder {
        let decoder = JSONDecoder()
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let dateString = try container.decode(String.self)

            // Try ISO 8601 with fractional seconds
            if let date = formatter.date(from: dateString) {
                return date
            }

            // Try ISO 8601 without fractional seconds
            formatter.formatOptions = [.withInternetDateTime]
            if let date = formatter.date(from: dateString) {
                return date
            }

            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Cannot decode date: \(dateString)"
            )
        }
        return decoder
    }
}
