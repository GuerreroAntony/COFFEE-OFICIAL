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

// MARK: - Waveform Animation (Recording active — responsive to audio)
// Static bar positions — bars only grow/shrink vertically with audio level.
// No lateral wave movement. Each bar has a fixed random-looking height pattern.

struct WaveformBar: View {
    let index: Int
    let barCount: Int
    let color: Color
    let audioLevel: Float

    // Fixed per-bar pattern (seeded by index, no time dependency = no lateral movement)
    private var fixedPattern: Double {
        // Deterministic "random" height per bar using golden ratio hash
        let golden = 0.618033988749895
        let hash = (Double(index) * golden).truncatingRemainder(dividingBy: 1.0)
        return hash
    }

    private var targetHeight: CGFloat {
        let minH: CGFloat = 4
        let maxH: CGFloat = 48
        let pos = Double(index) / Double(max(barCount - 1, 1))

        // Base shape: center bars taller, edges shorter (like reference image)
        let centerCurve = 1.0 - pow(abs(pos - 0.5) * 2.0, 1.5)
        let base = 0.08 + centerCurve * 0.12

        // Per-bar fixed variation (gives irregular look without movement)
        let variation = fixedPattern * 0.15

        // Audio response: scales all bars proportionally
        let audioScale = Double(audioLevel) * centerCurve * 0.7
        let barVariation = fixedPattern * Double(audioLevel) * 0.3

        let level = max(0, min(1, base + variation + audioScale + barVariation))
        return minH + CGFloat(level) * (maxH - minH)
    }

    var body: some View {
        RoundedRectangle(cornerRadius: 2.5)
            .fill(color)
            .frame(width: 3.5, height: targetHeight)
            .animation(.easeOut(duration: 0.15), value: audioLevel)
    }
}

struct WaveformView: View {
    let barCount: Int
    let color: Color
    var audioLevel: Float

    init(barCount: Int = 40, color: Color = .coffeePrimaryLight, audioLevel: Float = 0) {
        self.barCount = barCount
        self.color = color
        self.audioLevel = audioLevel
    }

    var body: some View {
        HStack(spacing: 2.5) {
            ForEach(0..<barCount, id: \.self) { index in
                WaveformBar(
                    index: index,
                    barCount: barCount,
                    color: color,
                    audioLevel: audioLevel
                )
            }
        }
        .frame(height: 48)
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

// MARK: - Barista Avatar (reusable AI identity icon)

struct BaristaAvatar: View {
    var size: CGFloat = 28
    var body: some View {
        ZStack {
            Circle()
                .fill(Color.coffeePrimary.opacity(0.1))
                .frame(width: size, height: size)
            Image(systemName: "cup.and.saucer.fill")
                .font(.system(size: size * 0.46))
                .foregroundStyle(Color.coffeePrimary)
        }
    }
}

// MARK: - Thinking Steps (AI Chat — replaces TypingIndicator)

struct ThinkingStepsView: View {
    private let steps = [
        "Preparando sua resposta...",
        "Buscando nos seus materiais...",
        "Analisando transcrições...",
        "Formulando resposta..."
    ]

    @State private var currentStep = 0
    @State private var opacity: Double = 0

    let timer = Timer.publish(every: 2.0, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Divider()
                .padding(.bottom, 16)

            HStack(spacing: 8) {
                BaristaAvatar(size: 28)
                Text(steps[currentStep])
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Color.coffeeTextSecondary)
                    .opacity(opacity)
            }
        }
        .onAppear {
            withAnimation(.easeIn(duration: 0.4)) { opacity = 1 }
        }
        .onReceive(timer) { _ in
            withAnimation(.easeInOut(duration: 0.3)) { opacity = 0 }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                currentStep = (currentStep + 1) % steps.count
                withAnimation(.easeInOut(duration: 0.3)) { opacity = 1 }
            }
        }
    }
}
