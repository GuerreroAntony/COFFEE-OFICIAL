import SwiftUI
import UniformTypeIdentifiers
import WebKit

// MARK: - Course Detail Screen
// Shows recordings and materials for a discipline with tabbed layout
// Tabs: "Aulas" (recordings) | "Conteúdo" (materials)

struct CourseDetailScreenView: View {
    let discipline: Discipline
    @Environment(\.dismiss) private var dismiss
    @Environment(\.router) private var router
    @Environment(\.subscriptionService) private var subscriptionService

    @State private var recordings: [Recording] = []
    @State private var materials: [Material] = []
    @State private var activeTab = 0
    @State private var selectedRecording: Recording? = nil
    @State private var recordingToDelete: Recording? = nil
    @State private var materialToDelete: Material? = nil
    @State private var isSyncing = false
    @State private var syncError: String? = nil
    @State private var hasAutoSynced = false
    @State private var showFileImporter = false
    @State private var isUploading = false
    @State private var previewMaterial: Material? = nil

    private let tabs = ["Aulas", "Conteúdo"]

    var body: some View {
        VStack(spacing: 0) {
            // Nav Bar
            CoffeeNavBar(
                title: discipline.nome,
                trailingIcon: CoffeeIcon.sparkles,
                trailingAction: {
                    if subscriptionService.isPremium {
                        dismiss()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                            router.openAIFromCourse(
                                disciplineName: discipline.nome,
                                recordingDate: "Todas"
                            )
                        }
                    } else {
                        router.showPremiumOffer()
                    }
                },
                onBack: { dismiss() }
            )

            // Segmented Control
            CoffeeSegmentedControl(segments: tabs, selected: $activeTab)
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 4)

