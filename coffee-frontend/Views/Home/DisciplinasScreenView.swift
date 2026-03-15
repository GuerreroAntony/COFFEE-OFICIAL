import SwiftUI

// MARK: - Disciplinas Screen (Home Tab)
// 3 sub-tabs: Disciplinas, Outros (repos), Recebidos
// Matches Disciplinas.jsx

struct DisciplinasScreenView: View {
    @Environment(\.router) private var router

    @State private var activeTab = 0
    @State private var disciplines: [Discipline] = []
    @State private var repositories: [Repository] = []
    @State private var sharedItems: [SharedItem] = []
    @State private var isLoading = true
    @State private var creatingRepo = false
    @State private var newRepoName = ""
    @State private var allocatingItem: SharedItem? = nil
    @State private var repoToDelete: Repository? = nil

    private var newCount: Int { sharedItems.filter(\.isNew).count }
    private var tabs: [String] { ["Disciplinas", "Outros", "Recebidos\(newCount > 0 ? " (\(newCount))" : "")"] }

    private var dynamicSubtitle: String {
        // Extract semester number and sala from the first discipline that has them
        let semestre = disciplines.compactMap(\.semestre).first
        let sala = disciplines.compactMap(\.sala).first

        if let semestre, let sala {
            return "\(semestre)º semestre · Sala \(sala)"
        } else if let semestre {
            return "\(semestre)º semestre"
        } else if let sala {
            return "Sala \(sala)"
        } else {
            return "ESPM"
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Large Title Header
            CoffeeLargeTitleHeader(
                greeting: "Olá, \(router.currentUser?.nome ?? "Aluno")",
                subtitle: dynamicSubtitle,
                userName: router.currentUser?.nome ?? "Aluno",
                onProfileTap: { router.showProfile = true },
                onGiftTap: { router.showPromoCodes = true },
                onSettingsTap: { router.showSettings = true }
            )

            ScrollView {
                VStack(spacing: 0) {
                    // Segmented Control
                    CoffeeSegmentedControl(
                        segments: tabs,
                        selected: $activeTab
                    )
                    .padding(.horizontal, 16)
                    .padding(.top, 20)
                    .padding(.bottom, 20)

                    // Tab Content
                    switch activeTab {
                    case 0: disciplinasTab
                    case 1: outrosTab
                    case 2: recebidosTab
                    default: EmptyView()
                    }
                }
                .padding(.bottom, 120)
            }
        }
        .background(Color.coffeeBackground)
        .task { await loadData() }
        .onChange(of: router.selectedRepository) { _, newValue in
            if newValue == nil { Task { await loadData() } }
        }
        .onChange(of: router.selectedCourse) { _, newValue in
            if newValue == nil { Task { await loadData() } }
        }
        .confirmationDialog(
            "Excluir repositório?",
            isPresented: Binding(
                get: { repoToDelete != nil },
                set: { if !$0 { repoToDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Excluir", role: .destructive) {
                if let repo = repoToDelete {
                    handleDeleteRepo(repo)
                    repoToDelete = nil
                }
            }
            Button("Cancelar", role: .cancel) {
                repoToDelete = nil
            }
        } message: {
            if let repo = repoToDelete {
                Text("O repositório \"\(repo.nome)\" e todas as gravações dentro dele serão excluídos. Esta ação não pode ser desfeita.")
            }
        }
        .sheet(item: $allocatingItem) { item in
            AllocationSheet(
                item: item,
                disciplines: disciplines,
                repositories: repositories,
                onAllocate: { _ in
                    sharedItems.removeAll { $0.id == item.id }
                    allocatingItem = nil
                },
                onClose: { allocatingItem = nil }
            )
            .presentationDetents([.medium, .large])
        }
    }

    // MARK: - Disciplinas Tab

    private var disciplinasTab: some View {
        VStack(alignment: .leading, spacing: 12) {
            CoffeeSectionHeader(title: "Suas Disciplinas")
                .padding(.horizontal, 20)

            CoffeeCellGroup {
                ForEach(Array(disciplines.enumerated()), id: \.element.id) { index, discipline in
                    Button {
                        router.selectCourse(discipline)
                    } label: {
                        HStack(spacing: 14) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .fill(Color.coffeePrimary.opacity(0.09))
                                    .frame(width: 52, height: 52)

                                Image(systemName: CoffeeIcon.menuBook)
                                    .font(.system(size: 20))
                                    .foregroundStyle(Color.coffeePrimary)
                            }

                            VStack(alignment: .leading, spacing: 3) {
                                Text(discipline.nome)
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundStyle(Color.coffeeTextPrimary)
                                Text("\(discipline.gravacoesCount) aulas")
                                    .font(.system(size: 14))
                                    .foregroundStyle(Color.coffeeTextSecondary)
                            }

                            Spacer()

                            Image(systemName: "chevron.right")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(Color.coffeeTextSecondary.opacity(0.4))
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 16)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(CoffeeCellButtonStyle())

                    if index < disciplines.count - 1 {
                        Divider().padding(.leading, 82)
                    }
                }
            }
            .padding(.horizontal, 16)
        }
    }

    // MARK: - Outros Tab (Repositories)

    private var outrosTab: some View {
        VStack(alignment: .leading, spacing: 12) {
            CoffeeSectionHeader(title: "Seus Repositórios")
                .padding(.horizontal, 20)

            CoffeeCellGroup {
                ForEach(Array(repositories.enumerated()), id: \.element.id) { index, repo in
                    Button {
                        router.selectRepository(repo)
                    } label: {
                        HStack(spacing: 14) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .fill(Color.coffeePrimary.opacity(0.09))
                                    .frame(width: 52, height: 52)

                                Image(systemName: repo.icone)
                                    .font(.system(size: 20))
                                    .foregroundStyle(Color.coffeePrimary)
                            }

                            VStack(alignment: .leading, spacing: 3) {
                                Text(repo.nome)
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundStyle(Color.coffeeTextPrimary)
                                Text("\(repo.gravacoesCount) aulas")
                                    .font(.system(size: 14))
                                    .foregroundStyle(Color.coffeeTextSecondary)
                            }

                            Spacer()

                            Image(systemName: "chevron.right")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(Color.coffeeTextSecondary.opacity(0.4))
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 16)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(CoffeeCellButtonStyle())
                    .contextMenu {
                        Button {
                            router.selectRepository(repo)
                        } label: {
                            Label("Abrir", systemImage: "folder")
                        }
                        Button(role: .destructive) {
                            repoToDelete = repo
                        } label: {
                            Label("Excluir", systemImage: "trash")
                        }
                    }

                    if index < repositories.count - 1 {
                        Divider().padding(.leading, 82)
                    }
                }
            }
            .padding(.horizontal, 16)

            // Create repo
            if creatingRepo {
                CoffeeCellGroup {
                    HStack(spacing: 12) {
                        Image(systemName: "folder.badge.plus")
                            .foregroundStyle(Color.coffeePrimary)
                        TextField("Nome do repositório", text: $newRepoName)
                            .font(.system(size: 15))
                            .tint(Color.coffeePrimary)
                            .onSubmit { handleCreateRepo() }
                        Button("Criar") { handleCreateRepo() }
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Color.coffeePrimary)
                            .disabled(newRepoName.trimmingCharacters(in: .whitespaces).isEmpty)
                        Button("Cancelar") {
                            creatingRepo = false
                            newRepoName = ""
                        }
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.red)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }
                .padding(.horizontal, 16)
            } else {
                Button {
                    creatingRepo = true
                } label: {
                    HStack(spacing: 14) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(Color.coffeePrimary.opacity(0.09))
                                .frame(width: 52, height: 52)

                            Image(systemName: "plus")
                                .font(.system(size: 20))
                                .foregroundStyle(Color.coffeePrimary)
                        }

                        Text("Criar novo repositório")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Color.coffeePrimary)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.coffeeCardBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(Color.coffeeSeparator, lineWidth: 0.5)
                    )
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 16)
            }
        }
    }

    // MARK: - Recebidos Tab

    private var recebidosTab: some View {
        VStack(alignment: .leading, spacing: 0) {
            let newItems = sharedItems.filter(\.isNew)
            let olderItems = sharedItems.filter { !$0.isNew }

            if !newItems.isEmpty {
                CoffeeSectionHeader(title: "Novos (\(newItems.count))")
                    .padding(.horizontal, 20)
                    .padding(.bottom, 12)

                CoffeeCellGroup {
                    ForEach(Array(newItems.enumerated()), id: \.element.id) { index, item in
                        sharedItemRow(item, isNew: true)
                        if index < newItems.count - 1 {
                            Divider().padding(.leading, 62)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 20)
            }

            if !olderItems.isEmpty {
                CoffeeSectionHeader(title: "Anteriores")
                    .padding(.horizontal, 20)
                    .padding(.bottom, 12)

                CoffeeCellGroup {
                    ForEach(Array(olderItems.enumerated()), id: \.element.id) { index, item in
                        sharedItemRow(item, isNew: false)
                        if index < olderItems.count - 1 {
                            Divider().padding(.leading, 62)
                        }
                    }
                }
                .padding(.horizontal, 16)
            }

            if sharedItems.isEmpty {
                CoffeeEmptyState(
                    icon: "person.2.fill",
                    title: "Nada por aqui ainda",
                    message: "Quando colegas compartilharem aulas com você, elas aparecerão aqui."
                )
                .padding(.top, 40)
            }
        }
    }

    private func sharedItemRow(_ item: SharedItem, isNew: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 14) {
                // Avatar
                ZStack(alignment: .topTrailing) {
                    Circle()
                        .fill(isNew ? Color.blue.opacity(0.1) : Color.coffeeTextSecondary.opacity(0.08))
                        .frame(width: 50, height: 50)
                        .overlay(
                            Text(item.sender.initials)
                                .font(.system(size: 16, weight: .bold))
                                .foregroundStyle(isNew ? .blue : Color.coffeeTextSecondary)
                        )

                    if isNew {
                        Circle()
                            .fill(.blue)
                            .frame(width: 12, height: 12)
                            .overlay(
                                Circle().stroke(.white, lineWidth: 2)
                            )
                            .offset(x: 2, y: -2)
                    }
                }

                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.sender.nome)
                                .font(.system(size: 15, weight: isNew ? .semibold : .medium))
                                .foregroundStyle(Color.coffeeTextPrimary)
                            Text("\(item.sourceDiscipline) · \(item.gravacao.dateLabel)")
                                .font(.system(size: 13))
                                .foregroundStyle(Color.coffeeTextSecondary)
                                .lineLimit(1)
                        }
                        Spacer()
                        Text(item.createdAt.coffeeRelativeShort)
                            .font(.system(size: 11))
                            .foregroundStyle(Color.coffeeTextSecondary)
                    }

                    // Content badges
                    HStack(spacing: 6) {
                        ForEach(item.sharedContent, id: \.self) { type in
                            Text(type == "resumo" ? "Resumo" : "Mapa Mental")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(isNew ? .blue : Color.coffeeTextSecondary)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(isNew ? Color.blue.opacity(0.08) : Color.coffeeTextSecondary.opacity(0.06))
                                .clipShape(Capsule())
                        }
                    }

                    if let message = item.message, !message.isEmpty {
                        Text("\"\(message)\"")
                            .font(.system(size: 12))
                            .foregroundStyle(Color.coffeeTextSecondary)
                            .italic()
                            .lineLimit(1)
                    }

                    // Accept / Reject buttons
                    HStack(spacing: 8) {
                        Button {
                            allocatingItem = item
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 14, weight: .bold))
                                Text("Aceitar")
                                    .font(.system(size: 13, weight: .semibold))
                            }
                            .foregroundStyle(.green)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(Color.green.opacity(0.1))
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                        .buttonStyle(.plain)

                        Button {
                            handleRejectItem(item)
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "xmark")
                                    .font(.system(size: 14, weight: .bold))
                                Text("Recusar")
                                    .font(.system(size: 13, weight: .semibold))
                            }
                            .foregroundStyle(.red)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(Color.red.opacity(0.08))
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.top, 4)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
        }
    }

    // MARK: - Actions

    private func loadData() async {
        isLoading = true
        async let d = try? DisciplineService.getDisciplines()
        async let r = try? DisciplineService.getRepositories()
        async let s = try? DisciplineService.getSharedItems()
        disciplines = await d ?? []
        repositories = await r ?? []
        sharedItems = await s ?? []
        isLoading = false
    }

    private func handleCreateRepo() {
        let name = newRepoName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        newRepoName = ""
        creatingRepo = false
        Task {
            do {
                let repo = try await DisciplineService.createRepository(name: name, icon: "folder.fill")
                repositories.append(repo)
            } catch {
                print("[DisciplinasScreen] Error creating repo: \(error)")
            }
        }
    }

    private func handleDeleteRepo(_ repo: Repository) {
        let repoId = repo.id
        withAnimation { repositories.removeAll { $0.id == repoId } }
        Task {
            do {
                try await DisciplineService.deleteRepository(id: repoId)
            } catch {
                print("[DisciplinasScreen] Error deleting repo: \(error)")
                await loadData()
            }
        }
    }

    private func handleRejectItem(_ item: SharedItem) {
        Task {
            do {
                try await DisciplineService.rejectSharedItem(id: item.id)
                withAnimation { sharedItems.removeAll { $0.id == item.id } }
            } catch {
                print("[DisciplinasScreen] Error rejecting item: \(error)")
            }
        }
    }
}

