import SwiftUI

// MARK: - Icon Picker Sheet
// Allows users to customize discipline icon and color

struct IconPickerSheet: View {
    let discipline: Discipline
    let onSave: (String, String) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var selectedIcon: String
    @State private var selectedColor: String
    @State private var isSaving = false

    private let availableIcons: [(name: String, label: String)] = [
        ("text.bubble.fill", "Chat"),
        ("heart.fill", "Favorito"),
        ("star.fill", "Destaque"),
        ("lightbulb.fill", "Ideias"),
        ("book.fill", "Livro"),
        ("graduationcap.fill", "Formatura"),
        ("brain.head.profile", "Mente"),
        ("chart.bar.fill", "Dados"),
        ("paintbrush.fill", "Arte"),
        ("globe.americas.fill", "Mundo"),
        ("music.note", "Musica"),
        ("function", "Exatas"),
        ("atom", "Ciencias"),
        ("building.columns.fill", "Direito"),
        ("megaphone.fill", "Comunic."),
        ("person.3.fill", "Pessoas"),
    ]

    private let availableColors: [(hex: String, name: String)] = [
        ("715038", "Cafe"),
        ("D4A574", "Caramelo"),
        ("C4956A", "Rose"),
        ("8B6914", "Dourado"),
        ("4A7C59", "Verde"),
        ("5B6ABF", "Indigo"),
        ("BF5B5B", "Vermelho"),
        ("2C7DA0", "Azul"),
    ]

    init(discipline: Discipline, onSave: @escaping (String, String) -> Void) {
        self.discipline = discipline
        self.onSave = onSave
        _selectedIcon = State(initialValue: discipline.icon ?? "text.bubble.fill")
        _selectedColor = State(initialValue: discipline.iconColor ?? "715038")
    }

    var body: some View {
        VStack(spacing: 0) {
            CoffeeSheetHeader(title: "Personalizar", onClose: { dismiss() })

            ScrollView {
                VStack(spacing: 24) {
                    // Preview
                    VStack(spacing: 10) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .fill(Color(hex: selectedColor).opacity(0.12))
                                .frame(width: 64, height: 64)

                            Image(systemName: selectedIcon)
                                .font(.system(size: 26))
                                .foregroundStyle(Color(hex: selectedColor))
                        }

                        Text(discipline.nome)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Color.coffeeTextPrimary)
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                    }
                    .padding(.top, 4)

                    // Icons grid
                    VStack(alignment: .leading, spacing: 10) {
                        Text("ÍCONE")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Color.coffeeTextSecondary)
                            .tracking(0.8)

                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 10) {
                            ForEach(availableIcons, id: \.name) { icon in
                                Button {
                                    withAnimation(.easeInOut(duration: 0.15)) {
                                        selectedIcon = icon.name
                                    }
                                } label: {
                                    VStack(spacing: 4) {
                                        ZStack {
                                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                                .fill(selectedIcon == icon.name
                                                      ? Color(hex: selectedColor).opacity(0.12)
                                                      : Color.coffeeInputBackground)
                                                .frame(width: 44, height: 44)

                                            Image(systemName: icon.name)
                                                .font(.system(size: 18))
                                                .foregroundStyle(
                                                    selectedIcon == icon.name
                                                    ? Color(hex: selectedColor)
                                                    : Color.coffeeTextSecondary
                                                )
                                        }
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                                .stroke(
                                                    selectedIcon == icon.name
                                                    ? Color(hex: selectedColor)
                                                    : Color.clear,
                                                    lineWidth: 1.5
                                                )
                                        )

                                        Text(icon.label)
                                            .font(.system(size: 9, weight: .medium))
                                            .foregroundStyle(Color.coffeeTextSecondary)
                                            .lineLimit(1)
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .padding(.horizontal, 20)

                    // Colors
                    VStack(alignment: .leading, spacing: 10) {
                        Text("COR")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Color.coffeeTextSecondary)
                            .tracking(0.8)

                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 8), spacing: 8) {
                            ForEach(availableColors, id: \.hex) { color in
                                Button {
                                    withAnimation(.easeInOut(duration: 0.15)) {
                                        selectedColor = color.hex
                                    }
                                } label: {
                                    ZStack {
                                        Circle()
                                            .fill(Color(hex: color.hex))
                                            .frame(width: 32, height: 32)

                                        if selectedColor == color.hex {
                                            Circle()
                                                .stroke(Color(hex: color.hex), lineWidth: 2.5)
                                                .frame(width: 40, height: 40)
                                        }
                                    }
                                    .frame(width: 40, height: 40)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .padding(.horizontal, 20)

                    // Save button
                    CoffeeButton("Salvar", isLoading: isSaving) {
                        isSaving = true
                        onSave(selectedIcon, selectedColor)
                        dismiss()
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 20)
                }
            }
        }
        .background(Color.coffeeBackground)
    }
}

#Preview {
    IconPickerSheet(
        discipline: Discipline(id: "1", nome: "Argumentacao Oral e Escrita")
    ) { icon, color in
        print("Selected: \(icon) \(color)")
    }
}
