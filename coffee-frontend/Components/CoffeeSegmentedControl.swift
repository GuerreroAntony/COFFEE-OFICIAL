import SwiftUI

// MARK: - Segmented Control Style

enum SegmentedStyle {
    case pill      // Original iOS-style with white pill on gray background
    case underline // Text with animated underline bar
}

// MARK: - Coffee Segmented Control
// Supports two styles: pill (default) and underline

struct CoffeeSegmentedControl: View {
    let segments: [String]
    @Binding var selected: Int
    var badgeCounts: [Int]? = nil
    var style: SegmentedStyle = .pill

    @Namespace private var animation

    var body: some View {
        switch style {
        case .pill:
            pillStyle
        case .underline:
            underlineStyle
        }
    }

    // MARK: - Pill Style (original)

    private var pillStyle: some View {
        HStack(spacing: 0) {
            ForEach(Array(segments.enumerated()), id: \.offset) { index, title in
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        selected = index
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(title)
                            .font(.coffeeSegmented)
                            .foregroundStyle(
                                selected == index
                                ? Color.coffeeTextPrimary
                                : Color.coffeeTextSecondary
                            )

                        if let counts = badgeCounts, index < counts.count, counts[index] > 0 {
                            Text("(\(counts[index]))")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(
                                    selected == index
                                    ? Color.coffeePrimary
                                    : Color.coffeeTextSecondary
                                )
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 9)
                    .background {
                        if selected == index {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(Color.white)
                                .shadow(color: .black.opacity(0.12), radius: 1.5, y: 0.5)
                                .shadow(color: .black.opacity(0.08), radius: 0.5, y: 0.25)
                                .matchedGeometryEffect(id: "segment", in: animation)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(Color.coffeeSegmentedBackground)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    // MARK: - Underline Style

    private var underlineStyle: some View {
        HStack(spacing: 0) {
            ForEach(Array(segments.enumerated()), id: \.offset) { index, title in
                Button {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        selected = index
                    }
                } label: {
                    VStack(spacing: 8) {
                        HStack(spacing: 4) {
                            Text(title)
                                .font(.system(size: 15, weight: selected == index ? .semibold : .regular))
                                .foregroundStyle(
                                    selected == index
                                    ? Color.coffeeTextPrimary
                                    : Color.coffeeTextSecondary
                                )

                            if let counts = badgeCounts, index < counts.count, counts[index] > 0 {
                                Text("(\(counts[index]))")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(
                                        selected == index
                                        ? Color.coffeePrimary
                                        : Color.coffeeTextSecondary
                                    )
                            }
                        }

                        // Underline bar
                        ZStack {
                            Rectangle()
                                .fill(Color.clear)
                                .frame(height: 2.5)

                            if selected == index {
                                Rectangle()
                                    .fill(Color.coffeePrimary)
                                    .frame(height: 2.5)
                                    .clipShape(Capsule())
                                    .matchedGeometryEffect(id: "underline", in: animation)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
            }
        }
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.coffeeSeparator)
                .frame(height: 0.5)
        }
    }
}

// MARK: - Preview

#Preview("Segmented Control") {
    VStack(spacing: 24) {
        CoffeeSegmentedControl(
            segments: ["Disciplinas", "Outros", "Recebidos"],
            selected: .constant(0),
            badgeCounts: [0, 0, 2],
            style: .underline
        )

        CoffeeSegmentedControl(
            segments: ["Disciplinas", "Outros", "Recebidos"],
            selected: .constant(0),
            badgeCounts: [0, 0, 2]
        )

        CoffeeSegmentedControl(
            segments: ["Resumo", "Mapa Mental"],
            selected: .constant(1)
        )
    }
    .padding(20)
    .background(Color.coffeeBackground)
}
