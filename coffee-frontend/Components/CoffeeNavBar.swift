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
        .padding(.horizontal, 16)
        .frame(height: 56)
        .background(
            Rectangle()
                .fill(.ultraThinMaterial)
        )
    }
}

// MARK: - Large Title Header (for Disciplinas)
// Dark gradient header with split greeting layout

struct CoffeeLargeTitleHeader: View {
    let greeting: String
    let subtitle: String
    var planStatus: UserPlan? = nil
    var trialEnd: Date? = nil
    var onCalendarTap: (() -> Void)? = nil
    var upcomingCount: Int = 0
    var onMenuTap: (() -> Void)? = nil
    var onPlanTap: (() -> Void)? = nil

    /// Extract just the name from "Olá, Leonardo"
    private var userName: String {
        if let commaIndex = greeting.firstIndex(of: ",") {
            return String(greeting[greeting.index(after: commaIndex)...]).trimmingCharacters(in: .whitespaces)
        }
        return greeting
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Top row: "OLÁ," + action icons
            HStack(alignment: .center) {
                Text("Vai um cafezinho?")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.coffeePrimaryLight)
                    .tracking(0.5)

                Spacer()

                HStack(spacing: 10) {
                    // Calendar icon (Black/Trial only)
                    if let onCalendarTap {
                        Button(action: onCalendarTap) {
                            ZStack(alignment: .topTrailing) {
                                Image(systemName: "calendar")
                                    .font(.system(size: 17, weight: .medium))
                                    .foregroundStyle(Color.coffeePrimaryLight)
                                    .frame(width: 38, height: 38)
                                    .background(Color.white.opacity(0.12))
                                    .clipShape(Circle())

                                // Badge with upcoming count
                                if upcomingCount > 0 {
                                    Text("\(min(upcomingCount, 99))")
                                        .font(.system(size: 9, weight: .bold))
                                        .foregroundStyle(.white)
                                        .frame(minWidth: 16, minHeight: 16)
                                        .background(.red)
                                        .clipShape(Circle())
                                        .offset(x: 4, y: -4)
                                }
                            }
                        }
                    }

                    // Hamburger menu
                    if let onMenuTap {
                        Button(action: onMenuTap) {
                            Image(systemName: "line.3.horizontal")
                                .font(.system(size: 18, weight: .medium))
                                .foregroundStyle(Color.coffeePrimaryLight)
                                .frame(width: 38, height: 38)
                                .background(Color.white.opacity(0.12))
                                .clipShape(Circle())
                        }
                    }
                }
            }

            // Name — large and bold
            Text(userName)
                .font(.system(size: 32, weight: .bold))
                .foregroundStyle(.white)

            // Subtitle + plan badge
            HStack(spacing: 8) {
                Text(subtitle)
                    .font(.system(size: 13))
                    .foregroundStyle(Color.white.opacity(0.55))

                Spacer()

                if let plan = planStatus {
                    Button { onPlanTap?() } label: {
                        planBadge(plan)
                    }
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 24)
        .padding(.top, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            Color.coffeeHeaderGradientTop
                .ignoresSafeArea(edges: .top)
        )
    }

    @ViewBuilder
    private func planBadge(_ plan: UserPlan) -> some View {
        switch plan {
        case .cafeCurto:
            badgeCapsule(
                icon: "cup.and.saucer",
                text: "Café Curto",
                color: Color.coffeePrimaryLight
            )

        case .cafeComLeite:
            badgeCapsule(
                icon: "cup.and.saucer.fill",
                text: "Café com Leite",
                color: Color.coffeePrimaryLight
            )

        case .black:
            badgeCapsule(
                icon: "flame.fill",
                text: "Black",
                color: Color.coffeePrimaryLight
            )

        case .trial:
            badgeCapsule(
                icon: nil,
                text: trialDaysText,
                color: Color.coffeeWarning,
                showDot: true
            )

        case .expired:
            badgeCapsule(
                icon: nil,
                text: "Expirado",
                color: Color.coffeeDanger,
                showDot: true
            )
        }
    }

    private func badgeCapsule(icon: String?, text: String, color: Color, showDot: Bool = false) -> some View {
        HStack(spacing: 5) {
            if showDot {
                Circle()
                    .fill(color)
                    .frame(width: 6, height: 6)
            }
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 10))
            }
            Text(text)
                .font(.system(size: 11, weight: .bold))
        }
        .foregroundStyle(color)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Color.white.opacity(0.15))
        .clipShape(Capsule())
    }

    private var trialDaysText: String {
        guard let end = trialEnd else { return "Trial" }
        let days = Calendar.current.dateComponents([.day], from: Date(), to: end).day ?? 0
        if days <= 0 { return "Trial expirado" }
        if days == 1 { return "Trial · 1 dia" }
        return "Trial · \(days) dias"
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
            onMenuTap: { }
        )

        Spacer()

        CoffeeSheetHeader(title: "Onde salvar?", onClose: { })
    }
    .background(Color.coffeeBackground)
}
