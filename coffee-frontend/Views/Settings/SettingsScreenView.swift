import SwiftUI

// MARK: - Settings Screen
// App settings, about, legal, contact
// Matches Settings section from the React app

struct SettingsScreenView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.router) private var router

    @State private var showTerms = false
    @State private var showPrivacy = false
    @State private var showContact = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Perfil
                    CoffeeSectionHeader(title: "Conta")
                        .padding(.horizontal, 20)

                    CoffeeCellGroup {
                        NavigationLink {
                            ProfileScreenView()
                        } label: {
                            CoffeeCell(
                                icon: "person.fill",
                                title: "Perfil",
                                subtitle: router.currentUser?.email ?? "",
                                trailing: .chevron
                            )
                        }
                        .buttonStyle(CoffeeCellButtonStyle())
                    }
                    .padding(.horizontal, 16)

                    // Sobre
                    CoffeeSectionHeader(title: "Sobre")
                        .padding(.horizontal, 20)

                    CoffeeCellGroup {
                        Button { showTerms = true } label: {
                            CoffeeCell(
                                icon: "doc.text.fill",
                                title: "Termos de Uso",
                                subtitle: nil,
                                trailing: .chevron
                            )
                        }
                        .buttonStyle(CoffeeCellButtonStyle())

                        Button { showPrivacy = true } label: {
                            CoffeeCell(
                                icon: CoffeeIcon.lock,
                                title: "Política de Privacidade",
                                subtitle: nil,
                                trailing: .chevron
                            )
                        }
                        .buttonStyle(CoffeeCellButtonStyle())

                        Button { showContact = true } label: {
                            CoffeeCell(
                                icon: "envelope.fill",
                                title: "Fale Conosco",
                                subtitle: "suporte@mdwbravo.com.br",
                                trailing: .chevron
                            )
                        }
                        .buttonStyle(CoffeeCellButtonStyle())

                        CoffeeCell(
                            icon: "info.circle.fill",
                            title: "Versão",
                            subtitle: nil,
                            trailing: .text("1.0.0 (1)")
                        )
                    }
                    .padding(.horizontal, 16)

                    VStack(spacing: 10) {
                        Text("Criado por:")
                            .font(.system(size: 15))
                            .foregroundStyle(Color.coffeeTextSecondary)
                        Text("Antony Marques Guerrero")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(Color.coffeeTextSecondary)
                        Text("Leonardo Di Giglio Millan")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(Color.coffeeTextSecondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 12)
                }
                .padding(.bottom, 40)
            }
            .background(Color.coffeeBackground)
            .navigationTitle("Configurações")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Fechar") { dismiss() }
                        .foregroundStyle(Color.coffeePrimary)
                }
            }
            .sheet(isPresented: $showTerms) {
                LegalDocView(title: "Termos de Uso", sections: [
                    ("1. Aceitação", "Ao usar o COFFEE, você concorda com estes termos de uso. Se não concordar, por favor não use o aplicativo."),
                    ("2. Serviço", "O COFFEE é uma plataforma educacional que grava, transcreve e resume aulas usando inteligência artificial."),
                    ("3. Conta do Usuário", "Você é responsável por manter a segurança da sua conta e senha. O COFFEE não se responsabiliza por acessos não autorizados."),
                    ("4. Propriedade Intelectual", "O conteúdo gerado (transcrições, resumos, mapas mentais) pertence ao usuário. O COFFEE não reivindica propriedade."),
                    ("5. Privacidade", "Seus dados são protegidos conforme a LGPD. Consulte a Política de Privacidade para detalhes."),
                ])
            }
            .sheet(isPresented: $showPrivacy) {
                LegalDocView(title: "Política de Privacidade", sections: [
                    ("Coleta de Dados", "Coletamos apenas os dados necessários para o funcionamento do app: nome, email, matrícula ESPM e gravações de áudio."),
                    ("Uso dos Dados", "Seus dados são usados exclusivamente para gerar transcrições, resumos e respostas do Barista IA."),
                    ("Armazenamento", "Áudio é processado localmente no dispositivo e nunca sai do seu iPhone. Transcrições e resumos são armazenados de forma segura. Credenciais ESPM não são armazenadas — utilizamos apenas tokens temporários."),
                    ("LGPD", "Você tem direito a acessar, corrigir e excluir seus dados. Envie solicitações para suporte@mdwbravo.com.br."),
                    ("Terceiros", "Usamos serviços de IA para processamento. Os dados são anonimizados antes do envio e não são usados para treinamento."),
                ])
            }
            .sheet(isPresented: $showContact) {
                ContactView()
            }
        }
    }
}

