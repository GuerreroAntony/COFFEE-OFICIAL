import SwiftUI

// MARK: - Supporting Types

enum AIChatPickerStep { case discipline, recording }

struct ChatBubbleItem: Identifiable {
    let id = UUID()
    let sender: MessageSender
    let text: String
    var sources: [ChatSource] = []
}

struct AIChatPickerDiscipline: Identifiable, Equatable {
    let id: String
    let name: String
    let icon: String
    let recordingsCount: Int
}

struct AIChatPickerRecording: Identifiable, Equatable {
    let id: String
    let title: String
    let date: String
    let duration: String
}

enum AIModeOption: String, CaseIterable, Identifiable {
    case coldBrew, lungo, espresso
    var id: String { rawValue }

    var name: String {
        switch self {
        case .espresso: "Espresso"
        case .lungo: "Lungo"
        case .coldBrew: "Cold Brew"
        }
    }

    var icon: String {
        switch self {
        case .espresso: "bolt.fill"
        case .lungo: CoffeeIcon.sparkles
        case .coldBrew: "brain.head.profile"
        }
    }

    var modeDescription: String {
        switch self {
        case .espresso: "Rápido e direto ao ponto"
        case .lungo: "Equilibrado e claro"
        case .coldBrew: "Profundo e detalhado"
        }
    }
}

// MARK: - AI Chat Screen

struct AIChatScreenView: View {
    @Environment(\.router) private var router

    @State private var messages: [ChatBubbleItem] = []
    @State private var input = ""
    @State private var isTyping = false
    @AppStorage("hasSeenBaristaIntro") private var hasSeenIntro = false
    @State private var showIntro = false
    @State private var showHistory = false
    @State private var showContextPicker = false
    @State private var showModePicker = false
    @State private var pickerStep: AIChatPickerStep = .discipline

    @State private var selectedDiscipline: AIChatPickerDiscipline? = nil
    @State private var selectedRecording: AIChatPickerRecording? = nil
    @State private var selectedMode = AIModeOption.lungo
    @State private var currentChatId: String? = nil

    @State private var disciplines: [AIChatPickerDiscipline] = []
    @State private var recordings: [AIChatPickerRecording] = []
    @State private var isLoadingDisciplines = true
    @State private var isLoadingRecordings = false
    @State private var showNoDisciplineAlert = false

    var body: some View {
        VStack(spacing: 0) {
            navBar
            contextStrip
            messagesList

            AIChatInputArea(
                input: $input,
                showModePicker: $showModePicker,
                selectedMode: $selectedMode,
                onSend: handleSend
            )
        }
        .background(Color.coffeeBackground)
        .sheet(isPresented: $showIntro) {
            AIChatIntroSheet(onDismiss: {
                showIntro = false
                hasSeenIntro = true
            })
        }
        .onAppear {
            if !hasSeenIntro {
                showIntro = true
            }
        }
        .sheet(isPresented: $showHistory) {
            AIChatHistorySheet(
                onSelect: { chat, items in
                    messages = items
                    if let chat {
                        currentChatId = chat.id
                        // Match discipline from history chat
                        if let disc = disciplines.first(where: { $0.id == chat.sourceId }) {
                            selectedDiscipline = disc
                        }
                    } else {
                        // New conversation
                        currentChatId = nil
                        messages = []
                    }
                    showHistory = false
                },
                onDismiss: { showHistory = false }
            )
        }
        .sheet(isPresented: $showContextPicker) {
            AIChatContextPickerSheet(
                pickerStep: $pickerStep,
                selectedDiscipline: $selectedDiscipline,
                selectedRecording: $selectedRecording,
                disciplines: $disciplines,
                recordings: $recordings,
                isLoadingDisciplines: isLoadingDisciplines,
                isLoadingRecordings: isLoadingRecordings,
                onDismiss: { showContextPicker = false }
            )
        }
        .alert("Selecione uma matéria", isPresented: $showNoDisciplineAlert) {
            Button("OK") { }
        } message: {
            Text("Escolha uma matéria no seletor acima antes de enviar sua pergunta.")
        }
        .task { await loadDisciplines() }
        .onChange(of: selectedDiscipline) { _, newDisc in
            currentChatId = nil
            Task { await loadRecordingsForDiscipline(newDisc) }
        }
    }

