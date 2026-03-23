import SwiftUI
import MarkdownUI
import Speech
import AVFoundation
import UniformTypeIdentifiers
import PDFKit

// MARK: - Supporting Types

enum AIChatPickerStep { case discipline, recording }
enum AIChatSourceTab: String, CaseIterable { case disciplinas = "Disciplinas", outros = "Outros" }

struct ChatBubbleItem: Identifiable {
    let id = UUID()
    let sender: MessageSender
    let text: String
    var sources: [ChatSource] = []
    var isStreaming: Bool = false
}

struct AIChatPickerDiscipline: Identifiable, Equatable {
    let id: String
    let name: String
    let icon: String
    let iconColor: String
    let recordingsCount: Int
}

struct AIChatPickerRecording: Identifiable, Equatable {
    let id: String
    let title: String
    let date: String
    let duration: String
}

enum AIModeOption: String, CaseIterable, Identifiable {
    case amigo, professor, rapido
    var id: String { rawValue }

    var name: String {
        switch self {
        case .rapido: "Rapido"
        case .professor: "Professor"
        case .amigo: "Amigo"
        }
    }

    var icon: String {
        switch self {
        case .rapido: "bolt.fill"
        case .professor: "graduationcap.fill"
        case .amigo: "person.2.fill"
        }
    }

    var modeDescription: String {
        switch self {
        case .rapido: "Direto ao ponto"
        case .professor: "Explicacao clara e estruturada"
        case .amigo: "Como um amigo explicando"
        }
    }
}

// MARK: - AI Chat Screen

struct AIChatScreenView: View {
    @Environment(\.router) private var router

    @State private var messages: [ChatBubbleItem] = []
    @State private var input = ""
    @State private var isTyping = false
    @State private var isStreaming = false
    @AppStorage("hasSeenBaristaIntro") private var hasSeenIntro = false
    @State private var showIntro: Bool? = nil  // nil = not yet decided
    @State private var showHistory = false
    @State private var showContextPicker = false
    @State private var showModePicker = false
    @State private var pickerStep: AIChatPickerStep = .discipline

    @State private var selectedDiscipline: AIChatPickerDiscipline? = nil
    @State private var selectedRecording: AIChatPickerRecording? = nil
    @State private var selectedMode = AIModeOption.professor
    @State private var currentChatId: String? = nil

    @State private var disciplines: [AIChatPickerDiscipline] = []
    @State private var recordings: [AIChatPickerRecording] = []
    @State private var isLoadingDisciplines = true
    @State private var isLoadingRecordings = false
    @State private var showNoDisciplineAlert = false

