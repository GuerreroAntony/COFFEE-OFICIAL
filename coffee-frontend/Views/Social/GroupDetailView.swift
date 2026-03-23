import SwiftUI

// MARK: - Shared Recording Item (inline model for group feed)

struct SharedRecordingItem: Identifiable {
    let id: String
    let senderName: String
    let summary: String?
    let discipline: String?
    let status: String
    let createdAt: Date?
}

// MARK: - Group Detail View
// Shows group members, shared classes feed, send button

struct GroupDetailView: View {
    let groupId: String

    @Environment(\.dismiss) private var dismiss

    @Environment(\.router) private var router

    @State private var group: SocialGroup?
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var showAddMember = false
    @State private var showDeleteConfirmation = false
    @State private var isDeleting = false
    @State private var friendIds: Set<String> = []
    @State private var pendingRequestIds: Set<String> = []
    @State private var showShareSheet = false
    @State private var sharedItems: [SharedRecordingItem] = []
    @State private var showMembers = false

    var body: some View {
        VStack(spacing: 0) {
            // Grab indicator
            Capsule()
                .fill(Color.coffeeTextSecondary.opacity(0.3))
                .frame(width: 36, height: 5)
                .padding(.top, 10)
                .padding(.bottom, 4)

            // Header with title + close
            HStack {
                Spacer()
                Text(group?.nome ?? "Grupo")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Color.coffeeTextPrimary)
                Spacer()
            }
            .overlay(alignment: .trailing) {
                Button { dismiss() } label: {
                    Text("Fechar")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(Color.coffeePrimary)
                }
                .padding(.trailing, 16)
            }
            .padding(.vertical, 12)

            if isLoading {
                loadingView
            } else if let group {
                groupContent(group)
            } else {
                errorView
            }
        }
        .background(Color.coffeeBackground)
        .navigationBarHidden(true)
        .task {
            await loadGroup()
        }
        .sheet(isPresented: $showAddMember) {
            AddMemberSheet(groupId: groupId) {
                Task { await loadGroup() }
            }
        }
        .alert("Excluir grupo?", isPresented: $showDeleteConfirmation) {
            Button("Cancelar", role: .cancel) { }
            Button("Excluir", role: .destructive) {
                deleteGroup()
            }
        } message: {
            Text("Esta acao nao pode ser desfeita. Todos os membros serao removidos.")
        }
    }

    // MARK: - Group Content

    private func groupContent(_ group: SocialGroup) -> some View {
        ScrollView {
            VStack(spacing: 16) {
                // Send class button
                Button { showShareSheet = true } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 15, weight: .semibold))
                        Text("Enviar aula para o grupo")
                            .font(.system(size: 15, weight: .semibold))
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.coffeePrimary)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .padding(.horizontal, 16)

                // Shared classes feed
                VStack(alignment: .leading, spacing: 8) {
                    Text("Aulas compartilhadas")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.coffeeTextSecondary)
                        .textCase(.uppercase)
                        .padding(.horizontal, 20)

                    if sharedItems.isEmpty {
                        VStack(spacing: 8) {
                            Image(systemName: "tray")
                                .font(.system(size: 28))
                                .foregroundStyle(Color.coffeeTextSecondary.opacity(0.4))
                            Text("Nenhuma aula enviada ainda")
                                .font(.system(size: 14))
                                .foregroundStyle(Color.coffeeTextSecondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 24)
                    } else {
                        CoffeeCellGroup {
                            ForEach(Array(sharedItems.enumerated()), id: \.element.id) { index, item in
                                sharedItemRow(item)
                                if index < sharedItems.count - 1 {
                                    Divider().padding(.leading, 60)
                                }
                            }
                        }
                    }
                }

                // Members section (collapsible)
                VStack(alignment: .leading, spacing: 0) {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) { showMembers.toggle() }
                    } label: {
                        HStack {
                            Text("Membros (\(group.memberCount))")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(Color.coffeeTextSecondary)
                                .textCase(.uppercase)
                            Spacer()
                            Image(systemName: showMembers ? "chevron.up" : "chevron.down")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(Color.coffeeTextSecondary)
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 8)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    if showMembers {
                        VStack(spacing: 0) {
                            if let members = group.members {
                                ForEach(members) { member in
                                    memberRow(member, isAuto: group.isAuto)
                                    if member.id != members.last?.id {
                                        Divider().padding(.leading, 72)
                                    }
                                }
                            }
                        }
                        .background(Color.coffeeCardBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .padding(.horizontal, 16)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }

                // Bottom actions
                if !group.isAuto {
                    CoffeeButton(
                        "Excluir grupo",
                        icon: CoffeeIcon.deleteForever,
                        style: .destructive,
                        isLoading: isDeleting
                    ) {
                        showDeleteConfirmation = true
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 16)
                }

                Spacer(minLength: 40)
            }
            .padding(.top, 8)
        }
    }

    // MARK: - Shared Item Row

    private func sharedItemRow(_ item: SharedRecordingItem) -> some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.coffeePrimary.opacity(0.1))
                    .frame(width: 40, height: 40)
                Image(systemName: "doc.text")
                    .font(.system(size: 16))
                    .foregroundStyle(Color.coffeePrimary)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(item.senderName)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.coffeeTextPrimary)
                    .lineLimit(1)
                Text(item.summary ?? item.discipline ?? "Gravação")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.coffeeTextSecondary)
                    .lineLimit(1)
            }

            Spacer()

            if item.status == "pending" {
                Button {
                    // Accept will be handled by existing flow
                } label: {
                    Text("Salvar")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.coffeePrimary)
                        .clipShape(Capsule())
                }
            } else {
                Image(systemName: "checkmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Color.coffeeSuccess)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    // MARK: - Member Row

    private func memberRow(_ member: GroupMember, isAuto: Bool) -> some View {
        HStack(spacing: 12) {
            // Avatar
            ZStack {
                Circle()
                    .fill(Color.coffeePrimary.opacity(0.12))
                    .frame(width: 44, height: 44)
                Text(member.initials)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.coffeePrimary)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(member.nome)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(Color.coffeeTextPrimary)
                    .lineLimit(1)
            }

            Spacer()

            if member.role == "admin" {
                Text("Admin")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.coffeeWarning)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.coffeeWarning.opacity(0.1))
                    .clipShape(Capsule())
            } else if member.userId != currentUserId {
                if friendIds.contains(member.userId) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Color.coffeeSuccess)
                } else if pendingRequestIds.contains(member.userId) {
                    Text("Pendente")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Color.coffeeTextSecondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.coffeeTextSecondary.opacity(0.1))
                        .clipShape(Capsule())
                } else {
                    Button {
                        sendFriendRequest(to: member)
                    } label: {
                        Text("Adicionar")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Color.coffeePrimary)
                            .clipShape(Capsule())
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .if(!isAuto && member.role != "admin") { view in
            view.swipeActions(edge: .trailing) {
                Button(role: .destructive) {
                    removeMember(member)
                } label: {
                    Label("Remover", systemImage: CoffeeIcon.deleteForever)
                }
            }
        }
    }

    // MARK: - Loading / Error

    private var loadingView: some View {
        VStack {
            Spacer()
            ProgressView()
                .scaleEffect(1.2)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private var errorView: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: CoffeeIcon.warning)
                .font(.system(size: 36))
                .foregroundStyle(Color.coffeeTextTertiary)
            Text(errorMessage ?? "Erro ao carregar grupo")
                .font(.system(size: 15))
                .foregroundStyle(Color.coffeeTextSecondary)
            Button("Tentar novamente") {
                Task { await loadGroup() }
            }
            .font(.system(size: 15, weight: .medium))
            .foregroundStyle(Color.coffeePrimary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Actions

    @MainActor
    private func loadGroup() async {
        isLoading = true
        errorMessage = nil
        do {
            async let g = SocialService.getGroupDetail(id: groupId)
            async let f = SocialService.getFriends()
            async let r = SocialService.getFriendRequests()
            group = try await g
            let friends = (try? await f) ?? []
            let requests = try? await r
            friendIds = Set(friends.map(\.userId))
            pendingRequestIds = Set((requests?.sent ?? []).map(\.userId))

            // Load shared items for this group
            await loadGroupShares()
        } catch {
            errorMessage = "Erro ao carregar grupo"
        }
        isLoading = false
    }

    private func loadGroupShares() async {
        do {
            let items: [SharedItem] = try await APIClient.shared.request(
                path: "\(APIEndpoints.compartilhamentosReceived)?group_id=\(groupId)"
            )
            sharedItems = items.map { item in
                SharedRecordingItem(
                    id: item.id,
                    senderName: item.sender.nome,
                    summary: item.gravacao.shortSummary,
                    discipline: item.sourceDiscipline,
                    status: item.status.rawValue,
                    createdAt: item.createdAt
                )
            }
        } catch {
            print("[GroupDetail] Failed to load group shares: \(error)")
            sharedItems = []
        }
    }

    private var currentUserId: String {
        router.currentUser?.id ?? ""
    }

    private func sendFriendRequest(to member: GroupMember) {
        // Optimistic UI — show "Pendente" immediately
        pendingRequestIds.insert(member.userId)
        Task {
            do {
                try await SocialService.sendFriendRequest(userId: member.userId)
                print("[Social] ✅ Friend request sent to \(member.nome)")
            } catch {
                // Keep "Pendente" — error usually means request already exists
                print("[Social] Friend request for \(member.userId): \(error)")
            }
        }
    }

    private func removeMember(_ member: GroupMember) {
        Task {
            do {
                try await SocialService.removeGroupMember(
                    groupId: groupId,
                    userId: member.userId
                )
                await loadGroup()
            } catch {
                errorMessage = "Erro ao remover membro"
            }
        }
    }

    private func deleteGroup() {
        isDeleting = true
        Task {
            do {
                try await SocialService.deleteGroup(id: groupId)
                dismiss()
            } catch {
                errorMessage = "Erro ao excluir grupo"
                isDeleting = false
            }
        }
    }
}

// MARK: - Add Member Sheet (Internal)

private struct AddMemberSheet: View {
    let groupId: String
    let onAdded: () -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var friends: [Friend] = []
    @State private var isLoading = true
    @State private var addingId: String?
    @State private var addedIds: Set<String> = []
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            CoffeeSheetHeader(
                title: "Adicionar Membro",
                onClose: { dismiss() }
            )

            if isLoading {
                VStack {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
            } else if friends.isEmpty {
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: CoffeeIcon.person)
                        .font(.system(size: 36))
                        .foregroundStyle(Color.coffeeTextTertiary)
                    Text("Adicione amigos primeiro")
                        .font(.system(size: 15))
                        .foregroundStyle(Color.coffeeTextSecondary)
                    Spacer()
                }
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(friends) { friend in
                            HStack(spacing: 12) {
                                ZStack {
                                    Circle()
                                        .fill(Color.coffeePrimary.opacity(0.12))
                                        .frame(width: 44, height: 44)
                                    Text(friend.initials)
                                        .font(.system(size: 15, weight: .semibold))
                                        .foregroundStyle(Color.coffeePrimary)
                                }

                                Text(friend.nome)
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundStyle(Color.coffeeTextPrimary)
                                    .lineLimit(1)

                                Spacer()

                                if addedIds.contains(friend.userId) {
                                    Image(systemName: CoffeeIcon.checkCircle)
                                        .font(.system(size: 22))
                                        .foregroundStyle(Color.coffeeSuccess)
                                } else {
                                    Button {
                                        addMember(friend)
                                    } label: {
                                        if addingId == friend.userId {
                                            ProgressView()
                                                .scaleEffect(0.8)
                                        } else {
                                            Text("Adicionar")
                                                .font(.system(size: 13, weight: .semibold))
                                                .foregroundStyle(.white)
                                                .padding(.horizontal, 12)
                                                .padding(.vertical, 6)
                                                .background(Color.coffeePrimary)
                                                .clipShape(Capsule())
                                        }
                                    }
                                    .disabled(addingId != nil)
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)

                            if friend.id != friends.last?.id {
                                Divider().padding(.leading, 72)
                            }
                        }
                    }
                    .background(Color.coffeeCardBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .padding(.horizontal, 16)
                }
            }

            if let error = errorMessage {
                Text(error)
                    .font(.system(size: 13))
                    .foregroundStyle(Color.coffeeDanger)
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
            }
        }
        .background(Color.coffeeBackground)
        .task {
            await loadFriends()
        }
    }

    @MainActor
    private func loadFriends() async {
        isLoading = true
        do {
            friends = try await SocialService.getFriends()
        } catch {
            errorMessage = "Erro ao carregar amigos"
        }
        isLoading = false
    }

    private func addMember(_ friend: Friend) {
        addingId = friend.userId
        errorMessage = nil
        Task {
            do {
                try await SocialService.addGroupMember(
                    groupId: groupId,
                    userId: friend.userId
                )
                addedIds.insert(friend.userId)
                onAdded()
            } catch {
                errorMessage = "Erro ao adicionar membro"
            }
            addingId = nil
        }
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        GroupDetailView(groupId: "group-1")
    }
}