            GeometryReader { geo in
                ScrollView {
                    switch activeTab {
                    case 0: aulasTab(scrollHeight: geo.size.height)
                    case 1: conteudoTab(scrollHeight: geo.size.height)
                    default: EmptyView()
                    }
                }
            }
        }
        .background(Color.coffeeBackground)
        .task {
            async let r = try? RecordingService.getRecordings(sourceType: "disciplina", sourceId: discipline.id)
            async let m = try? MaterialService.getMaterials(disciplinaId: discipline.id)
            recordings = await r ?? []
            materials = await m ?? []

            // Auto-sync materials from Canvas if empty and discipline is linked
            if materials.isEmpty && discipline.canvasCourseId != nil && !hasAutoSynced {
                hasAutoSynced = true
                await syncMaterials()
            }
        }
        .sheet(item: $selectedRecording) { recording in
            RecordingDetailSheet(recording: recording, disciplineName: discipline.nome)
        }
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
                    withAnimation { recordings.removeAll { $0.id == recId } }
                    recordingToDelete = nil
                    Task {
                        do {
                            try await RecordingService.deleteRecording(id: recId)
                        } catch {
                            print("[CourseDetail] Error deleting recording: \(error)")
                            // Reload to restore if API failed
                            if let recs = try? await RecordingService.getRecordings(sourceType: "disciplina", sourceId: discipline.id) {
                                recordings = recs
                            }
                        }
                    }
                }
            }
            Button("Cancelar", role: .cancel) { recordingToDelete = nil }
        } message: {
            Text("Esta ação não pode ser desfeita.")
        }
        .confirmationDialog(
            "Apagar material?",
            isPresented: Binding(
                get: { materialToDelete != nil },
                set: { if !$0 { materialToDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Apagar", role: .destructive) {
                if let mat = materialToDelete {
                    withAnimation { materials.removeAll { $0.id == mat.id } }
                    materialToDelete = nil
                }
            }
            Button("Cancelar", role: .cancel) { materialToDelete = nil }
        } message: {
            Text("Esta ação não pode ser desfeita.")
        }
        .fileImporter(
            isPresented: $showFileImporter,
            allowedContentTypes: [.pdf, .presentation, UTType("org.openxmlformats.wordprocessingml.document") ?? .data],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                guard url.startAccessingSecurityScopedResource() else { return }
                defer { url.stopAccessingSecurityScopedResource() }
                Task {
                    isUploading = true
                    do {
                        let data = try Data(contentsOf: url)
                        let fileName = url.lastPathComponent
                        let ext = url.pathExtension.lowercased()
                        let mimeType: String
                        switch ext {
                        case "pdf": mimeType = "application/pdf"
                        case "pptx", "ppt": mimeType = "application/vnd.openxmlformats-officedocument.presentationml.presentation"
                        case "docx", "doc": mimeType = "application/vnd.openxmlformats-officedocument.wordprocessingml.document"
                        default: mimeType = "application/octet-stream"
                        }
                        let material = try await MaterialService.uploadMaterial(
                            disciplinaId: discipline.id,
                            fileData: data,
                            fileName: fileName,
                            mimeType: mimeType,
                            aiEnabled: true
                        )
                        materials.append(material)
                    } catch {
                        print("[CourseDetail] Upload error: \(error)")
                    }
                    isUploading = false
                }
            case .failure(let error):
                print("[CourseDetail] File picker error: \(error)")
            }
        }
        .sheet(item: $previewMaterial) { material in
            MaterialPreviewSheet(material: material)
        }
    }

    // MARK: - Aulas Tab

    @ViewBuilder
    private func aulasTab(scrollHeight: CGFloat) -> some View {
        if recordings.isEmpty {
            VStack(spacing: 12) {
                Spacer()
                CoffeeEmptyState(
                    icon: CoffeeIcon.mic,
                    title: "Nenhuma gravação",
                    message: "Grave sua primeira aula desta disciplina."
                )
                Spacer()
            }
            .frame(maxWidth: .infinity)
            .frame(minHeight: scrollHeight)
        } else {
            VStack(alignment: .leading, spacing: 16) {
                CoffeeSectionHeader(title: "\(recordings.count) aulas gravadas")
                    .padding(.horizontal, 20)
                    .padding(.top, 16)

                CoffeeCellGroup {
                    ForEach(Array(recordings.enumerated()), id: \.element.id) { index, recording in
                        SwipeableRow(
                            onTap: { selectedRecording = recording },
                            onDelete: { recordingToDelete = recording }
                        ) {
                            recordingRow(recording)
                        }

                        if index < recordings.count - 1 {
                            Divider()
                                .padding(.leading, 80)
                        }
                    }
                }
                .padding(.horizontal, 16)
            }
            .padding(.bottom, 40)
        }
    }

    // MARK: - Conteúdo Tab

    @ViewBuilder
    private func conteudoTab(scrollHeight: CGFloat) -> some View {
        if materials.isEmpty {
            VStack(spacing: 16) {
                Spacer()
                CoffeeEmptyState(
                    icon: "doc.fill",
                    title: "Nenhum material",
                    message: "Sincronize com o Canvas para importar materiais."
                )

                // Sync button in empty state
                if discipline.canvasCourseId != nil {
                    Button {
                        Task { await syncMaterials() }
                    } label: {
                        HStack(spacing: 8) {
                            if isSyncing {
                                ProgressView()
                                    .tint(Color.coffeePrimary)
                                    .scaleEffect(0.8)
                            } else {
                                Image(systemName: CoffeeIcon.sync)
                                    .font(.system(size: 15, weight: .semibold))
                            }
                            Text(isSyncing ? "Sincronizando..." : "Sincronizar com Canvas")
                                .font(.system(size: 15, weight: .semibold))
                        }
                        .foregroundStyle(Color.coffeePrimary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(Color.coffeePrimary.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .disabled(isSyncing)
                    .padding(.horizontal, 40)
                }

                if let syncError {
                    Text(syncError)
                        .font(.system(size: 13))
                        .foregroundStyle(Color.coffeeDanger)
                        .padding(.horizontal, 40)
                }

                Spacer()
            }
            .frame(maxWidth: .infinity)
            .frame(minHeight: scrollHeight)
        } else {
            VStack(alignment: .leading, spacing: 16) {
                // Header with sync + upload buttons
                HStack {
                    CoffeeSectionHeader(title: "\(materials.count) materiais")

                    Spacer()

                    // Upload material button
                    Button {
                        showFileImporter = true
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 22))
                            .foregroundStyle(Color.coffeePrimary)
                    }
                    .buttonStyle(.plain)

                    if discipline.canvasCourseId != nil {
                        Button {
                            Task { await syncMaterials() }
                        } label: {
                            if isSyncing {
                                ProgressView()
                                    .tint(Color.coffeePrimary)
                                    .scaleEffect(0.7)
                                    .frame(width: 32, height: 32)
                            } else {
                                Image(systemName: CoffeeIcon.sync)
                                    .font(.system(size: 16))
                                    .foregroundStyle(Color.coffeePrimary)
                                    .frame(width: 32, height: 32)
                                    .background(Color.coffeePrimary.opacity(0.08))
                                    .clipShape(Circle())
                            }
                        }
                        .buttonStyle(.plain)
                        .disabled(isSyncing)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)

                if isUploading {
                    HStack(spacing: 10) {
                        ProgressView()
                            .tint(Color.coffeePrimary)
                            .scaleEffect(0.8)
                        Text("Enviando material...")
                            .font(.system(size: 14))
                            .foregroundStyle(Color.coffeeTextSecondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                }

                CoffeeCellGroup {
                    ForEach(Array(materials.enumerated()), id: \.element.id) { index, material in
                        SwipeableRow(
                            onTap: { previewMaterial = material },
                            onDelete: { materialToDelete = material }
                        ) {
                            materialRow(material)
                        }

                        if index < materials.count - 1 {
                            Divider()
                                .padding(.leading, 80)
                        }
                    }
                }
                .padding(.horizontal, 16)
            }
            .padding(.bottom, 40)
        }
    }

    // MARK: - Sync Materials

    private func syncMaterials() async {
        guard !isSyncing else { return }
        isSyncing = true
        syncError = nil

        do {
            _ = try await MaterialService.syncMaterials(disciplinaId: discipline.id)

            // Poll for materials — background task downloads files sequentially
            for attempt in 1...6 {
                try await Task.sleep(for: .seconds(attempt <= 2 ? 5 : 8))
                let updated = try await MaterialService.getMaterials(disciplinaId: discipline.id)
                if !updated.isEmpty || attempt == 6 {
                    withAnimation { materials = updated }
                    break
                }
            }
        } catch let error as APIError {
            switch error {
            case .syncCooldown:
                syncError = "Aguarde 1 hora entre sincronizações."
            default:
                syncError = "Erro ao sincronizar: \(error.localizedDescription)"
            }
        } catch {
            syncError = "Erro ao sincronizar."
        }

        isSyncing = false
    }

    // MARK: - Recording Row (matches screenshot layout)

    private func recordingRow(_ recording: Recording) -> some View {
        HStack(spacing: 14) {
            // Icon
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.coffeePrimary.opacity(0.09))
                    .frame(width: 50, height: 50)
                Image(systemName: "waveform")
                    .font(.system(size: 20))
                    .foregroundStyle(Color.coffeePrimary)
            }

            // Content
            VStack(alignment: .leading, spacing: 4) {
                // Title row: date + status badge
                HStack(spacing: 8) {
                    Text(recording.dateLabel)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Color.coffeeTextPrimary)
                        .lineLimit(1)

                    statusBadge(for: recording.status)

                    Spacer(minLength: 0)
                }

                // Duration
                Text(recording.durationLabel)
                    .font(.system(size: 14))
                    .foregroundStyle(Color.coffeeTextSecondary)

                // Summary preview
                if let summary = recording.shortSummary, !summary.isEmpty {
                    Text(summary)
                        .font(.system(size: 14))
                        .foregroundStyle(Color.coffeeTextSecondary.opacity(0.8))
                        .lineLimit(1)
                }
            }

            // Chevron
            Image(systemName: CoffeeIcon.forward)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color(red: 60/255, green: 60/255, blue: 67/255).opacity(0.35))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .contentShape(Rectangle())
    }

    // MARK: - Status Badge

    private func statusBadge(for status: RecordingStatus) -> some View {
        Group {
            switch status {
            case .ready:
                Text("Pronto")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.coffeeSuccess)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 3)
                    .background(Color.coffeeSuccess.opacity(0.12))
                    .clipShape(Capsule())

            case .processing:
                Text("Processando")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.coffeeWarning)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 3)
                    .background(Color.coffeeWarning.opacity(0.12))
                    .clipShape(Capsule())

            case .error:
                Text("Erro")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.coffeeDanger)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 3)
                    .background(Color.coffeeDanger.opacity(0.12))
                    .clipShape(Capsule())
            }
        }
    }

    // MARK: - Material Row

    private func materialRow(_ material: Material) -> some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.blue.opacity(0.09))
                    .frame(width: 50, height: 50)
                Image(systemName: material.iconName)
                    .font(.system(size: 20))
                    .foregroundStyle(.blue)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(material.nome)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.coffeeTextPrimary)
                    .lineLimit(1)

                HStack(spacing: 6) {
                    Text(material.tipo.uppercased())
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.blue.opacity(0.7))
                    if let size = material.sizeLabel {
                        Text("·")
                            .foregroundStyle(Color.coffeeTextSecondary.opacity(0.5))
                        Text(size)
                            .font(.system(size: 13))
                            .foregroundStyle(Color.coffeeTextSecondary)
                    }
                }
            }

            Spacer()

            Toggle("", isOn: Binding(
                get: { material.aiEnabled },
                set: { newValue in
                    if let idx = materials.firstIndex(where: { $0.id == material.id }) {
                        materials[idx].aiEnabled = newValue
                        Task {
                            do {
                                let updated = try await MaterialService.toggleAI(materialId: material.id)
                                if let i = materials.firstIndex(where: { $0.id == material.id }) {
                                    materials[i] = updated
                                }
                            } catch {
                                if let i = materials.firstIndex(where: { $0.id == material.id }) {
                                    materials[i].aiEnabled = !newValue
                                }
                            }
                        }
                    }
                }
            ))
            .labelsHidden()
            .tint(Color.coffeePrimary)

            Image(systemName: CoffeeIcon.forward)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color(red: 60/255, green: 60/255, blue: 67/255).opacity(0.35))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .contentShape(Rectangle())
    }
}

