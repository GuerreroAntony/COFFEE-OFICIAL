import SwiftUI

struct DisciplinaDetailView: View {
    let disciplina: Disciplina
    @State private var selectedSegment = 0
    @Environment(\.dismiss) private var dismiss

    private let segments = ["Gravações", "Materiais", "Chat"]

    var body: some View {
        VStack(spacing: 0) {
            // Custom header
            VStack(alignment: .leading, spacing: CoffeeTheme.Spacing.xs) {
                Text(disciplina.nome)
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundColor(CoffeeTheme.Colors.espresso)
                    .lineLimit(2)

                Text(disciplina.professor)
                    .font(.system(size: 14))
                    .foregroundColor(CoffeeTheme.Colors.almond)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, CoffeeTheme.Spacing.lg)
            .padding(.vertical, CoffeeTheme.Spacing.md)
            .background(CoffeeTheme.Colors.background)

            // Segment picker
            HStack(spacing: 0) {
                ForEach(segments.indices, id: \.self) { i in
                    Button {
                        selectedSegment = i
                    } label: {
                        VStack(spacing: 6) {
                            Text(segments[i])
                                .font(.system(size: 14, weight: selectedSegment == i ? .semibold : .regular))
                                .foregroundColor(selectedSegment == i ? CoffeeTheme.Colors.coffee : CoffeeTheme.Colors.almond)
                                .frame(maxWidth: .infinity)

                            Rectangle()
                                .fill(selectedSegment == i ? CoffeeTheme.Colors.coffee : Color.clear)
                                .frame(height: 2)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .background(CoffeeTheme.Colors.background)
            .overlay(
                Rectangle()
                    .fill(CoffeeTheme.Colors.vanilla)
                    .frame(height: 1),
                alignment: .bottom
            )

            // Content
            ZStack {
                CoffeeTheme.Colors.background.ignoresSafeArea()
                switch selectedSegment {
                case 0: GravacoesTabView(disciplina: disciplina)
                case 1: MateriaisTabView(disciplina: disciplina)
                case 2: ChatTabView(disciplina: disciplina)
                default: EmptyView()
                }
            }
        }
        .background(CoffeeTheme.Colors.background.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(false)
    }
}
