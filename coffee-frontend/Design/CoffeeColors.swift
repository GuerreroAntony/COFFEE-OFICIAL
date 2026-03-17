import SwiftUI

// MARK: - Coffee Design System Colors
// Mapped from Tailwind config in index.html

extension Color {
    // Primary
    static let coffeePrimary = Color(hex: "715038")
    static let coffeePrimaryLight = Color(hex: "D4A574")

    // Backgrounds
    static let coffeeBackground = Color(hex: "F2F2F7")
    static let coffeeCardBackground = Color.white
    static let coffeeRecordingBackground = Color(hex: "2A1E14")
    static let coffeeHeaderGradientTop = Color(hex: "2A1E14")
    static let coffeeHeaderGradientBottom = Color(hex: "3D2E22")

    // Text
    static let coffeeTextPrimary = Color(hex: "1C1C1E")
    static let coffeeTextSecondary = Color(hex: "6C6C70")
    static let coffeeTextTertiary = Color(hex: "8E8E93")
    static let coffeeTextPlaceholder = Color(red: 60/255, green: 60/255, blue: 67/255).opacity(0.5)

    // Semantic
    static let coffeeDanger = Color(hex: "FF3B30")
    static let coffeeSuccess = Color(hex: "34C759")
    static let coffeeWarning = Color(hex: "FF9500")
    static let coffeeInfo = Color(hex: "007AFF")
    static let coffeeYellow = Color(hex: "FFD60A")

    // Borders & Separators
    static let coffeeSeparator = Color(red: 60/255, green: 60/255, blue: 67/255).opacity(0.18)
    static let coffeeInputBackground = Color(red: 118/255, green: 118/255, blue: 128/255).opacity(0.12)

    // Tab Bar
    static let coffeeTabInactive = Color(hex: "8E8E93")

    // Segmented Control
    static let coffeeSegmentedBackground = Color(red: 118/255, green: 118/255, blue: 128/255).opacity(0.12)
}

// MARK: - Hex Initializer

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}
