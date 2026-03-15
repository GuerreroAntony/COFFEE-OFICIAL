import Foundation

// MARK: - Mock Data Provider
// All mock data matching the React prototype + API Contract v3.1
// Used until backend is ready — toggle via APIClient.useMocks

enum MockData {

    // MARK: - Current User

    static let currentUser = User(
        id: "u1",
        nome: "Gabriel Lima",
        email: "gabriel@email.com",
        plano: .trial,
        trialEnd: Calendar.current.date(byAdding: .day, value: 7, to: Date()),
        subscriptionActive: false,
        espmConnected: true,
        espmLogin: "gabriel.lima@acad.espm.br",
        createdAt: Date()
    )

    static let authResponse = AuthResponse(
        user: currentUser,
        token: "mock_jwt_token_\(UUID().uuidString)"
    )

    static let userProfile = UserProfile(
        id: "u1",
        nome: "Gabriel Lima",
        email: "gabriel@email.com",
        plano: .trial,
        trialEnd: Calendar.current.date(byAdding: .day, value: 7, to: Date()),
        subscriptionActive: false,
        espmConnected: true,
        espmLogin: "gabriel.lima@acad.espm.br",
        usage: UserUsage(
            gravacoesTotal: 20,
            horasGravadas: 12.5,
            questionsRemaining: QuestionsRemaining(
                espresso: -1,
                lungo: 27,
                coldBrew: 14
            ),
            questionsResetAt: Calendar.current.date(byAdding: .day, value: 18, to: Date())
        ),
        giftCodes: [
            GiftCode(code: "ABC12345", redeemed: false, redeemedBy: nil, redeemedAt: nil),
            GiftCode(code: "XYZ67890", redeemed: true, redeemedBy: "Ana", redeemedAt: Date())
        ],
        createdAt: Date()
    )

    // MARK: - Disciplines (from API Contract v3.1)
    // Added lastSyncedAt per contract

    static let disciplines: [Discipline] = [
        Discipline(
            id: "d1",
            nome: "Gestão de Marketing",
            turma: "AD1N",
            semestre: "2026/1",
            canvasCourseId: 49137,
            gravacoesCount: 12,
            materiaisCount: 3,
            aiActive: true,
            lastSyncedAt: Date()
        ),
        Discipline(
            id: "d2",
            nome: "Finanças I",
            turma: "FIN-B",
            semestre: "2026/1",
            canvasCourseId: 49138,
            gravacoesCount: 8,
            materiaisCount: 2,
            aiActive: false,
            lastSyncedAt: Calendar.current.date(byAdding: .day, value: -1, to: Date())
        ),
        Discipline(
            id: "d3",
            nome: "Economia",
            turma: "ECO-A",
            semestre: "2026/1",
            canvasCourseId: 49139,
            gravacoesCount: 5,
            materiaisCount: 1,
            aiActive: true,
            lastSyncedAt: Calendar.current.date(byAdding: .day, value: -2, to: Date())
        ),
    ]

    // MARK: - Repositories

    static let repositories: [Repository] = [
        Repository(
            id: "r101",
            nome: "Resumos para P1",
            icone: "doc.text",
            gravacoesCount: 4,
            aiActive: true,
            createdAt: Date()
        ),
        Repository(
            id: "r102",
            nome: "Aulas extras",
            icone: "folder",
            gravacoesCount: 2,
            aiActive: false,
            createdAt: Date()
        ),
    ]

    // MARK: - Recordings

