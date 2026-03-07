import SwiftUI

struct DisciplinaCard: View {
    let disciplina: Disciplina
    let index: Int

    private let barColors: [Color] = [
        CoffeeTheme.Colors.caramel,
        CoffeeTheme.Colors.mocca,
        CoffeeTheme.Colors.coffee,
        CoffeeTheme.Colors.almond,
    ]

    private var barColor: Color { barColors[index % barColors.count] }

    var body: some View {
        HStack(spacing: 0) {
            // Left color bar
            Rectangle()
                .fill(barColor)
                .frame(width: 3)
                .clipShape(RoundedRectangle(cornerRadius: 2))

            // Content
            VStack(alignment: .leading, spacing: CoffeeTheme.Spacing.xs) {
                Text(disciplina.nome)
                    .font(.system(size: 17, weight: .medium))
                    .foregroundColor(CoffeeTheme.Colors.espresso)
                    .lineLimit(1)

                Text(disciplina.professor)
                    .font(.system(size: 13))
                    .foregroundColor(CoffeeTheme.Colors.almond)
                    .lineLimit(1)

                HStack(spacing: 4) {
                    Image(systemName: "mic.fill")
                        .font(.system(size: 10))
                    Text("\(disciplina.gravacoesCount) aulas gravadas")
                        .font(.system(size: 12))
                }
                .foregroundColor(CoffeeTheme.Colors.almond)
            }
            .padding(.leading, CoffeeTheme.Spacing.md)
            .padding(.vertical, CoffeeTheme.Spacing.md)

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(CoffeeTheme.Colors.vanilla)
                .padding(.trailing, CoffeeTheme.Spacing.md)
        }
        .background(CoffeeTheme.Colors.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: CoffeeTheme.Radius.lg))
        .shadow(color: .black.opacity(0.04), radius: 8, x: 0, y: 2)
    }
}
