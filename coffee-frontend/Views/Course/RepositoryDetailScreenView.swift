import SwiftUI

// MARK: - Repository Detail Screen
// Shows recordings inside a repository, similar to CourseDetailScreenView
// Supports: swipe-to-delete recordings, rename repository

struct RepositoryDetailScreenView: View {
    @State var repository: Repository
    @Environment(\.router) private var router
    @State private var selectedRecording: Recording? = nil
    @State private var recordings: [Recording] = []
    @State private var isLoadingRecordings = true
    @State private var recordingToDelete: Recording? = nil

    // Rename
    @State private var showRenameAlert = false
    @State private var newName = ""

    var body: some View {
        VStack(spacing: 0) {
            CoffeeNavBar(
                title: repository.nome,
                trailingIcon: "pencil",
                trailingAction: {
                    newName = repository.nome
                    showRenameAlert = true
                },
                onBack: { router.goBack() }
            )

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Header info
                    HStack(spacing: 14) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(Color.coffeePrimary.opacity(0.09))
                                .frame(width: 56, height: 56)
                            Image(systemName: repository.icone)
                                .font(.system(size: 24))
                                .foregroundStyle(Color.coffeePrimary)
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            Text(repository.nome)
                                .font(.system(size: 20, weight: .bold))
                                .foregroundStyle(Color.coffeeTextPrimary)
                            Text("\(recordings.count) aulas")
                                .font(.system(size: 14))
                                .foregroundStyle(Color.coffeeTextSecondary)
                        }

                        Spacer()
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 20)

                    // Recordings section
                    if isLoadingRecordings {
                        VStack(spacing: 16) {
                            ProgressView()
                                .tint(Color.coffeePrimary)
                            Text("Carregando aulas...")
                                .font(.system(size: 14))
                                .foregroundStyle(Color.coffeeTextSecondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, 60)
                    } else if !recordings.isEmpty {
                        CoffeeSectionHeader(title: "\(recordings.count) AULAS")
                            .padding(.horizontal, 20)
                            .padding(.top, 8)

                        CoffeeCellGroup {
                            ForEach(Array(recordings.enumerated()), id: \.element.id) { index, rec in
                                SwipeableRow(
                                    onTap: { selectedRecording = rec },
                                    onDelete: { recordingToDelete = rec }
                                ) {
                                    recordingRow(rec)
                                }

                                if index < recordings.count - 1 {
                                    Divider().padding(.leading, 82)
                                }
                            }
                        }
                        .padding(.horizontal, 16)
                    } else {
                        CoffeeEmptyState(
                            icon: "waveform",
                            title: "Nenhuma aula ainda",
                            message: "As aulas que forem salvas neste repositório aparecerão aqui."
                        )
                        .frame(maxWidth: .infinity)
                        .padding(.top, 40)
                    }
                }
                .padding(.bottom, 40)
            }
        }
        .background(Color.coffeeBackground)
        .task { await loadRecordings() }
        .sheet(item: $selectedRecording) { recording in
            RecordingDetailSheet(recording: recording, disciplineName: repository.nome)
        }
        .confirmationDialog(
            "Apagar gravação?",
            isPresented: Binding(
                get: { recordingToDelete != nil },
                set: { if !$0 { recordingToDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Apagar", role: .destructive) {
                if let rec = recordingToDelete {
                    let recId = rec.id
                    withAnimation {
                        recordings.removeAll { $0.id == recId }
                    }
                    recordingToDelete = nil
                    Task {
                        do {
                            try await RecordingService.deleteRecording(id: recId)
                        } catch {
                            print("[RepositoryDetail] Error deleting recording: \(error)")
                            await loadRecordings()
                        }
                    }
                }
            }
            Button("Cancelar", role: .cancel) {
                recordingToDelete = nil
            }
        } message: {
            Text("Esta ação não pode ser desfeita.")
        }
        .alert("Renomear repositório", isPresented: $showRenameAlert) {
            TextField("Nome", text: $newName)
            Button("Cancelar", role: .cancel) { }
            Button("Salvar") {
                let trimmed = newName.trimmingCharacters(in: .whitespaces)
                if !trimmed.isEmpty {
                    let oldName = repository.nome
                    repository.nome = trimmed
                    Task {
                        do {
                            let _ = try await DisciplineService.renameRepository(id: repository.id, name: trimmed)
                        } catch {
                            print("[RepositoryDetail] Error renaming repo: \(error)")
                            repository.nome = oldName
                        }
                    }
                }
            }
        } message: {
            Text("Digite o novo nome do repositório.")
        }
    }

    private func loadRecordings() async {
        isLoadingRecordings = true
        do {
            recordings = try await RecordingService.getRecordings(sourceType: "repositorio", sourceId: repository.id)
        } catch {
            print("[RepositoryDetail] Error loading recordings: \(error)")
        }
        isLoadingRecordings = false
    }

    private func recordingRow(_ rec: Recording) -> some View {
        HStack(spacing: 14) {
            // Icon
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.coffeePrimary.opacity(0.09))
                    .frame(width: 50, height: 50)
                Image(systemName: "waveform")
                    .font(.system(size: 20))
                    .foregroundStyle(Color.coffeePrimary)
            }

            // Content
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(rec.shortSummary ?? rec.dateLabel)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Color.coffeeTextPrimary)
                        .lineLimit(1)

                    statusBadge(for: rec.status)

                    Spacer(minLength: 0)
                }

                Text(rec.durationLabel)
                    .font(.system(size: 14))
                    .foregroundStyle(Color.coffeeTextSecondary)

                if let summary = rec.shortSummary {
                    Text(summary)
                        .font(.system(size: 14))
                        .foregroundStyle(Color.coffeeTextSecondary.opacity(0.8))
                        .lineLimit(1)
                }
            }

            // Chevron
            Image(systemName: CoffeeIcon.forward)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color(red: 60/255, green: 60/255, blue: 67/255).opacity(0.35))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .contentShape(Rectangle())
    }

    private func statusBadge(for status: RecordingStatus) -> some View {
        Group {
            switch status {
            case .ready:
                Text("Pronto")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.coffeeSuccess)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 3)
                    .background(Color.coffeeSuccess.opacity(0.12))
                    .clipShape(Capsule())

            case .processing:
                Text("Processando")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.coffeeWarning)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 3)
                    .background(Color.coffeeWarning.opacity(0.12))
                    .clipShape(Capsule())

            case .error:
                Text("Erro")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.coffeeDanger)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 3)
                    .background(Color.coffeeDanger.opacity(0.12))
                    .clipShape(Capsule())
            }
        }
    }
}

#Preview {
    RepositoryDetailScreenView(
        repository: Repository(id: "preview", nome: "Preview", icone: "folder", gravacoesCount: 0, aiActive: false, createdAt: nil)
    )
    .environment(\.router, NavigationRouter())
}
