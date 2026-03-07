import SwiftUI

struct ChatView: View {
    let initialDisciplinaId: UUID?
    let initialDisciplinaNome: String

    @StateObject private var viewModel: ChatViewModel
    @State private var inputText = ""
    @State private var showSettings = false
    @State private var showContextPicker = false
    @State private var disciplinas: [Disciplina] = []
    @State private var selectedDisciplinaId: UUID?
    @State private var selectedDisciplinaNome: String
    @FocusState private var inputFocused: Bool

    init(disciplinaId: UUID? = nil, disciplinaNome: String = "Todas as disciplinas") {
        self.initialDisciplinaId = disciplinaId
        self.initialDisciplinaNome = disciplinaNome
        let vm = ChatViewModel()
        vm.disciplinaId = disciplinaId
        vm.modo = disciplinaId != nil ? "disciplina" : "interdisciplinar"
        _viewModel = StateObject(wrappedValue: vm)
        _selectedDisciplinaId = State(initialValue: disciplinaId)
        _selectedDisciplinaNome = State(initialValue: disciplinaId != nil ? disciplinaNome : "Todas as disciplinas")
    }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            Divider().background(CoffeeTheme.Colors.vanilla)
            messagesArea
            Divider().background(CoffeeTheme.Colors.vanilla)
            inputBar
        }
        .background(CoffeeTheme.Colors.background)
        .sheet(isPresented: $showSettings) {
            AISettingsView(personality: $viewModel.personality)
        }
        .sheet(isPresented: $showContextPicker) {
            contextPickerSheet
        }
        .task {
            await loadDisciplinas()
        }
    }

    // MARK: - Top bar

    private var topBar: some View {
        HStack {
            Button {
                showContextPicker = true
            } label: {
                HStack(spacing: 6) {
                    Text(selectedDisciplinaNome)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(CoffeeTheme.Colors.espresso)
                        .lineLimit(1)

                    Image(systemName: "chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(CoffeeTheme.Colors.almond)
                }
                .padding(.horizontal, CoffeeTheme.Spacing.sm)
                .padding(.vertical, 6)
                .background(CoffeeTheme.Colors.vanilla)
                .clipShape(RoundedRectangle(cornerRadius: CoffeeTheme.Radius.sm))
            }
            .buttonStyle(.plain)

            Spacer()

            Button {
                showSettings = true
            } label: {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 18))
                    .foregroundColor(CoffeeTheme.Colors.espresso)
            }
        }
        .padding(.horizontal, CoffeeTheme.Spacing.lg)
        .padding(.vertical, CoffeeTheme.Spacing.sm)
        .background(CoffeeTheme.Colors.background)
    }

    // MARK: - Context picker sheet

    private var contextPickerSheet: some View {
        NavigationStack {
            List {
                // "Todas" option (interdisciplinar)
                Button {
                    selectContext(id: nil, nome: "Todas as disciplinas")
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Todas as disciplinas")
                                .font(.system(size: 15, weight: .medium))
                                .foregroundColor(CoffeeTheme.Colors.espresso)
                            Text("contexto interdisciplinar")
                                .font(.system(size: 12))
                                .foregroundColor(CoffeeTheme.Colors.almond)
                        }
                        Spacer()
                        if selectedDisciplinaId == nil {
                            Image(systemName: "checkmark")
                                .foregroundColor(CoffeeTheme.Colors.coffee)
                                .font(.system(size: 14, weight: .semibold))
                        }
                    }
                }
                .listRowBackground(CoffeeTheme.Colors.background)

                // Individual disciplines
                Section("Disciplinas") {
                    ForEach(disciplinas) { disc in
                        Button {
                            selectContext(id: disc.id, nome: disc.nome)
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(disc.nome)
                                        .font(.system(size: 15, weight: .medium))
                                        .foregroundColor(CoffeeTheme.Colors.espresso)
                                        .lineLimit(1)
                                    Text(disc.professor)
                                        .font(.system(size: 12))
                                        .foregroundColor(CoffeeTheme.Colors.almond)
                                        .lineLimit(1)
                                }
                                Spacer()
                                if selectedDisciplinaId == disc.id {
                                    Image(systemName: "checkmark")
                                        .foregroundColor(CoffeeTheme.Colors.coffee)
                                        .font(.system(size: 14, weight: .semibold))
                                }
                            }
                        }
                        .listRowBackground(CoffeeTheme.Colors.background)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(CoffeeTheme.Colors.background)
            .navigationTitle("Contexto da IA")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("OK") { showContextPicker = false }
                        .foregroundColor(CoffeeTheme.Colors.coffee)
                }
            }
        }
        .presentationDetents([.medium])
    }

    // MARK: - Messages area

    private var messagesArea: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: CoffeeTheme.Spacing.sm) {
                    ForEach(viewModel.messages) { msg in
                        MessageBubble(message: msg)
                            .id(msg.id)
                    }

                    if viewModel.isStreaming {
                        StreamingBubble(text: viewModel.currentStreamText)
                            .id("streaming")
                    }
                }
                .padding(.horizontal, CoffeeTheme.Spacing.md)
                .padding(.vertical, CoffeeTheme.Spacing.md)
            }
            .onChange(of: viewModel.messages.count) { _, _ in
                withAnimation { proxy.scrollTo(viewModel.messages.last?.id) }
            }
            .onChange(of: viewModel.currentStreamText) { _, _ in
                proxy.scrollTo("streaming", anchor: .bottom)
            }
        }
    }

    // MARK: - Input bar

    private var inputBar: some View {
        HStack(spacing: CoffeeTheme.Spacing.sm) {
            TextField("pergunte sobre a aula...", text: $inputText, axis: .vertical)
                .font(.system(size: 15))
                .foregroundColor(CoffeeTheme.Colors.espresso)
                .lineLimit(1...4)
                .padding(.horizontal, CoffeeTheme.Spacing.md)
                .padding(.vertical, 10)
                .background(CoffeeTheme.Colors.vanilla)
                .clipShape(RoundedRectangle(cornerRadius: 20))
                .focused($inputFocused)
                .onSubmit { send() }

            Button(action: send) {
                Image(systemName: "arrow.up")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: 36, height: 36)
                    .background(canSend ? CoffeeTheme.Colors.coffee : CoffeeTheme.Colors.vanilla)
                    .clipShape(Circle())
            }
            .disabled(!canSend)
        }
        .padding(.horizontal, CoffeeTheme.Spacing.md)
        .padding(.vertical, CoffeeTheme.Spacing.sm)
        .background(CoffeeTheme.Colors.background)
    }

    private var canSend: Bool {
        !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !viewModel.isStreaming
    }

    // MARK: - Actions

    private func send() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !viewModel.isStreaming else { return }
        inputText = ""
        Task { await viewModel.sendMessage(text) }
    }

    private func selectContext(id: UUID?, nome: String) {
        selectedDisciplinaId = id
        selectedDisciplinaNome = nome
        viewModel.disciplinaId = id
        viewModel.modo = id != nil ? "disciplina" : "interdisciplinar"
        showContextPicker = false
    }

    private func loadDisciplinas() async {
        do {
            disciplinas = try await DisciplinasService.shared.fetchDisciplinas()
        } catch {
            // Non-critical — picker just won't show disciplines
        }
    }
}

