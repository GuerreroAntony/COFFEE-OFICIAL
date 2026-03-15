import SwiftUI

// MARK: - Coffee Button
// iOS-style primary button matching .ios-btn-primary from index.css
// Also includes secondary, destructive, and text variants

struct CoffeeButton: View {
    let title: String
    let icon: String?
    let style: CoffeeButtonVariant
    let isLoading: Bool
    let isDisabled: Bool
    let action: () -> Void

    init(
        _ title: String,
        icon: String? = nil,
        style: CoffeeButtonVariant = .primary,
        isLoading: Bool = false,
        isDisabled: Bool = false,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.icon = icon
        self.style = style
        self.isLoading = isLoading
        self.isDisabled = isDisabled
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if isLoading {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: style.foregroundColor))
                        .scaleEffect(0.9)
                } else {
                    if let icon {
                        Image(systemName: icon)
                            .font(.system(size: 17, weight: .semibold))
                    }
                    Text(title)
                        .font(.coffeeButton)
                }
            }
            .foregroundStyle(style.foregroundColor)
            .frame(maxWidth: .infinity)
            .frame(height: style.height)
            .background(style.backgroundColor)
            .clipShape(RoundedRectangle(cornerRadius: style.cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: style.cornerRadius, style: .continuous)
                    .stroke(style.borderColor, lineWidth: style.borderWidth)
            )
        }
        .disabled(isDisabled || isLoading)
        .opacity(isDisabled ? 0.5 : 1.0)
        .if(style == .primary) { view in
            view.coffeeShimmer()
        }
    }
}

// MARK: - Button Variants

enum CoffeeButtonVariant: Equatable {
    case primary
    case secondary
    case destructive
    case text
    case outline

    var backgroundColor: Color {
        switch self {
        case .primary: return .coffeePrimary
        case .secondary: return .coffeeInputBackground
        case .destructive: return .coffeeDanger
        case .text: return .clear
        case .outline: return .clear
        }
    }

    var foregroundColor: Color {
        switch self {
        case .primary, .destructive: return .white
        case .secondary: return .coffeePrimary
        case .text: return .coffeePrimary
        case .outline: return .coffeePrimary
        }
    }

    var borderColor: Color {
        switch self {
        case .outline: return .coffeeSeparator
        default: return .clear
        }
    }

    var borderWidth: CGFloat {
        switch self {
        case .outline: return 0.5
        default: return 0
        }
    }

    var height: CGFloat {
        switch self {
        case .text: return 44
        default: return 50
        }
    }

    var cornerRadius: CGFloat {
        switch self {
        case .text: return 0
        default: return 14
        }
    }
}

// MARK: - Preview

#Preview("Primary") {
    VStack(spacing: 16) {
        CoffeeButton("Entrar", icon: "arrow.right") { }
        CoffeeButton("Criar conta", style: .secondary) { }
        CoffeeButton("Excluir conta", style: .destructive) { }
        CoffeeButton("Cancelar", style: .text) { }
        CoffeeButton("Selecionar", style: .outline) { }
        CoffeeButton("Carregando...", isLoading: true) { }
        CoffeeButton("Desativado", isDisabled: true) { }
    }
    .padding(20)
    .background(Color.coffeeBackground)
}
