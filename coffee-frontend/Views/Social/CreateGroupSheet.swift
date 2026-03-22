import SwiftUI

// MARK: - Create Group Sheet
// Name field + friend selector (checkboxes) + create button

struct CreateGroupSheet: View {
    var onCreated: ((SocialGroup) -> Void)?

    @Environment(\.dismiss) private var dismiss

    @State private var groupName = ""
    @State private var friends: [Friend] = []
    @State private var selectedIds: Set<String> = []
    @State private var isLoadingFriends = true
    @State private var isCreating = false
    @State private var errorMessage: String?

    private var canCreate: Bool {
        !groupName.trimmingCharacters(in: .whitespaces).isEmpty && !selectedIds.isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            CoffeeSheetHeader(
                title: "Criar Grupo",
                onClose: { dismiss() }
            )

            ScrollView {
                VStack(spacing: 20) {
                    // Group name field
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Nome do grupo")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Color.coffeeTextSecondary)
                            .textCase(.uppercase)
                            .padding(.horizontal, 4)

                        CoffeeTextField(
                            placeholder: "Ex: Grupo de Marketing",
                            text: $groupName,
                            icon: CoffeeIcon.group,
                            autocapitalization: .words
                        )
                    }
                    .padding(.horizontal, 20)

                    // Friends selection
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Selecionar membros")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(Color.coffeeTextSecondary)
                                .textCase(.uppercase)

                            Spacer()

                            if !selectedIds.isEmpty {
                                Text("\(selectedIds.count) selecionados")
                                    .font(.system(size: 13))
                                    .foregroundStyle(Color.coffeePrimary)
                            }
                        }
                        .padding(.horizontal, 24)

                        if isLoadingFriends {
                            VStack {
                                ProgressView()
                                    .padding(.vertical, 40)
                            }
                            .frame(maxWidth: .infinity)
                        } else if friends.isEmpty {
                            VStack(spacing: 12) {
                                Image(systemName: CoffeeIcon.person)
                                    .font(.system(size: 32))
                                    .foregroundStyle(Color.coffeeTextTertiary)
                                Text("Adicione amigos primeiro para criar um grupo")
                                    .font(.system(size: 14))
                                    .foregroundStyle(Color.coffeeTextSecondary)
                                    .multilineTextAlignment(.center)
                            }
                            .padding(.vertical, 32)
                            .frame(maxWidth: .infinity)
                        } else {
                            friendsList
                        }
                    }

                    if let error = errorMessage {
                        Text(error)
                            .font(.system(size: 13))
                            .foregroundStyle(Color.coffeeDanger)
                            .padding(.horizontal, 20)
                    }
                }
                .padding(.top, 8)
            }

            // Create button
            VStack(spacing: 0) {
                Divider()
                CoffeeButton(
                    "Criar grupo",
                    icon: CoffeeIcon.groups,
                    isLoading: isCreating,
                    isDisabled: !canCreate
                ) {
                    createGroup()
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 16)
            }
            .background(Color.coffeeBackground)
        }
        .background(Color.coffeeBackground)
        .task {
            await loadFriends()
        }
    }

    // MARK: - Friends List

    private var friendsList: some View {
        VStack(spacing: 0) {
            ForEach(friends) { friend in
                Button {
                    toggleSelection(friend)
                } label: {
                    HStack(spacing: 12) {
                        // Avatar
                        ZStack {
                            Circle()
                                .fill(Color.coffeePrimary.opacity(0.12))
                                .frame(width: 44, height: 44)
                            Text(friend.initials)
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(Color.coffeePrimary)
                        }

                        // Name
                        Text(friend.nome)
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(Color.coffeeTextPrimary)
                            .lineLimit(1)

                        Spacer()

                        // Checkbox
                        ZStack {
                            Circle()
                                .fill(selectedIds.contains(friend.userId) ? Color.coffeePrimary : Color.clear)
                                .frame(width: 26, height: 26)
                                .overlay(
                                    Circle()
                                        .stroke(
                                            selectedIds.contains(friend.userId)
                                                ? Color.coffeePrimary
                                                : Color.coffeeTextSecondary.opacity(0.3),
                                            lineWidth: 1.5
                                        )
                                )

                            if selectedIds.contains(friend.userId) {
                                Image(systemName: CoffeeIcon.check)
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundStyle(.white)
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if friend.id != friends.last?.id {
                    Divider().padding(.leading, 72)
                }
            }
        }
        .background(Color.coffeeCardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .padding(.horizontal, 16)
    }

    // MARK: - Actions

    private func toggleSelection(_ friend: Friend) {
        if selectedIds.contains(friend.userId) {
            selectedIds.remove(friend.userId)
        } else {
            selectedIds.insert(friend.userId)
        }
    }

    @MainActor
    private func loadFriends() async {
        isLoadingFriends = true
        do {
            friends = try await SocialService.getFriends()
        } catch {
            errorMessage = "Erro ao carregar amigos"
        }
        isLoadingFriends = false
    }

    private func createGroup() {
        isCreating = true
        errorMessage = nil
        Task {
            do {
                let newGroup = try await SocialService.createGroup(
                    nome: groupName.trimmingCharacters(in: .whitespaces),
                    memberIds: Array(selectedIds)
                )
                onCreated?(newGroup)
                dismiss()
            } catch {
                errorMessage = "Erro ao criar grupo"
                isCreating = false
            }
        }
    }
}

// MARK: - Preview

#Preview {
    CreateGroupSheet()
}