// MARK: - Legal Document View

struct LegalDocView: View {
    let title: String
    let sections: [(String, String)]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    ForEach(Array(sections.enumerated()), id: \.offset) { _, section in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(section.0)
                                .font(.system(size: 17, weight: .bold))
                                .foregroundStyle(Color.coffeeTextPrimary)
                            Text(section.1)
                                .font(.system(size: 15))
                                .foregroundStyle(Color.coffeeTextSecondary)
                                .lineSpacing(4)
                        }
                    }
                }
                .padding(20)
            }
            .background(Color.coffeeBackground)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Fechar") { dismiss() }
                        .foregroundStyle(Color.coffeePrimary)
                }
            }
        }
    }
}

// MARK: - Contact View

struct ContactView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var subject = ""
    @State private var message = ""
    @State private var isSending = false
    @State private var showSuccess = false
    @State private var errorMessage: String? = nil

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    if showSuccess {
                        // Success state
                        Spacer().frame(height: 60)
                        VStack(spacing: 20) {
                            ZStack {
                                Circle()
                                    .fill(Color.green.opacity(0.1))
                                    .frame(width: 80, height: 80)
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 44))
                                    .foregroundStyle(.green)
                            }

                            Text("Mensagem enviada!")
                                .font(.system(size: 22, weight: .bold))
                                .foregroundStyle(Color.coffeeTextPrimary)

                            Text("Responderemos o mais breve possível.")
                                .font(.system(size: 15))
                                .foregroundStyle(Color.coffeeTextSecondary)
                                .multilineTextAlignment(.center)

                            CoffeeButton("Fechar") {
                                dismiss()
                            }
                            .padding(.horizontal, 20)
                        }
                    } else {
                        // Form state
                        VStack(spacing: 12) {
                            ZStack {
                                Circle()
                                    .fill(Color.coffeePrimary.opacity(0.1))
                                    .frame(width: 64, height: 64)
                                Image(systemName: "envelope.fill")
                                    .font(.system(size: 28))
                                    .foregroundStyle(Color.coffeePrimary)
                            }

                            Text("Fale Conosco")
                                .font(.system(size: 22, weight: .bold))
                                .foregroundStyle(Color.coffeeTextPrimary)

                            Text("suporte@mdwbravo.com.br")
                                .font(.system(size: 15))
                                .foregroundStyle(Color.coffeePrimary)
                        }
                        .padding(.top, 16)

                        CoffeeCellGroup {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Assunto")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(Color.coffeeTextSecondary)
                                TextField("Como podemos ajudar?", text: $subject)
                                    .font(.coffeeBody)
                                    .tint(Color.coffeePrimary)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)

                            Divider()

                            VStack(alignment: .leading, spacing: 6) {
                                Text("Mensagem")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(Color.coffeeTextSecondary)
                                TextEditor(text: $message)
                                    .font(.coffeeBody)
                                    .tint(Color.coffeePrimary)
                                    .frame(minHeight: 120)
                                    .scrollContentBackground(.hidden)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                        }
                        .padding(.horizontal, 16)

                        if let error = errorMessage {
                            Text(error)
                                .font(.system(size: 13))
                                .foregroundStyle(.red)
                                .padding(.horizontal, 20)
                        }

                        CoffeeButton(isSending ? "Enviando..." : "Enviar") {
                            handleSend()
                        }
                        .padding(.horizontal, 20)
                        .disabled(subject.isEmpty || message.isEmpty || isSending)
                        .opacity(isSending ? 0.7 : 1)
                    }
                }
            }
            .background(Color.coffeeBackground)
            .navigationTitle("Contato")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Fechar") { dismiss() }
                        .foregroundStyle(Color.coffeePrimary)
                }
            }
            .animation(.easeInOut(duration: 0.3), value: showSuccess)
        }
    }

    // MARK: - Send Contact

    private func handleSend() {
        let trimmedSubject = subject.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedMessage = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedSubject.isEmpty, !trimmedMessage.isEmpty else { return }

        isSending = true
        errorMessage = nil

        Task {
            do {
                try await AccountService.contactSupport(subject: trimmedSubject, message: trimmedMessage)
                withAnimation { showSuccess = true }
            } catch {
                errorMessage = "Erro ao enviar mensagem. Tente novamente."
                print("[ContactView] Error sending: \(error)")
            }
            isSending = false
        }
    }
}

#Preview {
    SettingsScreenView()
        .environment(\.router, NavigationRouter())
}
