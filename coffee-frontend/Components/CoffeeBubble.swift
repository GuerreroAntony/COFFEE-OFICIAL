import SwiftUI
import MarkdownUI

// MARK: - Coffee Chat Bubble
// iOS-style chat bubbles matching .ios-bubble-sent / .ios-bubble-received from index.css

struct CoffeeBubble: View {
    let text: String
    let isFromUser: Bool
    var isStreaming: Bool = false

    var body: some View {
        HStack {
            if isFromUser { Spacer(minLength: 60) }

            Group {
                if isFromUser || isStreaming {
                    Text(text)
                        .font(.system(size: 15))
                        .lineSpacing(4)
                } else {
                    Markdown(text)
                        .markdownTheme(.coffee)
                }
            }
            .foregroundStyle(isFromUser ? .white : Color.coffeeTextPrimary)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(isFromUser ? Color.coffeePrimary : Color(hex: "E9E9EB"))
            .clipShape(ChatBubbleShape(isFromUser: isFromUser))

            if !isFromUser { Spacer(minLength: 60) }
        }
    }
}

// MARK: - Source Citation Card

struct CoffeeSourceCard: View {
    let title: String
    let subtitle: String
    let icon: String
    var onTap: (() -> Void)? = nil

    var body: some View {
        Button {
            onTap?()
        } label: {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.coffeePrimary.opacity(0.1))
                        .frame(width: 32, height: 32)

                    Image(systemName: icon)
                        .font(.system(size: 14))
                        .foregroundStyle(Color.coffeePrimary)
                }

                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.coffeePrimary)
                        .lineLimit(1)

                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(Color.coffeeTextSecondary)
                        .lineLimit(1)
                }

                Spacer()

                Image(systemName: CoffeeIcon.forward)
                    .font(.system(size: 14))
                    .foregroundStyle(Color(red: 60/255, green: 60/255, blue: 67/255).opacity(0.35))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Color.coffeeCardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.coffeeSeparator, lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - AI Mode Pill

struct CoffeeModePill: View {
    let mode: AIMode
    var onTap: (() -> Void)? = nil

    var body: some View {
        Button {
            onTap?()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: mode.icon)
                    .font(.system(size: 13))
                Text(mode.displayName)
                    .font(.system(size: 12, weight: .semibold))
            }
            .foregroundStyle(Color.coffeePrimary)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color.coffeeInputBackground)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Context Pill (Discipline/Recording selector)

struct CoffeeContextPill: View {
    let icon: String
    let label: String
    let isSelected: Bool
    var onTap: (() -> Void)? = nil

    var body: some View {
        Button {
            onTap?()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 14))

                Text(label)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)

                Image(systemName: CoffeeIcon.expandMore)
                    .font(.system(size: 14))
                    .foregroundStyle(Color(red: 60/255, green: 60/255, blue: 67/255).opacity(0.4))
            }
            .foregroundStyle(isSelected ? Color.coffeePrimary : Color.coffeeTextSecondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity)
            .background(
                isSelected
                ? Color.coffeePrimary.opacity(0.1)
                : Color.coffeeInputBackground.opacity(0.75)
            )
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Preview

#Preview("Chat Bubbles") {
    VStack(spacing: 12) {
        CoffeeBubble(text: "O que são os 4Ps do Marketing?", isFromUser: true)

        CoffeeBubble(
            text: "Os 4Ps do Marketing são: Produto, Preço, Praça e Promoção.",
            isFromUser: false
        )

        CoffeeSourceCard(
            title: "Aula 25/02",
            subtitle: "25 fev 2026 · 1h 20min",
            icon: CoffeeIcon.playCircle
        )

        HStack {
            CoffeeModePill(mode: .lungo)
            CoffeeModePill(mode: .espresso)
            CoffeeModePill(mode: .coldBrew)
        }

        HStack(spacing: 8) {
            CoffeeContextPill(icon: CoffeeIcon.menuBook, label: "Marketing", isSelected: true)
            Image(systemName: CoffeeIcon.forward)
                .font(.system(size: 16))
                .foregroundStyle(Color.coffeeSeparator)
            CoffeeContextPill(icon: CoffeeIcon.mic, label: "Todas", isSelected: false)
        }

        TypingIndicator()
            .frame(maxWidth: .infinity, alignment: .leading)
    }
    .padding(16)
    .background(Color.coffeeBackground)
}
