import SwiftUI

@main
struct COFFEEApp: App {
    init() {
        // Fix: ScrollView delays first tap on buttons — disable it globally
        UIScrollView.appearance().delaysContentTouches = false

        // DEBUG: Print registered Circular font names
        #if DEBUG
        for family in UIFont.familyNames.sorted() where family.lowercased().contains("circular") {
            print("📝 Font family: \(family)")
            for name in UIFont.fontNames(forFamilyName: family) {
                print("   → \(name)")
            }
        }
        #endif
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .preferredColorScheme(.light)
        }
    }
}