    static let recordings: [Recording] = [
        Recording(
            id: "rec1",
            sourceType: "disciplina",
            sourceId: "d1",
            date: "2026-02-25",
            dateLabel: "Terça, 25 de fevereiro",
            durationSeconds: 4800,
            durationLabel: "1h 20min",
            status: .ready,
            shortSummary: "Os 4Ps do Marketing: Produto, Preço, Praça e Promoção com exemplos práticos.",
            mediaCount: 3,
            materialsCount: 2,
            hasMindMap: true,
            receivedFrom: nil,
            createdAt: Date()
        ),
        Recording(
            id: "rec2",
            sourceType: "disciplina",
            sourceId: "d1",
            date: "2026-02-20",
            dateLabel: "Quinta, 20 de fevereiro",
            durationSeconds: 5700,
            durationLabel: "1h 35min",
            status: .ready,
            shortSummary: "Segmentação de mercado e posicionamento de marca.",
            mediaCount: 1,
            materialsCount: 0,
            hasMindMap: true,
            receivedFrom: nil,
            createdAt: Date()
        ),
        Recording(
            id: "rec3",
            sourceType: "disciplina",
            sourceId: "d1",
            date: "2026-02-18",
            dateLabel: "Terça, 18 de fevereiro",
            durationSeconds: 3300,
            durationLabel: "55min",
            status: .ready,
            shortSummary: "Introdução ao mix de marketing e análise SWOT.",
            mediaCount: 0,
            materialsCount: 0,
            hasMindMap: false,
            receivedFrom: nil,
            createdAt: Date()
        ),
        Recording(
            id: "rec4",
            sourceType: "disciplina",
            sourceId: "d1",
            date: "2026-02-13",
            dateLabel: "Quinta, 13 de fevereiro",
            durationSeconds: 4200,
            durationLabel: "1h 10min",
            status: .ready,
            shortSummary: "Conceitos fundamentais de marketing e comportamento do consumidor.",
            mediaCount: 0,
            materialsCount: 0,
            hasMindMap: false,
            receivedFrom: nil,
            createdAt: Date()
        ),
        Recording(
            id: "rec5",
            sourceType: "disciplina",
            sourceId: "d2",
            date: "2026-02-24",
            dateLabel: "Segunda, 24 de fevereiro",
            durationSeconds: 4500,
            durationLabel: "1h 15min",
            status: .ready,
            shortSummary: "Fluxo de caixa e análise de investimentos com VPL e TIR.",
            mediaCount: 0,
            materialsCount: 0,
            hasMindMap: true,
            receivedFrom: nil,
            createdAt: Date()
        ),
        Recording(
            id: "rec6",
            sourceType: "disciplina",
            sourceId: "d2",
            date: "2026-02-19",
            dateLabel: "Quarta, 19 de fevereiro",
            durationSeconds: 3900,
            durationLabel: "1h 05min",
            status: .ready,
            shortSummary: "Balanços patrimoniais e demonstração de resultados.",
            mediaCount: 0,
            materialsCount: 0,
            hasMindMap: false,
            receivedFrom: nil,
            createdAt: Date()
        ),
        Recording(
            id: "rec7",
            sourceType: "disciplina",
            sourceId: "d3",
            date: "2026-02-21",
            dateLabel: "Sexta, 21 de fevereiro",
            durationSeconds: 3000,
            durationLabel: "50min",
            status: .ready,
            shortSummary: "Oferta e demanda: equilíbrio de mercado.",
            mediaCount: 0,
            materialsCount: 0,
            hasMindMap: false,
            receivedFrom: nil,
            createdAt: Date()
        ),
        Recording(
            id: "rec8",
            sourceType: "disciplina",
            sourceId: "d3",
            date: "2026-02-14",
            dateLabel: "Sexta, 14 de fevereiro",
            durationSeconds: 3600,
            durationLabel: "1h 00min",
            status: .ready,
            shortSummary: "Microeconomia: elasticidade-preço e curvas de custo.",
            mediaCount: 0,
            materialsCount: 0,
            hasMindMap: true,
            receivedFrom: nil,
            createdAt: Date()
        ),
    ]

    // MARK: - Shared Items

    static let sharedItems: [SharedItem] = [
        SharedItem(
            id: "s1",
            sender: SharedSender(nome: "Ana Beatriz", initials: "AB"),
            gravacao: SharedGravacao(
                date: "2026-02-25",
                dateLabel: "Terça, 25 de fevereiro",
                durationLabel: "1h 20min",
                shortSummary: "Os 4Ps do Marketing",
                hasMindMap: true
            ),
            sourceDiscipline: "Gestão de Marketing",
            sharedContent: ["resumo", "mapa"],
            message: "Olha o resumo da aula que você perdeu!",
            status: .pending,
            isNew: true,
            createdAt: Date()
        ),
        SharedItem(
            id: "s2",
            sender: SharedSender(nome: "Lucas Oliveira", initials: "LO"),
            gravacao: SharedGravacao(
                date: "2026-02-24",
                dateLabel: "Segunda, 24 de fevereiro",
                durationLabel: "1h 15min",
                shortSummary: "Fluxo de caixa",
                hasMindMap: false
            ),
            sourceDiscipline: "Finanças I",
            sharedContent: ["resumo"],
            message: nil,
            status: .pending,
            isNew: true,
            createdAt: Calendar.current.date(byAdding: .day, value: -1, to: Date())
        ),
        SharedItem(
            id: "s3",
            sender: SharedSender(nome: "Mariana Costa", initials: "MC"),
            gravacao: SharedGravacao(
                date: "2026-02-24",
                dateLabel: "Segunda, 24 de fevereiro",
                durationLabel: "55min",
                shortSummary: "Segmentação de mercado",
                hasMindMap: false
            ),
            sourceDiscipline: "Gestão de Marketing",
            sharedContent: ["resumo"],
            message: "Resumo da prova!",
            status: .pending,
            isNew: false,
            createdAt: Calendar.current.date(byAdding: .day, value: -7, to: Date())
        ),
    ]

