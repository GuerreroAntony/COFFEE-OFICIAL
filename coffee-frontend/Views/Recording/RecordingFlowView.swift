import SwiftUI
import Speech

// MARK: - Recording State

enum RecordingState: Equatable {
    case idle, recording, paused, stopped
}

// MARK: - Recording Flow Container

struct RecordingFlowView: View {
    @Environment(\.router) private var router

    @State private var state: RecordingState = .idle
    @State private var seconds = 0
    @State private var transcription = ""
    @State private var showStopSheet = false
    @State private var processing = false
    @State private var timer: Timer? = nil
    @State private var showFullTranscription = false
    @State private var selectedDiscipline: Discipline? = nil
    @State private var selectedRepoIds: Set<String> = []
    @State private var whisperKit = WhisperKitManager()
    @State private var isSaving = false
    @State private var saveError: String? = nil
    @State private var permissionDenied = false
    @State private var showCamera = false
    @State private var capturedPhotos: [(data: Data, timestamp: Int)] = []

    var body: some View {
        Group {
            switch state {
            case .idle:
                RecordingIdleView(onStart: startRecording)
            case .recording, .paused:
                RecordingActiveView(
                    isRecording: state == .recording,
                    seconds: seconds,
                    transcription: transcription,
                    photosCount: capturedPhotos.count,
                    showStopSheet: $showStopSheet,
                    showFullTranscription: $showFullTranscription,
                    onPause: {
                        withAnimation { state = .paused }
                        whisperKit.stopRealtimeTranscription()
                    },
                    onResume: {
                        withAnimation {
                            state = .recording
                            startTimer()
                        }
                        // Restart transcription on resume
                        do {
                            try whisperKit.startRealtimeTranscription { text in
                                Task { @MainActor in
                                    transcription = text
                                }
                            }
                        } catch {
                            print("[Recording] Resume transcription error: \(error)")
                        }
                    },
                    onFinish: finishRecording,
                    onCameraCapture: { showCamera = true },
                    formatTime: formatTime
                )
            case .stopped:
                RecordingStoppedView(
                    seconds: seconds,
                    processing: processing,
                    isSaving: isSaving,
                    selectedDiscipline: $selectedDiscipline,
                    selectedRepoIds: $selectedRepoIds,
                    onDiscard: resetToIdle,
                    onSave: saveRecording,
                    formatTime: formatTime
                )
            }
        }
        .onChange(of: state) { _, newValue in
            let active = (newValue == .recording || newValue == .paused || newValue == .stopped)
            router.isRecordingActive = active
        }
        .alert("Permissao Necessaria", isPresented: $permissionDenied) {
            Button("Abrir Configuracoes") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            Button("Cancelar", role: .cancel) { }
        } message: {
            Text("O COFFEE precisa de acesso ao microfone para gravar aulas. Habilite nas Configuracoes.")
        }
        .alert("Erro ao Salvar", isPresented: Binding(
            get: { saveError != nil },
            set: { if !$0 { saveError = nil } }
        )) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(saveError ?? "")
        }
        .fullScreenCover(isPresented: $showCamera) {
            CameraPickerView(isPresented: $showCamera) { imageData in
                capturedPhotos.append((data: imageData, timestamp: seconds))
            }
            .ignoresSafeArea()
        }
    }

    private func formatTime(_ s: Int) -> String {
        String(format: "%02d:%02d:%02d", s / 3600, (s % 3600) / 60, s % 60)
    }

    private func startRecording() {
        Task {
            // Request microphone permission
            let granted = await AudioRecorder.requestPermission()
            guard granted else {
                permissionDenied = true
                return
            }

            // Load speech recognition model / request permission
            await whisperKit.loadModel()

            state = .recording
            seconds = 0
            transcription = ""
            capturedPhotos = []
            startTimer()

            // Start real-time transcription
            do {
                try whisperKit.startRealtimeTranscription { text in
                    Task { @MainActor in
                        transcription = text
                    }
                }
            } catch {
                print("[Recording] Transcription error: \(error)")
                // Continue recording even if transcription fails —
                // user can still save the recording with empty transcription
            }
        }
    }

    private func startTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            if state == .recording { seconds += 1 }
        }
    }

    private func finishRecording() {
        timer?.invalidate()
        timer = nil

        // Stop transcription and get final text
        let finalText = whisperKit.stopRealtimeTranscription()
        if !finalText.isEmpty {
            transcription = finalText
        }

        state = .stopped
        processing = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { processing = false }
    }

    private func resetToIdle() {
        timer?.invalidate()
        timer = nil
        whisperKit.reset()
        state = .idle
        seconds = 0
        transcription = ""
        selectedDiscipline = nil
        selectedRepoIds = []
        capturedPhotos = []
        isSaving = false
        saveError = nil
        router.isRecordingActive = false
    }

    private func saveRecording() {
        guard let discipline = selectedDiscipline else { return }
        guard !isSaving else { return }
        isSaving = true

        Task {
            do {
                let recording = try await RecordingService.createRecording(
                    sourceType: "disciplina",
                    sourceId: discipline.id,
                    transcription: transcription,
                    durationSeconds: seconds,
                    date: ISO8601DateFormatter().string(from: Date())
                )

                // Upload captured photos
                if !capturedPhotos.isEmpty {
                    for photo in capturedPhotos {
                        try? await RecordingService.uploadMedia(
                            recordingId: recording.id,
                            imageData: photo.data,
                            label: "Foto da aula",
                            timestampSeconds: photo.timestamp
                        )
                    }
                }

                resetToIdle()
            } catch {
                saveError = "Erro ao salvar: \(error.localizedDescription)"
                isSaving = false
            }
        }
    }
}

