import SwiftUI

// MARK: - Add Friend Sheet
// Search users by name/email and send friend requests

struct AddFriendSheet: View {
    @Environment(\.dismiss) private var dismiss

    @State private var searchText = ""
    @State private var results: [UserSearchResult] = []
    @State private var isSearching = false
    @State private var searchTask: Task<Void, Never>?
    @State private var pendingIds: Set<String> = []
    @State private var acceptedIds: Set<String> = []
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            CoffeeSheetHeader(
                title: "Adicionar Amigo",
                onClose: { dismiss() }
            )

            // Search bar
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 16))
                    .foregroundStyle(Color.coffeeTextTertiary)

                TextField("Buscar por nome ou email", text: $searchText)
                    .font(.system(size: 15))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()

                if isSearching {
                    ProgressView()
                        .scaleEffect(0.8)
                }
            }
            .padding(.horizontal, 14)
            .frame(height: 44)
            .background(Color.coffeeInputBackground)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .padding(.horizontal, 20)
            .padding(.bottom, 16)

            if let error = errorMessage {
                Text(error)
                    .font(.system(size: 13))
                    .foregroundStyle(Color.coffeeDanger)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 8)
            }

            if results.isEmpty && !searchText.isEmpty && !isSearching {
                emptyStateView
            } else {
                resultsList
            }
        }
        .background(Color.coffeeBackground)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .onChange(of: searchText) { _, newValue in
            debounceSearch(query: newValue)
        }
    }

    // MARK: - Results List

    private var resultsList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(results) { user in
                    userRow(user)

                    if user.id != results.last?.id {
                        Divider()
                            .padding(.leading, 72)
                    }
                }
            }
            .background(Color.coffeeCardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .padding(.horizontal, 16)
        }
    }

    // MARK: - User Row

    private func userRow(_ user: UserSearchResult) -> some View {
        HStack(spacing: 12) {
            // Avatar circle with initials
            ZStack {
                Circle()
                    .fill(Color.coffeePrimary.opacity(0.12))
                    .frame(width: 44, height: 44)
                Text(user.initials)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.coffeePrimary)
            }

            // Name + email
            VStack(alignment: .leading, spacing: 2) {
                Text(user.nome)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(Color.coffeeTextPrimary)
                    .lineLimit(1)
                Text(user.email)
                    .font(.system(size: 13))
                    .foregroundStyle(Color.coffeeTextSecondary)
                    .lineLimit(1)
            }

            Spacer()

            // Action button
            actionButton(for: user)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: - Action Button

    @ViewBuilder
    private func actionButton(for user: UserSearchResult) -> some View {
        if acceptedIds.contains(user.id) || user.isFriend {
            // Already friends
            Image(systemName: CoffeeIcon.checkCircle)
                .font(.system(size: 22))
                .foregroundStyle(Color.coffeeSuccess)
        } else if pendingIds.contains(user.id) || user.friendshipStatus == "pending_sent" {
            // Pending sent
            Text("Pendente")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color.coffeeTextSecondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.coffeeInputBackground)
                .clipShape(Capsule())
        } else if user.friendshipStatus == "pending_received" {
            // Pending received - can accept
            Button {
                acceptRequest(user: user)
            } label: {
                Text("Aceitar")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.coffeeSuccess)
                    .clipShape(Capsule())
            }
        } else {
            // Not friends - can add
            Button {
                sendRequest(user: user)
            } label: {
                Text("Adicionar")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.coffeePrimary)
                    .clipShape(Capsule())
            }
        }
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: CoffeeIcon.person)
                .font(.system(size: 36))
                .foregroundStyle(Color.coffeeTextTertiary)
            Text("Nenhum usuario encontrado")
                .font(.system(size: 15))
                .foregroundStyle(Color.coffeeTextSecondary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Actions

    private func debounceSearch(query: String) {
        searchTask?.cancel()
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else {
            results = []
            return
        }

        searchTask = Task {
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            await performSearch(query: query)
        }
    }

    @MainActor
    private func performSearch(query: String) async {
        isSearching = true
        errorMessage = nil
        do {
            results = try await SocialService.searchUsers(query: query)
        } catch {
            errorMessage = "Erro ao buscar usuarios"
            results = []
        }
        isSearching = false
    }

    private func sendRequest(user: UserSearchResult) {
        Task {
            do {
                try await SocialService.sendFriendRequest(email: user.email)
                pendingIds.insert(user.id)
            } catch {
                errorMessage = "Erro ao enviar convite"
            }
        }
    }

    private func acceptRequest(user: UserSearchResult) {
        Task {
            do {
                try await SocialService.acceptFriendRequest(id: user.id)
                acceptedIds.insert(user.id)
            } catch {
                errorMessage = "Erro ao aceitar convite"
            }
        }
    }
}

// MARK: - Preview

#Preview {
    AddFriendSheet()
}
