import SwiftUI

struct AISettingsView: View {
    @Binding var personality: PersonalityConfig
    @Environment(\.dismiss) private var dismiss
    @State private var activeProfile: PersonalityProfile? = nil

    var body: some View {
        ZStack {
            CoffeeTheme.Colors.background.ignoresSafeArea()

            VStack(spacing: 0) {
                // Header
                HStack {
                    Text("personalizar ia")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(CoffeeTheme.Colors.espresso)

                    Spacer()

                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(CoffeeTheme.Colors.almond)
                            .frame(width: 32, height: 32)
                            .background(CoffeeTheme.Colors.vanilla)
                            .clipShape(Circle())
                    }
                }
                .padding(.horizontal, CoffeeTheme.Spacing.lg)
                .padding(.top, CoffeeTheme.Spacing.lg)
                .padding(.bottom, CoffeeTheme.Spacing.md)

                ScrollView {
                    VStack(alignment: .leading, spacing: CoffeeTheme.Spacing.md) {
                        Text("estilo de resposta")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(CoffeeTheme.Colors.almond)
                            .textCase(.uppercase)
                            .tracking(0.5)

                        VStack(spacing: CoffeeTheme.Spacing.sm) {
                            ForEach(PersonalityProfile.allCases) { profile in
                                ProfileCard(
                                    profile: profile,
                                    isActive: activeProfile == profile
                                ) {
                                    activeProfile = profile
                                    personality = profile.config
                                }
                            }
                        }
                    }
                    .padding(.horizontal, CoffeeTheme.Spacing.lg)
                    .padding(.bottom, CoffeeTheme.Spacing.xl)
                }

                // Apply button
                CoffeeButton(title: "aplicar") {
                    dismiss()
                }
                .padding(.horizontal, CoffeeTheme.Spacing.lg)
                .padding(.bottom, CoffeeTheme.Spacing.lg)
            }
        }
    }
}

// MARK: - ProfileCard

private struct ProfileCard: View {
    let profile: PersonalityProfile
    let isActive: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: CoffeeTheme.Spacing.md) {
                Image(systemName: profile.icon)
                    .font(.system(size: 22))
                    .foregroundColor(isActive ? .white : CoffeeTheme.Colors.espresso)
                    .frame(width: 32)

                VStack(alignment: .leading, spacing: 2) {
                    Text(profile.label)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(isActive ? .white : CoffeeTheme.Colors.espresso)

                    Text(profile.description)
                        .font(.system(size: 12))
                        .foregroundColor(isActive ? .white.opacity(0.8) : CoffeeTheme.Colors.almond)
                        .lineLimit(1)
                }

                Spacer()

                if isActive {
                    Image(systemName: "checkmark")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)
                }
            }
            .padding(CoffeeTheme.Spacing.md)
            .background(isActive ? CoffeeTheme.Colors.coffee : .white)
            .clipShape(RoundedRectangle(cornerRadius: CoffeeTheme.Radius.md))
            .overlay(
                RoundedRectangle(cornerRadius: CoffeeTheme.Radius.md)
                    .stroke(
                        isActive ? Color.clear : CoffeeTheme.Colors.vanilla,
                        lineWidth: 1.5
                    )
            )
        }
        .buttonStyle(.plain)
    }
}