// MARK: - Idle View

struct RecordingIdleView: View {
    let onStart: () -> Void
    @Environment(\.router) private var router
    @State private var recentRecordings: [Recording] = []
    @State private var disciplines: [Discipline] = []
    @State private var recordingToDelete: Recording? = nil

    var body: some View {
        VStack(spacing: 0) {
            Text("Gravar Aula")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Color.coffeeTextPrimary)
                .padding(.top, 16)
                .padding(.bottom, 8)

            GeometryReader { geo in
                ScrollView {
                    VStack(spacing: 0) {
                        if recentRecordings.isEmpty {
                            Spacer(minLength: 0)
                        }

                        micButton

                        Text("Toque para começar a gravar")
                            .font(.system(size: 14))
                            .foregroundStyle(Color.coffeeTextSecondary)

                        if recentRecordings.isEmpty {
                            Spacer(minLength: 0)
                        } else {
                            recentList
                        }
                    }
                    .frame(maxWidth: .infinity, minHeight: geo.size.height)
                    .padding(.bottom, recentRecordings.isEmpty ? 0 : 120)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            LinearGradient(
                colors: [Color.coffeePrimary.opacity(0.07), Color.coffeeBackground, Color.coffeeBackground],
                startPoint: .top,
                endPoint: .init(x: 0.5, y: 0.18)
            )
        )
        .task { await loadRecentData() }
        .confirmationDialog(
            "Apagar gravação?",
            isPresented: Binding(
                get: { recordingToDelete != nil },
                set: { if !$0 { recordingToDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Apagar", role: .destructive) {
                if let rec = recordingToDelete {
                    let recId = rec.id
                    withAnimation { recentRecordings.removeAll { $0.id == recId } }
                    recordingToDelete = nil
                    Task {
                        do {
                            try await RecordingService.deleteRecording(id: recId)
                        } catch {
                            print("[RecordingIdle] Error deleting recording: \(error)")
                            await loadRecentData()
                        }
                    }
                }
            }
            Button("Cancelar", role: .cancel) { recordingToDelete = nil }
        } message: {
            Text("Esta ação não pode ser desfeita.")
        }
    }

    private var micButton: some View {
        ZStack {
            RippleEffect()
                .frame(width: 220, height: 220)

            Button(action: onStart) {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [Color(hex: "8B6340"), Color.coffeePrimary],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 100, height: 100)
                        .shadow(color: Color.coffeePrimary.opacity(0.52), radius: 20, y: 14)
                    Image(systemName: CoffeeIcon.mic)
                        .font(.system(size: 40))
                        .foregroundStyle(.white)
                }
            }
            .buttonStyle(.plain)
        }
        .frame(height: 300)
    }

    @ViewBuilder
    private var recentList: some View {
        if !recentRecordings.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Divider().padding(.top, 16)
                Text("Recentes")
                    .font(.system(size: 11, weight: .semibold))
                    .textCase(.uppercase)
                    .tracking(1)
                    .foregroundStyle(Color.coffeeTextSecondary.opacity(0.6))
                    .padding(.horizontal, 20)
                    .padding(.top, 8)

                CoffeeCellGroup {
                    ForEach(Array(recentRecordings.enumerated()), id: \.element.id) { index, rec in
                        SwipeableRow(
                            onTap: {
                                if let disc = disciplines.first(where: { $0.id == rec.sourceId }) {
                                    router.selectCourse(disc)
                                }
                            },
                            onDelete: { recordingToDelete = rec }
                        ) {
                            recentRowContent(rec)
                        }

                        if index < recentRecordings.count - 1 {
                            Divider().padding(.leading, 74)
                        }
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }

    private func recentRowContent(_ rec: Recording) -> some View {
        let discName = disciplines.first(where: { $0.id == rec.sourceId })?.nome ?? ""
        let dateShort = rec.dateLabel.components(separatedBy: ", ").first ?? ""

        return HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.coffeePrimary.opacity(0.09))
                    .frame(width: 44, height: 44)
                Image(systemName: "waveform")
                    .font(.system(size: 18))
                    .foregroundStyle(Color.coffeePrimary)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(rec.shortSummary ?? rec.dateLabel)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.coffeeTextPrimary)
                    .lineLimit(1)
                Text(discName)
                    .font(.system(size: 13))
                    .foregroundStyle(Color.coffeeTextSecondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 3) {
                Text(rec.durationLabel)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.coffeeTextPrimary)
                Text(dateShort)
                    .font(.system(size: 12))
                    .foregroundStyle(Color.coffeeTextSecondary.opacity(0.5))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .contentShape(Rectangle())
    }

    // MARK: - Load Recent Data

    private func loadRecentData() async {
        do {
            let discs = try await DisciplineService.getDisciplines()
            disciplines = discs

            // Load recent recordings from each discipline (limited to keep it fast)
            var allRecordings: [Recording] = []
            for disc in discs.prefix(5) {
                if let recs = try? await RecordingService.getRecordings(sourceType: "disciplina", sourceId: disc.id) {
                    allRecordings.append(contentsOf: recs)
                }
            }
            // Sort by date descending and take the 6 most recent
            recentRecordings = Array(
                allRecordings.sorted { ($0.createdAt ?? .distantPast) > ($1.createdAt ?? .distantPast) }.prefix(6)
            )
        } catch {
            print("[RecordingIdle] Error loading recent data: \(error)")
        }
    }
}

// MARK: - Active View (Recording / Paused)

struct RecordingActiveView: View {
    let isRecording: Bool
    let seconds: Int
    let transcription: String
    let photosCount: Int
    @Binding var showStopSheet: Bool
    @Binding var showFullTranscription: Bool
    let onPause: () -> Void
    let onResume: () -> Void
    let onFinish: () -> Void
    let onCameraCapture: () -> Void
    let formatTime: (Int) -> String

