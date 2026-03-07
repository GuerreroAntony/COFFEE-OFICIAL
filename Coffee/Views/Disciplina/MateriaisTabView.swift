import SwiftUI

struct MateriaisTabView: View {
    let disciplina: Disciplina

    @State private var materiais: [Material] = []
    @State private var isLoading = false
    @State private var isSyncing = false
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if materiais.isEmpty {
                emptyState
            } else {
                listContent
            }
        }
        .task {
            await load()
            await triggerSync()
        }
    }

    // MARK: - Subviews

    private var emptyState: some View {
        VStack(spacing: CoffeeTheme.Spacing.md) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 40))
                .foregroundColor(CoffeeTheme.Colors.vanilla)

            Text("nenhum material ainda")
                .font(.system(size: 15))
                .foregroundColor(CoffeeTheme.Colors.almond)

            if isSyncing {
                HStack(spacing: 8) {
                    ProgressView().scaleEffect(0.8)
                    Text("sincronizando com Canvas...")
                        .font(.system(size: 13))
                        .foregroundColor(CoffeeTheme.Colors.vanilla)
                }
            } else {
                Text("materiais aparecerão aqui automaticamente")
                    .font(.system(size: 13))
                    .foregroundColor(CoffeeTheme.Colors.vanilla)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(CoffeeTheme.Spacing.lg)
    }

    private var listContent: some View {
        ScrollView {
            if isSyncing {
                HStack(spacing: 8) {
                    ProgressView().scaleEffect(0.7)
                    Text("verificando novos materiais...")
                        .font(.system(size: 12))
                        .foregroundColor(CoffeeTheme.Colors.almond)
                }
                .padding(.top, CoffeeTheme.Spacing.sm)
            }

            LazyVStack(spacing: CoffeeTheme.Spacing.sm) {
                ForEach(materiais) { material in
                    MaterialCard(
                        material: material,
                        onToggleAI: { await toggleAI(materialId: material.id) }
                    )
                }
            }
            .padding(CoffeeTheme.Spacing.md)
        }
        .refreshable { await load() }
    }

    // MARK: - Actions

    private func load() async {
        isLoading = materiais.isEmpty
        defer { isLoading = false }
        do {
            materiais = try await MateriaisService.shared.listar(disciplinaId: disciplina.id)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func triggerSync() async {
        isSyncing = true
        defer { isSyncing = false }
        do {
            let resp = try await MateriaisService.shared.triggerSync(disciplinaId: disciplina.id)
            if resp.status == "triggered" {
                try? await Task.sleep(nanoseconds: 30_000_000_000) // 30s
                await load()
            }
        } catch {
            // Sync failure is non-critical
        }
    }

    private func toggleAI(materialId: UUID) async {
        do {
            _ = try await MateriaisService.shared.toggleAI(materialId: materialId)
            await load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Material Card

private struct MaterialCard: View {
    let material: Material
    let onToggleAI: () async -> Void

    private var typeIcon: String {
        switch material.tipo {
        case "pdf":   return "doc.fill"
        case "slide": return "rectangle.split.3x1.fill"
        default:      return "doc"
        }
    }

    private var dateString: String {
        let fmt = DateFormatter()
        fmt.dateStyle = .medium
        fmt.locale = Locale(identifier: "pt_BR")
        return fmt.string(from: material.createdAt)
    }

    var body: some View {
        HStack(spacing: CoffeeTheme.Spacing.md) {
            Image(systemName: typeIcon)
                .font(.system(size: 20))
                .foregroundColor(CoffeeTheme.Colors.coffee)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 4) {
                Text(material.nome)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(CoffeeTheme.Colors.espresso)
                    .lineLimit(2)

                HStack(spacing: 6) {
                    Text(material.tipo.uppercased())
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(CoffeeTheme.Colors.almond)

                    Text("·")
                        .foregroundColor(CoffeeTheme.Colors.vanilla)

                    Text(dateString)
                        .font(.system(size: 10))
                        .foregroundColor(CoffeeTheme.Colors.almond)
                }
            }

            Spacer()

            Button {
                Task { await onToggleAI() }
            } label: {
                Text(material.aiEnabled ? "ON" : "OFF")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(material.aiEnabled ? Color.green : Color.red.opacity(0.7))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            .buttonStyle(.plain)
        }
        .padding(CoffeeTheme.Spacing.md)
        .background(CoffeeTheme.Colors.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: CoffeeTheme.Radius.md))
    }
}