    // MARK: - Nav Bar

    private var navBar: some View {
        VStack(spacing: 0) {
            HStack {
                Button {
                    router.activeTab = .home
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 16, weight: .semibold))
                        Text("Voltar")
                            .font(.system(size: 15))
                    }
                    .foregroundStyle(Color.coffeePrimary)
                }
                .frame(width: 80, alignment: .leading)

                Spacer()

                HStack(spacing: 6) {
                    Image(systemName: CoffeeIcon.sparkles)
                        .font(.system(size: 14))
                        .foregroundStyle(Color.coffeePrimary)
                    Text("Barista IA")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Color.coffeeTextPrimary)
                }

                Spacer()

                Button {
                    showHistory = true
                } label: {
                    ZStack {
                        Circle()
                            .fill(Color.coffeeTextSecondary.opacity(0.1))
                            .frame(width: 34, height: 34)
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.system(size: 15))
                            .foregroundStyle(Color.coffeePrimary)
                    }
                }
                .frame(width: 80, alignment: .trailing)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 10)

            Divider()
        }
        .padding(.top, 4)
        .background(Color.coffeeCardBackground)
    }

    // MARK: - Context Strip

    private var contextStrip: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                contextPill(
                    icon: selectedDiscipline?.icon ?? "book.fill",
                    label: selectedDiscipline?.name ?? "Todas",
                    isActive: selectedDiscipline != nil
                ) {
                    pickerStep = .discipline
                    showContextPicker = true
                }

                Image(systemName: "chevron.right")
                    .font(.system(size: 10))
                    .foregroundStyle(Color.coffeeTextSecondary.opacity(0.3))

                contextPill(
                    icon: "mic.fill",
                    label: selectedRecording?.title ?? "Todas",
                    isActive: selectedRecording != nil
                ) {
                    pickerStep = selectedDiscipline != nil ? .recording : .discipline
                    showContextPicker = true
                }
                .opacity(selectedDiscipline != nil ? 1 : 0.45)

                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)

            Divider()
        }
        .background(Color.coffeeCardBackground)
    }

    private func contextPill(icon: String, label: String, isActive: Bool, action: @escaping () -> Void) -> some View {
        let fg: Color = isActive ? .coffeePrimary : .coffeeTextSecondary
        let bg: Color = isActive ? Color.coffeePrimary.opacity(0.1) : Color.coffeeTextSecondary.opacity(0.09)
        return Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 12))
                Text(label)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.system(size: 10))
                    .foregroundStyle(Color.coffeeTextSecondary.opacity(0.5))
            }
            .foregroundStyle(fg)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(bg)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Messages List

    private var messagesList: some View {
        GeometryReader { geo in
        ScrollViewReader { proxy in
            ScrollView {
                if messages.isEmpty && !isTyping {
                    emptyState
                        .frame(minHeight: geo.size.height)
                } else {
                    LazyVStack(spacing: 20) {
                        ForEach(messages) { msg in
                            AIChatMessageRow(msg: msg)
                        }

                        if isTyping {
                            HStack {
                                TypingIndicator()
                                Spacer()
                            }
                        }

                        Color.clear.frame(height: 1).id("bottom")
                    }
                    .padding(16)
                }
            }
            .onChange(of: messages.count) {
                withAnimation { proxy.scrollTo("bottom") }
            }
            .onChange(of: isTyping) {
                withAnimation { proxy.scrollTo("bottom") }
            }
        }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        let title = selectedDiscipline != nil ? "Pergunte qualquer coisa" : "Escolha uma matéria"
        let subtitle = selectedDiscipline != nil
            ? "Selecione uma aula ou pergunte sobre todas"
            : "Selecione uma matéria acima para dar contexto à IA"

        return VStack(spacing: 12) {
            Spacer()
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.coffeePrimary.opacity(0.1))
                    .frame(width: 64, height: 64)
                Image(systemName: "bubble.left.and.bubble.right.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(Color.coffeePrimary)
            }

            Text(title)
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(Color.coffeeTextPrimary)

            Text(subtitle)
                .font(.system(size: 15))
                .foregroundStyle(Color.coffeeTextSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Send Message

    private func handleSend() {
        let text = input.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        guard let disc = selectedDiscipline else {
            showNoDisciplineAlert = true
            return
        }

        messages.append(ChatBubbleItem(sender: .user, text: text))
        input = ""
        isTyping = true

        let mode: AIMode = {
            switch selectedMode {
            case .espresso: return .espresso
            case .lungo: return .lungo
            case .coldBrew: return .coldBrew
            }
        }()

        Task {
            do {
                // Create chat if needed
                if currentChatId == nil {
                    let chat = try await AIService.createChat(sourceType: "disciplina", sourceId: disc.id)
                    currentChatId = chat.id
                }

                guard let chatId = currentChatId else { return }

                // Stream AI response
                var responseText = ""
                let stream = AIService.sendMessage(
                    chatId: chatId,
                    text: text,
                    mode: mode,
                    gravacaoId: selectedRecording?.id
                )

                // Add empty AI bubble that will accumulate text
                let aiIndex = messages.count
                messages.append(ChatBubbleItem(sender: .ai, text: ""))
                var extractedSources: [ChatSource] = []

                for try await chunk in stream {
                    // Check for SSE done payload (contains sources)
                    if chunk.hasPrefix(APIClient.sseDonePrefix) {
                        let jsonStr = String(chunk.dropFirst(APIClient.sseDonePrefix.count))
                        if let jsonData = jsonStr.data(using: .utf8),
                           let payload = try? JSONDecoder.coffeeDecoder.decode(SSEDonePayload.self, from: jsonData) {
                            extractedSources = payload.sources ?? []
                        }
                        continue
                    }
                    responseText += chunk
                    messages[aiIndex] = ChatBubbleItem(sender: .ai, text: responseText)
                }

                // Attach sources to the AI bubble
                messages[aiIndex] = ChatBubbleItem(sender: .ai, text: responseText, sources: extractedSources)
                isTyping = false
            } catch {
                print("[AIChat] Error sending message: \(error)")
                messages.append(ChatBubbleItem(sender: .ai, text: "Erro ao processar sua pergunta. Tente novamente."))
                isTyping = false
            }
        }
    }

    // MARK: - Load Data

    private func loadDisciplines() async {
        isLoadingDisciplines = true
        do {
            let discs = try await DisciplineService.getDisciplines()
            print("[AIChat] Loaded \(discs.count) disciplines from API")
            disciplines = discs.map {
                AIChatPickerDiscipline(id: $0.id, name: $0.nome, icon: CoffeeIcon.menuBook, recordingsCount: $0.gravacoesCount)
            }

            // Handle initial source from router
            if let source = router.aiInitialSource {
                if let disc = disciplines.first(where: { source.name.contains($0.name) }) {
                    selectedDiscipline = disc
                }
                router.aiInitialSource = nil
            }
        } catch {
            print("[AIChat] Error loading disciplines: \(error)")
        }
        isLoadingDisciplines = false
    }

    private func loadRecordingsForDiscipline(_ disc: AIChatPickerDiscipline?) async {
        guard let disc else {
            recordings = []
            return
        }
        isLoadingRecordings = true
        do {
            let recs = try await RecordingService.getRecordings(sourceType: "disciplina", sourceId: disc.id)
            print("[AIChat] Loaded \(recs.count) recordings for discipline \(disc.name)")
            recordings = recs.map {
                AIChatPickerRecording(id: $0.id, title: $0.shortSummary ?? $0.dateLabel, date: $0.dateLabel, duration: $0.durationLabel)
            }
        } catch {
            print("[AIChat] Error loading recordings: \(error)")
            recordings = []
        }
        isLoadingRecordings = false
    }
}

// MARK: - Message Row

struct AIChatMessageRow: View {
    let msg: ChatBubbleItem

    var body: some View {
        if msg.sender == .ai {
            aiMessage
        } else {
            userMessage
        }
    }

    private var aiMessage: some View {
        VStack(alignment: .leading, spacing: 8) {
            CoffeeBubble(text: msg.text, isFromUser: false)

            if !msg.sources.isEmpty {
                Text("Fontes citadas")
                    .font(.system(size: 11, weight: .semibold))
                    .textCase(.uppercase)
                    .tracking(1)
                    .foregroundStyle(Color.coffeeTextSecondary)
                    .padding(.leading, 4)

                ForEach(msg.sources) { source in
                    let isTranscription = source.type == "transcription"
                    let subtitle = isTranscription
                        ? "\(source.date ?? "") · Transcrição"
                        : "Material"
                    CoffeeSourceCard(
                        title: source.title,
                        subtitle: subtitle,
                        icon: isTranscription ? "mic.fill" : "doc.text.fill"
                    )
                }
            }
        }
        .frame(maxWidth: UIScreen.main.bounds.width * 0.85, alignment: .leading)
    }

    private var userMessage: some View {
        HStack {
            Spacer()
            CoffeeBubble(text: msg.text, isFromUser: true)
                .frame(maxWidth: UIScreen.main.bounds.width * 0.8, alignment: .trailing)
        }
    }
}

// MARK: - Input Area

struct AIChatInputArea: View {
    @Binding var input: String
    @Binding var showModePicker: Bool
    @Binding var selectedMode: AIModeOption
    let onSend: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            if showModePicker {
                AIChatModePickerPopup(
                    selectedMode: $selectedMode,
                    showModePicker: $showModePicker
                )
            }
            inputField
        }
    }

    private var inputField: some View {
        let isEmpty = input.trimmingCharacters(in: .whitespaces).isEmpty
        let sendBg: Color = isEmpty ? Color.coffeeTextSecondary.opacity(0.1) : Color.coffeePrimary
        let sendFg: Color = isEmpty ? Color.coffeeTextSecondary : .white

        return VStack(spacing: 0) {
            TextField("Pergunte qualquer coisa...", text: $input, axis: .vertical)
                .font(.system(size: 16))
                .lineLimit(1...6)
                .tint(Color.coffeePrimary)
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 8)
                .onSubmit { onSend() }

            HStack(spacing: 8) {
                Button { } label: {
                    ZStack {
                        Circle()
                            .fill(Color.coffeeTextSecondary.opacity(0.1))
                            .frame(width: 36, height: 36)
                        Image(systemName: "plus")
                            .font(.system(size: 16))
                            .foregroundStyle(Color.coffeeTextSecondary)
                    }
                }

                Button { showModePicker.toggle() } label: {
                    HStack(spacing: 6) {
                        Image(systemName: selectedMode.icon)
                            .font(.system(size: 11))
                        Text(selectedMode.name)
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .foregroundStyle(Color.coffeePrimary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.coffeeTextSecondary.opacity(0.1))
                    .clipShape(Capsule())
                }

                Spacer()

                Button { } label: {
                    ZStack {
                        Circle()
                            .fill(Color.coffeeTextSecondary.opacity(0.1))
                            .frame(width: 36, height: 36)
                        Image(systemName: "mic.fill")
                            .font(.system(size: 16))
                            .foregroundStyle(Color.coffeeTextSecondary)
                    }
                }

                Button { onSend() } label: {
                    ZStack {
                        Circle()
                            .fill(sendBg)
                            .frame(width: 36, height: 36)
                        Image(systemName: "arrow.up")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(sendFg)
                    }
                }
                .disabled(isEmpty)
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 14)
        }
        .background(Color.coffeeCardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .shadow(color: .black.opacity(0.07), radius: 8, y: 2)
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
    }
}

// MARK: - Mode Picker Popup

struct AIChatModePickerPopup: View {
    @Binding var selectedMode: AIModeOption
    @Binding var showModePicker: Bool

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(AIModeOption.allCases.enumerated()), id: \.element.id) { index, mode in
                Button {
                    selectedMode = mode
                    showModePicker = false
                } label: {
                    modeRow(mode)
                }
                .buttonStyle(.plain)

                if index < AIModeOption.allCases.count - 1 {
                    Divider().padding(.leading, 76)
                }
            }
        }
        .background(Color.coffeeCardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: .black.opacity(0.1), radius: 12, y: -4)
        .padding(.horizontal, 12)
        .padding(.bottom, 4)
    }

    private func modeRow(_ mode: AIModeOption) -> some View {
        let isSelected = selectedMode == mode
        let iconBg: Color = isSelected ? Color.coffeePrimary.opacity(0.1) : Color.coffeeTextSecondary.opacity(0.08)
        let iconFg: Color = isSelected ? Color.coffeePrimary : Color.coffeeTextSecondary

        return HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(iconBg)
                    .frame(width: 46, height: 46)
                Image(systemName: mode.icon)
                    .font(.system(size: 20))
                    .foregroundStyle(iconFg)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(mode.name)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.coffeeTextPrimary)
                Text(mode.modeDescription)
                    .font(.system(size: 14))
                    .foregroundStyle(Color.coffeeTextSecondary)
            }

            Spacer()

            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(Color.coffeePrimary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }
}