    var body: some View {
        VStack(spacing: 0) {
            statusHeader
            waveform
            Spacer()
            controls
            transcriptionPreview
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.coffeeRecordingBackground.ignoresSafeArea())
        .confirmationDialog("O que deseja fazer?", isPresented: $showStopSheet) {
            Button("Finalizar gravação", role: .destructive) { onFinish() }
            Button("Cancelar", role: .cancel) { }
        } message: {
            Text("Duração: \(formatTime(seconds))")
        }
        .fullScreenCover(isPresented: $showFullTranscription) {
            RecordingFullTranscriptionView(
                seconds: seconds,
                transcription: transcription,
                showFullTranscription: $showFullTranscription,
                formatTime: formatTime
            )
        }
    }

    private var statusHeader: some View {
        let dotColor: Color = isRecording ? .red : .yellow
        let labelText = isRecording ? "Gravando" : "Pausado"
        let labelColor: Color = isRecording ? Color.red.opacity(0.8) : Color.yellow.opacity(0.8)

        return VStack(spacing: 12) {
            HStack(spacing: 8) {
                Circle().fill(dotColor).frame(width: 10, height: 10)
                Text(labelText)
                    .font(.system(size: 11, weight: .semibold))
                    .textCase(.uppercase)
                    .tracking(2)
                    .foregroundStyle(labelColor)
            }
            Text(formatTime(seconds))
                .font(.coffeeTimer)
                .foregroundStyle(.white)
        }
        .padding(.top, 70)
    }

