import SwiftUI

extension View {
    func coffeeCard() -> some View {
        self
            .background(CoffeeTheme.Colors.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: CoffeeTheme.Radius.md))
            .shadow(color: .black.opacity(0.06), radius: 4, x: 0, y: 2)
    }

    func coffeeBackground() -> some View {
        self.background(CoffeeTheme.Colors.background.ignoresSafeArea())
    }
}
