import SwiftUI

// MARK: - Profile Screen
// User profile, plan info, usage stats, gift codes
// Matches Profile section from the React app

struct ProfileScreenView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.router) private var router
    @Environment(\.subscriptionService) private var subscription

    @State private var showCancellation = false
    @State private var showDeleteAccount = false
    @State private var isPurchasing = false
    @State private var profile: UserProfile? = nil
    @State private var isLoading = true

    private var userName: String {
        router.currentUser?.nome ?? profile?.nome ?? "Aluno"
    }

    private var userEmail: String {
        router.currentUser?.email ?? profile?.email ?? ""
    }

    private var userInitials: String {
        userName.split(separator: " ").prefix(2).map { String($0.prefix(1)) }.joined().uppercased()
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Profile header
                    VStack(spacing: 12) {
                        CoffeeAvatar(
                            initials: userInitials,
                            size: 80
                        )

                        Text(userName)
                            .font(.system(size: 22, weight: .bold))
                            .foregroundStyle(Color.coffeeTextPrimary)

                        Text(userEmail)
                            .font(.system(size: 15))
                            .foregroundStyle(Color.coffeeTextSecondary)

                        // Plan badge (reactive to subscription state)
                        HStack(spacing: 6) {
                            Image(systemName: subscription.isPremium ? "crown.fill" : "clock.fill")
                                .font(.system(size: 12))
                            Text(subscription.isPremium ? "Premium" : "Gratuito")
                                .font(.system(size: 13, weight: .semibold))
                        }
                        .foregroundStyle(subscription.isPremium ? .orange : Color.coffeeTextSecondary)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 6)
                        .background(subscription.isPremium ? Color.orange.opacity(0.1) : Color.coffeeTextSecondary.opacity(0.1))
                        .clipShape(Capsule())
                    }
                    .padding(.top, 16)

                    // Usage stats
                    CoffeeSectionHeader(title: "Uso")
                        .padding(.horizontal, 20)

                    if isLoading {
                        ProgressView()
                            .tint(Color.coffeePrimary)
                            .padding(.vertical, 20)
                    } else if let usage = profile?.usage {
                        CoffeeCellGroup {
                            CoffeeCell(
                                icon: CoffeeIcon.mic,
                                title: "Gravações",
                                subtitle: nil,
                                trailing: .text("\(usage.gravacoesTotal)")
                            )
                            CoffeeCell(
                                icon: "clock.fill",
                                title: "Horas gravadas",
                                subtitle: nil,
                                trailing: .text(String(format: "%.1fh", usage.horasGravadas))
                            )
                            CoffeeCell(
                                icon: "bolt.fill",
                                title: "Espresso (restantes)",
                                subtitle: nil,
                                trailing: .text(usage.questionsRemaining.espresso < 0 ? "∞" : "\(usage.questionsRemaining.espresso)")
                            )
                            CoffeeCell(
                                icon: CoffeeIcon.sparkles,
                                title: "Lungo (restantes)",
                                subtitle: nil,
                                trailing: .text("\(usage.questionsRemaining.lungo)")
                            )
                            CoffeeCell(
                                icon: "brain.head.profile",
                                title: "Cold Brew (restantes)",
                                subtitle: nil,
                                trailing: .text("\(usage.questionsRemaining.coldBrew)")
                            )
                        }
                        .padding(.horizontal, 16)
                    }

                    // ESPM Connection
                    CoffeeSectionHeader(title: "Conexão ESPM")
                        .padding(.horizontal, 20)

                    CoffeeCellGroup {
                        CoffeeCell(
                            icon: CoffeeIcon.school,
                            title: "Status",
                            subtitle: nil,
                            trailing: .text((router.currentUser?.espmConnected ?? false) ? "Conectado" : "Desconectado")
                        )
                        if let login = router.currentUser?.espmLogin {
                            CoffeeCell(
                                icon: "person.text.rectangle.fill",
                                title: "Matrícula",
                                subtitle: nil,
                                trailing: .text(login)
                            )
                        }
                    }
                    .padding(.horizontal, 16)

                    // Account actions
                    CoffeeSectionHeader(title: "Conta")
                        .padding(.horizontal, 20)

                    CoffeeCellGroup {
                        if subscription.isPremium {
                            // User is premium — show cancel option
                            Button { showCancellation = true } label: {
                                CoffeeCell(
                                    icon: "xmark.circle.fill",
                                    title: "Cancelar assinatura",
                                    subtitle: nil,
                                    trailing: .chevron
                                )
                            }
                            .buttonStyle(CoffeeCellButtonStyle())
                        } else {
                            // User is NOT premium — show subscribe option (no trial)
                            Button { handleResubscribe() } label: {
                                HStack(spacing: 14) {
                                    ZStack {
                                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                                            .fill(Color.coffeePrimary.opacity(0.1))
                                            .frame(width: 50, height: 50)
                                        Image(systemName: "crown.fill")
                                            .font(.system(size: 20))
                                            .foregroundStyle(Color.coffeePrimary)
                                    }
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Assinar Premium")
                                            .font(.system(size: 16, weight: .semibold))
                                            .foregroundStyle(Color.coffeePrimary)
                                        HStack(spacing: 4) {
                                            Text("R$59,90")
                                                .font(.system(size: 13))
                                                .strikethrough()
                                                .foregroundStyle(Color.coffeeTextSecondary.opacity(0.6))
                                            Text("R$29,90/mês")
                                                .font(.system(size: 13, weight: .medium))
                                                .foregroundStyle(Color.coffeeTextSecondary)
                                        }
                                    }
                                    Spacer()
                                    if isPurchasing {
                                        ProgressView()
                                            .tint(Color.coffeePrimary)
                                    } else {
                                        Image(systemName: "chevron.right")
                                            .font(.system(size: 14, weight: .semibold))
                                            .foregroundStyle(Color.coffeeTextSecondary.opacity(0.4))
                                    }
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 12)
                            }
                            .buttonStyle(CoffeeCellButtonStyle())
                            .disabled(isPurchasing)
                        }

                        Button { router.logout() } label: {
                            HStack(spacing: 14) {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .fill(Color.red.opacity(0.1))
                                        .frame(width: 50, height: 50)
                                    Image(systemName: "rectangle.portrait.and.arrow.right")
                                        .font(.system(size: 20))
                                        .foregroundStyle(.red)
                                }
                                Text("Sair da conta")
                                    .font(.system(size: 16))
                                    .foregroundStyle(.red)
                                Spacer()
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                        }
                        .buttonStyle(CoffeeCellButtonStyle())

                        Button { showDeleteAccount = true } label: {
                            HStack(spacing: 14) {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .fill(Color.red.opacity(0.1))
                                        .frame(width: 50, height: 50)
                                    Image(systemName: "trash.fill")
                                        .font(.system(size: 20))
                                        .foregroundStyle(.red)
                                }
                                Text("Excluir conta")
                                    .font(.system(size: 16))
                                    .foregroundStyle(.red)
                                Spacer()
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                        }
                        .buttonStyle(CoffeeCellButtonStyle())
                    }
                    .padding(.horizontal, 16)
                }
                .padding(.bottom, 40)
            }
            .background(Color.coffeeBackground)
            .navigationTitle("Perfil")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Fechar") { dismiss() }
                        .foregroundStyle(Color.coffeePrimary)
                }
            }
            .sheet(isPresented: $showCancellation) {
                CancellationView(onCancelled: {
                    subscription.cancelSubscription()
                })
            }
            .alert("Excluir conta", isPresented: $showDeleteAccount) {
                Button("Cancelar", role: .cancel) { }
                Button("Excluir", role: .destructive) {
                    Task {
                        try? await AccountService.deleteAccount()
                        router.logout()
                    }
                }
            } message: {
                Text("Tem certeza que deseja excluir sua conta? Esta ação é irreversível.")
            }
            .task { await loadProfile() }
        }
    }

    // MARK: - Load Profile

    private func loadProfile() async {
        isLoading = true
        do {
            profile = try await ProfileService.getProfile()
        } catch {
            print("[ProfileScreen] Error loading profile: \(error)")
        }
        isLoading = false
    }

    // MARK: - Resubscribe (direct purchase, no trial)

    private func handleResubscribe() {
        isPurchasing = true
        Task {
            if let plan = subscription.availablePlans.first {
                let _ = try? await subscription.purchase(plan: plan)
            }
            isPurchasing = false
        }
    }
}