// MARK: - Intro Sheet

struct AIChatIntroSheet: View {
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Drag indicator
            RoundedRectangle(cornerRadius: 2.5)
                .fill(Color.coffeeTextSecondary.opacity(0.3))
                .frame(width: 36, height: 5)
                .padding(.top, 10)

            ScrollView {
                VStack(spacing: 28) {
                    // Hero header
                    VStack(spacing: 16) {
                        ZStack {
                            Circle()
                                .fill(Color.coffeePrimary.opacity(0.12))
                                .frame(width: 88, height: 88)

                            Circle()
                                .fill(Color.coffeePrimary)
                                .frame(width: 68, height: 68)
                                .shadow(color: Color.coffeePrimary.opacity(0.3), radius: 12, y: 6)

                            Image(systemName: CoffeeIcon.sparkles)
                                .font(.system(size: 30))
                                .foregroundStyle(.white)
                        }

                        Text("Conheça o Barista IA")
                            .font(.system(size: 24, weight: .bold))
                            .foregroundStyle(Color.coffeeTextPrimary)

                        Text("Seu assistente de estudos com base\nnas suas aulas gravadas")
                            .font(.system(size: 15))
                            .foregroundStyle(Color.coffeeTextSecondary)
                            .multilineTextAlignment(.center)
                            .lineSpacing(2)
                    }
                    .padding(.top, 24)

                    // Features card
                    VStack(spacing: 0) {
                        introFeatureRow(
                            icon: "book.fill",
                            color: Color.coffeePrimary,
                            title: "Selecione a matéria",
                            desc: "Escolha uma disciplina para dar contexto",
                            showDivider: true
                        )
                        introFeatureRow(
                            icon: "mic.fill",
                            color: .orange,
                            title: "Filtre por aula",
                            desc: "Consulte uma aula específica ou todas",
                            showDivider: true
                        )
                        introFeatureRow(
                            icon: "brain.head.profile",
                            color: .purple,
                            title: "Escolha o modo",
                            desc: "Espresso, Lungo ou Cold Brew",
                            showDivider: true
                        )
                        introFeatureRow(
                            icon: "text.magnifyingglass",
                            color: .blue,
                            title: "Busque entre aulas",
                            desc: "Encontre conceitos em todas as suas aulas",
                            showDivider: true
                        )
                        introFeatureRow(
                            icon: "bubble.left.fill",
                            color: .green,
                            title: "Pergunte livremente",
                            desc: "A IA usa suas aulas como fonte",
                            showDivider: false
                        )
                    }
                    .background(Color.coffeeCardBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .padding(.horizontal, 20)
                }
                .padding(.bottom, 20)
            }

            CoffeeButton("Entendido, vamos lá") {
                onDismiss()
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 40)
        }
        .background(Color.coffeeBackground)
        .presentationDetents([.large])
    }

    private func introFeatureRow(icon: String, color: Color, title: String, desc: String, showDivider: Bool) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(color.opacity(0.1))
                        .frame(width: 44, height: 44)
                    Image(systemName: icon)
                        .font(.system(size: 20))
                        .foregroundStyle(color)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color.coffeeTextPrimary)
                    Text(desc)
                        .font(.system(size: 13))
                        .foregroundStyle(Color.coffeeTextSecondary)
                }

                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            if showDivider {
                Divider()
                    .padding(.leading, 74)
            }
        }
    }
}

