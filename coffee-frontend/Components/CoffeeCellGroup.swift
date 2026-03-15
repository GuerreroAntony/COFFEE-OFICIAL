import SwiftUI

// MARK: - Coffee Cell Group
// iOS-style grouped list matching .ios-cell-group + .ios-cell from index.css
// White card with rounded corners, 44pt min height rows, separators

struct CoffeeCellGroup<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        VStack(spacing: 0) {
            content
        }
        .background(Color.coffeeCardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

// MARK: - Coffee Cell (individual row)

struct CoffeeCell: View {
    let icon: String?
    let iconColor: Color
    let iconBackground: Color
    let title: String
    let subtitle: String?
    let trailing: CoffeeCellTrailing
    let showSeparator: Bool
    let action: (() -> Void)?

    init(
        icon: String? = nil,
        iconColor: Color = .coffeePrimary,
        iconBackground: Color = Color.coffeePrimary.opacity(0.1),
        title: String,
        subtitle: String? = nil,
        trailing: CoffeeCellTrailing = .chevron,
        showSeparator: Bool = true,
        action: (() -> Void)? = nil
    ) {
        self.icon = icon
        self.iconColor = iconColor
        self.iconBackground = iconBackground
        self.title = title
        self.subtitle = subtitle
        self.trailing = trailing
        self.showSeparator = showSeparator
        self.action = action
    }

    var body: some View {
        Button {
            action?()
        } label: {
            HStack(spacing: 12) {
                // Icon
                if let icon {
                    ZStack {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(iconBackground)
                            .frame(width: 44, height: 44)

                        Image(systemName: icon)
                            .font(.system(size: 20))
                            .foregroundStyle(iconColor)
                    }
                }

                // Title + Subtitle
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color.coffeeTextPrimary)
                        .lineLimit(1)

                    if let subtitle {
                        Text(subtitle)
                            .font(.coffeeFootnote)
                            .foregroundStyle(Color.coffeeTextSecondary)
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                // Trailing element
                trailingView
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(CoffeeCellButtonStyle())
        .disabled(action == nil)
        .overlay(alignment: .bottom) {
            if showSeparator {
                Rectangle()
                    .fill(Color.coffeeSeparator)
                    .frame(height: 0.5)
                    .padding(.leading, icon != nil ? 72 : 16)
            }
        }
    }

    @ViewBuilder
    private var trailingView: some View {
        switch trailing {
        case .chevron:
            Image(systemName: CoffeeIcon.forward)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color(red: 60/255, green: 60/255, blue: 67/255).opacity(0.35))

        case .text(let value):
            Text(value)
                .font(.coffeeSubheadline)
                .foregroundStyle(Color.coffeeTextSecondary)

        case .toggle(let isOn, let onChange):
            Toggle("", isOn: Binding(
                get: { isOn },
                set: { onChange($0) }
            ))
            .labelsHidden()
            .tint(Color.coffeeSuccess)

        case .check(let isSelected):
            if isSelected {
                Image(systemName: CoffeeIcon.checkCircle)
                    .font(.system(size: 20))
                    .foregroundStyle(Color.coffeePrimary)
            }

        case .badge(let count):
            if count > 0 {
                Text("\(count)")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(Color.coffeeDanger)
                    .clipShape(Capsule())
            }

        case .none:
            EmptyView()

        case .custom(let view):
            AnyView(view)
        }
    }
}

// MARK: - Cell Trailing Options

enum CoffeeCellTrailing {
    case chevron
    case text(String)
    case toggle(isOn: Bool, onChange: (Bool) -> Void)
    case check(isSelected: Bool)
    case badge(Int)
    case none
    case custom(any View)
}

// MARK: - Cell Button Style (subtle press effect)

struct CoffeeCellButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                configuration.isPressed
                ? Color(red: 60/255, green: 60/255, blue: 67/255).opacity(0.08)
                : Color.clear
            )
    }
}

// MARK: - Section Header

struct CoffeeSectionHeader: View {
    let title: String

    var body: some View {
        Text(title.uppercased())
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(Color.coffeeTextSecondary)
            .tracking(0.8)
            .padding(.horizontal, 4)
    }
}

// MARK: - Preview

#Preview("Cell Group") {
    ScrollView {
        VStack(alignment: .leading, spacing: 16) {
            CoffeeSectionHeader(title: "Suas Disciplinas")

            CoffeeCellGroup {
                CoffeeCell(
                    icon: CoffeeIcon.discipline,
                    title: "Gestão de Marketing",
                    subtitle: "12 aulas"
                ) { }

                CoffeeCell(
                    icon: CoffeeIcon.discipline,
                    title: "Finanças I",
                    subtitle: "8 aulas",
                    showSeparator: false
                ) { }
            }

            CoffeeSectionHeader(title: "Configurações")

            CoffeeCellGroup {
                CoffeeCell(
                    icon: CoffeeIcon.sparkles,
                    title: "IA Ativa",
                    trailing: .toggle(isOn: true, onChange: { _ in })
                )

                CoffeeCell(
                    icon: CoffeeIcon.person,
                    title: "Perfil",
                    trailing: .text("Gabriel"),
                    showSeparator: false
                ) { }
            }
        }
        .padding(16)
    }
    .background(Color.coffeeBackground)
}
