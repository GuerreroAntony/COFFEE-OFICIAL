import SwiftUI
import UserNotifications
import ActivityKit

// MARK: - Recording State

enum RecordingState: Equatable {
    case idle, recording, paused, stopped, uploaded
}

// MARK: - Recording Flow Container

struct RecordingFlowView: View {
    @Environment(\.router) private var router

    @State private var state: RecordingState = .idle
    @State private var seconds = 0
    @State private var showStopSheet = false
    @State private var timer: Timer? = nil
    @State private var selectedDiscipline: Discipline? = nil
    @State private var selectedRepoIds: Set<String> = []
    @State private var audioRecorder = AudioRecorder()
    @State private var recordingStartTime: Date? = nil
    @State private var audioFileURL: URL? = nil
    @State private var uploadedRecordingId: String? = nil
    @State private var uploadedDisciplineName: String? = nil
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
                    photosCount: capturedPhotos.count,
                    audioLevel: audioRecorder.audioLevel,
                    showStopSheet: $showStopSheet,
                    onPause: {
                        withAnimation { state = .paused }
                        audioRecorder.pauseRecording()
                        LiveActivityService.update(elapsedSeconds: seconds, status: "paused")
                    },
                    onResume: {
                        withAnimation {
                            state = .recording
                            startTimer()
                        }
                        audioRecorder.resumeRecording()
                        LiveActivityService.update(elapsedSeconds: seconds, status: "recording")
                    },
                    onFinish: finishRecording,
                    onCameraCapture: { showCamera = true },
                    formatTime: formatTime
                )
            case .stopped:
                RecordingStoppedView(
                    seconds: seconds,
                    isSaving: isSaving,
                    selectedDiscipline: $selectedDiscipline,
                    selectedRepoIds: $selectedRepoIds,
                    onDiscard: resetToIdle,
                    onSave: saveRecording,
                    formatTime: formatTime
                )
            case .uploaded:
                RecordingUploadedView(
                    seconds: seconds,
                    disciplineName: uploadedDisciplineName ?? "",
                    recordingId: uploadedRecordingId ?? "",
                    onRecordAnother: resetToIdle,
                    onViewDiscipline: {
                        if let disc = selectedDiscipline {
                            resetToIdle()
                            router.selectCourse(disc)
                        } else {
                            resetToIdle()
                        }
                    },
                    formatTime: formatTime
                )
            }
        }
        .onChange(of: state) { _, newValue in
            let active = (newValue == .recording || newValue == .paused || newValue == .stopped || newValue == .uploaded)
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
        .onChange(of: showCamera) { _, isShowing in
            if !isShowing && state == .recording {
                // Camera dismissed — AudioRecorder handles interruption automatically
            }
        }
        // Sync UI state with AudioRecorder interruptions (phone calls, alarms)
        .onChange(of: audioRecorder.interruptionEvent) { _, _ in
            if case .paused = audioRecorder.state, state == .recording {
                withAnimation { state = .paused }
                timer?.invalidate()
                LiveActivityService.update(elapsedSeconds: seconds, status: "paused")
            } else if case .recording = audioRecorder.state, state == .paused {
                withAnimation { state = .recording }
                startTimer()
                LiveActivityService.update(elapsedSeconds: seconds, status: "recording")
            }
        }
    }

    private func formatTime(_ s: Int) -> String {
        String(format: "%02d:%02d:%02d", s / 3600, (s % 3600) / 60, s % 60)
    }

    private func startRecording() {
        Task {
            let granted = await AudioRecorder.requestPermission()
            guard granted else {
                permissionDenied = true
                return
            }

            state = .recording
            seconds = 0
            capturedPhotos = []
            recordingStartTime = Date()
            audioFileURL = nil
            startTimer()

            audioRecorder.startRecording()

            // Start Live Activity (discipline name TBD — updated on save)
            LiveActivityService.startRecording(disciplineName: "Gravando aula...")
        }
    }

    private func startTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            if state == .recording {
                seconds += 1
                // Update Live Activity timer every 5 seconds (avoid excessive updates)
                if seconds % 5 == 0 {
                    LiveActivityService.update(elapsedSeconds: seconds, status: "recording")
                }
            }
        }
    }

    private func finishRecording() {
        timer?.invalidate()
        timer = nil

        audioFileURL = audioRecorder.stopRecording()
        LiveActivityService.update(elapsedSeconds: seconds, status: "uploading")
        state = .stopped
    }

    private func resetToIdle() {
        timer?.invalidate()
        timer = nil
        audioRecorder.discardRecording()
        audioFileURL = nil
        recordingStartTime = nil
        LiveActivityService.end()
        state = .idle
        seconds = 0
        selectedDiscipline = nil
        selectedRepoIds = []
        capturedPhotos = []
        isSaving = false
        saveError = nil
        router.isRecordingActive = false
    }

    private func saveRecording() {
        guard selectedDiscipline != nil || !selectedRepoIds.isEmpty else { return }
        guard !isSaving else { return }
        guard let fileURL = audioFileURL else {
            saveError = "Arquivo de áudio não encontrado"
            return
        }
        isSaving = true

        // Determine destination
        let disciplinaId: String
        if let discipline = selectedDiscipline {
            disciplinaId = discipline.id
        } else if let repoId = selectedRepoIds.first {
            // TODO: repos will use cloud pipeline too in the future
            disciplinaId = repoId
        } else {
            isSaving = false
            return
        }

        Task {
            do {
                // Calculate quality score before upload
                let qualityScore = AudioQualityAnalyzer.calculateQualityScore(
                    audioURL: fileURL,
                    expectedDurationSeconds: 3000
                )

                let recording = try await RecordingService.uploadAudioRecording(
                    audioFileURL: fileURL,
                    disciplinaId: disciplinaId,
                    durationSeconds: max(seconds, 1),
                    startTime: recordingStartTime ?? Date(),
                    endTime: Date(),
                    qualityScore: qualityScore
                )

                // Delete local audio file after successful upload
                audioRecorder.deleteRecordingFile()

                // Upload captured photos
                for photo in capturedPhotos {
                    try? await RecordingService.uploadMedia(
                        recordingId: recording.id,
                        imageData: photo.data,
                        label: "Foto da aula",
                        timestampSeconds: photo.timestamp
                    )
                }

                // Show uploaded confirmation screen
                uploadedRecordingId = recording.id
                uploadedDisciplineName = selectedDiscipline?.nome
                isSaving = false
                withAnimation { state = .uploaded }
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
            // Sort by date descending and take the 3 most recent
            recentRecordings = Array(
                allRecordings.sorted { ($0.createdAt ?? .distantPast) > ($1.createdAt ?? .distantPast) }.prefix(3)
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
    let photosCount: Int
    var audioLevel: Float = 0
    @Binding var showStopSheet: Bool
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
            cloudTranscriptionBanner
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.coffeeRecordingBackground.ignoresSafeArea())
        .confirmationDialog("O que deseja fazer?", isPresented: $showStopSheet) {
            Button("Finalizar gravação", role: .destructive) { onFinish() }
            Button("Cancelar", role: .cancel) { }
        } message: {
            Text("Duração: \(formatTime(seconds))")
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
        WaveformView(barCount: 48, color: Color.coffeePrimaryLight, audioLevel: isRecording ? audioLevel : 0)
            .opacity(isRecording ? 1.0 : 0.4)
            .frame(height: 72)
            .padding(.horizontal, 20)
            .padding(.vertical, 24)
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

    private var cloudTranscriptionBanner: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "cloud.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(Color.coffeePrimaryLight.opacity(0.7))
                Text("Transcrição via IA")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                Spacer()
                if isRecording {
                    HStack(spacing: 4) {
                        Circle().fill(Color.green).frame(width: 6, height: 6)
                        Text("Captando")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Color.green.opacity(0.85))
                    }
                }
            }
            Text("A transcrição será gerada automaticamente após a gravação com alta precisão.")
                .font(.system(size: 13))
                .foregroundStyle(Color.coffeePrimaryLight.opacity(0.5))
                .lineSpacing(4)
        }
        .padding(16)
        .background(Color.coffeePrimary.opacity(0.28))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.coffeePrimaryLight.opacity(0.15), lineWidth: 0.5)
        )
        .padding(.horizontal, 24)
        .padding(.bottom, 32)
    }
}