// MARK: - Allocation Sheet

struct AllocationSheet: View {
    let item: SharedItem
    let disciplines: [Discipline]
    let repositories: [Repository]
    let onAllocate: (String) -> Void
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            CoffeeSheetHeader(title: "Onde salvar?", onClose: onClose)

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Item info
                    HStack(spacing: 14) {
                        Circle()
                            .fill(Color.blue.opacity(0.1))
                            .frame(width: 50, height: 50)
                            .overlay(
                                Text(item.sender.initials)
                                    .font(.system(size: 16, weight: .bold))
                                    .foregroundStyle(.blue)
                            )
                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.sender.nome)
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(Color.coffeeTextPrimary)
                            Text("\(item.sourceDiscipline) · \(item.gravacao.dateLabel)")
                                .font(.system(size: 14))
                                .foregroundStyle(Color.coffeeTextSecondary)
                        }
                    }
                    .padding(.bottom, 12)
                    .overlay(alignment: .bottom) {
                        Divider()
                    }

                    // Disciplines
                    CoffeeSectionHeader(title: "Disciplinas")

                    CoffeeCellGroup {
                        ForEach(Array(disciplines.enumerated()), id: \.element.id) { index, d in
                            Button { onAllocate(d.nome) } label: {
                                HStack(spacing: 14) {
                                    ZStack {
                                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                                            .fill(Color.coffeePrimary.opacity(0.1))
                                            .frame(width: 50, height: 50)
                                        Image(systemName: CoffeeIcon.menuBook)
                                            .font(.system(size: 20))
                                            .foregroundStyle(Color.coffeePrimary)
                                    }
                                    Text(d.nome)
                                        .font(.system(size: 16, weight: .medium))
                                        .foregroundStyle(Color.coffeeTextPrimary)
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundStyle(Color.coffeeTextSecondary.opacity(0.5))
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 16)
                            }
                            .buttonStyle(.plain)

                            if index < disciplines.count - 1 {
                                Divider().padding(.leading, 76)
                            }
                        }
                    }

                    // Repositories
                    CoffeeSectionHeader(title: "Repositórios")

                    CoffeeCellGroup {
                        ForEach(Array(repositories.enumerated()), id: \.element.id) { index, repo in
                            Button { onAllocate(repo.nome) } label: {
                                HStack(spacing: 14) {
                                    ZStack {
                                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                                            .fill(Color.coffeePrimary.opacity(0.1))
                                            .frame(width: 50, height: 50)
                                        Image(systemName: repo.icone)
                                            .font(.system(size: 20))
                                            .foregroundStyle(Color.coffeePrimary)
                                    }
                                    Text(repo.nome)
                                        .font(.system(size: 16, weight: .medium))
                                        .foregroundStyle(Color.coffeeTextPrimary)
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundStyle(Color.coffeeTextSecondary.opacity(0.5))
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 16)
                            }
                            .buttonStyle(.plain)

                            if index < repositories.count - 1 {
                                Divider().padding(.leading, 76)
                            }
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 32)
            }
        }
        .background(Color.coffeeBackground)
    }
}

// MARK: - Date helper

extension Optional where Wrapped == Date {
    var coffeeRelativeShort: String {
        guard let date = self else { return "" }
        let days = Calendar.current.dateComponents([.day], from: date, to: Date()).day ?? 0
        if days == 0 { return "Hoje" }
        if days == 1 { return "Ontem" }
        let f = DateFormatter()
        f.dateFormat = "d MMM"
        f.locale = Locale(identifier: "pt_BR")
        return f.string(from: date)
    }
}

#Preview {
    DisciplinasScreenView()
        .environment(\.router, NavigationRouter())
}
