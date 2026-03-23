import SwiftUI

// MARK: - Group Detail View
// Shows group info, members list, add/remove members

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

    var body: some View {
        VStack(spacing: 0) {
            if isLoading {
                loadingView
            } else if let group {
                groupContent(group)
            } else {
                errorView
            }
        }
        .background(Color.coffeeBackground)
        .navigationBarTitleDisplayMode(.inline)
        .navigationTitle(group?.nome ?? "Grupo")
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
                // Group header card
                VStack(spacing: 8) {
                    ZStack {
                        Circle()
                            .fill(Color.coffeePrimary.opacity(0.12))
                            .frame(width: 64, height: 64)
                        Image(systemName: CoffeeIcon.groups)
                            .font(.system(size: 26))
                            .foregroundStyle(Color.coffeePrimary)
                    }

                    Text(group.nome)
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(Color.coffeeTextPrimary)

                    if group.isAuto {
                        Text("Turma")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Color.coffeePrimary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(Color.coffeePrimary.opacity(0.1))
                            .clipShape(Capsule())
                    }

                    Text("\(group.memberCount) membros")
                        .font(.system(size: 14))
                        .foregroundStyle(Color.coffeeTextSecondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
                .background(Color.coffeeCardBackground)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .padding(.horizontal, 16)

                // Members section
                VStack(alignment: .leading, spacing: 0) {
                    HStack {
                        Text("Membros")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Color.coffeeTextSecondary)
                            .textCase(.uppercase)

                        Spacer()

                        if !group.isAuto {
                            Button {
                                showAddMember = true
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: CoffeeIcon.add)
                                        .font(.system(size: 12, weight: .semibold))
                                    Text("Adicionar")
                                        .font(.system(size: 13, weight: .medium))
                                }
                                .foregroundStyle(Color.coffeePrimary)
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 8)

                    VStack(spacing: 0) {
                        if let members = group.members {
                            ForEach(members) { member in
                                memberRow(member, isAuto: group.isAuto)

                                if member.id != members.last?.id {
                                    Divider()
                                        .padding(.leading, 72)
                                }
                            }
                        }
                    }
                    .background(Color.coffeeCardBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .padding(.horizontal, 16)
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
            group = try await g
            let friends = (try? await f) ?? []
            friendIds = Set(friends.map(\.userId))
        } catch {
            errorMessage = "Erro ao carregar grupo"
        }
        isLoading = false
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
            } catch {
                // Revert on failure
                pendingRequestIds.remove(member.userId)
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
