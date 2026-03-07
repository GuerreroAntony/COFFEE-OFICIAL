import SwiftUI

struct NovaDisciplinaView: View {
    @ObservedObject var viewModel: DisciplinasViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var nome = ""
    @State private var professor = ""
    @State private var semestre = ""
    @State private var previousCount: Int = 0

    var body: some View {
        NavigationStack {
            ZStack {
                CoffeeTheme.Colors.background.ignoresSafeArea()

                VStack(alignment: .leading, spacing: CoffeeTheme.Spacing.lg) {
                    // Fields
                    VStack(spacing: CoffeeTheme.Spacing.md) {
                        fieldView(label: "nome da matéria *", text: $nome, placeholder: "ex: Marketing Digital")
                        fieldView(label: "professor(a)", text: $professor, placeholder: "ex: Prof. Ana Silva")
                        fieldView(label: "semestre", text: $semestre, placeholder: "ex: 2026.1")
                    }

                    if let error = viewModel.errorMessage {
                        Text(error)
                            .font(.system(size: 13))
                            .foregroundColor(.red)
                    }

                    Spacer()

                    // Add button
                    Button {
                        Task {
                            let count = viewModel.disciplinas.count
                            previousCount = count
                            await viewModel.criar(
                                nome: nome.trimmingCharacters(in: .whitespacesAndNewlines),
                                professor: professor.trimmingCharacters(in: .whitespacesAndNewlines),
                                semestre: semestre.trimmingCharacters(in: .whitespacesAndNewlines)
                            )
                        }
                    } label: {
                        HStack {
                            if viewModel.isLoading {
                                ProgressView()
                                    .tint(.white)
                                    .padding(.trailing, 4)
                            }
                            Text("adicionar")
                                .font(.system(size: 16, weight: .semibold))
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(canAdd ? CoffeeTheme.Colors.coffee : CoffeeTheme.Colors.vanilla)
                        .clipShape(RoundedRectangle(cornerRadius: CoffeeTheme.Radius.md))
                    }
                    .disabled(!canAdd || viewModel.isLoading)
                }
                .padding(CoffeeTheme.Spacing.lg)
            }
            .navigationTitle("nova matéria")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(CoffeeTheme.Colors.espresso)
                    }
                }
            }
            .onChange(of: viewModel.disciplinas.count) { _, newCount in
                if newCount > previousCount {
                    dismiss()
                }
            }
        }
    }

    private var canAdd: Bool {
        !nome.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    @ViewBuilder
    private func fieldView(label: String, text: Binding<String>, placeholder: String) -> some View {
        VStack(alignment: .leading, spacing: CoffeeTheme.Spacing.xs) {
            Text(label)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(CoffeeTheme.Colors.almond)
                .textCase(.uppercase)

            TextField(placeholder, text: text)
                .font(.system(size: 15))
                .foregroundColor(CoffeeTheme.Colors.espresso)
                .padding(.horizontal, CoffeeTheme.Spacing.md)
                .padding(.vertical, 12)
                .background(CoffeeTheme.Colors.cardBackground)
                .clipShape(RoundedRectangle(cornerRadius: CoffeeTheme.Radius.md))
        }
    }
}
