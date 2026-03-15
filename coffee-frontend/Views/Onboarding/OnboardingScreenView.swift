import SwiftUI

// MARK: - Onboarding View
// 3-step carousel matching Onboarding.jsx
// Each step: icon + title + description + dots + Next/Start button

struct OnboardingScreenView: View {
    @Environment(\.router) private var router
    @State private var currentStep = 0

    private let steps: [(icon: String, title: String, description: String)] = [
        (CoffeeIcon.school, "Conecte sua conta ESPM", "Vamos importar sua grade e materiais automaticamente. Suas credenciais são criptografadas."),
        (CoffeeIcon.mic, "Grave suas aulas", "Com um toque, grave e transcreva suas aulas automaticamente com inteligência artificial."),
        (CoffeeIcon.sparkles, "Consulte o Barista", "Receba resumos, conceitos-chave e respostas sobre suas aulas gravadas."),
    ]

    var body: some View {
        VStack(spacing: 0) {
            // Skip button
            HStack {
                Spacer()
                if currentStep < steps.count - 1 {
                    Button("Pular") {
                        router.completeOnboarding()
                    }
                    .font(.coffeeBody)
                    .foregroundStyle(Color.coffeePrimary)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .frame(height: 44)

            Spacer()

            // Content
            TabView(selection: $currentStep) {
                ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                    VStack(spacing: 0) {
                        // Icon container
                        ZStack {
                            RoundedRectangle(cornerRadius: 24, style: .continuous)
                                .fill(Color.coffeePrimary.opacity(0.1))
                                .frame(width: 96, height: 96)

                            Image(systemName: step.icon)
                                .font(.system(size: 44))
                                .foregroundStyle(Color.coffeePrimary)
                        }
                        .padding(.bottom, 40)

                        // Title
                        Text(step.title)
                            .font(.coffeeTitle)
                            .foregroundStyle(Color.coffeeTextPrimary)
                            .multilineTextAlignment(.center)
                            .padding(.bottom, 16)

                        // Description
                        Text(step.description)
                            .font(.coffeeBody)
                            .foregroundStyle(Color.coffeeTextSecondary)
                            .multilineTextAlignment(.center)
                            .lineSpacing(4)
                            .frame(maxWidth: 300)
                    }
                    .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))

            Spacer()

            // Page dots
            CoffeeProgressDots(total: steps.count, current: currentStep)
                .padding(.bottom, 40)

            // Next / Start button
            CoffeeButton(
                currentStep < steps.count - 1 ? "Próximo" : "Começar"
            ) {
                if currentStep < steps.count - 1 {
                    withAnimation {
                        currentStep += 1
                    }
                } else {
                    router.completeOnboarding()
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 32)
        }
        .background(Color.coffeeBackground)
    }
}

#Preview {
    OnboardingScreenView()
        .environment(\.router, NavigationRouter())
}