    private var waveform: some View {
        WaveformView(barCount: 40, color: Color.coffeePrimaryLight)
            .opacity(isRecording ? 1.0 : 0.3)
            .frame(height: 90)
            .padding(.horizontal, 16)
            .padding(.vertical, 20)
    }

    private var controls: some View {
        HStack(spacing: 40) {
            if isRecording {
                Button(action: onPause) {
                    controlCircle(icon: "pause.fill", color: Color.coffeePrimaryLight)
                }
            } else {
                Button(action: onResume) {
                    controlCircle(icon: "play.fill", color: Color.green)
                }
            }

            Button { showStopSheet = true } label: {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [Color(hex: "8B6340"), Color.coffeePrimary],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 76, height: 76)
                        .shadow(color: Color.coffeePrimary.opacity(0.55), radius: 14, y: 8)
                    Image(systemName: "stop.fill")
                        .font(.system(size: 30))
                        .foregroundStyle(.white)
                }
            }
            .buttonStyle(.plain)

            Button(action: onCameraCapture) {
                ZStack(alignment: .topTrailing) {
                    controlCircle(icon: "camera.fill", color: Color.coffeePrimaryLight)

                    if photosCount > 0 {
                        Text("\(photosCount)")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 20, height: 20)
                            .background(Color.coffeePrimary)
                            .clipShape(Circle())
                            .offset(x: 4, y: -4)
                    }
                }
            }
        }
        .padding(.bottom, 24)
    }

    private func controlCircle(icon: String, color: Color) -> some View {
        ZStack {
            Circle()
                .fill(color.opacity(0.12))
                .frame(width: 56, height: 56)
                .overlay(Circle().stroke(color.opacity(0.25), lineWidth: 0.5))
            Image(systemName: icon)
                .font(.system(size: 22))
                .foregroundStyle(color)
        }
    }

    private var transcriptionPreview: some View {
        let displayText = transcription.isEmpty ? "Aguardando fala..." : transcription
        let textOpacity: Double = transcription.isEmpty ? 0.35 : 0.75

        return Button { showFullTranscription = true } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Transcrição")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                    Spacer()
                    if isRecording {
                        HStack(spacing: 4) {
                            Circle().fill(Color.green).frame(width: 6, height: 6)
                            Text("Transcrevendo")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(Color.green.opacity(0.85))
                        }
                    }
                }
                Text(displayText)
                    .font(.system(size: 13))
                    .foregroundStyle(Color.coffeePrimaryLight.opacity(textOpacity))
                    .lineLimit(3)
                    .lineSpacing(4)
            }
            .padding(16)
            .background(Color.coffeePrimary.opacity(0.28))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.coffeePrimaryLight.opacity(0.15), lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 24)
        .padding(.bottom, 32)
    }
}

// MARK: - Full Transcription View

struct RecordingFullTranscriptionView: View {
    let seconds: Int
    let transcription: String
    @Binding var showFullTranscription: Bool
    let formatTime: (Int) -> String

    var body: some View {
        let displayText = transcription.isEmpty ? "Aguardando fala..." : transcription
        let textOpacity: Double = transcription.isEmpty ? 0.4 : 0.9
        let wordCount = transcription.split(separator: " ").count

        VStack(spacing: 0) {
            HStack {
                Button { showFullTranscription = false } label: {
                    HStack(spacing: 2) {
                        Image(systemName: "chevron.left").font(.system(size: 20))
                        Text("Voltar").font(.system(size: 17))
                    }
                    .foregroundStyle(Color.coffeePrimaryLight)
                }
                Spacer()
                HStack(spacing: 6) {
                    Circle().fill(Color.red).frame(width: 8, height: 8)
                    Text(formatTime(seconds))
                        .font(.system(size: 13, weight: .semibold).monospacedDigit())
                        .foregroundStyle(Color.red.opacity(0.8))
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 60)
            .padding(.bottom, 12)

            ScrollView {
                Text(displayText)
                    .font(.system(size: 15))
                    .foregroundStyle(Color.coffeePrimaryLight.opacity(textOpacity))
                    .lineSpacing(7)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 16)
            }

            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "text.alignleft")
                        .foregroundStyle(Color.coffeePrimaryLight.opacity(0.5))
                    Text("\(wordCount) palavras")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.coffeePrimaryLight.opacity(0.5))
                }
                Spacer()
                Button("Minimizar") { showFullTranscription = false }
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color.coffeePrimary)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
        }
        .background(Color.coffeeRecordingBackground.ignoresSafeArea())
    }
}

