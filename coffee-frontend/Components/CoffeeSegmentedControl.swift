import SwiftUI

// MARK: - Coffee Segmented Control
// iOS-style segmented control matching .ios-segmented from index.css
// Pill-shaped with animated selection indicator

struct CoffeeSegmentedControl: View {
    let segments: [String]
    @Binding var selected: Int
    var badgeCounts: [Int]? = nil

    @Namespace private var animation

    var body: some View {
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

                        // Badge
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
}

// MARK: - Preview

#Preview("Segmented Control") {
    VStack(spacing: 24) {
        CoffeeSegmentedControl(
            segments: ["Disciplinas", "Outros", "Recebidos"],
            selected: .constant(0),
            badgeCounts: [0, 0, 2]
        )

        CoffeeSegmentedControl(
            segments: ["Resumo", "Mapa Mental"],
            selected: .constant(1)
        )

        CoffeeSegmentedControl(
            segments: ["Mensal", "Anual"],
            selected: .constant(0)
        )
    }
    .padding(20)
    .background(Color.coffeeBackground)
}
