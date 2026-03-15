import SwiftUI

// MARK: - Coffee Progress Dots
// Page indicator dots for onboarding and multi-step flows

struct CoffeeProgressDots: View {
    let total: Int
    let current: Int

    var body: some View {
        HStack(spacing: 8) {
            ForEach(0..<total, id: \.self) { index in
                Circle()
                    .fill(index == current ? Color.coffeePrimary : Color.coffeePrimary.opacity(0.2))
                    .frame(width: index == current ? 24 : 8, height: 8)
                    .animation(.easeInOut(duration: 0.2), value: current)
            }
        }
    }
}

// MARK: - Step Indicator (for LinkESPM, PaymentFlow)

struct CoffeeStepIndicator: View {
    let steps: Int
    let current: Int

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<steps, id: \.self) { index in
                Capsule()
                    .fill(index <= current ? Color.coffeePrimary : Color.coffeePrimary.opacity(0.15))
                    .frame(height: 3)
                    .animation(.easeInOut(duration: 0.3), value: current)
            }
        }
    }
}

// MARK: - Empty State View

struct CoffeeEmptyState: View {
    let icon: String
    let title: String
    let message: String
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 48))
                .foregroundStyle(Color(red: 60/255, green: 60/255, blue: 67/255).opacity(0.2))

            Text(title)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Color.coffeeTextPrimary)

            Text(message)
                .font(.system(size: 14))
                .foregroundStyle(Color.coffeeTextSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 240)

            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.coffeePrimary)
                    .padding(.top, 4)
            }
        }
        .padding(.vertical, 48)
    }
}

// MARK: - Initials Avatar

struct CoffeeAvatar: View {
    let initials: String
    let size: CGFloat
    let color: Color
    let isNew: Bool

    init(
        initials: String,
        size: CGFloat = 44,
        color: Color = .coffeeInfo,
        isNew: Bool = false
    ) {
        self.initials = initials
        self.size = size
        self.color = color
        self.isNew = isNew
    }

    var body: some View {
        ZStack {
            Circle()
                .fill(color.opacity(0.1))
                .frame(width: size, height: size)

            Text(initials)
                .font(.system(size: size * 0.3, weight: .bold))
                .foregroundStyle(color)
        }
        .overlay(alignment: .topTrailing) {
            if isNew {
                Circle()
                    .fill(Color.coffeeInfo)
                    .frame(width: 12, height: 12)
                    .overlay(
                        Circle()
                            .stroke(.white, lineWidth: 2)
                    )
                    .offset(x: 2, y: -2)
            }
        }
    }
}

// MARK: - Content Badge (Resumo, Mapa)

struct CoffeeContentBadge: View {
    let label: String
    let isHighlighted: Bool

    var body: some View {
        Text(label)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(isHighlighted ? Color.coffeeInfo : Color.coffeeTextTertiary)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(
                isHighlighted
                ? Color.coffeeInfo.opacity(0.08)
                : Color(red: 60/255, green: 60/255, blue: 67/255).opacity(0.06)
            )
            .clipShape(Capsule())
    }
}

// MARK: - Preview

#Preview("Progress & Misc") {
    VStack(spacing: 32) {
        CoffeeProgressDots(total: 3, current: 1)

        CoffeeStepIndicator(steps: 4, current: 2)
            .padding(.horizontal, 20)

        CoffeeEmptyState(
            icon: CoffeeIcon.groups,
            title: "Nada por aqui ainda",
            message: "Quando colegas compartilharem aulas com você, elas aparecerão aqui."
        )

        HStack(spacing: 12) {
            CoffeeAvatar(initials: "AB", isNew: true)
            CoffeeAvatar(initials: "LO", color: .coffeeTextTertiary)
            CoffeeAvatar(initials: "MC", size: 36)
        }

        HStack(spacing: 8) {
            CoffeeContentBadge(label: "Resumo", isHighlighted: true)
            CoffeeContentBadge(label: "Mapa Mental", isHighlighted: true)
            CoffeeContentBadge(label: "Mídia", isHighlighted: false)
        }
    }
    .padding(20)
    .background(Color.coffeeBackground)
}
