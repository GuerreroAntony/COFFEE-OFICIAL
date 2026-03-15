import SwiftUI

// MARK: - Coffee Typography
// Uses system SF Pro (default on iOS) — matches the React font stack
// Logo text uses Circular Std (brand typography from Lineto)

extension Font {

    // MARK: - Circular Std (Brand / Logo)

    /// Logo text — Splash screen (36px)
    static let coffeeLogoLarge = Font.custom("CircularStd-Bold", size: 36)

    /// Logo text — Login/Signup headers (28px)
    static let coffeeLogo = Font.custom("CircularStd-Bold", size: 28)

    /// Logo text — Small inline mentions (13px)
    static let coffeeLogoSmall = Font.custom("CircularStd-Bold", size: 13)

    /// Circular Std helper for arbitrary sizes
    static func circularStd(_ weight: CircularWeight, size: CGFloat) -> Font {
        Font.custom(weight.postScriptName, size: size)
    }

    // MARK: - System Fonts

    // Large Titles (34px in React)
    static let coffeeLargeTitle = Font.system(size: 34, weight: .bold, design: .default)

    // Title (28px)
    static let coffeeTitle = Font.system(size: 28, weight: .bold, design: .default)

    // Title 2 (22px)
    static let coffeeTitle2 = Font.system(size: 22, weight: .bold, design: .default)

    // Title 3 (20px)
    static let coffeeTitle3 = Font.system(size: 20, weight: .semibold, design: .default)

    // Headline (17px semibold)
    static let coffeeHeadline = Font.system(size: 17, weight: .semibold, design: .default)

    // Body (17px regular)
    static let coffeeBody = Font.system(size: 17, weight: .regular, design: .default)

    // Callout (16px)
    static let coffeeCallout = Font.system(size: 16, weight: .regular, design: .default)

    // Subheadline (15px)
    static let coffeeSubheadline = Font.system(size: 15, weight: .regular, design: .default)

    // Footnote (13px)
    static let coffeeFootnote = Font.system(size: 13, weight: .regular, design: .default)

    // Caption (12px)
    static let coffeeCaption = Font.system(size: 12, weight: .regular, design: .default)

    // Caption 2 (11px)
    static let coffeeCaption2 = Font.system(size: 11, weight: .regular, design: .default)

    // Segmented Control (13px semibold)
    static let coffeeSegmented = Font.system(size: 13, weight: .semibold, design: .default)

    // Tab Bar Label (10px medium)
    static let coffeeTabLabel = Font.system(size: 10, weight: .medium, design: .default)

    // Timer Display (RecordingFlow large timer)
    static let coffeeTimer = Font.system(size: 64, weight: .light, design: .monospaced)

    // Nav Bar Title (17px semibold)
    static let coffeeNavTitle = Font.system(size: 17, weight: .semibold, design: .default)

    // Button (17px semibold)
    static let coffeeButton = Font.system(size: 17, weight: .semibold, design: .default)
}

// MARK: - Circular Std Weights

enum CircularWeight: String {
    case book
    case medium
    case bold
    case black

    var postScriptName: String {
        switch self {
        case .book:   return "CircularStd-Book"
        case .medium: return "CircularStd-Medium"
        case .bold:   return "CircularStd-Bold"
        case .black:  return "CircularStd-Black"
        }
    }
}
