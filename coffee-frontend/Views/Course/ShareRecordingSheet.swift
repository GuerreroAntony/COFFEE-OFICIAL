import SwiftUI

// MARK: - Share Recording Sheet
// Two-step in-app share: 1) Select content → 2) Enter recipient email

struct ShareRecordingSheet: View {
    let recordingId: String
    let hasResumo: Bool
    let hasMindMap: Bool

    @Environment(\.dismiss) private var dismiss

    @State private var step = 1
    @State private var shareResumo = true
    @State private var shareMapa = true
    @State private var emails: [String] = []
    @State private var currentEmail = ""
    @State private var isSending = false
    @State private var showSuccess = false
    @State private var errorMessage: String? = nil

    var body: some View {
        VStack(spacing: 0) {
            if showSuccess {
                successView
            } else if step == 1 {
                step1ContentSelection
            } else {
                step2EmailEntry
            }
        }
        .background(Color.coffeeBackground)
    }

    // MARK: - Step 1: Content Selection

    private var step1ContentSelection: some View {
        VStack(spacing: 0) {
            CoffeeSheetHeader(
                title: "Compartilhar",
                onClose: { dismiss() }
            )

            VStack(spacing: 20) {
                Text("Selecione o que deseja compartilhar desta aula:")
                    .font(.system(size: 15))
                    .foregroundStyle(Color.coffeeTextSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                    .padding(.top, 8)

                // Selection cards
                CoffeeCellGroup {
                    // Resumo option
                    if hasResumo {
                        Button {
                            shareResumo.toggle()
                        } label: {
                            shareOptionRow(
                                icon: CoffeeIcon.sparkles,
                                title: "Resumo",
                                subtitle: "Resumo gerado por IA",
                                isSelected: shareResumo
                            )
                        }
                        .buttonStyle(CoffeeCellButtonStyle())
                    }

                    if hasResumo && hasMindMap {
                        Divider().padding(.leading, 72)
                    }

                    // Mapa Mental option
                    if hasMindMap {
                        Button {
                            shareMapa.toggle()
                        } label: {
                            shareOptionRow(
                                icon: "rectangle.3.group",
                                title: "Mapa Mental",
                                subtitle: "Mapa mental da aula",
                                isSelected: shareMapa
                            )
                        }
                        .buttonStyle(CoffeeCellButtonStyle())
                    }
                }
                .padding(.horizontal, 16)

                Spacer()

                // Continue button
                CoffeeButton(
                    "Continuar",
                    isDisabled: !shareResumo && !shareMapa
                ) {
                    step = 2
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 40)
            }
        }
    }

    // MARK: - Step 2: Email Entry

    private var step2EmailEntry: some View {
        VStack(spacing: 0) {
            // Custom header with back button
            VStack(spacing: 0) {
                Capsule()
                    .fill(Color(red: 60/255, green: 60/255, blue: 67/255).opacity(0.3))
                    .frame(width: 36, height: 5)
                    .padding(.top, 10)
                    .padding(.bottom, 8)

                ZStack {
                    Text("Enviar para")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Color.coffeeTextPrimary)

                    HStack {
                        Button {
                            step = 1
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "chevron.left")
                                    .font(.system(size: 13, weight: .semibold))
                                Text("Voltar")
                                    .font(.system(size: 15, weight: .medium))
                            }
                            .foregroundStyle(Color.coffeePrimary)
                        }

                        Spacer()

                        Button("Fechar") { dismiss() }
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(Color.coffeePrimary)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 18)
            }

            VStack(spacing: 20) {
                Text("Digite o e-mail de cadastro da pessoa que deseja compartilhar:")
                    .font(.system(size: 15))
                    .foregroundStyle(Color.coffeeTextSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                    .padding(.top, 8)

                // Email input
                HStack(spacing: 10) {
                    HStack(spacing: 10) {
                        Image(systemName: "envelope")
                            .font(.system(size: 16))
                            .foregroundStyle(Color.coffeeTextSecondary.opacity(0.5))

                        TextField("email@exemplo.com", text: $currentEmail)
                            .font(.system(size: 15))
                            .keyboardType(.emailAddress)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                    .background(Color.coffeeInputBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                    // Add button
                    Button {
                        addEmail()
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Color.coffeePrimary)
                            .frame(width: 48, height: 48)
                            .background(Color.coffeePrimary.opacity(0.1))
                            .clipShape(Circle())
                    }
                    .disabled(currentEmail.trimmingCharacters(in: .whitespaces).isEmpty)
                    .opacity(currentEmail.trimmingCharacters(in: .whitespaces).isEmpty ? 0.4 : 1)
                }
                .padding(.horizontal, 20)

                // Added emails list
                if !emails.isEmpty {
                    VStack(spacing: 8) {
                        ForEach(emails, id: \.self) { email in
                            HStack {
                                Image(systemName: "person.circle.fill")
                                    .font(.system(size: 20))
                                    .foregroundStyle(Color.coffeePrimary.opacity(0.5))
                                Text(email)
                                    .font(.system(size: 14))
                                    .foregroundStyle(Color.coffeeTextPrimary)
                                Spacer()
                                Button {
                                    emails.removeAll { $0 == email }
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.system(size: 18))
                                        .foregroundStyle(Color.coffeeTextSecondary.opacity(0.4))
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background(Color.coffeeCardBackground)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        }
                    }
                    .padding(.horizontal, 20)
                }

                if let error = errorMessage {
                    Text(error)
                        .font(.system(size: 13))
                        .foregroundStyle(Color.coffeeDanger)
                        .padding(.horizontal, 20)
                }

                Spacer()

                // Share button
                CoffeeButton(
                    "Compartilhar",
                    isLoading: isSending,
                    isDisabled: emails.isEmpty && currentEmail.trimmingCharacters(in: .whitespaces).isEmpty
                ) {
                    handleShare()
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 40)
            }
        }
    }

    // MARK: - Success View

    private var successView: some View {
        VStack(spacing: 20) {
            Spacer()

            ZStack {
                Circle()
                    .fill(Color.coffeeSuccess.opacity(0.1))
                    .frame(width: 80, height: 80)
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(Color.coffeeSuccess)
            }

            Text("Compartilhado!")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(Color.coffeeTextPrimary)

            Text("A gravação foi compartilhada com sucesso.")
                .font(.system(size: 15))
                .foregroundStyle(Color.coffeeTextSecondary)
                .multilineTextAlignment(.center)

            Spacer()

            CoffeeButton("Fechar") {
                dismiss()
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 40)
        }
    }

    // MARK: - Option Row

    private func shareOptionRow(icon: String, title: String, subtitle: String, isSelected: Bool) -> some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.coffeePrimary.opacity(0.09))
                    .frame(width: 48, height: 48)
                Image(systemName: icon)
                    .font(.system(size: 20))
                    .foregroundStyle(Color.coffeePrimary)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.coffeeTextPrimary)
                Text(subtitle)
                    .font(.system(size: 13))
                    .foregroundStyle(Color.coffeeTextSecondary)
            }

            Spacer()

            // Checkmark
            ZStack {
                Circle()
                    .fill(isSelected ? Color.coffeePrimary : Color.clear)
                    .frame(width: 26, height: 26)
                    .overlay(
                        Circle()
                            .stroke(isSelected ? Color.coffeePrimary : Color.coffeeTextSecondary.opacity(0.3), lineWidth: 1.5)
                    )

                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.white)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .contentShape(Rectangle())
    }

    // MARK: - Actions

    private func addEmail() {
        let email = currentEmail.trimmingCharacters(in: .whitespaces).lowercased()
        guard !email.isEmpty, !emails.contains(email) else { return }
        emails.append(email)
        currentEmail = ""
    }

    private func handleShare() {
        // Add current email if typed but not yet added
        if !currentEmail.trimmingCharacters(in: .whitespaces).isEmpty {
            addEmail()
        }

        guard !emails.isEmpty else { return }

        var content: [String] = []
        if shareResumo { content.append("resumo") }
        if shareMapa { content.append("mapa") }

        isSending = true
        errorMessage = nil

        Task {
            do {
                let _ = try await DisciplineService.shareRecording(
                    gravacaoId: recordingId,
                    recipientEmails: emails,
                    sharedContent: content,
                    message: nil
                )
                isSending = false
                showSuccess = true
            } catch {
                isSending = false
                errorMessage = "Erro ao compartilhar. Tente novamente."
            }
        }
    }
}

// MARK: - Preview

#Preview {
    ShareRecordingSheet(
        recordingId: "rec1",
        hasResumo: true,
        hasMindMap: true
    )
}