// MARK: - Cancellation View (3-step flow)

struct CancellationView: View {
    var onCancelled: (() -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @State private var step = 0
    @State private var selectedReason: String? = nil
    @State private var detailText = ""

    var body: some View {
        NavigationStack {
            Group {
                switch step {
                case 0: reasonStep
                case 1: detailStep
                default: confirmedStep
                }
            }
            .background(Color.coffeeBackground)
            .navigationTitle(step < 2 ? "Cancelar assinatura" : "")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if step < 2 {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Fechar") { dismiss() }
                            .foregroundStyle(Color.coffeePrimary)
                    }
                }
            }
            .animation(.easeInOut(duration: 0.3), value: step)
        }
    }

    // MARK: Step 0 — Select Reason

    private var reasonStep: some View {
        ScrollView {
            VStack(spacing: 20) {
                VStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(Color.red.opacity(0.1))
                            .frame(width: 64, height: 64)
                        Image(systemName: "heart.slash.fill")
                            .font(.system(size: 28))
                            .foregroundStyle(.red.opacity(0.8))
                    }

                    Text("Sentiremos sua falta")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(Color.coffeeTextPrimary)

                    Text("Nos ajude a melhorar: por que deseja cancelar?")
                        .font(.system(size: 15))
                        .foregroundStyle(Color.coffeeTextSecondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.top, 16)
                .padding(.horizontal, 24)

                CoffeeCellGroup {
                    ForEach(Array(CancelReason.all.enumerated()), id: \.offset) { index, reason in
                        Button {
                            selectedReason = reason.label
                        } label: {
                            HStack(spacing: 14) {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .fill(Color.coffeeTextSecondary.opacity(0.08))
                                        .frame(width: 50, height: 50)
                                    Image(systemName: reason.icon)
                                        .font(.system(size: 20))
                                        .foregroundStyle(Color.coffeeTextSecondary)
                                }
                                Text(reason.label)
                                    .font(.system(size: 16))
                                    .foregroundStyle(Color.coffeeTextPrimary)
                                Spacer()
                                if selectedReason == reason.label {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.system(size: 22))
                                        .foregroundStyle(Color.coffeePrimary)
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 14)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)

                        if index < CancelReason.all.count - 1 {
                            Divider().padding(.leading, 82)
                        }
                    }
                }
                .padding(.horizontal, 16)

                CoffeeButton("Continuar") {
                    step = 1
                }
                .padding(.horizontal, 20)
                .disabled(selectedReason == nil)
                .opacity(selectedReason == nil ? 0.5 : 1)

                Button("Voltar, mudei de ideia") {
                    dismiss()
                }
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color.coffeePrimary)
                .padding(.bottom, 20)
            }
        }
    }

    // MARK: Step 1 — Detail Text

    private var detailStep: some View {
        ScrollView {
            VStack(spacing: 20) {
                VStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(Color.coffeePrimary.opacity(0.1))
                            .frame(width: 64, height: 64)
                        Image(systemName: "text.bubble.fill")
                            .font(.system(size: 28))
                            .foregroundStyle(Color.coffeePrimary)
                    }

                    Text("Conte-nos mais")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(Color.coffeeTextPrimary)

                    Text("Sua opinião nos ajuda a melhorar o COFFEE.")
                        .font(.system(size: 15))
                        .foregroundStyle(Color.coffeeTextSecondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.top, 16)
                .padding(.horizontal, 24)

                // Selected reason badge
                if let reason = selectedReason {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(Color.coffeePrimary)
                        Text(reason)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Color.coffeePrimary)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Color.coffeePrimary.opacity(0.1))
                    .clipShape(Capsule())
                }

                // Text editor
                VStack(alignment: .leading, spacing: 8) {
                    Text("DETALHES (OBRIGATÓRIO)")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.coffeeTextSecondary)
                        .padding(.horizontal, 20)

                    TextEditor(text: $detailText)
                        .font(.system(size: 15))
                        .tint(Color.coffeePrimary)
                        .frame(minHeight: 120)
                        .padding(12)
                        .scrollContentBackground(.hidden)
                        .background(Color.coffeeCardBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(Color.coffeeSeparator, lineWidth: 0.5)
                        )
                        .overlay(alignment: .topLeading) {
                            if detailText.isEmpty {
                                Text("Explique o motivo do cancelamento...")
                                    .font(.system(size: 15))
                                    .foregroundStyle(Color.coffeeTextSecondary.opacity(0.5))
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 20)
                                    .allowsHitTesting(false)
                            }
                        }
                }
                .padding(.horizontal, 16)

                CoffeeButton("Confirmar cancelamento", style: .destructive) {
                    onCancelled?()
                    step = 2
                }
                .padding(.horizontal, 20)
                .disabled(detailText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .opacity(detailText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.5 : 1)

                Button {
                    step = 0
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 12))
                        Text("Voltar")
                    }
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.coffeePrimary)
                }
                .padding(.bottom, 20)
            }
        }
    }

    // MARK: Step 2 — Confirmed

    private var confirmedStep: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 20) {
                ZStack {
                    Circle()
                        .fill(Color.green.opacity(0.1))
                        .frame(width: 80, height: 80)
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 44))
                        .foregroundStyle(.green)
                }

                Text("Assinatura cancelada")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(Color.coffeeTextPrimary)

                Text("Seu plano permanece ativo até o final do período já pago. Você pode reativar a qualquer momento.")
                    .font(.system(size: 15))
                    .foregroundStyle(Color.coffeeTextSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }

            Spacer()

            CoffeeButton("Fechar") {
                dismiss()
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 40)
        }
    }
}

#Preview {
    ProfileScreenView()
        .environment(\.router, NavigationRouter())
}