// MARK: - History Sheet

struct AIChatHistorySheet: View {
    let onSelect: (Chat?, [ChatBubbleItem]) -> Void
    let onDismiss: () -> Void

    @State private var chats: [Chat] = []
    @State private var isLoading = true
    @State private var loadingChatId: String? = nil

    var body: some View {
        VStack(spacing: 0) {
            CoffeeSheetHeader(title: "Histórico", onClose: onDismiss)
            newConversationButton
            chatList
        }
        .background(Color.coffeeBackground)
        .presentationDetents([.large])
        .task {
            do {
                chats = try await AIService.getChats()
            } catch {
                print("[AIChatHistory] Error loading chats: \(error)")
            }
            isLoading = false
        }
    }

    private var newConversationButton: some View {
        Button {
            onSelect(nil, [])
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "plus.circle.fill")
                    .foregroundStyle(Color.coffeePrimary)
                Text("Nova conversa")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.coffeePrimary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(Color.coffeePrimary.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
    }

    private var chatList: some View {
        ScrollView {
            if isLoading {
                ProgressView()
                    .tint(Color.coffeePrimary)
                    .padding(.top, 40)
            } else if chats.isEmpty {
                CoffeeEmptyState(
                    icon: "bubble.left.and.bubble.right",
                    title: "Nenhuma conversa",
                    message: "Suas conversas com o Barista IA aparecerão aqui."
                )
                .padding(.top, 40)
            } else {
                CoffeeSectionHeader(title: "Conversas recentes")
                    .padding(.horizontal, 20)
                    .padding(.bottom, 8)

                CoffeeCellGroup {
                    ForEach(Array(chats.enumerated()), id: \.element.id) { index, chat in
                        Button {
                            guard loadingChatId == nil else { return }
                            loadingChatId = chat.id
                            Task {
                                do {
                                    let chatMessages = try await AIService.getChatMessages(chatId: chat.id)
                                    let bubbles = chatMessages.map { msg in
                                        ChatBubbleItem(sender: msg.sender, text: msg.text, sources: msg.sources ?? [])
                                    }
                                    onSelect(chat, bubbles)
                                } catch {
                                    print("[AIChatHistory] Error loading messages: \(error)")
                                    loadingChatId = nil
                                }
                            }
                        } label: {
                            AIChatHistoryRow(chat: chat, isLoading: loadingChatId == chat.id)
                        }
                        .buttonStyle(.plain)
                        .disabled(loadingChatId != nil)

                        if index < chats.count - 1 {
                            Divider().padding(.leading, 76)
                        }
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }
}

// MARK: - History Row

struct AIChatHistoryRow: View {
    let chat: Chat
    var isLoading: Bool = false

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.coffeePrimary.opacity(0.08))
                    .frame(width: 50, height: 50)
                Image(systemName: "bubble.left.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(Color.coffeePrimary)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(chat.lastMessage ?? "")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.coffeeTextPrimary)
                    .lineLimit(1)
                Text("\(chat.sourceName) · \(chat.messageCount) msgs")
                    .font(.system(size: 14))
                    .foregroundStyle(Color.coffeeTextSecondary)
            }

            Spacer()

            if isLoading {
                ProgressView()
                    .tint(Color.coffeePrimary)
            } else {
                Image(systemName: "chevron.right")
                    .font(.system(size: 14))
                    .foregroundStyle(Color.coffeeTextSecondary.opacity(0.5))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .contentShape(Rectangle())
    }
}

// MARK: - Context Picker Sheet

struct AIChatContextPickerSheet: View {
    @Binding var pickerStep: AIChatPickerStep
    @Binding var selectedDiscipline: AIChatPickerDiscipline?
    @Binding var selectedRecording: AIChatPickerRecording?
    @Binding var disciplines: [AIChatPickerDiscipline]
    @Binding var recordings: [AIChatPickerRecording]
    let isLoadingDisciplines: Bool
    let isLoadingRecordings: Bool
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            pickerHeader
            ScrollView {
                if pickerStep == .discipline {
                    if isLoadingDisciplines && disciplines.isEmpty {
                        ProgressView()
                            .tint(Color.coffeePrimary)
                            .padding(.top, 40)
                    } else if disciplines.isEmpty {
                        CoffeeEmptyState(
                            icon: "book.closed",
                            title: "Nenhuma matéria",
                            message: "Conecte sua conta ESPM para ver suas matérias aqui."
                        )
                        .padding(.top, 40)
                    } else {
                        disciplineList
                    }
                } else {
                    if isLoadingRecordings {
                        ProgressView()
                            .tint(Color.coffeePrimary)
                            .padding(.top, 40)
                    } else {
                        recordingList
                    }
                }
            }
        }
        .background(Color.coffeeBackground)
        .presentationDetents([.medium, .large])
    }

    private var pickerHeader: some View {
        let headerTitle = pickerStep == .discipline ? "Escolher matéria" : (selectedDiscipline?.name ?? "")

        return HStack {
            if pickerStep == .recording {
                Button {
                    pickerStep = .discipline
                } label: {
                    HStack(spacing: 2) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 18))
                        Text("Matérias")
                            .font(.system(size: 15))
                    }
                    .foregroundStyle(Color.coffeePrimary)
                }
            } else {
                Spacer().frame(width: 70)
            }

            Spacer()

            Text(headerTitle)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color.coffeeTextPrimary)