// MARK: - Stopped View

struct RecordingStoppedView: View {
    let seconds: Int
    let processing: Bool
    let isSaving: Bool
    @Binding var selectedDiscipline: Discipline?
    @Binding var selectedRepoIds: Set<String>
    let onDiscard: () -> Void
    let onSave: () -> Void
    let formatTime: (Int) -> String

    @State private var localDisciplines: [Discipline] = []
    @State private var localRepositories: [Repository] = []
    @State private var creatingRepo = false
    @State private var newRepoName = ""

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 0) {
                    successHeader
                    Divider()
                    saveSection
                }
                .padding(.bottom, 20)
            }
            bottomActions
        }
        .background(Color.coffeeBackground)
        .task {
            async let d = try? DisciplineService.getDisciplines()
            async let r = try? DisciplineService.getRepositories()
            localDisciplines = await d ?? []
            localRepositories = await r ?? []
        }
    }

    private var successHeader: some View {
        let summaryIcon = processing ? "hourglass" : "checkmark"
        let aiIcon = processing ? "hourglass" : CoffeeIcon.sparkles

        return VStack(spacing: 12) {
            ZStack {
                Circle().fill(Color.green.opacity(0.1)).frame(width: 76, height: 76)
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(Color.green)
            }
            Text("Aula processada!")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(Color.coffeeTextPrimary)
            Text("\(formatTime(seconds)) de aula gravados")
                .font(.system(size: 15))
                .foregroundStyle(Color.coffeeTextSecondary)
            HStack(spacing: 8) {
                statusPill(icon: summaryIcon, label: "Resumo", active: !processing)
                statusPill(icon: aiIcon, label: "Notas com IA", active: !processing)
            }
        }
        .padding(.top, 72)
        .padding(.bottom, 32)
        .frame(maxWidth: .infinity)
        .background(Color.coffeeCardBackground)
    }

    private var saveSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            CoffeeSectionHeader(title: "Salvar em")
            disciplineList
            repoHeader
            repoList
        }
        .padding(.horizontal, 16)
        .padding(.top, 24)
    }

    private var disciplineList: some View {
        CoffeeCellGroup {
            ForEach(Array(localDisciplines.enumerated()), id: \.element.id) { index, disc in
                StoppedDisciplineRow(
                    disc: disc,
                    isSelected: selectedDiscipline?.id == disc.id,
                    onTap: {
                        selectedDiscipline = selectedDiscipline?.id == disc.id ? nil : disc
                    }
                )
                if index < localDisciplines.count - 1 {
                    Divider().padding(.leading, 76)
                }
            }
        }
    }

    private var repoHeader: some View {
        HStack {
            CoffeeSectionHeader(title: "Repositórios")
            Spacer()
            Text("Opcional · múltipla seleção")
                .font(.system(size: 11))
                .foregroundStyle(Color.coffeeTextSecondary)
        }
    }

    private var repoList: some View {
        VStack(spacing: 12) {
            CoffeeCellGroup {
                ForEach(Array(localRepositories.enumerated()), id: \.element.id) { index, repo in
                    let isSelected = selectedRepoIds.contains(repo.id)
                    StoppedRepoRow(
                        repo: repo,
                        isSelected: isSelected,
                        onTap: {
                            if isSelected { selectedRepoIds.remove(repo.id) }
                            else { selectedRepoIds.insert(repo.id) }
                        }
                    )
                    if index < localRepositories.count - 1 {
                        Divider().padding(.leading, 76)
                    }
                }
            }

            if creatingRepo {
                // Inline create form
                HStack(spacing: 10) {
                    TextField("Nome do repositório", text: $newRepoName)
                        .font(.system(size: 15))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(Color.coffeeInputBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                    Button("Criar") {
                        handleCreateRepo()
                    }
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.coffeePrimary)
                    .disabled(newRepoName.trimmingCharacters(in: .whitespaces).isEmpty)

                    Button("Cancelar") {
                        creatingRepo = false
                        newRepoName = ""
                    }
                    .font(.system(size: 15))
                    .foregroundStyle(Color.coffeeTextSecondary)
                }
            } else {
                Button {
                    creatingRepo = true
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 16))
                        Text("Novo repositório")
                            .font(.system(size: 15, weight: .medium))
                    }
                    .foregroundStyle(Color.coffeePrimary)
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
                localRepositories.append(repo)
                selectedRepoIds.insert(repo.id)
            } catch {
                print("[RecordingStopped] Error creating repo: \(error)")
            }
        }
    }

    private var bottomActions: some View {
        let saveDisabled = (selectedDiscipline == nil && selectedRepoIds.isEmpty) || isSaving
        return VStack(spacing: 0) {
            Divider()
            HStack(spacing: 12) {
                Button(action: onDiscard) {
                    Text("Descartar")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Color.coffeePrimary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(Color.coffeeCardBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(Color.coffeePrimary, lineWidth: 1.5)
                        )
                }
                .disabled(isSaving)
                CoffeeButton(isSaving ? "Salvando..." : "Salvar Gravação", isDisabled: saveDisabled, action: onSave)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
        }
        .background(
            Color.coffeeBackground.opacity(0.95)
                .background(.ultraThinMaterial)
                .ignoresSafeArea(edges: .bottom)
        )
    }

    private func statusPill(icon: String, label: String, active: Bool) -> some View {
        let fg: Color = active ? .green : Color.coffeeTextSecondary
        let bg: Color = active ? Color.green.opacity(0.09) : Color.coffeeTextSecondary.opacity(0.06)
        return HStack(spacing: 6) {
            Image(systemName: icon).font(.system(size: 11))
            Text(label).font(.system(size: 12, weight: .medium))
        }
        .foregroundStyle(fg)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(bg)
        .clipShape(Capsule())
    }
}