// MARK: - Stopped View

struct RecordingStoppedView: View {
    let seconds: Int
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

    @State private var coffeePulse = false
    @State private var notifyEnabled = false

    private var successHeader: some View {
        VStack(spacing: 16) {
            // Loading spinner
            ProgressView()
                .controlSize(.large)
                .tint(Color.coffeePrimary)

            Text("Processando...")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(Color.coffeeTextPrimary)

            Text("\(formatTime(seconds)) gravados")
                .font(.system(size: 14))
                .foregroundStyle(Color.coffeeTextSecondary)

            // Notify button
            if !notifyEnabled {
                Button {
                    notifyEnabled = true
                    UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
                        if granted {
                            DispatchQueue.main.async {
                                UIApplication.shared.registerForRemoteNotifications()
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "bell.fill")
                            .font(.system(size: 13))
                        Text("Me notifique quando pronto")
                            .font(.system(size: 14, weight: .semibold))
                    }
                    .foregroundStyle(Color.coffeePrimary)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(Color.coffeePrimary.opacity(0.1))
                    .clipShape(Capsule())
                }
            } else {
                HStack(spacing: 6) {
                    Image(systemName: "bell.badge.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(Color.green)
                    Text("Você será notificado")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color.green)
                }
            }
        }
        .padding(.top, 56)
        .padding(.bottom, 24)
        .padding(.horizontal, 20)
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
                    index: index,
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

}

// MARK: - Row Sub-Views

struct StoppedDisciplineRow: View {
    let disc: Discipline
    let index: Int
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        let discColor = Color(hex: disc.displayColorHex(at: index))
        let bg: Color = isSelected ? discColor : discColor.opacity(0.1)
        let fg: Color = isSelected ? .white : discColor