            Spacer()

            Button("Fechar") { onDismiss() }
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color.coffeePrimary)
                .frame(width: 70, alignment: .trailing)
        }
        .padding(.horizontal, 16)
        .padding(.top, 24)
        .padding(.bottom, 16)
    }

    private var disciplineList: some View {
        CoffeeCellGroup {
            ForEach(Array(disciplines.enumerated()), id: \.element.id) { index, disc in
                Button {
                    if selectedDiscipline?.id != disc.id {
                        selectedRecording = nil
                    }
                    selectedDiscipline = disc
                    pickerStep = .recording
                } label: {
                    AIChatDisciplineRow(disc: disc, isSelected: selectedDiscipline?.id == disc.id)
                }
                .buttonStyle(.plain)

                if index < disciplines.count - 1 {
                    Divider().padding(.leading, 76)
                }
            }
        }
        .padding(.horizontal, 16)
    }

    private var recordingList: some View {
        CoffeeCellGroup {
            // All recordings option
            Button {
                selectedRecording = nil
                onDismiss()
            } label: {
                AIChatRecordingAllRow(count: recordings.count, isSelected: selectedRecording == nil)
            }
            .buttonStyle(.plain)

            Divider().padding(.leading, 56)

            ForEach(Array(recordings.enumerated()), id: \.element.id) { index, rec in
                Button {
                    selectedRecording = rec
                    onDismiss()
                } label: {
                    AIChatRecordingRow(rec: rec, isSelected: selectedRecording?.id == rec.id)
                }
                .buttonStyle(.plain)

                if index < recordings.count - 1 {
                    Divider().padding(.leading, 76)
                }
            }
        }
        .padding(.horizontal, 16)
    }
}

