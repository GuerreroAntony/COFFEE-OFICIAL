import SwiftUI

// MARK: - Share Recording Sheet
// Two-step: 1) Select content → 2) Pick friends or search by name/email

struct ShareRecordingSheet: View {
    let recordingId: String
    let hasResumo: Bool
    let hasMindMap: Bool

    @Environment(\.dismiss) private var dismiss

    @State private var step = 1
    @State private var shareResumo = true
    @State private var shareMapa = true
    @State private var isSending = false
    @State private var showSuccess = false
    @State private var errorMessage: String? = nil

    // Step 2 state
    @State private var friends: [Friend] = []
    @State private var selectedFriendIds: Set<String> = []
    @State private var searchText = ""
    @State private var searchResults: [UserSearchResult] = []
    @State private var isSearching = false
    @State private var selectedSearchIds: Set<String> = []
    @State private var searchTask: Task<Void, Never>?

    var body: some View {
        VStack(spacing: 0) {
            if showSuccess {
                successView
            } else if step == 1 {
                step1ContentSelection
            } else {
                step2RecipientPicker
            }
        }
        .background(Color.coffeeBackground)
    }

    // MARK: - Step 1: Content Selection

    private var step1ContentSelection: some View {
        VStack(spacing: 0) {
            CoffeeSheetHeader(
                title: "Compartilhar",
                onClose: { dismiss() }
            )

            VStack(spacing: 20) {
                Text("Selecione o que deseja compartilhar desta aula:")
                    .font(.system(size: 15))
                    .foregroundStyle(Color.coffeeTextSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                    .padding(.top, 8)

                CoffeeCellGroup {
                    if hasResumo {
                        Button {
                            shareResumo.toggle()
                        } label: {
                            shareOptionRow(
                                icon: CoffeeIcon.sparkles,
                                title: "Resumo",
                                subtitle: "Resumo gerado por IA",
                                isSelected: shareResumo
                            )
                        }
                        .buttonStyle(CoffeeCellButtonStyle())
                    }

                    if hasResumo && hasMindMap {
                        Divider().padding(.leading, 72)
                    }

                    if hasMindMap {
                        Button {
                            shareMapa.toggle()
                        } label: {
                            shareOptionRow(
                                icon: "rectangle.3.group",
                                title: "Mapa Mental",
                                subtitle: "Mapa mental da aula",
                                isSelected: shareMapa
                            )
                        }
                        .buttonStyle(CoffeeCellButtonStyle())
                    }
                }
                .padding(.horizontal, 16)

                Spacer()

                CoffeeButton(
                    "Continuar",
                    isDisabled: !shareResumo && !shareMapa
                ) {
                    step = 2
                    loadFriends()
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 40)
            }
        }
    }

    // MARK: - Step 2: Recipient Picker

    private var step2RecipientPicker: some View {
        VStack(spacing: 0) {
            // Header with back
            VStack(spacing: 0) {
                Capsule()
                    .fill(Color(red: 60/255, green: 60/255, blue: 67/255).opacity(0.3))
                    .frame(width: 36, height: 5)
                    .padding(.top, 10)
                    .padding(.bottom, 8)

                ZStack {
                    Text("Enviar para")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Color.coffeeTextPrimary)

                    HStack {
                        Button {
                            step = 1
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "chevron.left")
                                    .font(.system(size: 13, weight: .semibold))
                                Text("Voltar")
                                    .font(.system(size: 15, weight: .medium))
                            }
                            .foregroundStyle(Color.coffeePrimary)
                        }

                        Spacer()

                        Button("Fechar") { dismiss() }
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(Color.coffeePrimary)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 12)
            }

            // Search bar
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 15))
                    .foregroundStyle(Color.coffeeTextSecondary.opacity(0.5))

                TextField("Buscar por nome ou email", text: $searchText)
                    .font(.system(size: 15))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .onChange(of: searchText) { _, newValue in
                        debounceSearch(query: newValue)
                    }

                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                        searchResults = []
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 16))
                            .foregroundStyle(Color.coffeeTextSecondary.opacity(0.4))
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .background(Color.coffeeInputBackground)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .padding(.horizontal, 20)
            .padding(.bottom, 12)

            ScrollView {
                VStack(spacing: 16) {
                    // Friends section (when not searching)
                    if searchText.isEmpty && !friends.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("AMIGOS")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(Color.coffeeTextSecondary)
                                .padding(.horizontal, 20)

                            VStack(spacing: 0) {
                                ForEach(friends) { friend in
                                    Button {
                                        toggleFriend(friend)
                                    } label: {
                                        recipientRow(
                                            initials: friend.initials,
                                            name: friend.nome,
                                            subtitle: nil,
                                            isSelected: selectedFriendIds.contains(friend.userId)
                                        )
                                    }
                                    .buttonStyle(.plain)

                                    if friend.id != friends.last?.id {
                                        Divider().padding(.leading, 68)
                                    }
                                }
                            }
                            .background(Color.coffeeCardBackground)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .padding(.horizontal, 16)
                        }
                    }

                    // Search results
                    if !searchText.isEmpty {
                        if isSearching {
                            ProgressView()
                                .padding(.top, 20)
                        } else if searchResults.isEmpty && searchText.count >= 2 {
                            VStack(spacing: 8) {
                                Image(systemName: "person.slash")
                                    .font(.system(size: 28))
                                    .foregroundStyle(Color.coffeeTextSecondary.opacity(0.4))
                                Text("Nenhum resultado")
                                    .font(.system(size: 14))
                                    .foregroundStyle(Color.coffeeTextSecondary)
                            }
                            .padding(.top, 20)
                        } else {
                            VStack(spacing: 0) {
                                ForEach(searchResults) { user in
                                    Button {
                                        toggleSearchUser(user)
                                    } label: {
                                        recipientRow(
                                            initials: user.initials,
                                            name: user.nome,
                                            subtitle: user.email,
                                            isSelected: selectedSearchIds.contains(user.id)
                                        )
                                    }
                                    .buttonStyle(.plain)

                                    if user.id != searchResults.last?.id {
                                        Divider().padding(.leading, 68)
                                    }
                                }
                            }
                            .background(Color.coffeeCardBackground)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .padding(.horizontal, 16)
                        }
                    }

                    // Empty state
                    if searchText.isEmpty && friends.isEmpty {
                        VStack(spacing: 8) {
                            Image(systemName: "person.2")
                                .font(.system(size: 28))
                                .foregroundStyle(Color.coffeeTextSecondary.opacity(0.4))
                            Text("Busque por nome ou email")
                                .font(.system(size: 14))
                                .foregroundStyle(Color.coffeeTextSecondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, 40)
                    }
                }
                .padding(.bottom, 100)
            }

            if let error = errorMessage {
                Text(error)
                    .font(.system(size: 13))
                    .foregroundStyle(Color.coffeeDanger)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 4)
            }

            // Share button
            CoffeeButton(
                "Compartilhar",
                isLoading: isSending,
                isDisabled: selectedFriendIds.isEmpty && selectedSearchIds.isEmpty
            ) {
                handleShare()
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 40)
            .padding(.top, 8)
            .background(Color.coffeeBackground)
        }
    }

    // MARK: - Success View

    private var successView: some View {
        VStack(spacing: 20) {
            Spacer()

            ZStack {
                Circle()
                    .fill(Color.coffeeSuccess.opacity(0.1))
                    .frame(width: 80, height: 80)
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(Color.coffeeSuccess)
            }

            Text("Compartilhado!")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(Color.coffeeTextPrimary)

            Text("A gravação foi compartilhada com sucesso.")
                .font(.system(size: 15))
                .foregroundStyle(Color.coffeeTextSecondary)
                .multilineTextAlignment(.center)

            Spacer()

            CoffeeButton("Fechar") {
                dismiss()
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 40)
        }
    }

    // MARK: - Row Components

    private func recipientRow(initials: String, name: String, subtitle: String?, isSelected: Bool) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.coffeePrimary.opacity(0.12))
                    .frame(width: 40, height: 40)
                Text(initials)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.coffeePrimary)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Color.coffeeTextPrimary)
                    .lineLimit(1)
                if let sub = subtitle {
                    Text(sub)
                        .font(.system(size: 12))
                        .foregroundStyle(Color.coffeeTextSecondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            ZStack {
                Circle()
                    .fill(isSelected ? Color.coffeePrimary : Color.clear)
                    .frame(width: 24, height: 24)
                    .overlay(
                        Circle()
                            .stroke(isSelected ? Color.coffeePrimary : Color.coffeeTextSecondary.opacity(0.3), lineWidth: 1.5)
                    )
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }

    private func shareOptionRow(icon: String, title: String, subtitle: String, isSelected: Bool) -> some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.coffeePrimary.opacity(0.09))
                    .frame(width: 48, height: 48)
                Image(systemName: icon)
                    .font(.system(size: 20))
                    .foregroundStyle(Color.coffeePrimary)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.coffeeTextPrimary)
                Text(subtitle)
                    .font(.system(size: 13))
                    .foregroundStyle(Color.coffeeTextSecondary)
            }

            Spacer()

            ZStack {
                Circle()
                    .fill(isSelected ? Color.coffeePrimary : Color.clear)
                    .frame(width: 26, height: 26)
                    .overlay(
                        Circle()
                            .stroke(isSelected ? Color.coffeePrimary : Color.coffeeTextSecondary.opacity(0.3), lineWidth: 1.5)
                    )
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.white)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .contentShape(Rectangle())
    }

    // MARK: - Actions

    private func loadFriends() {
        Task {
            friends = (try? await SocialService.getFriends()) ?? []
        }
    }

    private func toggleFriend(_ friend: Friend) {
        if selectedFriendIds.contains(friend.userId) {
            selectedFriendIds.remove(friend.userId)
        } else {
            selectedFriendIds.insert(friend.userId)
        }
    }

    private func toggleSearchUser(_ user: UserSearchResult) {
        if selectedSearchIds.contains(user.id) {
            selectedSearchIds.remove(user.id)
        } else {
            selectedSearchIds.insert(user.id)
        }
    }

    private func debounceSearch(query: String) {
        searchTask?.cancel()
        guard query.count >= 2 else {
            searchResults = []
            return
        }
        searchTask = Task {
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            isSearching = true
            searchResults = (try? await SocialService.searchUsers(query: query)) ?? []
            isSearching = false
        }
    }

    private func handleShare() {
        var content: [String] = []
        if shareResumo { content.append("resumo") }
        if shareMapa { content.append("mapa") }

        // Collect all recipient IDs
        let allIds = Array(selectedFriendIds.union(selectedSearchIds))
        guard !allIds.isEmpty else { return }

        isSending = true
        errorMessage = nil

        Task {
            do {
                let request = ShareByIdsRequest(
                    gravacaoId: recordingId,
                    recipientIds: allIds,
                    sharedContent: content,
                    message: ""
                )
                let _ = try await DisciplineService.shareRecordingByIds(request: request)
                isSending = false
                showSuccess = true
            } catch {
                isSending = false
                errorMessage = "Erro ao compartilhar. Tente novamente."
            }
        }
    }
}

struct ShareByIdsRequest: Codable {
    let gravacaoId: String
    let recipientIds: [String]
    let sharedContent: [String]
    let message: String

    enum CodingKeys: String, CodingKey {
        case gravacaoId = "gravacao_id"
        case recipientIds = "recipient_ids"
        case sharedContent = "shared_content"
        case message
    }
}

#Preview {
    ShareRecordingSheet(
        recordingId: "rec1",
        hasResumo: true,
        hasMindMap: true
    )
}