    // MARK: - Chat History

    static let chatHistory: [Chat] = [
        Chat(id: "ch1", sourceType: "disciplina", sourceId: "d1", sourceName: "Gestão de Marketing", sourceIcon: "school", lastMessage: "O que são os 4Ps do Marketing?", messageCount: 4, updatedAt: Date()),
        Chat(id: "ch2", sourceType: "disciplina", sourceId: "d1", sourceName: "Gestão de Marketing", sourceIcon: "school", lastMessage: "Resumo da aula sobre segmentação", messageCount: 6, updatedAt: Calendar.current.date(byAdding: .day, value: -1, to: Date())),
        Chat(id: "ch3", sourceType: "disciplina", sourceId: "d2", sourceName: "Finanças I", sourceIcon: "school", lastMessage: "Diferença entre valuation e brand equity", messageCount: 3, updatedAt: Calendar.current.date(byAdding: .day, value: -6, to: Date())),
        Chat(id: "ch4", sourceType: "disciplina", sourceId: "d3", sourceName: "Economia", sourceIcon: "school", lastMessage: "Explicar oferta e demanda", messageCount: 8, updatedAt: Calendar.current.date(byAdding: .day, value: -7, to: Date())),
    ]

    // MARK: - Chat Messages (mock AI response)

    static let sampleAIResponse = ChatMessageItem(
        id: "msg2",
        sender: .ai,
        text: "Os 4Ps discutidos na aula de 25/02 são: Produto, Preço, Praça e Promoção. Esse conceito foi reforçado na aula seguinte com exemplos práticos de segmentação de mercado.",
        label: "Barista de Gestão de Marketing",
        mode: .lungo,
        sources: [
            ChatSource(type: "transcription", gravacaoId: "rec1", materialId: nil, title: "Aula 25/02", date: "25 fev 2026", excerpt: "Os 4Ps do marketing...", similarity: 0.94),
            ChatSource(type: "material", gravacaoId: nil, materialId: "mat1", title: "Cap. 3.pdf", date: nil, excerpt: "modelo clássico de Kotler...", similarity: 0.82),
        ],
        createdAt: Date()
    )

    // MARK: - Recording Detail