// MARK: - Discipline Row

struct AIChatDisciplineRow: View {
    let disc: AIChatPickerDiscipline
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.coffeePrimary.opacity(0.1))
                    .frame(width: 52, height: 52)
                Image(systemName: disc.icon)
                    .font(.system(size: 20))
                    .foregroundStyle(Color.coffeePrimary)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(disc.name)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.coffeeTextPrimary)
                Text("\(disc.recordingsCount) aulas")
                    .font(.system(size: 14))
                    .foregroundStyle(Color.coffeeTextSecondary)
            }

            Spacer()

            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(Color.coffeePrimary)
            } else {
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.coffeeTextSecondary.opacity(0.5))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 16)
        .contentShape(Rectangle())
    }
}

// MARK: - Recording All Row

struct AIChatRecordingAllRow: View {
    let count: Int
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.coffeePrimary.opacity(0.1))
                    .frame(width: 52, height: 52)
                Image(systemName: "square.stack.3d.up.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(Color.coffeePrimary)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text("Todas as aulas")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.coffeeTextPrimary)
                Text("\(count) aulas")
                    .font(.system(size: 14))
                    .foregroundStyle(Color.coffeeTextSecondary)
            }

            Spacer()

            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(Color.coffeePrimary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 16)
        .contentShape(Rectangle())
    }
}

// MARK: - Recording Row

struct AIChatRecordingRow: View {
    let rec: AIChatPickerRecording
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.coffeeTextSecondary.opacity(0.08))
                    .frame(width: 52, height: 52)
                Image(systemName: "mic.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(Color.coffeeTextSecondary)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(rec.title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.coffeeTextPrimary)
                Text("\(rec.date) · \(rec.duration)")
                    .font(.system(size: 14))
                    .foregroundStyle(Color.coffeeTextSecondary)
            }

            Spacer()

            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(Color.coffeePrimary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 16)
        .contentShape(Rectangle())
    }
}

#Preview {
    AIChatScreenView()
        .environment(\.router, NavigationRouter())
}