// MARK: - Recording Detail Sheet

struct RecordingDetailSheet: View {
    let recording: Recording
    let disciplineName: String
    @Environment(\.dismiss) private var dismiss
    @Environment(\.router) private var router
    @Environment(\.subscriptionService) private var subscriptionService

    @State private var detail: RecordingDetail? = nil
    @State private var activeTab = 0
    @State private var mindMapExpanded = false
    @State private var showShareSheet = false

    private let tabs = ["Resumo", "Mapa Mental", "Mídia"]

    var body: some View {
        VStack(spacing: 0) {
            CoffeeSheetHeader(
                title: recording.displayTitle,
                onClose: { dismiss() }
            )

            // Sub-header
            HStack {
                Text(disciplineName)
                    .font(.system(size: 14))
                    .foregroundStyle(Color.coffeeTextSecondary)
                Text("·")
                    .foregroundStyle(Color.coffeeTextSecondary.opacity(0.5))
                Text(recording.durationLabel)
                    .font(.system(size: 14))
                    .foregroundStyle(Color.coffeeTextSecondary)
                Spacer()

                // Share button
                Button {
                    showShareSheet = true
                } label: {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Color.coffeePrimary)
                        .frame(width: 36, height: 36)
                        .background(Color.coffeePrimary.opacity(0.1))
                        .clipShape(Circle())
                }

                Button {
                    if subscriptionService.isPremium {
                        dismiss()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                            router.openAIFromCourse(
                                disciplineName: disciplineName,
                                recordingDate: recording.dateLabel
                            )
                        }
                    } else {
                        router.showPremiumOffer()
                    }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: CoffeeIcon.sparkles)
                            .font(.system(size: 12))
                        Text("Barista")
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .foregroundStyle(Color.coffeePrimary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Color.coffeePrimary.opacity(0.1))
                    .clipShape(Capsule())
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 4)
            .padding(.bottom, 16)

