import SwiftUI

/// Reusable locked feature overlay — shows lock icon, message, and "Ver planos" button.
struct UpgradeGateView: View {
    let feature: PlanAccess.LockedFeature
    let onUpgrade: () -> Void

    private var info: (title: String, message: String, requiredPlan: String) {
        PlanAccess.upgradeMessage(for: feature)
    }

    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            ZStack {
                Circle()
                    .fill(Color.coffeePrimary.opacity(0.08))
                    .frame(width: 80, height: 80)

                Image(systemName: "lock.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(Color.coffeePrimary.opacity(0.6))
            }

            VStack(spacing: 8) {
                Text(info.title)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(Color.coffeeTextPrimary)

                Text(info.message)
                    .font(.system(size: 15))
                    .foregroundStyle(Color.coffeeTextSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }

            Button {
                onUpgrade()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 16))
                    Text("Ver planos")
                        .font(.system(size: 16, weight: .semibold))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 28)
                .padding(.vertical, 13)
                .background(Color.coffeePrimary)
                .clipShape(Capsule())
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
