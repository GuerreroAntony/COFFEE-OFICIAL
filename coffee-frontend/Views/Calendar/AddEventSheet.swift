import SwiftUI

// MARK: - Add Event Sheet
// Form to create a manual calendar event

struct AddEventSheet: View {
    let disciplines: [Discipline]
    let onSave: (String, Date, Date?, Bool, String, String?, String?) -> Void
    let onClose: () -> Void

    @State private var title = ""
    @State private var date = Date()
    @State private var endDate = Date()
    @State private var hasEndDate = false
    @State private var allDay = false
    @State private var eventType = "event"
    @State private var description = ""
    @State private var selectedDisciplinaId: String? = nil
    @State private var isSaving = false

    private let eventTypes = [
        ("event", "Evento", "calendar"),
        ("exam", "Prova", "pencil.line"),
        ("deadline", "Prazo", "clock.fill"),
        ("reminder", "Lembrete", "bell.fill"),
    ]

    var body: some View {
        VStack(spacing: 0) {
            CoffeeSheetHeader(title: "Novo Evento", onClose: onClose)

            ScrollView {
                VStack(spacing: 20) {
                    // Title
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Título")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Color.coffeeTextSecondary)

                        TextField("Ex: Prova de Marketing", text: $title)
                            .font(.system(size: 16))
                            .padding(12)
                            .background(Color.coffeeInputBackground)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                            .tint(Color.coffeePrimary)
                    }

                    // Event Type
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Tipo")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Color.coffeeTextSecondary)

                        HStack(spacing: 8) {
                            ForEach(eventTypes, id: \.0) { type in
                                let isActive = eventType == type.0
                                Button {
                                    eventType = type.0
                                } label: {
                                    HStack(spacing: 6) {
                                        Image(systemName: type.2)
                                            .font(.system(size: 12))
                                        Text(type.1)
                                            .font(.system(size: 13, weight: .medium))
                                    }
                                    .foregroundStyle(isActive ? .white : Color.coffeeTextPrimary)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .background(isActive ? Color.coffeePrimary : Color.coffeeInputBackground)
                                    .clipShape(Capsule())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    // Date & Time
                    VStack(alignment: .leading, spacing: 12) {
                        Toggle(isOn: $allDay) {
                            Text("Dia todo")
                                .font(.system(size: 15))
                                .foregroundStyle(Color.coffeeTextPrimary)
                        }
                        .tint(Color.coffeePrimary)

                        if allDay {
                            DatePicker("Data", selection: $date, displayedComponents: .date)
                                .tint(Color.coffeePrimary)
                        } else {
                            DatePicker("Início", selection: $date, displayedComponents: [.date, .hourAndMinute])
                                .tint(Color.coffeePrimary)

                            Toggle(isOn: $hasEndDate) {
                                Text("Horário de fim")
                                    .font(.system(size: 15))
                                    .foregroundStyle(Color.coffeeTextPrimary)
                            }
                            .tint(Color.coffeePrimary)

                            if hasEndDate {
                                DatePicker("Fim", selection: $endDate, in: date..., displayedComponents: [.date, .hourAndMinute])
                                    .tint(Color.coffeePrimary)
                            }
                        }
                    }
                    .padding(16)
                    .background(Color.coffeeCardBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(Color.coffeeSeparator, lineWidth: 0.5)
                    )

                    // Discipline picker
                    if !disciplines.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Disciplina (opcional)")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(Color.coffeeTextSecondary)

                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 8) {
                                    // None option
                                    chipButton(label: "Nenhuma", isActive: selectedDisciplinaId == nil) {
                                        selectedDisciplinaId = nil
                                    }

                                    ForEach(disciplines, id: \.id) { disc in
                                        chipButton(label: disc.nome, isActive: selectedDisciplinaId == disc.id) {
                                            selectedDisciplinaId = disc.id
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // Description
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Descrição (opcional)")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Color.coffeeTextSecondary)

                        TextField("Detalhes do evento...", text: $description, axis: .vertical)
                            .font(.system(size: 15))
                            .lineLimit(3...6)
                            .padding(12)
                            .background(Color.coffeeInputBackground)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                            .tint(Color.coffeePrimary)
                    }

                    // Save button
                    Button {
                        isSaving = true
                        onSave(
                            title,
                            date,
                            hasEndDate ? endDate : nil,
                            allDay,
                            eventType,
                            description.isEmpty ? nil : description,
                            selectedDisciplinaId
                        )
                    } label: {
                        HStack(spacing: 8) {
                            if isSaving {
                                ProgressView()
                                    .tint(.white)
                            }
                            Text("Salvar evento")
                                .font(.system(size: 17, weight: .semibold))
                        }
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(title.isEmpty ? Color.coffeePrimary.opacity(0.4) : Color.coffeePrimary)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .disabled(title.isEmpty || isSaving)
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 40)
            }
        }
        .background(Color.coffeeBackground)
    }

    private func chipButton(label: String, isActive: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(isActive ? .white : Color.coffeeTextPrimary)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(isActive ? Color.coffeePrimary : Color.coffeeInputBackground)
                .clipShape(Capsule())
                .lineLimit(1)
        }
        .buttonStyle(.plain)
    }
}