            CoffeeSegmentedControl(segments: tabs, selected: $activeTab)
                .padding(.horizontal, 16)
                .padding(.bottom, 12)

            ScrollView {
                if let detail {
                    switch activeTab {
                    case 0: summaryView(detail)
                    case 1: mindMapView(detail)
                    case 2: mediaView(detail)
                    default: EmptyView()
                    }
                } else {
                    ProgressView()
                        .padding(.top, 40)
                }
            }
        }
        .background(Color.coffeeBackground)
        .task {
            do {
                detail = try await RecordingService.getRecordingDetail(id: recording.id)
            } catch {
                print("[RecordingDetail] Error loading: \(error)")
            }
        }
        .sheet(isPresented: $showShareSheet) {
            ShareRecordingSheet(
                recordingId: recording.id,
                hasResumo: detail?.fullSummary != nil,
                hasMindMap: detail?.mindMap != nil
            )
            .presentationDetents([.medium, .large])
        }
    }

    // MARK: - Summary

    private func summaryView(_ detail: RecordingDetail) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            if let sections = detail.fullSummary {
                ForEach(Array(sections.enumerated()), id: \.offset) { _, section in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(section.title)
                            .font(.system(size: 17, weight: .bold))
                            .foregroundStyle(Color.coffeeTextPrimary)

                        ForEach(section.bullets, id: \.self) { bullet in
                            HStack(alignment: .top, spacing: 8) {
                                Text("•")
                                    .font(.system(size: 15))
                                    .foregroundStyle(Color.coffeePrimary)
                                    .padding(.top, 1)
                                Text(bullet)
                                    .font(.system(size: 15))
                                    .foregroundStyle(Color.coffeeTextPrimary)
                                    .lineSpacing(4)
                            }
                        }
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.coffeeCardBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }

                // Download PDF button
                downloadButton(label: "Baixar resumo em PDF") {
                    let pdf = PDFExportService.generateSummaryPDF(
                        title: recording.displayTitle,
                        disciplineName: disciplineName,
                        date: recording.dateLabel,
                        duration: recording.durationLabel,
                        sections: sections
                    )
                    PDFExportService.sharePDF(
                        data: pdf,
                        fileName: "Resumo - \(disciplineName) - \(recording.dateLabel).pdf"
                    )
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 32)
    }

    // MARK: - Mind Map

    private func mindMapView(_ detail: RecordingDetail) -> some View {
        VStack(spacing: 16) {
            if let mindMap = detail.mindMap {
                // Collapsible mind map card
                Button {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        mindMapExpanded.toggle()
                    }
                } label: {
                    VStack(spacing: 0) {
                        // Central topic pill
                        Text(mindMap.topic)
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(Color.coffeePrimary)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 10)
                            .background(Color.coffeePrimary.opacity(0.1))
                            .clipShape(Capsule())
                            .padding(.top, 20)
                            .padding(.bottom, 16)

                        if mindMapExpanded {
                            // Expanded: full branches with children
                            VStack(spacing: 12) {
                                ForEach(Array(mindMap.branches.enumerated()), id: \.offset) { index, branch in
                                    let colors: [Color] = [.blue, .green, .orange, .purple]
                                    let color = colors[index % colors.count]

                                    VStack(alignment: .leading, spacing: 8) {
                                        HStack(spacing: 8) {
                                            Circle()
                                                .fill(color)
                                                .frame(width: 8, height: 8)
                                            Text(branch.topic)
                                                .font(.system(size: 16, weight: .semibold))
                                                .foregroundStyle(Color.coffeeTextPrimary)
                                        }

                                        ForEach(branch.children, id: \.self) { child in
                                            HStack(spacing: 8) {
                                                Rectangle()
                                                    .fill(color.opacity(0.3))
                                                    .frame(width: 2, height: 16)
                                                    .padding(.leading, 3)
                                                Text(child)
                                                    .font(.system(size: 14))
                                                    .foregroundStyle(Color.coffeeTextSecondary)
                                                    .multilineTextAlignment(.leading)
                                            }
                                            .padding(.leading, 12)
                                        }
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.bottom, 8)

                            // Collapse footer
                            HStack(spacing: 6) {
                                Image(systemName: "chevron.up")
                                    .font(.system(size: 11, weight: .semibold))
                                Text("Toque para recolher")
                                    .font(.system(size: 13))
                            }
                            .foregroundStyle(Color.coffeeTextSecondary.opacity(0.6))
                            .padding(.bottom, 16)
                        } else {
                            // Collapsed: branch capsules preview
                            let colors: [Color] = [.blue, .green, .orange, .purple]

                            // Branch capsules in a flowing layout
                            VStack(spacing: 8) {
                                HStack(spacing: 8) {
                                    ForEach(Array(mindMap.branches.prefix(2).enumerated()), id: \.offset) { index, branch in
                                        branchCapsule(branch.topic, color: colors[index % colors.count])
                                    }
                                }
                                if mindMap.branches.count > 2 {
                                    HStack(spacing: 8) {
                                        ForEach(Array(mindMap.branches.dropFirst(2).enumerated()), id: \.offset) { index, branch in
                                            branchCapsule(branch.topic, color: colors[(index + 2) % colors.count])
                                        }
                                    }
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.bottom, 12)

                            // Divider
                            Rectangle()
                                .fill(Color.coffeeSeparator)
                                .frame(height: 0.5)
                                .padding(.horizontal, 16)

                            // Footer
                            HStack(spacing: 6) {
                                Text("\(mindMap.branches.count) ramificações")
                                    .font(.system(size: 13))
                                    .foregroundStyle(Color.coffeeTextSecondary)
                                Text("·")
                                    .foregroundStyle(Color.coffeeTextSecondary.opacity(0.5))
                                Text("Toque para expandir")
                                    .font(.system(size: 13))
                                    .foregroundStyle(Color.coffeePrimary)
                                Image(systemName: "chevron.down")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(Color.coffeePrimary)
                            }
                            .padding(.vertical, 12)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .background(Color.coffeeCardBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .buttonStyle(.plain)
                .padding(.top, 8)

                // Download PDF button
                downloadButton(label: "Baixar mapa mental") {
                    let pdf = PDFExportService.generateMindMapPDF(
                        title: recording.displayTitle,
                        disciplineName: disciplineName,
                        date: recording.dateLabel,
                        mindMap: mindMap
                    )
                    PDFExportService.sharePDF(
                        data: pdf,
                        fileName: "Mapa Mental - \(disciplineName) - \(recording.dateLabel).pdf"
                    )
                }
            } else {
                CoffeeEmptyState(
                    icon: CoffeeIcon.mindMap,
                    title: "Sem mapa mental",
                    message: "Mapas mentais são gerados automaticamente pela IA."
                )
                .padding(.top, 40)
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 32)
    }

    // MARK: - Media

    private func mediaView(_ detail: RecordingDetail) -> some View {
        VStack(spacing: 16) {
            if let media = detail.media, !media.isEmpty {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                    ForEach(media) { item in
                        VStack(spacing: 8) {
                            if let urlString = item.url, !urlString.isEmpty, let url = URL(string: urlString) {
                                AsyncImage(url: url) { phase in
                                    switch phase {
                                    case .success(let image):
                                        image
                                            .resizable()
                                            .aspectRatio(contentMode: .fill)
                                            .frame(height: 140)
                                            .clipped()
                                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                            .overlay(alignment: .bottomTrailing) {
                                                Text(item.timestampLabel)
                                                    .font(.system(size: 10, weight: .semibold))
                                                    .foregroundStyle(.white)
                                                    .padding(.horizontal, 6)
                                                    .padding(.vertical, 3)
                                                    .background(Color.black.opacity(0.5))
                                                    .clipShape(Capsule())
                                                    .padding(6)
                                            }
                                    case .failure:
                                        mediaPlaceholder(timestampLabel: item.timestampLabel)
                                    default:
                                        ZStack {
                                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                                .fill(Color.coffeePrimary.opacity(0.06))
                                                .frame(height: 140)
                                            ProgressView()
                                        }
                                    }
                                }
                            } else {
                                mediaPlaceholder(timestampLabel: item.timestampLabel)
                            }

                            if let label = item.label {
                                Text(label)
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundStyle(Color.coffeeTextPrimary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }
                }
                .padding(.top, 8)
            } else {
                CoffeeEmptyState(
                    icon: "photo.on.rectangle",
                    title: "Sem mídia",
                    message: "Fotos tiradas durante a aula aparecerão aqui."
                )
                .padding(.top, 40)
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 32)
    }

    private func mediaPlaceholder(timestampLabel: String) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.coffeePrimary.opacity(0.06))
                .frame(height: 140)

            VStack(spacing: 6) {
                Image(systemName: "photo.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(Color.coffeePrimary.opacity(0.35))
                Text(timestampLabel)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.coffeePrimary.opacity(0.5))
            }
        }
    }

    // MARK: - Branch Capsule

    private func branchCapsule(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(color)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(color.opacity(0.1))
            .clipShape(Capsule())
    }

    // MARK: - Download Button

    private func downloadButton(label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: "arrow.down.to.line")
                    .font(.system(size: 15, weight: .semibold))
                Text(label)
                    .font(.system(size: 15, weight: .semibold))
            }
            .foregroundStyle(Color.coffeePrimary)
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .background(Color.coffeePrimary.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .padding(.top, 4)
    }
}

// MARK: - Material Preview Sheet

struct MaterialPreviewSheet: View {
    let material: Material
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            CoffeeSheetHeader(
                title: material.nome,
                onClose: { dismiss() }
            )

            if let urlString = material.urlStorage, let url = URL(string: urlString) {
                WebView(url: url)
            } else {
                VStack(spacing: 12) {
                    Spacer()
                    CoffeeEmptyState(
                        icon: "doc.fill",
                        title: "Preview indisponível",
                        message: "Este material não possui URL de armazenamento."
                    )
                    Spacer()
                }
            }
        }
        .background(Color.coffeeBackground)
    }
}

// MARK: - WebView

struct WebView: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> WKWebView {
        let webView = WKWebView()
        webView.load(URLRequest(url: url))
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}
}

#Preview {
    CourseDetailScreenView(discipline: Discipline(id: "preview", nome: "Preview", turma: nil, semestre: nil, sala: nil, canvasCourseId: nil, gravacoesCount: 0, materiaisCount: 0, aiActive: false, lastSyncedAt: nil))
        .environment(\.router, NavigationRouter())
}
