import SwiftUI

// MARK: - Splash Screen
// Full-screen coffee-colored splash with logo + steam + CTA
// Matches SplashScreen from AuthScreens.jsx

struct SplashScreenView: View {
    @Environment(\.router) private var router
    @State private var showButton = false

    var body: some View {
        ZStack {
            // Background gradient
            LinearGradient(
                colors: [
                    Color.coffeePrimary,
                    Color(hex: "5A3E28")
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            // Dark overlay at top
            VStack {
                LinearGradient(
                    colors: [.black.opacity(0.1), .clear],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 200)
                Spacer()
            }
            .ignoresSafeArea()

            // Center: Full Logo
            VStack(spacing: 20) {
                Spacer()

                // Full logo (cup + coffee text)
                Image("logo-wide")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(height: 110)

                Text("Seu caderno automático de aulas.")
                    .font(.system(size: 22))
                    .foregroundStyle(.white.opacity(0.7))

                Spacer()

                // CTA button
                if showButton {
                    Button {
                        withAnimation {
                            router.authState = .onboarding
                        }
                    } label: {
                        Text("Começar agora")
                            .font(.coffeeButton)
                            .foregroundStyle(Color.coffeePrimary)
                            .frame(maxWidth: .infinity)
                            .frame(height: 50)
                            .background(.white.opacity(0.95))
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .padding(.horizontal, 20)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }

                Spacer().frame(height: 32)
            }
        }
        .onAppear {
            // Only show button for non-logged-in users
            // Logged-in users will auto-transition to .authenticated
            if !KeychainManager.isLoggedIn {
                withAnimation(.easeOut(duration: 0.6).delay(1.0)) {
                    showButton = true
                }
            }
        }
    }
}

#Preview {
    SplashScreenView()
        .environment(\.router, NavigationRouter())
}
