import SwiftUI

// MARK: - Coffee Text Field
// iOS-style input matching .ios-input from index.css
// Height: 44pt, rounded corners, system gray fill

struct CoffeeTextField: View {
    let placeholder: String
    @Binding var text: String
    var icon: String? = nil
    var isSecure: Bool = false
    var keyboardType: UIKeyboardType = .default
    var textContentType: UITextContentType? = nil
    var autocapitalization: TextInputAutocapitalization = .sentences
    var onSubmit: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 10) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 17))
                    .foregroundStyle(Color.coffeeTextTertiary)
                    .frame(width: 20)
            }

            if isSecure {
                SecureField(placeholder, text: $text)
                    .font(.coffeeBody)
                    .textContentType(textContentType)
                    .onSubmit { onSubmit?() }
            } else {
                TextField(placeholder, text: $text)
                    .font(.coffeeBody)
                    .keyboardType(keyboardType)
                    .textContentType(textContentType)
                    .textInputAutocapitalization(autocapitalization)
                    .onSubmit { onSubmit?() }
            }

            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(Color.coffeeTextTertiary)
                }
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 44)
        .background(Color.coffeeInputBackground)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .tint(Color.coffeePrimary)
    }
}

// MARK: - Text Area Variant

struct CoffeeTextArea: View {
    let placeholder: String
    @Binding var text: String
    var minHeight: CGFloat = 100

    var body: some View {
        ZStack(alignment: .topLeading) {
            if text.isEmpty {
                Text(placeholder)
                    .font(.coffeeBody)
                    .foregroundStyle(Color.coffeeTextPlaceholder)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
            }

            TextEditor(text: $text)
                .font(.coffeeBody)
                .scrollContentBackground(.hidden)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .tint(Color.coffeePrimary)
        }
        .frame(minHeight: minHeight)
        .background(Color.coffeeInputBackground)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

// MARK: - Preview

#Preview("Text Fields") {
    VStack(spacing: 16) {
        CoffeeTextField(
            placeholder: "Email",
            text: .constant(""),
            icon: "envelope",
            keyboardType: .emailAddress
        )

        CoffeeTextField(
            placeholder: "Senha",
            text: .constant("teste123"),
            icon: "lock",
            isSecure: true
        )

        CoffeeTextField(
            placeholder: "Nome completo",
            text: .constant("Gabriel Santos"),
            icon: "person"
        )

        CoffeeTextArea(
            placeholder: "Mensagem opcional...",
            text: .constant("")
        )
    }
    .padding(20)
    .background(Color.coffeeBackground)
}
