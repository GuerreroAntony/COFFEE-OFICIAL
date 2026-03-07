import SwiftUI

struct EmptyStateView: View {
    let icon: String
    let title: String
    let subtitle: String

    var body: some View {
        VStack(spacing: CoffeeTheme.Spacing.md) {
            Spacer()
            Image(systemName: icon)
                .font(.system(size: 48))
                .foregroundColor(CoffeeTheme.Colors.vanilla)
            Text(title)
                .font(.system(size: CoffeeTheme.Typography.bodySize, weight: .semibold))
                .foregroundColor(CoffeeTheme.Colors.espresso)
            Text(subtitle)
                .font(.system(size: CoffeeTheme.Typography.captionSize))
                .foregroundColor(CoffeeTheme.Colors.almond)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .padding(CoffeeTheme.Spacing.xl)
    }
}