    static func recordingDetail(for recordingId: String) -> RecordingDetail {
        let recording = recordings.first { $0.id == recordingId } ?? recordings[0]

        return RecordingDetail(
            id: recording.id,
            sourceType: recording.sourceType,
            sourceId: recording.sourceId,
            date: recording.date,
            dateLabel: recording.dateLabel,
            durationSeconds: recording.durationSeconds,
            durationLabel: recording.durationLabel,
            status: recording.status,
            shortSummary: recording.shortSummary,
            fullSummary: [
                SummarySection(title: "Conceitos Principais", bullets: [
                    "Os 4Ps do Marketing representam os pilares fundamentais: Produto, Preço, Praça e Promoção.",
                    "Cada P deve ser alinhado à estratégia geral da empresa."
                ]),
                SummarySection(title: "Exemplos Práticos", bullets: [
                    "Caso Nespresso: posicionamento premium com preço alto, distribuição seletiva e comunicação aspiracional.",
                    "Caso Havaianas: reposicionamento de produto popular para marca lifestyle."
                ]),
                SummarySection(title: "Conclusão", bullets: [
                    "A integração dos 4Ps é essencial para uma estratégia de marketing coerente e eficaz."
                ])
            ],
            transcription: "Professor: Hoje vamos falar sobre os 4Ps do Marketing...",
            mindMap: MindMap(
                topic: "4Ps do Marketing",
                branches: [
                    MindMapBranch(topic: "Produto", color: 0, children: ["Qualidade e Design", "Ciclo de Vida", "Marca e Embalagem"]),
                    MindMapBranch(topic: "Preço", color: 1, children: ["Precificação", "Elasticidade", "Preço Psicológico"]),
                    MindMapBranch(topic: "Praça", color: 2, children: ["Canais de Distrib.", "Logística", "E-commerce"]),
                    MindMapBranch(topic: "Promoção", color: 3, children: ["Publicidade", "Marketing Digital", "Relações Públicas"]),
                ]
            ),
            media: [
                RecordingMedia(id: "med1", type: "photo", label: "Quadro", timestampSeconds: 872, timestampLabel: "14:32", url: nil),
                RecordingMedia(id: "med2", type: "photo", label: "Slide projetado", timestampSeconds: 1695, timestampLabel: "28:15", url: nil),
                RecordingMedia(id: "med3", type: "photo", label: "Exercício", timestampSeconds: 2700, timestampLabel: "45:00", url: nil),
                RecordingMedia(id: "med4", type: "photo", label: "Anotação", timestampSeconds: 3420, timestampLabel: "57:00", url: nil)
            ],
            materials: [
                Material(id: "mat1", disciplinaId: "d1", tipo: "pdf", nome: "Cap. 3.pdf", urlStorage: nil, fonte: "canvas", aiEnabled: true, sizeBytes: 2_516_582, sizeLabel: "2.4 MB", createdAt: Date())
            ],
            receivedFrom: nil,
            createdAt: recording.createdAt
        )
    }

    // MARK: - Subscription Plans (API Contract v3.1)
    // Pricing: R$59,90/mês (cheio), R$29,90/mês (promo lançamento). Só mensal.

    static let subscriptionPlans: [SubscriptionPlan] = [
        SubscriptionPlan(
            id: "premium_promo",
            name: "Premium",
            price: 29.90,
            originalPrice: 59.90,
            isPromo: true,
            features: [
                "Gravações ilimitadas",
                "Transcrição com WhisperKit",
                "Resumos e mapas mentais com IA",
                "Chat Barista (todos os modos)",
                "Compartilhamento com colegas",
                "Sincronização com Canvas ESPM",
                "2 códigos de convite para amigos",
            ]
        ),
    ]

    // MARK: - Premium Benefits

    static let premiumBenefits: [PremiumBenefit] = [
        PremiumBenefit(icon: CoffeeIcon.mic, title: "Gravações ilimitadas", description: "Grave todas as suas aulas sem limite de tempo"),
        PremiumBenefit(icon: CoffeeIcon.notes, title: "Resumos automáticos", description: "IA gera resumos estruturados de cada aula"),
        PremiumBenefit(icon: CoffeeIcon.mindMap, title: "Mapas mentais", description: "Visualize conceitos conectados automaticamente"),
        PremiumBenefit(icon: CoffeeIcon.sparkles, title: "Barista IA completo", description: "Acesso a todos os modos: Espresso, Lungo e Cold Brew"),
        PremiumBenefit(icon: CoffeeIcon.share, title: "Compartilhamento", description: "Envie resumos e mapas para colegas"),
        PremiumBenefit(icon: CoffeeIcon.sync, title: "Sync Canvas ESPM", description: "Sincronize disciplinas e materiais automaticamente"),
    ]

    // MARK: - Cancel Reasons

    static let cancelReasons: [CancelReason] = [
        CancelReason(icon: CoffeeIcon.payments, label: "Está muito caro"),
        CancelReason(icon: CoffeeIcon.eventBusy, label: "Não uso o suficiente"),
        CancelReason(icon: CoffeeIcon.thumbDown, label: "Conteúdo inadequado"),
        CancelReason(icon: CoffeeIcon.bugReport, label: "Problemas técnicos"),
    ]

    // MARK: - Promo/Gift Codes

    static let validPromoCodes = ["COFFEE2026", "ESPM", "BARISTA", "AMIGO"]

    // MARK: - ESPM Status

    static let espmStatus = ESPMStatus(
        connected: true,
        matricula: "gabriel.lima@acad.espm.br",
        disciplinasCount: 3,
        tokenExpiresAt: Calendar.current.date(byAdding: .day, value: 120, to: Date())
    )