        Button(action: onTap) {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(bg).frame(width: 50, height: 50)
                    Image(systemName: disc.displayIcon(at: index))
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

// MARK: - Uploaded Confirmation View

struct RecordingUploadedView: View {
    let seconds: Int
    let disciplineName: String
    let recordingId: String
    let onRecordAnother: () -> Void
    let onViewDiscipline: () -> Void
    let formatTime: (Int) -> String

    @State private var notifyEnabled = false
    @State private var cloudPulse = false
    @State private var processingStatus: RecordingStatus? = nil

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 24) {
                    uploadHeader
                    processingCard
                    notifyButton
                }
                .padding(.bottom, 40)
            }
            bottomActions
        }
        .background(Color.coffeeBackground)
        .task { await pollStatus() }
    }

    private var uploadHeader: some View {
        VStack(spacing: 16) {
            // Animated coffee cup
            ZStack {
                Circle()
                    .fill(Color.coffeePrimary.opacity(cloudPulse ? 0.15 : 0.08))
                    .frame(width: 100, height: 100)
                    .animation(.easeInOut(duration: 2).repeatForever(autoreverses: true), value: cloudPulse)
                Image(systemName: processingStatus == .ready ? "checkmark.circle.fill" : "cup.and.saucer.fill")
                        .font(.system(size: 44))
                        .foregroundStyle(processingStatus == .ready ? Color.green : Color.coffeePrimary)
                    .font(.system(size: 48))
            }
            .onAppear { cloudPulse = true }

            Text(processingStatus == .ready ? "Café pronto!" : "Processando...")
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(Color.coffeeTextPrimary)

            HStack(spacing: 6) {
                Text(formatTime(seconds))
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.coffeePrimary)
                Text("•")
                    .foregroundStyle(Color.coffeeTextSecondary)
                Text(disciplineName)
                    .font(.system(size: 15))
                    .foregroundStyle(Color.coffeeTextSecondary)
                    .lineLimit(1)
            }
        }
        .padding(.top, 80)
        .frame(maxWidth: .infinity)
    }

    private var processingCard: some View {
        VStack(spacing: 16) {
            HStack(spacing: 12) {
                if processingStatus == .ready {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 24))
                        .foregroundStyle(Color.green)
                } else {
                    Image(systemName: "cup.and.saucer.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(Color.coffeePrimary)
                        .font(.system(size: 24))
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(processingStatus == .ready ? "Café pronto!" : "Processando...")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Color.coffeeTextPrimary)
                    Text(processingStatus == .ready
                         ? "Resumo e mapa mental disponíveis"
                         : "Suas notas ficam prontas em ~3 min")
                        .font(.system(size: 13))
                        .foregroundStyle(Color.coffeeTextSecondary)
                }
                Spacer()
            }

            // Progress steps
            VStack(alignment: .leading, spacing: 10) {
                progressStep(icon: "arrow.up.circle.fill", label: "Áudio enviado", done: true)
                progressStep(icon: "waveform", label: "Transcrevendo a aula", done: processingStatus == .ready)
                progressStep(icon: "cup.and.saucer.fill", label: "Preparando resumo e notas", done: processingStatus == .ready)
            }
        }
        .padding(20)
        .background(Color.coffeeCardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.coffeePrimary.opacity(0.1), lineWidth: 1)
        )
        .padding(.horizontal, 20)
    }

    private func progressStep(icon: String, label: String, done: Bool) -> some View {
        HStack(spacing: 10) {
            Image(systemName: done ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 16))
                .foregroundStyle(done ? Color.green : Color.coffeeTextSecondary.opacity(0.3))
            Text(label)
                .font(.system(size: 14))
                .foregroundStyle(done ? Color.coffeeTextPrimary : Color.coffeeTextSecondary.opacity(0.6))
        }
    }

    private var notifyButton: some View {
        Group {
            if !notifyEnabled && processingStatus != .ready {
                Button {
                    notifyEnabled = true
                    requestNotificationPermission()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "bell.fill")
                            .font(.system(size: 14))
                        Text("Me notifique quando pronto")
                            .font(.system(size: 15, weight: .semibold))
                    }
                    .foregroundStyle(Color.coffeePrimary)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 14)
                    .background(Color.coffeePrimary.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
            } else if notifyEnabled && processingStatus != .ready {
                HStack(spacing: 8) {
                    Image(systemName: "bell.badge.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(Color.green)
                    Text("Você será notificado")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Color.green)
                }
                .padding(.vertical, 8)
            }
        }
    }

    private var bottomActions: some View {
        VStack(spacing: 0) {
            Divider()
            VStack(spacing: 12) {
                if processingStatus == .ready {
                    CoffeeButton("Ver na disciplina", action: onViewDiscipline)
                }

                Button(action: onRecordAnother) {
                    Text(processingStatus == .ready ? "Gravar outra aula" : "Gravar outra aula")
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

    // MARK: - Polling

    private func pollStatus() async {
        guard !recordingId.isEmpty else { return }
        // Poll every 10s for up to 5 minutes
        for _ in 0..<30 {
            try? await Task.sleep(for: .seconds(10))
            if let detail = try? await RecordingService.getRecordingDetail(id: recordingId) {
                if detail.status == .ready {
                    withAnimation { processingStatus = .ready }
                    return
                } else if detail.status == .error {
                    return
                }
            }
        }
    }

    private func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
            if granted {
                DispatchQueue.main.async {
                    UIApplication.shared.registerForRemoteNotifications()
                }
            }
        }
    }
}

#Preview {
    RecordingFlowView()
        .environment(\.router, NavigationRouter())
}
