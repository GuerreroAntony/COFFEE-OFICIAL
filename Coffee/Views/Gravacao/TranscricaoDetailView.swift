import SwiftUI

struct TranscricaoDetailView: View {
    let gravacao: Gravacao

    @StateObject private var viewModel = ResumoViewModel()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: CoffeeTheme.Spacing.lg) {
                // Transcription text
                if let trans = gravacao.transcricao {
                    VStack(alignment: .leading, spacing: CoffeeTheme.Spacing.sm) {
                        Label("transcrição", systemImage: "text.quote")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(CoffeeTheme.Colors.almond)
                            .textCase(.uppercase)

                        Text(trans.texto)
                            .font(.system(size: 15))
                            .foregroundColor(CoffeeTheme.Colors.espresso)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(CoffeeTheme.Spacing.md)
                    .background(CoffeeTheme.Colors.cardBackground)
                    .clipShape(RoundedRectangle(cornerRadius: CoffeeTheme.Radius.md))
                }

                // Resumo section
                if viewModel.isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                } else if let resumo = viewModel.resumo {
                    NavigationLink(destination: ResumoView(resumo: resumo)) {
                        HStack {
                            Image(systemName: "doc.text.magnifyingglass")
                                .foregroundColor(CoffeeTheme.Colors.coffee)
                            Text("ver resumo")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(CoffeeTheme.Colors.coffee)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 13))
                                .foregroundColor(CoffeeTheme.Colors.almond)
                        }
                        .padding(CoffeeTheme.Spacing.md)
                        .background(CoffeeTheme.Colors.cardBackground)
                        .clipShape(RoundedRectangle(cornerRadius: CoffeeTheme.Radius.md))
                    }
                } else {
                    Button {
                        guard let trans = gravacao.transcricao else { return }
                        Task { await viewModel.gerar(transcricaoId: trans.id) }
                    } label: {
                        HStack {
                            if viewModel.isGenerating {
                                ProgressView()
                                    .tint(.white)
                                    .padding(.trailing, 4)
                            } else {
                                Image(systemName: "sparkles")
                            }
                            Text(viewModel.isGenerating ? "gerando resumo..." : "gerar resumo com IA")
                                .font(.system(size: 15, weight: .semibold))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(CoffeeTheme.Spacing.md)
                        .background(CoffeeTheme.Colors.coffee)
                        .foregroundColor(.white)
                        .clipShape(RoundedRectangle(cornerRadius: CoffeeTheme.Radius.md))
                    }
                    .disabled(viewModel.isGenerating)
                }

                if let err = viewModel.errorMessage {
                    Text(err)
                        .font(.system(size: 13))
                        .foregroundColor(.red)
                        .padding(.horizontal, CoffeeTheme.Spacing.sm)
                }
            }
            .padding(CoffeeTheme.Spacing.md)
        }
        .background(CoffeeTheme.Colors.background)
        .navigationTitle(gravacaoTitle)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if let trans = gravacao.transcricao {
                await viewModel.load(transcricaoId: trans.id)
            }
        }
    }

    private var gravacaoTitle: String {
        let fmt = DateFormatter()
        fmt.dateStyle = .medium
        fmt.locale = Locale(identifier: "pt_BR")
        return fmt.string(from: gravacao.dataAula)
    }
}
