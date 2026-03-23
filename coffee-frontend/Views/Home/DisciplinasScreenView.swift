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
    @State private var editingDiscipline: Discipline? = nil
    @State private var editingDisciplineIndex: Int = 0
    @State private var showMenu = false
    @State private var showCalendar = false
    @State private var showPlanGate = false
    @State private var upcomingCount: Int = 0
    // Social
    @State private var friends: [Friend] = []
    @State private var friendRequests: [Friend] = []
    @State private var groups: [SocialGroup] = []
    @State private var showAddFriend = false
    // @State private var showCreateGroup = false  // Groups disabled for now
    @State private var selectedGroup: SocialGroup? = nil
    @State private var selectedFriend: Friend? = nil

    // Default styles now live on Discipline.defaultStyles

    /// Calendar icon is always visible; access is gated via PlanAccess
    private var calendarAvailable: Bool { true }

    private var plano: UserPlan? { router.currentUser?.plano }

    private var socialBadgeCount: Int {
        let friendPending = friends.compactMap(\.pendingCount).reduce(0, +)
        return friendPending + friendRequests.count
    }
    private var tabs: [String] { ["Disciplinas", "Outros", "Social\(socialBadgeCount > 0 ? " (\(socialBadgeCount))" : "")"] }

    private var dynamicSubtitle: String {
        // Extract semester number and turma from the first discipline that has them
        let semestre = disciplines.compactMap(\.semestre).first
        let turma = disciplines.compactMap(\.turma).first

        // Format semestre: "2026/1" → "1º Semestre 2026"
        let formattedSemestre: String? = {
            guard let s = semestre else { return nil }
            let parts = s.split(separator: "/")
            if parts.count == 2, let num = parts.last {
                return "\(num)º Semestre \(parts.first!)"
            }
            return "\(s)º semestre"
        }()

        if let formattedSemestre, let turma {
            return "\(formattedSemestre) · Turma \(turma)"
        } else if let formattedSemestre {
            return formattedSemestre
        } else if let turma {
            return "Turma \(turma)"
        } else {
            return "ESPM"
        }
    }

    var body: some View {
        ZStack(alignment: .top) {
            // Dark background fills behind status bar
            Color.coffeeHeaderGradientTop
                .ignoresSafeArea(edges: .top)

            VStack(spacing: 0) {
                // Large Title Header
                CoffeeLargeTitleHeader(
                    greeting: "Olá, \((router.currentUser?.nome ?? "Aluno").components(separatedBy: " ").first ?? "Aluno")",
                    subtitle: dynamicSubtitle,
                    planStatus: router.currentUser?.plano,
                    trialEnd: router.currentUser?.trialEnd,
                    onCalendarTap: calendarAvailable ? {
                        if PlanAccess.canUseCalendar(plano) {
                            showCalendar = true
                        } else {
                            router.showPremiumOffer()
                        }
                    } : nil,
                    upcomingCount: upcomingCount,
                    onMenuTap: { withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { showMenu.toggle() } },
                    onPlanTap: { showPlanGate = true }
                )

                ScrollView {
                    VStack(spacing: 0) {
                        // Segmented Control
                        CoffeeSegmentedControl(
                            segments: tabs,
                            selected: $activeTab,
                            style: .underline
                        )
                        .padding(.horizontal, 16)
                        .padding(.top, 20)
                        .padding(.bottom, 20)

                        // Tab Content
                        switch activeTab {
                        case 0: disciplinasTab
                        case 1: outrosTab
                        case 2:
                            if PlanAccess.canUseSocial(plano) {
                                recebidosTab
                            } else {
                                UpgradeGateView(feature: .social) { router.showPremiumOffer() }
                                    .frame(minHeight: 300)
                            }
                        default: EmptyView()
                        }
                    }
                    .padding(.bottom, 120)
                }
                .background(Color.coffeeBackground)
                .clipShape(
                    UnevenRoundedRectangle(
                        topLeadingRadius: 24,
                        bottomLeadingRadius: 0,
                        bottomTrailingRadius: 0,
                        topTrailingRadius: 24
                    )
                )
            }

            // Floating menu overlay
            if showMenu {
                // Backdrop
                Color.black.opacity(0.3)
                    .ignoresSafeArea()
                    .onTapGesture {
                        withAnimation(.spring(response: 0.25, dampingFraction: 0.9)) {
                            showMenu = false
                        }
                    }

                // Floating card
                VStack(alignment: .leading, spacing: 0) {
                    // User header
                    HStack(spacing: 12) {
                        // Avatar
                        ZStack {
                            Circle()
                                .fill(Color.coffeePrimary.opacity(0.15))
                                .frame(width: 40, height: 40)
                            Text(userInitials)
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(Color.coffeePrimary)
                        }

                        VStack(alignment: .leading, spacing: 2) {
                            Text(router.currentUser?.nome ?? "Aluno")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(Color.coffeeTextPrimary)
                            Text(router.currentUser?.email ?? "")
                                .font(.system(size: 12))
                                .foregroundStyle(Color.coffeeTextSecondary)
                                .lineLimit(1)
                        }

                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)

                    Divider().padding(.horizontal, 12)

                    // Menu items
                    floatingMenuRow(icon: "person.fill", title: "Perfil") {
                        dismissMenuThen { router.showProfile = true }
                    }
                    floatingMenuRow(icon: "gearshape.fill", title: "Configurações") {
                        dismissMenuThen { router.showSettings = true }
                    }

                    Divider().padding(.horizontal, 12)

                    // Logout
                    floatingMenuRow(icon: "rectangle.portrait.and.arrow.right", title: "Sair", isDestructive: true) {
                        withAnimation(.spring(response: 0.25, dampingFraction: 0.9)) { showMenu = false }
                        router.logout()
                    }
                }
                .background(.ultraThinMaterial)
                .background(Color.coffeeCardBackground.opacity(0.85))
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .shadow(color: .black.opacity(0.2), radius: 20, x: 0, y: 8)
                .frame(width: 260)
                .padding(.trailing, 16)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.top, 56)
                .transition(.asymmetric(
                    insertion: .scale(scale: 0.9, anchor: .topTrailing).combined(with: .opacity),
                    removal: .scale(scale: 0.95, anchor: .topTrailing).combined(with: .opacity)
                ))
            }
        }
        .fullScreenCover(isPresented: $showCalendar) {
            CalendarioScreenView()
        }
        .sheet(isPresented: $showPlanGate) {
            PremiumGateSheet()
        }
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
                    router.cachedSharedItems = sharedItems
                    allocatingItem = nil
                },
                onClose: { allocatingItem = nil }
            )
            .presentationDetents([.medium, .large])
        }
    }

    // MARK: - Menu Helpers

    private var userInitials: String {
        let name = router.currentUser?.nome ?? "A"
        return name.split(separator: " ").prefix(2).map { String($0.prefix(1)) }.joined().uppercased()
    }

    private func dismissMenuThen(_ action: @escaping () -> Void) {
        withAnimation(.spring(response: 0.25, dampingFraction: 0.9)) { showMenu = false }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { action() }
    }

    private func floatingMenuRow(icon: String, title: String, isDestructive: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 15))
                    .foregroundStyle(isDestructive ? Color.red : Color.coffeeTextSecondary)
                    .frame(width: 24)

                Text(title)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(isDestructive ? Color.red : Color.coffeeTextPrimary)

                Spacer()

                if !isDestructive {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.coffeeTextSecondary.opacity(0.3))
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Disciplinas Tab

    private var disciplinasTab: some View {
        VStack(alignment: .leading, spacing: 12) {
            CoffeeSectionHeader(title: "Suas Disciplinas")
                .padding(.horizontal, 20)

            CoffeeCellGroup {
                ForEach(Array(disciplines.enumerated()), id: \.element.id) { index, discipline in
                    let iconName = discipline.displayIcon(at: index)
                    let iconColor = Color(hex: discipline.displayColorHex(at: index))

                    Button {
                        router.selectCourse(discipline)
                    } label: {
                        HStack(spacing: 14) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .fill(iconColor.opacity(0.09))
                                    .frame(width: 52, height: 52)

                                Image(systemName: iconName)
                                    .font(.system(size: 20))
                                    .foregroundStyle(iconColor)
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
                    .contextMenu {
                        Button {
                            editingDisciplineIndex = index
                            editingDiscipline = discipline
                        } label: {
                            Label("Personalizar ícone", systemImage: "paintpalette.fill")
                        }
                    }

                    if index < disciplines.count - 1 {
                        Divider().padding(.leading, 82)
                    }
                }
            }
            .padding(.horizontal, 16)
        }
        .sheet(item: $editingDiscipline) { disc in
            IconPickerSheet(discipline: disc) { icon, color in
                // Optimistic update: UI changes instantly
                if let idx = disciplines.firstIndex(where: { $0.id == disc.id }) {
                    disciplines[idx].icon = icon
                    disciplines[idx].iconColor = color
                }
                router.cachedDisciplines = disciplines

                // Persist to backend in background
                Task {
                    do {
                        try await DisciplineService.updateAppearance(
                            disciplinaId: disc.id,
                            icon: icon,
                            iconColor: color
                        )
                    } catch {
                        print("[Appearance] Failed to save: \(error)")
                    }
                }
            }
            .presentationDetents([.large])
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

    // MARK: - Social Tab

    private var recebidosTab: some View {
        VStack(alignment: .leading, spacing: 0) {

            // ── Friend Requests ──
            if !friendRequests.isEmpty {
                CoffeeSectionHeader(title: "Solicitações (\(friendRequests.count))")
                    .padding(.horizontal, 20)
                    .padding(.bottom, 12)

                CoffeeCellGroup {
                    ForEach(Array(friendRequests.enumerated()), id: \.element.id) { index, req in
                        friendRequestRow(req)
                        if index < friendRequests.count - 1 {
                            Divider().padding(.leading, 62)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 20)
            }

            // ── Friends ──
            HStack {
                CoffeeSectionHeader(title: "Amigos\(friends.isEmpty ? "" : " (\(friends.count))")")
                Spacer()
                Button { showAddFriend = true } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Color.coffeePrimary)
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 12)

            if friends.isEmpty {
                HStack {
                    Spacer()
                    VStack(spacing: 6) {
                        Image(systemName: "person.2")
                            .font(.system(size: 28))
                            .foregroundStyle(Color.coffeeTextSecondary.opacity(0.4))
                        Text("Adicione amigos para compartilhar aulas")
                            .font(.system(size: 13))
                            .foregroundStyle(Color.coffeeTextSecondary)
                    }
                    Spacer()
                }
                .padding(.vertical, 20)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 16) {
                        ForEach(friends) { friend in
                            Button { selectedFriend = friend } label: {
                                VStack(spacing: 6) {
                                    ZStack(alignment: .topTrailing) {
                                        Circle()
                                            .fill(Color.coffeePrimary.opacity(0.12))
                                            .frame(width: 52, height: 52)
                                            .overlay(
                                                Text(friend.initials)
                                                    .font(.system(size: 16, weight: .bold))
                                                    .foregroundStyle(Color.coffeePrimary)
                                            )
                                        if let count = friend.pendingCount, count > 0 {
                                            Text("\(count)")
                                                .font(.system(size: 10, weight: .bold))
                                                .foregroundStyle(.white)
                                                .frame(width: 18, height: 18)
                                                .background(Color.red)
                                                .clipShape(Circle())
                                        }
                                    }
                                    .padding(.top, 2)
                                    .padding(.trailing, 2)
                                    Text(friend.nome.components(separatedBy: " ").first ?? friend.nome)
                                        .font(.system(size: 11))
                                        .foregroundStyle(Color.coffeeTextSecondary)
                                        .lineLimit(1)
                                }
                                .frame(width: 64)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 20)
                }
                .padding(.bottom, 16)
            }

            Spacer().frame(height: 20)
        }
        .sheet(isPresented: $showAddFriend) {
            AddFriendSheet()
        }
        .sheet(item: $selectedFriend) { friend in
            FriendDetailSheet(friend: friend)
        }
    }

    private func friendRequestRow(_ req: Friend) -> some View {
        HStack(spacing: 14) {
            Circle()
                .fill(Color.blue.opacity(0.1))
                .frame(width: 44, height: 44)
                .overlay(
                    Text(req.initials)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.blue)
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(req.nome)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.coffeeTextPrimary)
                Text(req.email)
                    .font(.system(size: 12))
                    .foregroundStyle(Color.coffeeTextSecondary)
            }

            Spacer()

            HStack(spacing: 8) {
                Button {
                    Task {
                        try? await SocialService.acceptFriendRequest(id: req.id)
                        friendRequests.removeAll { $0.id == req.id }
                        friends = (try? await SocialService.getFriends()) ?? friends
                    }
                } label: {
                    Image(systemName: "checkmark")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 32, height: 32)
                        .background(Color.green)
                        .clipShape(Circle())
                }

                Button {
                    Task {
                        try? await SocialService.rejectFriendRequest(id: req.id)
                        friendRequests.removeAll { $0.id == req.id }
                    }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 32, height: 32)
                        .background(Color.red.opacity(0.8))
                        .clipShape(Circle())
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
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
        // Show cached data instantly (no blank screen on tab switch)
        if let cached = router.cachedDisciplines {
            disciplines = cached
            repositories = router.cachedRepositories ?? []
            sharedItems = router.cachedSharedItems ?? []
            isLoading = false

            // Skip refetch if data is fresh (< 30 seconds old)
            if let lastFetch = router.lastHomeDataFetch,
               Date().timeIntervalSince(lastFetch) < 30 {
                return
            }
        }

        // Fetch from API (first load or background refresh)
        if disciplines.isEmpty { isLoading = true }

        async let d = try? DisciplineService.getDisciplines()
        async let r = try? DisciplineService.getRepositories()
        async let s = try? DisciplineService.getSharedItems()
        async let f = try? SocialService.getFriends()
        async let fr = try? SocialService.getFriendRequests()
        async let g = try? SocialService.getGroups()

        disciplines = await d ?? disciplines
        repositories = await r ?? repositories
        sharedItems = await s ?? sharedItems
        friends = await f ?? friends
        let frResult = await fr
        friendRequests = frResult?.received ?? friendRequests
        groups = await g ?? groups

        // Update cache
        router.cachedDisciplines = disciplines
        router.cachedRepositories = repositories
        router.cachedSharedItems = sharedItems
        router.lastHomeDataFetch = Date()
        isLoading = false

        // Load upcoming calendar count (Black/Trial only)
        if calendarAvailable {
            Task {
                if let upcoming = try? await CalendarService.getUpcoming() {
                    upcomingCount = upcoming.totalUpcoming
                }
            }
        }
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
                router.cachedRepositories = repositories
            } catch {
                print("[DisciplinasScreen] Error creating repo: \(error)")
            }
        }
    }

    private func handleDeleteRepo(_ repo: Repository) {
        let repoId = repo.id
        withAnimation { repositories.removeAll { $0.id == repoId } }
        router.cachedRepositories = repositories
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
                router.cachedSharedItems = sharedItems
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
                                            .fill(Color(hex: d.displayColorHex(at: index)).opacity(0.1))
                                            .frame(width: 50, height: 50)
                                        Image(systemName: d.displayIcon(at: index))
                                            .font(.system(size: 20))
                                            .foregroundStyle(Color(hex: d.displayColorHex(at: index)))
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
