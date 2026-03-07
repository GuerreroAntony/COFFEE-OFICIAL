import SwiftUI

struct GravacaoConfirmView: View {
    let fileURL: URL
    let disciplina: Disciplina
    @ObservedObject var viewModel: GravacaoViewModel

    @State private var dataAula = Date()
    @State private var showResumo = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            CoffeeTheme.Colors.background.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: CoffeeTheme.Spacing.lg) {

                    // Header
                    VStack(alignment: .leading, spacing: CoffeeTheme.Spacing.xs) {
                        Text("confirmar gravação")
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundColor(CoffeeTheme.Colors.espresso)

                        Text(disciplina.nome.components(separatedBy: " - ").last ?? disciplina.nome)
                            .font(.system(size: 14))
                            .foregroundColor(CoffeeTheme.Colors.almond)
                    }

                    // Duration card
                    HStack(spacing: CoffeeTheme.Spacing.md) {
                        Image(systemName: "waveform")
                            .font(.system(size: 20))
                            .foregroundColor(CoffeeTheme.Colors.coffee)

                        VStack(alignment: .leading, spacing: 2) {
                            Text("duração gravada")
                                .font(.system(size: 12))
                                .foregroundColor(CoffeeTheme.Colors.almond)
                            Text(viewModel.formattedDuration)
                                .font(.system(size: 18, weight: .semibold, design: .monospaced))
                                .foregroundColor(CoffeeTheme.Colors.espresso)
                        }
                    }
                    .padding(CoffeeTheme.Spacing.md)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(CoffeeTheme.Colors.cardBackground)
                    .clipShape(RoundedRectangle(cornerRadius: CoffeeTheme.Radius.md))

                    // Date picker
                    VStack(alignment: .leading, spacing: CoffeeTheme.Spacing.xs) {
                        Text("data da aula")
                            .font(.system(size: 13))
                            .foregroundColor(CoffeeTheme.Colors.almond)

                        DatePicker("", selection: $dataAula, displayedComponents: .date)
                            .datePickerStyle(.compact)
                            .labelsHidden()
                            .environment(\.locale, Locale(identifier: "pt_BR"))
                    }

                    // Transcription result (preview)
                    if let gravacao = viewModel.uploadedGravacao,
                       let trans = gravacao.transcricao {
                        VStack(alignment: .leading, spacing: CoffeeTheme.Spacing.sm) {
                            Text("transcrição")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(CoffeeTheme.Colors.almond)

                            Text(trans.texto)
                                .font(.system(size: 14))
                                .foregroundColor(CoffeeTheme.Colors.espresso)
                                .lineLimit(6)
                                .padding(CoffeeTheme.Spacing.md)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(CoffeeTheme.Colors.cardBackground)
                                .clipShape(RoundedRectangle(cornerRadius: CoffeeTheme.Radius.md))
                        }
                    }

                    // Resumo state
                    if viewModel.isGeneratingResumo {
                        HStack(spacing: CoffeeTheme.Spacing.sm) {
                            ProgressView()
                                .scaleEffect(0.9)
                            Text("gerando resumo com IA...")
                                .font(.system(size: 14))
                                .foregroundColor(CoffeeTheme.Colors.almond)
                        }
                        .padding(CoffeeTheme.Spacing.md)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(CoffeeTheme.Colors.cardBackground)
                        .clipShape(RoundedRectangle(cornerRadius: CoffeeTheme.Radius.md))
                    } else if let resumo = viewModel.resumo {
                        // Resumo accordion inline
                        resumoSection(resumo)
                    }

                    if let error = viewModel.errorMessage {
                        Text(error)
                            .font(.system(size: 13))
                            .foregroundColor(.red)
                    }

                    // Action buttons
                    if viewModel.uploadedGravacao == nil {
                        CoffeeButton(
                            title: "enviar e transcrever",
                            isLoading: viewModel.isUploading
                        ) {
                            Task {
                                await viewModel.uploadRecording(
                                    fileURL: fileURL,
                                    disciplinaId: disciplina.id,
                                    dataAula: dataAula
                                )
                            }
                        }

                        CoffeeButton(title: "descartar", style: .secondary) {
                            dismiss()
                        }
                    } else {
                        CoffeeButton(title: "concluído") {
                            dismiss()
                        }
                    }
                }
                .padding(.horizontal, CoffeeTheme.Spacing.lg)
                .padding(.top, CoffeeTheme.Spacing.xl)
            }
        }
        .navigationTitle("confirmar")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(viewModel.isUploading || viewModel.isGeneratingResumo)
        .navigationDestination(isPresented: $showResumo) {
            if let resumo = viewModel.resumo {
                ResumoView(resumo: resumo)
            }
        }
    }

    // MARK: - Resumo inline accordion

    @State private var expandedTopicos: Set<String> = []

    @ViewBuilder
    private func resumoSection(_ resumo: Resumo) -> some View {
        VStack(alignment: .leading, spacing: CoffeeTheme.Spacing.sm) {
            HStack {
                Label("resumo gerado", systemImage: "sparkles")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(CoffeeTheme.Colors.almond)
                    .textCase(.uppercase)

                Spacer()

                Button {
                    showResumo = true
                } label: {
                    Text("ver completo")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(CoffeeTheme.Colors.coffee)
                }
            }

            // Title
            Text(resumo.titulo)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(CoffeeTheme.Colors.espresso)

            // Accordion tópicos
            VStack(spacing: CoffeeTheme.Spacing.xs) {
                ForEach(resumo.topicos, id: \.titulo) { topico in
                    let isExpanded = Binding<Bool>(
                        get: { expandedTopicos.contains(topico.titulo) },
                        set: { open in
                            if open { expandedTopicos.insert(topico.titulo) }
                            else { expandedTopicos.remove(topico.titulo) }
                        }
                    )
                    DisclosureGroup(isExpanded: isExpanded) {
                        if !topico.conteudo.isEmpty {
                            Text(topico.conteudo)
                                .font(.system(size: 13))
                                .foregroundColor(CoffeeTheme.Colors.almond)
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(.top, CoffeeTheme.Spacing.xs)
                        }
                    } label: {
                        Text(topico.titulo)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(CoffeeTheme.Colors.espresso)
                    }
                    .padding(CoffeeTheme.Spacing.md)
                    .background(CoffeeTheme.Colors.cardBackground)
                    .clipShape(RoundedRectangle(cornerRadius: CoffeeTheme.Radius.md))
                    .accentColor(CoffeeTheme.Colors.coffee)
                }
            }
        }
    }
}
