import SwiftUI

struct GravacoesTabView: View {
    let disciplina: Disciplina

    @State private var gravacoes: [Gravacao] = []
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if gravacoes.isEmpty {
                emptyState
            } else {
                listContent
            }
        }
        .task { await load() }
    }

    // MARK: - Subviews

    private var emptyState: some View {
        VStack(spacing: CoffeeTheme.Spacing.md) {
            Image(systemName: "mic.slash")
                .font(.system(size: 40))
                .foregroundColor(CoffeeTheme.Colors.vanilla)

            Text("nenhuma gravação ainda")
                .font(.system(size: 15))
                .foregroundColor(CoffeeTheme.Colors.almond)

            Text("use o tab 'Gravar' para registrar sua aula")
                .font(.system(size: 13))
                .foregroundColor(CoffeeTheme.Colors.vanilla)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(CoffeeTheme.Spacing.lg)
    }

    private var listContent: some View {
        ScrollView {
            LazyVStack(spacing: CoffeeTheme.Spacing.sm) {
                ForEach(gravacoes) { gravacao in
                    if gravacao.transcricao != nil {
                        NavigationLink(destination: TranscricaoDetailView(gravacao: gravacao)) {
                            GravacaoCard(gravacao: gravacao)
                        }
                        .buttonStyle(.plain)
                    } else {
                        GravacaoCard(gravacao: gravacao)
                    }
                }
            }
            .padding(CoffeeTheme.Spacing.md)
        }
    }

    // MARK: - Load

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            gravacoes = try await GravacoesService.shared.listar(disciplinaId: disciplina.id)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Gravacao card

private struct GravacaoCard: View {
    let gravacao: Gravacao

    private var dateString: String {
        let fmt = DateFormatter()
        fmt.dateStyle = .medium
        fmt.locale = Locale(identifier: "pt_BR")
        return fmt.string(from: gravacao.dataAula)
    }

    private var durationString: String {
        let mins = gravacao.duracaoSegundos / 60
        let secs = gravacao.duracaoSegundos % 60
        return String(format: "%02d:%02d", mins, secs)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: CoffeeTheme.Spacing.sm) {
            HStack {
                Image(systemName: "waveform")
                    .foregroundColor(CoffeeTheme.Colors.coffee)

                Text(dateString)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(CoffeeTheme.Colors.espresso)

                Spacer()

                Text(durationString)
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundColor(CoffeeTheme.Colors.almond)

                statusBadge
            }

            if let trans = gravacao.transcricao {
                Text(trans.texto)
                    .font(.system(size: 13))
                    .foregroundColor(CoffeeTheme.Colors.almond)
                    .lineLimit(3)
            }
        }
        .padding(CoffeeTheme.Spacing.md)
        .background(CoffeeTheme.Colors.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: CoffeeTheme.Radius.md))
    }

    @ViewBuilder
    private var statusBadge: some View {
        switch gravacao.status {
        case "completed":
            EmptyView()
        case "processing":
            Text("processando")
                .font(.system(size: 10))
                .foregroundColor(.orange)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.orange.opacity(0.15))
                .clipShape(RoundedRectangle(cornerRadius: 4))
        default:
            Text(gravacao.status)
                .font(.system(size: 10))
                .foregroundColor(CoffeeTheme.Colors.almond)
        }
    }
}
