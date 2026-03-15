import SwiftUI

// MARK: - Coffee Animations
// SwiftUI equivalents of CSS animations from index.css

// MARK: - Steam Animation (Splash screen logo)

struct SteamLine: View {
    let delay: Double
    @State private var animating = false

    var body: some View {
        Capsule()
            .fill(Color.coffeePrimary.opacity(0.4))
            .frame(width: 2, height: 12)
            .offset(y: animating ? -40 : 0)
            .scaleEffect(x: animating ? 1.5 : 1.0)
            .opacity(animating ? 0 : 0.5)
            .animation(
                .easeOut(duration: 2.0)
                .repeatForever(autoreverses: false)
                .delay(delay),
                value: animating
            )
            .onAppear { animating = true }
    }
}

struct SteamEffect: View {
    var body: some View {
        HStack(spacing: 6) {
            SteamLine(delay: 0)
            SteamLine(delay: 0.4)
            SteamLine(delay: 0.8)
        }
    }
}

// MARK: - Ripple Animation (Recording idle mic button)

struct RippleEffect: View {
    let color: Color
    let count: Int

    @State private var animating = false

    init(color: Color = .coffeePrimary, count: Int = 3) {
        self.color = color
        self.count = count
    }

    var body: some View {
        ZStack {
            ForEach(0..<count, id: \.self) { index in
                Circle()
                    .stroke(color.opacity(0.3), lineWidth: 1.5)
                    .scaleEffect(animating ? 2.5 : 1.0)
                    .opacity(animating ? 0 : 0.6)
                    .animation(
                        .easeOut(duration: 2.0)
                        .repeatForever(autoreverses: false)
                        .delay(Double(index) * 0.6),
                        value: animating
                    )
            }
        }
        .onAppear { animating = true }
    }
}

// MARK: - Waveform Animation (Recording active)

struct WaveformBar: View {
    let index: Int
    let color: Color
    @State private var height: CGFloat = 4

    var body: some View {
        RoundedRectangle(cornerRadius: 2)
            .fill(color)
            .frame(width: 3, height: height)
            .onAppear {
                withAnimation(
                    .easeInOut(duration: Double.random(in: 0.3...0.7))
                    .repeatForever(autoreverses: true)
                    .delay(Double(index) * 0.05)
                ) {
                    height = CGFloat.random(in: 8...32)
                }
            }
    }
}

struct WaveformView: View {
    let barCount: Int
    let color: Color

    init(barCount: Int = 40, color: Color = .coffeePrimaryLight) {
        self.barCount = barCount
        self.color = color
    }

    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<barCount, id: \.self) { index in
                WaveformBar(index: index, color: color)
            }
        }
        .frame(height: 32)
    }
}

// MARK: - Shimmer Effect (Premium buttons — coffee-wave from CSS)

struct ShimmerModifier: ViewModifier {
    @State private var phase: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .overlay(
                LinearGradient(
                    gradient: Gradient(colors: [
                        Color.clear,
                        Color.white.opacity(0.15),
                        Color.clear
                    ]),
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .offset(x: phase)
                .allowsHitTesting(false)
                .onAppear {
                    withAnimation(
                        .linear(duration: 3.0)
                        .repeatForever(autoreverses: false)
                    ) {
                        phase = 400
                    }
                }
            )
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

extension View {
    func coffeeShimmer() -> some View {
        modifier(ShimmerModifier())
    }
}

// MARK: - Typing Indicator (AI Chat)

struct TypingIndicator: View {
    @State private var dotScales: [CGFloat] = [1, 1, 1]

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .fill(Color.coffeeTextSecondary)
                    .frame(width: 8, height: 8)
                    .scaleEffect(dotScales[index])
                    .animation(
                        .easeInOut(duration: 0.6)
                        .repeatForever(autoreverses: true)
                        .delay(Double(index) * 0.2),
                        value: dotScales[index]
                    )
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(Color(hex: "E9E9EB"))
        .clipShape(ChatBubbleShape(isFromUser: false))
        .onAppear {
            dotScales = [0.5, 0.5, 0.5]
        }
    }
}

// MARK: - Chat Bubble Shape

struct ChatBubbleShape: Shape {
    let isFromUser: Bool

    func path(in rect: CGRect) -> Path {
        let radius: CGFloat = 18
        let smallRadius: CGFloat = 4

        var path = Path()

        if isFromUser {
            // User bubble: all corners rounded except bottom-right
            path.addRoundedRect(
                in: rect,
                cornerRadii: .init(
                    topLeading: radius,
                    bottomLeading: radius,
                    bottomTrailing: smallRadius,
                    topTrailing: radius
                )
            )
        } else {
            // AI bubble: all corners rounded except bottom-left
            path.addRoundedRect(
                in: rect,
                cornerRadii: .init(
                    topLeading: radius,
                    bottomLeading: smallRadius,
                    bottomTrailing: radius,
                    topTrailing: radius
                )
            )
        }

        return path
    }
}

// MARK: - Fade In Animation

struct FadeInModifier: ViewModifier {
    @State private var opacity: Double = 0
    let delay: Double

    func body(content: Content) -> some View {
        content
            .opacity(opacity)
            .onAppear {
                withAnimation(.easeIn(duration: 0.4).delay(delay)) {
                    opacity = 1
                }
            }
    }
}

extension View {
    func fadeIn(delay: Double = 0) -> some View {
        modifier(FadeInModifier(delay: delay))
    }
}

// MARK: - Pulse Animation

struct PulseModifier: ViewModifier {
    @State private var scale: CGFloat = 1

    func body(content: Content) -> some View {
        content
            .scaleEffect(scale)
            .onAppear {
                withAnimation(
                    .easeInOut(duration: 1.0)
                    .repeatForever(autoreverses: true)
                ) {
                    scale = 1.05
                }
            }
    }
}

extension View {
    func coffeePulse() -> some View {
        modifier(PulseModifier())
    }
}
