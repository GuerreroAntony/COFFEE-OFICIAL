import SwiftUI

enum CoffeeButtonStyle { case primary, secondary }

struct CoffeeButton: View {
    let title: String
    var style: CoffeeButtonStyle = .primary
    var isLoading: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                if isLoading {
                    ProgressView().tint(style == .primary ? .white : CoffeeTheme.Colors.almond)
                } else {
                    Text(title)
                        .font(.system(size: CoffeeTheme.Typography.buttonSize, weight: .semibold))
                        .foregroundColor(style == .primary ? .white : CoffeeTheme.Colors.almond)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .background(style == .primary ? CoffeeTheme.Colors.coffee : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: CoffeeTheme.Radius.sm))
            .overlay(
                RoundedRectangle(cornerRadius: CoffeeTheme.Radius.sm)
                    .stroke(style == .secondary ? CoffeeTheme.Colors.almond : Color.clear, lineWidth: 1.5)
            )
        }
        .disabled(isLoading)
    }
}
