import SwiftUI

struct CoffeeTextField: View {
    let placeholder: String
    @Binding var text: String
    var isSecure: Bool = false
    var icon: String? = nil

    var body: some View {
        HStack(spacing: CoffeeTheme.Spacing.sm) {
            if let icon {
                Image(systemName: icon)
                    .foregroundColor(CoffeeTheme.Colors.almond)
            }
            if isSecure {
                SecureField(placeholder, text: $text)
            } else {
                TextField(placeholder, text: $text)
            }
        }
        .font(.system(size: CoffeeTheme.Typography.bodySize))
        .foregroundColor(CoffeeTheme.Colors.espresso)
        .padding(.bottom, CoffeeTheme.Spacing.xs)
        .overlay(
            Rectangle()
                .frame(height: 1)
                .foregroundColor(CoffeeTheme.Colors.vanilla),
            alignment: .bottom
        )
    }
}
