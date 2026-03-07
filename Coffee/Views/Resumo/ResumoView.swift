import SwiftUI

struct ResumoView: View {
    let resumo: Resumo

    @State private var tituloEditado: String
    @State private var editandoTitulo = false
    @State private var expandedTopicos: Set<String> = []
    @State private var isSavingTitulo = false

    init(resumo: Resumo) {
        self.resumo = resumo
        _tituloEditado = State(initialValue: resumo.titulo)
    }

    private var shareText: String {
        var parts = [tituloEditado, "", resumo.resumoGeral]
        if !resumo.topicos.isEmpty {
            parts += ["", "Tópicos:"]
            parts += resumo.topicos.map { "• \($0.titulo)" }
        }
        if !resumo.conceitosChave.isEmpty {
            parts += ["", "Conceitos-chave:"]
            parts += resumo.conceitosChave.map { "• \($0.termo): \($0.definicao)" }
        }
        return parts.joined(separator: "\n")
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: CoffeeTheme.Spacing.lg) {

                // Título editável
                HStack(spacing: CoffeeTheme.Spacing.sm) {
                    if editandoTitulo {
                        TextField("título", text: $tituloEditado)
                            .font(.system(size: 20, weight: .bold))
                            .foregroundColor(CoffeeTheme.Colors.espresso)
                            .textFieldStyle(.plain)
                    } else {
                        Text(tituloEditado)
                            .font(.system(size: 22, weight: .bold))
                            .foregroundColor(CoffeeTheme.Colors.espresso)
                    }

                    Spacer()

                    Button {
                        if editandoTitulo {
                            Task { await saveTitulo() }
                        } else {
                            editandoTitulo = true
                        }
                    } label: {
                        if isSavingTitulo {
                            ProgressView()
                                .scaleEffect(0.8)
                        } else {
                            Image(systemName: editandoTitulo ? "checkmark.circle.fill" : "pencil")
                                .font(.system(size: 18))
                                .foregroundColor(CoffeeTheme.Colors.coffee)
                        }
                    }
                }

                // Accordion tópicos
                if !resumo.topicos.isEmpty {
                    sectionHeader("tópicos", icon: "list.bullet")
                    VStack(spacing: CoffeeTheme.Spacing.xs) {
                        ForEach(resumo.topicos, id: \.titulo) { topico in
                            let isExpanded = Binding<Bool>(
                                get: { expandedTopicos.contains(topico.titulo) },
                                set: { open in
                                    if open { expandedTopicos.insert(topico.titulo) }
                                    else { expandedTopicos.remove(topico.titulo) }
                                }
                            )
                            DisclosureGroup(isExpanded: isExpanded) {
                                if !topico.conteudo.isEmpty {
                                    Text(topico.conteudo)
                                        .font(.system(size: 14))
                                        .foregroundColor(CoffeeTheme.Colors.almond)
                                        .fixedSize(horizontal: false, vertical: true)
                                        .padding(.top, CoffeeTheme.Spacing.xs)
                                }
                            } label: {
                                Text(topico.titulo)
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundColor(CoffeeTheme.Colors.espresso)
                            }
                            .padding(CoffeeTheme.Spacing.md)
                            .background(CoffeeTheme.Colors.cardBackground)
                            .clipShape(RoundedRectangle(cornerRadius: CoffeeTheme.Radius.md))
                            .accentColor(CoffeeTheme.Colors.coffee)
                        }
                    }
                }

                // Resumo geral
                if !resumo.resumoGeral.isEmpty {
                    sectionHeader("resumo", icon: "text.alignleft")
                    Text(resumo.resumoGeral)
                        .font(.system(size: 15))
                        .foregroundColor(CoffeeTheme.Colors.espresso)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(CoffeeTheme.Spacing.md)
                        .background(CoffeeTheme.Colors.cardBackground)
                        .clipShape(RoundedRectangle(cornerRadius: CoffeeTheme.Radius.md))
                }

                // Conceitos-chave
                if !resumo.conceitosChave.isEmpty {
                    sectionHeader("conceitos-chave", icon: "lightbulb")
                    VStack(spacing: CoffeeTheme.Spacing.sm) {
                        ForEach(resumo.conceitosChave, id: \.termo) { conceito in
                            VStack(alignment: .leading, spacing: CoffeeTheme.Spacing.xs) {
                                Text(conceito.termo)
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(CoffeeTheme.Colors.espresso)
                                Text(conceito.definicao)
                                    .font(.system(size: 13))
                                    .foregroundColor(CoffeeTheme.Colors.almond)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .padding(CoffeeTheme.Spacing.md)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(CoffeeTheme.Colors.cardBackground)
                            .clipShape(RoundedRectangle(cornerRadius: CoffeeTheme.Radius.md))
                        }
                    }
                }

            }
            .padding(CoffeeTheme.Spacing.md)
        }
        .background(CoffeeTheme.Colors.background)
        .navigationTitle(tituloEditado)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                ShareLink(item: shareText) {
                    Image(systemName: "square.and.arrow.up")
                        .foregroundColor(CoffeeTheme.Colors.coffee)
                }
            }
        }
    }

    // MARK: - Helpers

    @ViewBuilder
    private func sectionHeader(_ title: String, icon: String) -> some View {
        Label(title, systemImage: icon)
            .font(.system(size: 12, weight: .semibold))
            .foregroundColor(CoffeeTheme.Colors.almond)
            .textCase(.uppercase)
    }

    private func saveTitulo() async {
        let trimmed = tituloEditado.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        isSavingTitulo = true
        defer { isSavingTitulo = false }
        _ = try? await ResumosService.shared.atualizarTitulo(resumoId: resumo.id, titulo: trimmed)
        tituloEditado = trimmed
        editandoTitulo = false
    }
}