    // MARK: - Canvas Materials

    static let allMaterials: [Material] = [
        Material(id: "mat1", disciplinaId: "d1", tipo: "pdf", nome: "Cap. 3 - Mix de Marketing.pdf", urlStorage: nil, fonte: "canvas", aiEnabled: true, sizeBytes: 2_516_582, sizeLabel: "2.4 MB", createdAt: Date()),
        Material(id: "mat2", disciplinaId: "d1", tipo: "slide", nome: "Slides Aula 3 - Posicionamento", urlStorage: nil, fonte: "canvas", aiEnabled: true, sizeBytes: 5_100_000, sizeLabel: "5.1 MB", createdAt: Date()),
        Material(id: "mat3", disciplinaId: "d1", tipo: "pdf", nome: "Estudo de Caso - Coca-Cola", urlStorage: nil, fonte: "manual", aiEnabled: false, sizeBytes: 1_800_000, sizeLabel: "1.8 MB", createdAt: Date()),
        Material(id: "mat4", disciplinaId: "d2", tipo: "pdf", nome: "Demonstrações Financeiras", urlStorage: nil, fonte: "canvas", aiEnabled: true, sizeBytes: 3_200_000, sizeLabel: "3.2 MB", createdAt: Date()),
        Material(id: "mat5", disciplinaId: "d2", tipo: "slide", nome: "Slides - Balanço Patrimonial", urlStorage: nil, fonte: "canvas", aiEnabled: true, sizeBytes: 4_500_000, sizeLabel: "4.5 MB", createdAt: Date()),
        Material(id: "mat6", disciplinaId: "d3", tipo: "pdf", nome: "Microeconomia - Capítulo 5", urlStorage: nil, fonte: "canvas", aiEnabled: true, sizeBytes: 2_900_000, sizeLabel: "2.9 MB", createdAt: Date()),
    ]

    // MARK: - Notifications

    static let notifications: [AppNotification] = [
        AppNotification(
            id: "n1",
            tipo: "compartilhamento",
            titulo: "Ana Beatriz compartilhou uma aula",
            corpo: "Gestao de Marketing - Aula 25/02",
            dataPayload: NotificationPayload(
                compartilhamentoId: "s1",
                deepLink: "coffee://compartilhamentos/s1"
            ),
            lida: false,
            createdAt: Date()
        ),
        AppNotification(
            id: "n2",
            tipo: "compartilhamento",
            titulo: "Lucas Oliveira compartilhou uma aula",
            corpo: "Financas I - Aula 24/02",
            dataPayload: NotificationPayload(
                compartilhamentoId: "s2",
                deepLink: "coffee://compartilhamentos/s2"
            ),
            lida: false,
            createdAt: Calendar.current.date(byAdding: .day, value: -1, to: Date())
        ),
        AppNotification(
            id: "n3",
            tipo: "compartilhamento",
            titulo: "Mariana Costa compartilhou uma aula",
            corpo: "Gestao de Marketing - Aula 24/02",
            dataPayload: NotificationPayload(
                compartilhamentoId: "s3",
                deepLink: "coffee://compartilhamentos/s3"
            ),
            lida: true,
            createdAt: Calendar.current.date(byAdding: .day, value: -7, to: Date())
        ),
    ]

    // MARK: - Helper: Recordings by source

    static func recordings(for sourceId: String) -> [Recording] {
        recordings.filter { $0.sourceId == sourceId }
    }

    // MARK: - Helper: Materials by discipline

    static func materials(for disciplinaId: String) -> [Material] {
        allMaterials.filter { $0.disciplinaId == disciplinaId }
    }

    // MARK: - Helper: Display title for a recording

    static func displayTitle(for recording: Recording) -> String {
        let components = recording.dateLabel.components(separatedBy: ", ")
        if components.count > 1 {
            return "Aula \(components[1].prefix(5))"
        }
        return "Aula \(recording.date)"
    }

    // MARK: - Helper: Icon for material type

    static func materialIcon(for tipo: String) -> String {
        switch tipo {
        case "pdf": return "doc.fill"
        case "slide": return "rectangle.on.rectangle.angled"
        case "foto": return "photo.fill"
        default: return "doc.fill"
        }
    }
}
