import SwiftUI

struct GravacaoView: View {
    @StateObject private var viewModel = GravacaoViewModel()
    @StateObject private var disciplinasVM = DisciplinasViewModel()
    @StateObject private var whisper = WhisperLiveService()

    @State private var selectedDisciplina: Disciplina?
    @State private var showDisciplinaPicker = false
    @State private var recordedURL: URL?
    @State private var showConfirm = false
    @State private var permissionDenied = false

    var body: some View {
        NavigationStack {
            ZStack {
                CoffeeTheme.Colors.background.ignoresSafeArea()

                VStack(spacing: CoffeeTheme.Spacing.xl) {
                    Spacer()

                    // Discipline selector
                    disciplineSelector

                    // Timer
                    Text(viewModel.formattedDuration)
                        .font(.system(size: 48, weight: .thin, design: .monospaced))
                        .foregroundColor(CoffeeTheme.Colors.espresso)

                    // Live transcription (WhisperKit)
                    if viewModel.isRecording && !whisper.liveText.isEmpty {
                        ScrollView {
                            Text(whisper.liveText)
                                .font(.system(size: 13))
                                .foregroundColor(CoffeeTheme.Colors.almond)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(CoffeeTheme.Spacing.sm)
                        }
                        .frame(maxHeight: 120)
                        .background(CoffeeTheme.Colors.cardBackground)
                        .clipShape(RoundedRectangle(cornerRadius: CoffeeTheme.Radius.md))
                        .padding(.horizontal, CoffeeTheme.Spacing.lg)
                    }

                    // Record button
                    recordButton

                    if let error = viewModel.errorMessage {
                        Text(error)
                            .font(.system(size: 13))
                            .foregroundColor(.red)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, CoffeeTheme.Spacing.lg)
                    }

                    if permissionDenied {
                        Text("Permissão de microfone negada. Habilite nas configurações do iPhone.")
                            .font(.system(size: 13))
                            .foregroundColor(.red)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, CoffeeTheme.Spacing.lg)
                    }

                    Spacer()
                }
            }
            .navigationTitle("gravar aula")
            .navigationBarTitleDisplayMode(.inline)
            .task { await disciplinasVM.loadDisciplinas() }
            .onAppear { viewModel.observeDuration() }
            .navigationDestination(isPresented: $showConfirm) {
                if let url = recordedURL, let disc = selectedDisciplina {
                    GravacaoConfirmView(
                        fileURL: url,
                        disciplina: disc,
                        viewModel: viewModel
                    )
                }
            }
        }
    }

    // MARK: - Subviews

    private var disciplineSelector: some View {
        Button {
            showDisciplinaPicker = true
        } label: {
            HStack {
                Image(systemName: "book.closed")
                    .foregroundColor(CoffeeTheme.Colors.coffee)
                Text(selectedDisciplina?.nome.components(separatedBy: " - ").last ?? "selecionar disciplina")
                    .font(.system(size: 15))
                    .foregroundColor(selectedDisciplina != nil
                        ? CoffeeTheme.Colors.espresso
                        : CoffeeTheme.Colors.almond)
                    .lineLimit(1)
                Spacer()
                Image(systemName: "chevron.down")
                    .font(.system(size: 12))
                    .foregroundColor(CoffeeTheme.Colors.almond)
            }
            .padding(.horizontal, CoffeeTheme.Spacing.md)
            .frame(height: 48)
            .background(CoffeeTheme.Colors.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: CoffeeTheme.Radius.md))
            .padding(.horizontal, CoffeeTheme.Spacing.lg)
        }
        .disabled(viewModel.isRecording)
        .sheet(isPresented: $showDisciplinaPicker) {
            DisciplinasPickerSheet(
                disciplinas: disciplinasVM.disciplinas,
                selected: $selectedDisciplina
            )
        }
    }

    private var recordButton: some View {
        Button {
            handleRecordTap()
        } label: {
            ZStack {
                Circle()
                    .fill(viewModel.isRecording
                        ? Color.red.opacity(0.15)
                        : CoffeeTheme.Colors.coffee.opacity(0.12))
                    .frame(width: 120, height: 120)

                Circle()
                    .fill(viewModel.isRecording ? Color.red : CoffeeTheme.Colors.coffee)
                    .frame(width: 84, height: 84)

                Image(systemName: viewModel.isRecording ? "stop.fill" : "mic.fill")
                    .font(.system(size: 30))
                    .foregroundColor(.white)
            }
        }
        .disabled(selectedDisciplina == nil && !viewModel.isRecording)
        .scaleEffect(viewModel.isRecording ? 1.05 : 1.0)
        .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true),
                   value: viewModel.isRecording)
    }

    // MARK: - Actions

    private func handleRecordTap() {
        if viewModel.isRecording {
            whisper.stop()
            if let url = viewModel.stopRecording() {
                recordedURL = url
                showConfirm = true
            }
        } else {
            Task {
                let granted = await viewModel.requestPermission()
                guard granted else {
                    permissionDenied = true
                    return
                }
                permissionDenied = false
                viewModel.startRecording()
                // Prepare WhisperKit model and start live transcription
                await whisper.prepare()
                whisper.startLiveTranscription(engine: viewModel.audioEngine)
            }
        }
    }
}

// MARK: - Disciplina picker sheet

private struct DisciplinasPickerSheet: View {
    let disciplinas: [Disciplina]
    @Binding var selected: Disciplina?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List(disciplinas) { disc in
                Button {
                    selected = disc
                    dismiss()
                } label: {
                    HStack {
                        Text(disc.nome.components(separatedBy: " - ").last ?? disc.nome)
                            .foregroundColor(CoffeeTheme.Colors.espresso)
                        Spacer()
                        if selected?.id == disc.id {
                            Image(systemName: "checkmark")
                                .foregroundColor(CoffeeTheme.Colors.coffee)
                        }
                    }
                }
            }
            .navigationTitle("disciplina")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("cancelar") { dismiss() }
                        .foregroundColor(CoffeeTheme.Colors.coffee)
                }
            }
        }
    }
}