// MARK: - Row Sub-Views

struct StoppedDisciplineRow: View {
    let disc: Discipline
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        let bg: Color = isSelected ? Color.coffeePrimary : Color.coffeeTextSecondary.opacity(0.12)
        let fg: Color = isSelected ? .white : Color.coffeeTextSecondary

        Button(action: onTap) {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(bg).frame(width: 50, height: 50)
                    Image(systemName: CoffeeIcon.menuBook)
                        .font(.system(size: 20)).foregroundStyle(fg)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(disc.nome)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(Color.coffeeTextPrimary)
                    Text("\(disc.gravacoesCount) aulas")
                        .font(.system(size: 14))
                        .foregroundStyle(Color.coffeeTextSecondary)
                }
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(Color.coffeePrimary)
                } else {
                    Circle()
                        .stroke(Color.coffeeTextSecondary.opacity(0.3), lineWidth: 2)
                        .frame(width: 22, height: 22)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 16)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct StoppedRepoRow: View {
    let repo: Repository
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        let bg: Color = isSelected ? Color.coffeePrimary.opacity(0.1) : Color.coffeeTextSecondary.opacity(0.1)
        let fg: Color = isSelected ? Color.coffeePrimary : Color.coffeeTextSecondary
        let checkBg: Color = isSelected ? Color.coffeePrimary : Color.coffeeTextSecondary.opacity(0.12)

        Button(action: onTap) {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(bg).frame(width: 50, height: 50)
                    Image(systemName: repo.icone)
                        .font(.system(size: 20)).foregroundStyle(fg)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(repo.nome)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(Color.coffeeTextPrimary)
                    Text("\(repo.gravacoesCount) aulas")
                        .font(.system(size: 14))
                        .foregroundStyle(Color.coffeeTextSecondary)
                }
                Spacer()
                ZStack {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(checkBg).frame(width: 22, height: 22)
                    if isSelected {
                        Image(systemName: "checkmark")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.white)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 16)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    RecordingFlowView()
        .environment(\.router, NavigationRouter())
}
