import SwiftUI

// MARK: - Coffee Navigation Bar
// iOS-style nav bar matching .ios-nav-bar from index.css
// Back button + centered title + optional trailing button

struct CoffeeNavBar: View {
    let title: String
    var backTitle: String? = "Voltar"
    var trailingIcon: String? = nil
    var trailingAction: (() -> Void)? = nil
    var onBack: (() -> Void)? = nil

    var body: some View {
        ZStack {
            // Centered title (padded to avoid overlap with back + trailing)
            Text(title)
                .font(.coffeeNavTitle)
                .foregroundStyle(Color.coffeeTextPrimary)
                .lineLimit(1)
                .truncationMode(.tail)
                .padding(.horizontal, 72)

            // Back + trailing
            HStack {
                // Back button
                if let onBack {
                    Button(action: onBack) {
                        HStack(spacing: 2) {
                            Image(systemName: CoffeeIcon.back)
                                .font(.system(size: 22, weight: .medium))
                            if let backTitle {
                                Text(backTitle)
                                    .font(.coffeeBody)
                            }
                        }
                        .foregroundStyle(Color.coffeePrimary)
                    }
                }

                Spacer()

                // Trailing button
                if let trailingIcon, let trailingAction {
                    Button(action: trailingAction) {
                        Image(systemName: trailingIcon)
                            .font(.system(size: 18))
                            .foregroundStyle(Color.coffeePrimary)
                            .frame(width: 32, height: 32)
                            .background(Color.coffeeInputBackground)
                            .clipShape(Circle())
                    }
                }
            }
        }
        .padding(.horizontal, 8)
        .frame(height: 56)
        .background(
            Rectangle()
                .fill(.ultraThinMaterial)
        )
    }
}

// MARK: - Large Title Header (for Disciplinas)

struct CoffeeLargeTitleHeader: View {
    let greeting: String
    let subtitle: String
    let userName: String
    var onProfileTap: (() -> Void)? = nil
    var onGiftTap: (() -> Void)? = nil
    var onSettingsTap: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Top row: avatar + settings
            HStack {
                Button {
                    onProfileTap?()
                } label: {
                    HStack(spacing: 10) {
                        // Avatar circle
                        ZStack {
                            Circle()
                                .fill(Color.coffeePrimary)
                                .frame(width: 36, height: 36)
                            Image(systemName: CoffeeIcon.person)
                                .font(.system(size: 16))
                                .foregroundStyle(.white)
                        }

                        Text(userName)
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(Color.coffeePrimary)
                    }
                }

                Spacer()

                HStack(spacing: 8) {
                    if let onGiftTap {
                        Button(action: onGiftTap) {
                            Image(systemName: CoffeeIcon.gift)
                                .font(.system(size: 20))
                                .foregroundStyle(Color.coffeeTextSecondary)
                                .frame(width: 36, height: 36)
                                .background(Color.coffeeInputBackground)
                                .clipShape(Circle())
                        }
                    }

                    if let onSettingsTap {
                        Button(action: onSettingsTap) {
                            Image(systemName: CoffeeIcon.settings)
                                .font(.system(size: 20))
                                .foregroundStyle(Color.coffeeTextSecondary)
                                .frame(width: 36, height: 36)
                                .background(Color.coffeeInputBackground)
                                .clipShape(Circle())
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 4)

            // Large title
            VStack(alignment: .leading, spacing: 2) {
                Text(greeting)
                    .font(.coffeeLargeTitle)
                    .foregroundStyle(Color.coffeeTextPrimary)

                Text(subtitle)
                    .font(.coffeeFootnote)
                    .foregroundStyle(Color.coffeeTextSecondary)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 16)
            .padding(.top, 4)
        }
        .background(Color.coffeeCardBackground)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.coffeeSeparator)
                .frame(height: 0.5)
        }
    }
}

// MARK: - Sheet Header

struct CoffeeSheetHeader: View {
    let title: String
    var onClose: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 0) {
            // Handle
            Capsule()
                .fill(Color(red: 60/255, green: 60/255, blue: 67/255).opacity(0.3))
                .frame(width: 36, height: 5)
                .padding(.top, 10)
                .padding(.bottom, 8)

            // Title (centered) + Close (right-aligned)
            ZStack {
                Text(title)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Color.coffeeTextPrimary)
                    .lineLimit(1)

                if let onClose {
                    HStack {
                        Spacer()
                        Button("Fechar", action: onClose)
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(Color.coffeePrimary)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 18)
        }
    }
}

// MARK: - Preview

#Preview("Nav Bars") {
    VStack(spacing: 0) {
        CoffeeNavBar(
            title: "Barista IA",
            trailingIcon: CoffeeIcon.history,
            trailingAction: { },
            onBack: { }
        )

        CoffeeLargeTitleHeader(
            greeting: "Olá, Gabriel",
            subtitle: "2026.1 · ESPM São Paulo",
            userName: "Gabriel",
            onProfileTap: { },
            onSettingsTap: { }
        )

        Spacer()

        CoffeeSheetHeader(title: "Onde salvar?", onClose: { })
    }
    .background(Color.coffeeBackground)
}