    // Microphone voice-to-text
    @State private var isListening = false
    @State private var audioEngine = AVAudioEngine()
    @State private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    @State private var recognitionTask: SFSpeechRecognitionTask?
    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "pt-BR"))

    // Attachments
    @State private var showAttachmentSheet = false
    @State private var showCameraForChat = false
    @State private var showFileImporterForChat = false
    @State private var chatAttachments: [(name: String, text: String)] = []

    var body: some View {
        ZStack {
            if !PlanAccess.canUseBarista(router.currentUser?.plano) {
                VStack(spacing: 0) {
                    HStack {
                        Button {
                            router.activeTab = .home
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "chevron.left")
                                    .font(.system(size: 16, weight: .semibold))
                                Text("Voltar")
                                    .font(.system(size: 17))
                            }
                            .foregroundStyle(Color.coffeePrimary)
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)

                    UpgradeGateView(feature: .barista) { router.showPremiumOffer() }
                }
            } else if showIntro == true {
                // Clean background while intro is visible — no flash of empty chat
                Color.coffeeBackground
                    .ignoresSafeArea()
            } else {
                VStack(spacing: 0) {
                    navBar
                    contextStrip
                    messagesList

                    AIChatInputArea(
                        input: $input,
                        showModePicker: $showModePicker,
                        selectedMode: $selectedMode,
                        isListening: isListening,
                        attachments: chatAttachments,
                        onSend: handleSend,
                        onMicTap: { isListening ? stopListening() : startListening() },
                        onAttachTap: { showAttachmentSheet = true },
                        onRemoveAttachment: { index in
                            if chatAttachments.indices.contains(index) {
                                chatAttachments.remove(at: index)
                            }
                        }
                    )
                }
                .transition(.opacity.animation(.easeOut(duration: 0.3)))
            }
        }
        .background(Color.coffeeBackground)
        .fullScreenCover(isPresented: Binding(
            get: { showIntro == true },
            set: { newVal in if !newVal { showIntro = false } }
        )) {
            AIChatIntroSheet(onDismiss: {
                withAnimation(.easeOut(duration: 0.35)) {
                    showIntro = false
                }
                hasSeenIntro = true
            })
        }
        .onAppear {
            if showIntro == nil {
                showIntro = hasSeenIntro ? false : true
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
                onSelectAll: {
                    selectedDiscipline = nil
                    selectedRecording = nil
                    currentChatId = nil
                },
                onDismiss: { showContextPicker = false }
            )
        }
        .alert("Nenhuma matéria disponível", isPresented: $showNoDisciplineAlert) {
            Button("OK") { }
        } message: {
            Text("Conecte sua conta ESPM para carregar suas matérias.")
        }
        .task { await loadDisciplines() }
        .onChange(of: selectedDiscipline) { _, newDisc in
            currentChatId = nil
            Task { await loadRecordingsForDiscipline(newDisc) }
        }
        .confirmationDialog("Adicionar", isPresented: $showAttachmentSheet) {
            Button("Câmera") { showCameraForChat = true }
            Button("Arquivo") { showFileImporterForChat = true }
            Button("Cancelar", role: .cancel) { }
        }
        .fullScreenCover(isPresented: $showCameraForChat) {
            CameraPickerView(isPresented: $showCameraForChat) { imageData in
                chatAttachments.append((name: "Foto capturada", text: "[Foto anexada pelo usuário]"))
            }
            .ignoresSafeArea()
        }
        .fileImporter(
            isPresented: $showFileImporterForChat,
            allowedContentTypes: [.pdf, .image],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                guard url.startAccessingSecurityScopedResource() else { return }
                defer { url.stopAccessingSecurityScopedResource() }
                let fileName = url.lastPathComponent
                if url.pathExtension.lowercased() == "pdf" {
                    if let data = try? Data(contentsOf: url),
                       let pdfDoc = PDFDocument(data: data) {
                        let text = (0..<pdfDoc.pageCount).compactMap { pdfDoc.page(at: $0)?.string }.joined(separator: "\n")
                        chatAttachments.append((name: fileName, text: text.isEmpty ? "[PDF sem texto extraível]" : text))
                    } else {
                        chatAttachments.append((name: fileName, text: "[Erro ao ler PDF]"))
                    }
                } else {
                    chatAttachments.append((name: fileName, text: "[Imagem anexada]"))
                }
            case .failure(let error):
                print("[AIChat] File picker error: \(error)")
            }
        }
        .onDisappear { stopListening() }
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
                    icon: selectedDiscipline?.icon ?? "books.vertical.fill",
                    label: selectedDiscipline?.name ?? "Todas as Disciplinas",
                    isActive: true
                ) {
                    pickerStep = .discipline
                    showContextPicker = true
                }

                if selectedDiscipline != nil {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10))
                        .foregroundStyle(Color.coffeeTextSecondary.opacity(0.3))

                    contextPill(
                        icon: "mic.fill",
                        label: selectedRecording?.title ?? "Todas",
                        isActive: selectedRecording != nil
                    ) {
                        pickerStep = .recording
                        showContextPicker = true
                    }
                }

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
                    LazyVStack(spacing: 24) {
                        ForEach(messages) { msg in
                            AIChatMessageRow(msg: msg)
                        }

                        if isTyping && !isStreaming {
                            HStack {
                                ThinkingStepsView()
                                Spacer()
                            }
                            .transition(.opacity)
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

    // MARK: - Voice Input

    private func startListening() {
        SFSpeechRecognizer.requestAuthorization { authStatus in
            DispatchQueue.main.async {
                guard authStatus == .authorized else {
                    print("[AIChat] Speech recognition not authorized: \(authStatus.rawValue)")
                    return
                }
                guard let speechRecognizer, speechRecognizer.isAvailable else {
                    print("[AIChat] Speech recognizer not available")
                    return
                }

                do {
                    let audioSession = AVAudioSession.sharedInstance()
                    try audioSession.setCategory(.playAndRecord, mode: .measurement, options: [.defaultToSpeaker, .duckOthers])
                    try audioSession.setActive(true, options: .notifyOthersOnDeactivation)

                    let request = SFSpeechAudioBufferRecognitionRequest()
                    request.shouldReportPartialResults = true
                    if #available(iOS 16, *) {
                        request.addsPunctuation = true
                    }
                    recognitionRequest = request

                    let inputNode = audioEngine.inputNode
                    let recordingFormat = inputNode.outputFormat(forBus: 0)
                    inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { buffer, _ in
                        request.append(buffer)
                    }

                    audioEngine.prepare()
                    try audioEngine.start()

                    let textBeforeListening = input
                    recognitionTask = speechRecognizer.recognitionTask(with: request) { result, error in
                        if let result {
                            let spokenText = result.bestTranscription.formattedString
                            DispatchQueue.main.async {
                                if textBeforeListening.isEmpty {
                                    input = spokenText
                                } else {
                                    input = textBeforeListening + " " + spokenText
                                }
                            }
                        }
                        if error != nil || (result?.isFinal ?? false) {
                            DispatchQueue.main.async {
                                stopListening()
                            }
                        }
                    }

                    isListening = true
                } catch {
                    print("[AIChat] Audio engine error: \(error)")
                }
            }
        }
    }

    private func stopListening() {
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionRequest = nil
        recognitionTask = nil
        isListening = false
    }

    // MARK: - Send Message

    private func handleSend() {
        var text = input.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty || !chatAttachments.isEmpty else { return }

        // "Todas as Disciplinas" = selectedDiscipline is nil → use source_type "all"
        let isAllDisciplines = (selectedDiscipline == nil)
        let disc = selectedDiscipline ?? disciplines.first
        // Allow sending even without a discipline when in "all" mode
        if !isAllDisciplines && disc == nil {
            showNoDisciplineAlert = true
            return
        }

        // Stop listening if active
        if isListening { stopListening() }

        // Prepend attachment context
        if !chatAttachments.isEmpty {
            var contextParts: [String] = []
            for att in chatAttachments {
                contextParts.append("[Contexto do arquivo: \(att.name)]\n\(att.text)")
            }
            let attachContext = contextParts.joined(separator: "\n\n")
            text = attachContext + "\n\n" + text
            chatAttachments.removeAll()
        }

        messages.append(ChatBubbleItem(sender: .user, text: input.trimmingCharacters(in: .whitespaces).isEmpty ? "📎 Arquivo(s) enviado(s)" : input.trimmingCharacters(in: .whitespaces)))
        input = ""
        isTyping = true

        let mode: AIMode = {
            switch selectedMode {
            case .rapido: return .rapido
            case .professor: return .professor
            case .amigo: return .amigo
            }
        }()

        Task {
            do {
                // Create chat if needed
                if currentChatId == nil {
                    if isAllDisciplines {
                        let chat = try await AIService.createChat(sourceType: "all", sourceId: nil)
                        currentChatId = chat.id
                    } else if let disc {
                        let chat = try await AIService.createChat(sourceType: "disciplina", sourceId: disc.id)
                        currentChatId = chat.id
                    }
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

                // AI bubble will be added on first real chunk
                var aiIndex: Int?
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

                    // First chunk: add AI bubble, hide thinking steps
                    if aiIndex == nil {
                        aiIndex = messages.count
                        messages.append(ChatBubbleItem(sender: .ai, text: "", isStreaming: true))
                        isStreaming = true
                    }

                    responseText += chunk
                    messages[aiIndex!] = ChatBubbleItem(sender: .ai, text: responseText, isStreaming: true)
                }

                // Final: attach sources, mark streaming complete
                if let idx = aiIndex {
                    messages[idx] = ChatBubbleItem(sender: .ai, text: responseText, sources: extractedSources, isStreaming: false)
                } else {
                    // No chunks received — add a fallback bubble
                    messages.append(ChatBubbleItem(sender: .ai, text: responseText.isEmpty ? "Não foi possível gerar uma resposta." : responseText, sources: extractedSources))
                }
                isTyping = false
                isStreaming = false
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
            disciplines = discs.enumerated().map { index, d in
                AIChatPickerDiscipline(
                    id: d.id,
                    name: d.nome,
                    icon: d.displayIcon(at: index),
                    iconColor: d.displayColorHex(at: index),
                    recordingsCount: d.gravacoesCount
                )
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
    @State private var sourcesExpanded = false
    @State private var previewMaterial: Material? = nil

    var body: some View {
        if msg.sender == .ai {
            aiMessage
        } else {
            userMessage
        }
    }

    private var aiMessage: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Avatar row
            HStack(spacing: 10) {
                BaristaAvatar(size: 26)
                Text("Barista")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.coffeeTextSecondary)
            }
            .padding(.bottom, 12)

            // Content — clean, full-width, breathable
            Group {
                if msg.isStreaming {
                    Text(msg.text)
                        .font(.system(size: 15.5))
                        .lineSpacing(6)
                } else {
                    Markdown(msg.text)
                        .markdownTheme(.coffee)
                }
            }
            .foregroundStyle(Color.coffeeTextPrimary)

            // Copy button (only after streaming completes)
            if !msg.isStreaming && !msg.text.isEmpty {
                HStack {
                    Spacer()
                    Button {
                        UIPasteboard.general.string = msg.text
                    } label: {
                        Image(systemName: "doc.on.doc")
                            .font(.system(size: 13))
                            .foregroundStyle(Color.coffeeTextTertiary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.top, 12)
            }

            if !msg.sources.isEmpty {
                // Collapsible "Fontes citadas (N)" button
                Button {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        sourcesExpanded.toggle()
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: sourcesExpanded ? "chevron.down" : "chevron.right")
                            .font(.system(size: 10, weight: .semibold))
                        Text("Fontes citadas (\(msg.sources.count))")
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .foregroundStyle(Color.coffeePrimary)
                    .padding(.leading, 4)
                    .padding(.vertical, 4)
                }
                .buttonStyle(.plain)
                .padding(.top, 8)

                if sourcesExpanded {
                    ForEach(msg.sources) { source in
                        let isTranscription = source.type == "transcription"
                        let subtitle = isTranscription
                            ? "\(source.date ?? "") · Transcrição"
                            : "Material"
                        CoffeeSourceCard(
                            title: source.title,
                            subtitle: subtitle,
                            icon: isTranscription ? "mic.fill" : "doc.text.fill",
                            onTap: source.type == "material" && source.materialId != nil ? {
                                loadMaterialPreview(materialId: source.materialId!)
                            } : nil
                        )
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
        }
        .sheet(item: $previewMaterial) { material in
            MaterialPreviewSheet(material: material)
        }
    }

    private var userMessage: some View {
        HStack {
            Spacer()
            CoffeeBubble(text: msg.text, isFromUser: true)
                .frame(maxWidth: UIScreen.main.bounds.width * 0.8, alignment: .trailing)
        }
    }

    private func loadMaterialPreview(materialId: String) {
        Task {
            do {
                let material = try await MaterialService.getMaterial(id: materialId)
                previewMaterial = material
            } catch {
                print("[AIChat] Error loading material preview: \(error)")
            }
        }
    }
}

// MARK: - Input Area

struct AIChatInputArea: View {
    @Binding var input: String
    @Binding var showModePicker: Bool
    @Binding var selectedMode: AIModeOption
    let isListening: Bool
    let attachments: [(name: String, text: String)]
    let onSend: () -> Void
    let onMicTap: () -> Void
    let onAttachTap: () -> Void
    let onRemoveAttachment: (Int) -> Void

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
        let isEmpty = input.trimmingCharacters(in: .whitespaces).isEmpty && attachments.isEmpty
        let sendBg: Color = isEmpty ? Color.coffeeTextSecondary.opacity(0.1) : Color.coffeePrimary
        let sendFg: Color = isEmpty ? Color.coffeeTextSecondary : .white

        return VStack(spacing: 0) {
            // Attachment chips
            if !attachments.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(Array(attachments.enumerated()), id: \.offset) { index, att in
                            HStack(spacing: 6) {
                                Image(systemName: "doc.fill")
                                    .font(.system(size: 11))
                                Text(att.name)
                                    .font(.system(size: 12, weight: .medium))
                                    .lineLimit(1)
                                Button {
                                    onRemoveAttachment(index)
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.system(size: 13))
                                        .foregroundStyle(Color.coffeeTextSecondary)
                                }
                            }
                            .foregroundStyle(Color.coffeePrimary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Color.coffeePrimary.opacity(0.08))
                            .clipShape(Capsule())
                        }
                    }
                    .padding(.horizontal, 16)
                }
                .padding(.top, 10)
            }

            TextField("Pergunte qualquer coisa...", text: $input, axis: .vertical)
                .font(.system(size: 16))
                .lineLimit(1...6)
                .tint(Color.coffeePrimary)
                .padding(.horizontal, 16)
                .padding(.top, attachments.isEmpty ? 16 : 8)
                .padding(.bottom, 8)
                .onSubmit { onSend() }

            HStack(spacing: 8) {
                Button { onAttachTap() } label: {
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

                Button { onMicTap() } label: {
                    ZStack {
                        Circle()
                            .fill(isListening ? Color.coffeeDanger : Color.coffeeTextSecondary.opacity(0.1))
                            .frame(width: 36, height: 36)
                            .scaleEffect(isListening ? 1.15 : 1.0)
                            .animation(isListening ? .easeInOut(duration: 0.8).repeatForever(autoreverses: true) : .easeInOut(duration: 0.2), value: isListening)
                        Image(systemName: "mic.fill")
                            .font(.system(size: 16))
                            .foregroundStyle(isListening ? .white : Color.coffeeTextSecondary)
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
            // Close button
            HStack {
                Spacer()
                Button {
                    onDismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color.coffeeTextSecondary)
                        .padding(10)
                        .background(Color.coffeeTextSecondary.opacity(0.1))
                        .clipShape(Circle())
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)

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
                    .padding(.top, 8)

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
    let onSelectAll: () -> Void
    let onDismiss: () -> Void

    @State private var sourceTab: AIChatSourceTab = .disciplinas
    @State private var repositories: [Repository] = []
    @State private var isLoadingRepos = false

    var body: some View {
        VStack(spacing: 0) {
            pickerHeader

            if pickerStep == .discipline {
                // Segmented picker
                Picker("", selection: $sourceTab) {
                    ForEach(AIChatSourceTab.allCases, id: \.self) { tab in
                        Text(tab.rawValue).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
            }

            ScrollView {
                if pickerStep == .discipline {
                    if sourceTab == .disciplinas {
                        disciplinesContent
                    } else {
                        repositoriesContent
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
        .onChange(of: sourceTab) { _, newTab in
            if newTab == .outros && repositories.isEmpty {
                loadRepositories()
            }
        }
    }

    // MARK: - Disciplines Content

    private var disciplinesContent: some View {
        VStack(spacing: 0) {
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
                .frame(maxWidth: .infinity)
                .padding(.top, 40)
            } else {
                CoffeeCellGroup {
                    // "Todas as Disciplinas" option
                    Button {
                        selectedDiscipline = nil
                        selectedRecording = nil
                        onSelectAll()
                        onDismiss()
                    } label: {
                        HStack(spacing: 14) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .fill(Color.coffeePrimary.opacity(0.1))
                                    .frame(width: 52, height: 52)
                                Image(systemName: "books.vertical.fill")
                                    .font(.system(size: 20))
                                    .foregroundStyle(Color.coffeePrimary)
                            }

                            VStack(alignment: .leading, spacing: 2) {
                                Text("Todas as Disciplinas")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundStyle(Color.coffeeTextPrimary)
                                Text("\(disciplines.count) matérias")
                                    .font(.system(size: 13))
                                    .foregroundStyle(Color.coffeeTextSecondary)
                            }

                            Spacer()

                            if selectedDiscipline == nil {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundStyle(Color.coffeePrimary)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                    }
                    .buttonStyle(.plain)

                    Divider().padding(.leading, 76)

                    // Individual disciplines
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
        }
    }

    // MARK: - Repositories Content

    private var repositoriesContent: some View {
        VStack(spacing: 0) {
            if isLoadingRepos {
                ProgressView()
                    .tint(Color.coffeePrimary)
                    .padding(.top, 40)
            } else if repositories.isEmpty {
                CoffeeEmptyState(
                    icon: "folder",
                    title: "Nenhum repositório",
                    message: "Crie repositórios na aba de matérias para organizar conteúdos extras."
                )
                .frame(maxWidth: .infinity)
                .padding(.top, 40)
            } else {
                CoffeeCellGroup {
                    ForEach(Array(repositories.enumerated()), id: \.element.id) { index, repo in
                        Button {
                            // Select repo as a "discipline" for the chat context
                            selectedDiscipline = AIChatPickerDiscipline(
                                id: repo.id,
                                name: repo.nome,
                                icon: repo.icone,
                                iconColor: "715038",
                                recordingsCount: repo.gravacoesCount
                            )
                            selectedRecording = nil
                            onDismiss()
                        } label: {
                            HStack(spacing: 14) {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .fill(Color.coffeePrimary.opacity(0.1))
                                        .frame(width: 52, height: 52)
                                    Image(systemName: repo.icone)
                                        .font(.system(size: 20))
                                        .foregroundStyle(Color.coffeePrimary)
                                }

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(repo.nome)
                                        .font(.system(size: 16, weight: .semibold))
                                        .foregroundStyle(Color.coffeeTextPrimary)
                                    Text("\(repo.gravacoesCount) gravações")
                                        .font(.system(size: 13))
                                        .foregroundStyle(Color.coffeeTextSecondary)
                                }

                                Spacer()

                                if selectedDiscipline?.id == repo.id {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 16, weight: .semibold))
                                        .foregroundStyle(Color.coffeePrimary)
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                        }
                        .buttonStyle(.plain)

                        if index < repositories.count - 1 {
                            Divider().padding(.leading, 76)
                        }
                    }
                }
                .padding(.horizontal, 16)
            }
        }
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
        .padding(.bottom, 12)
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

    private func loadRepositories() {
        isLoadingRepos = true
        Task {
            do {
                repositories = try await DisciplineService.getRepositories()
            } catch {
                print("[AIChat] Error loading repositories: \(error)")
            }
            isLoadingRepos = false
        }
    }
}

// MARK: - Discipline Row

struct AIChatDisciplineRow: View {
    let disc: AIChatPickerDiscipline
    let isSelected: Bool

    private var displayColor: Color { Color(hex: disc.iconColor) }

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(displayColor.opacity(0.1))
                    .frame(width: 52, height: 52)
                Image(systemName: disc.icon)
                    .font(.system(size: 20))
                    .foregroundStyle(displayColor)
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
