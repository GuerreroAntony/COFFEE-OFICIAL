import SwiftUI

struct CoffeeTheme {
    struct Colors {
        static let vanilla    = Color(hex: "D7BDA6")
        static let caramel    = Color(hex: "AB7743")
        static let almond     = Color(hex: "B7957F")
        static let coffee     = Color(hex: "6D3914")
        static let mocca      = Color(hex: "84593D")
        static let espresso   = Color(hex: "4C2B08")
        static let background = Color(hex: "FFFBF5")
        static let cardBackground = Color.white
    }

    struct Typography {
        static let titleSize:  CGFloat = 26
        static let bodySize:   CGFloat = 15
        static let captionSize: CGFloat = 12
        static let buttonSize: CGFloat = 16
    }

    struct Spacing {
        static let xs:  CGFloat = 4
        static let sm:  CGFloat = 8
        static let md:  CGFloat = 16
        static let lg:  CGFloat = 24
        static let xl:  CGFloat = 32
        static let xxl: CGFloat = 48
    }

    struct Radius {
        static let sm:   CGFloat = 8
        static let md:   CGFloat = 12
        static let lg:   CGFloat = 16
        static let full: CGFloat = 100
    }
}
