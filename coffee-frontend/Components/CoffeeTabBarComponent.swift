import SwiftUI

// MARK: - Coffee Tab Bar (Final Version)
// iOS-style tab bar matching .tab-bar from index.css
// 3 items: Disciplinas | FAB (Logo) | Barista IA
// The FAB floats above the bar with the COFFEE logo

struct CoffeeTabBarFinal: View {
    @Environment(\.router) private var router
    @Environment(\.subscriptionService) private var subscription

    var body: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(Color.coffeeSeparator)
                .frame(height: 0.5)

            HStack(alignment: .bottom, spacing: 0) {
                // Home tab
                tabItem(
                    icon: CoffeeIcon.home,
                    filledIcon: "book.fill",
                    label: "Disciplinas",
                    tab: .home
                )

                // FAB button (centered, same height as others)
                fabButton

                // AI tab
                tabItem(
                    icon: CoffeeIcon.barista,
                    filledIcon: CoffeeIcon.barista,
                    label: "Barista",
                    tab: .ai,
                    locked: !subscription.isPremium
                )
            }
            .padding(.vertical, 10)
        }
        .background(
            Rectangle()
                .fill(.ultraThinMaterial)
                .ignoresSafeArea(edges: .bottom)
        )
    }

    // MARK: - Tab Item

    private func tabItem(icon: String, filledIcon: String, label: String, tab: NavigationRouter.Tab, locked: Bool = false) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                router.switchTab(tab)
            }
        } label: {
            VStack(spacing: 3) {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: router.activeTab == tab ? filledIcon : icon)
                        .font(.system(size: 26))
                        .symbolRenderingMode(.monochrome)

                    if locked {
                        lockBadge
                            .offset(x: 8, y: -6)
                    }
                }
                .frame(height: 64)

                Text(label)
                    .font(.coffeeTabLabel)
            }
            .foregroundStyle(
                router.activeTab == tab
                ? Color.coffeePrimary
                : Color.coffeeTabInactive
            )
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Lock Badge

    private var lockBadge: some View {
        Image(systemName: "lock.fill")
            .font(.system(size: 8, weight: .bold))
            .foregroundStyle(.white)
            .padding(3.5)
            .background(Color.coffeeTextSecondary.opacity(0.8))
            .clipShape(Circle())
    }

    // MARK: - FAB Button

    private var fabButton: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                router.switchTab(.record)
            }
        } label: {
            VStack(spacing: 3) {
                ZStack {
                    Circle()
                        .fill(Color.coffeePrimary)
                        .frame(width: 64, height: 64)
                        .shadow(color: Color.coffeePrimary.opacity(0.3), radius: 6, y: 2)

                    Image("coffee-logo")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 34, height: 34)
                        .foregroundStyle(.white)

                    // Lock badge when not premium
                    if !subscription.isPremium {
                        lockBadge
                            .offset(x: 22, y: -22)
                    }
                }

                Text("Gravar")
                    .font(.coffeeTabLabel)
                    .foregroundStyle(Color.coffeePrimary)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(FABButtonStyle())
    }
}

// MARK: - FAB Button Style

private struct FABButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.94 : 1.0)
            .animation(.easeInOut(duration: 0.15), value: configuration.isPressed)
    }
}

// MARK: - Preview

#Preview("Tab Bar") {
    VStack {
        Spacer()
        Text("Content Area")
            .foregroundStyle(.secondary)
        Spacer()

        CoffeeTabBarFinal()
    }
    .background(Color.coffeeBackground)
    .environment(\.router, NavigationRouter.preview)
}
