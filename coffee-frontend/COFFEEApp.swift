import SwiftUI
import RevenueCat

@main
struct COFFEEApp: App {
    init() {
        // Fix: ScrollView delays first tap on buttons — disable it globally
        UIScrollView.appearance().delaysContentTouches = false
        
        // Configure RevenueCat SDK
        configureRevenueCat()

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
    
    private func configureRevenueCat() {
        #if DEBUG
        Purchases.logLevel = .debug
        #endif
        let apiKey = "appl_TCtLvTklrAajtSzmakUlbOxYcAh"
        
        Purchases.configure(withAPIKey: apiKey)
        print("✅ RevenueCat configurado com sucesso")
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .preferredColorScheme(.light)
        }
    }
}