// MARK: - MessageBubble

private struct MessageBubble: View {
    let message: ChatMessage

    var isUser: Bool { message.role == "user" }

    var body: some View {
        VStack(alignment: isUser ? .trailing : .leading, spacing: CoffeeTheme.Spacing.xs) {
            HStack {
                if isUser { Spacer(minLength: 60) }

                Text(message.conteudo)
                    .font(.system(size: 15))
                    .foregroundColor(isUser ? .white : CoffeeTheme.Colors.espresso)
                    .padding(.horizontal, CoffeeTheme.Spacing.md)
                    .padding(.vertical, CoffeeTheme.Spacing.sm)
                    .background(isUser ? CoffeeTheme.Colors.coffee : CoffeeTheme.Colors.cardBackground)
                    .clipShape(
                        UnevenRoundedRectangle(
                            topLeadingRadius: 16,
                            bottomLeadingRadius: isUser ? 16 : 4,
                            bottomTrailingRadius: isUser ? 4 : 16,
                            topTrailingRadius: 16
                        )
                    )

                if !isUser { Spacer(minLength: 60) }
            }

            if !isUser && !message.fontes.isEmpty {
                fontePills(message.fontes)
                    .padding(.leading, 4)
            }
        }
        .frame(maxWidth: .infinity, alignment: isUser ? .trailing : .leading)
    }

    private func fontePills(_ fontes: [FonteCitacao]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: CoffeeTheme.Spacing.xs) {
                ForEach(fontes) { fonte in
                    Text("\(fonte.disciplinaNome)")
                        .font(.system(size: 11))
                        .foregroundColor(CoffeeTheme.Colors.almond)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(CoffeeTheme.Colors.vanilla)
                        .clipShape(RoundedRectangle(cornerRadius: CoffeeTheme.Radius.sm))
                }
            }
        }
    }
}

// MARK: - StreamingBubble

private struct StreamingBubble: View {
    let text: String

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: CoffeeTheme.Spacing.xs) {
                if !text.isEmpty {
                    Text(text)
                        .font(.system(size: 15))
                        .foregroundColor(CoffeeTheme.Colors.espresso)
                }
                TypingDots()
            }
            .padding(.horizontal, CoffeeTheme.Spacing.md)
            .padding(.vertical, CoffeeTheme.Spacing.sm)
            .background(CoffeeTheme.Colors.cardBackground)
            .clipShape(
                UnevenRoundedRectangle(
                    topLeadingRadius: 16,
                    bottomLeadingRadius: 4,
                    bottomTrailingRadius: 16,
                    topTrailingRadius: 16
                )
            )

            Spacer(minLength: 60)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - TypingDots

private struct TypingDots: View {
    @State private var phase = 0

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .fill(CoffeeTheme.Colors.almond)
                    .frame(width: 6, height: 6)
                    .opacity(phase == i ? 1.0 : 0.3)
            }
        }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 400_000_000)
                withAnimation(.easeInOut(duration: 0.2)) {
                    phase = (phase + 1) % 3
                }
            }
        }
    }
}
