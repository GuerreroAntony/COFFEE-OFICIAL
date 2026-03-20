import SwiftUI

// MARK: - Skeleton Building Blocks
// Reusable shimmer placeholders that match real card shapes.
// Uses existing .coffeeShimmer() from CoffeeAnimations.swift.

/// A single skeleton rectangle with shimmer animation.
struct SkeletonBox: View {
    var width: CGFloat? = nil
    var height: CGFloat = 14
    var radius: CGFloat = 6

    var body: some View {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
            .fill(Color.coffeeTextSecondary.opacity(0.08))
            .frame(width: width, height: height)
            .coffeeShimmer()
    }
}

/// A circular skeleton with shimmer.
struct SkeletonCircle: View {
    var size: CGFloat = 44

    var body: some View {
        Circle()
            .fill(Color.coffeeTextSecondary.opacity(0.08))
            .frame(width: size, height: size)
            .coffeeShimmer()
    }
}

// MARK: - Discipline Card Skeleton
// Matches: 44×44 icon box + title (160pt) + subtitle (80pt) + chevron area

struct DisciplineCardSkeleton: View {
    var count: Int = 4

    var body: some View {
        CoffeeCellGroup {
            ForEach(0..<count, id: \.self) { index in
                HStack(spacing: 12) {
                    // Icon placeholder
                    SkeletonBox(width: 44, height: 44, radius: 10)

                    // Text placeholders
                    VStack(alignment: .leading, spacing: 6) {
                        SkeletonBox(width: 160, height: 14)
                        SkeletonBox(width: 80, height: 12)
                    }

                    Spacer()

                    // Chevron placeholder
                    SkeletonBox(width: 8, height: 14, radius: 3)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .frame(minHeight: 44)

                if index < count - 1 {
                    Rectangle()
                        .fill(Color.coffeeSeparator)
                        .frame(height: 0.5)
                        .padding(.leading, 72)
                }
            }
        }
    }
}

// MARK: - Recording Card Skeleton
// Matches: 50×50 icon box + date title + duration + status badge

struct RecordingCardSkeleton: View {
    var count: Int = 3

    var body: some View {
        CoffeeCellGroup {
            ForEach(0..<count, id: \.self) { index in
                HStack(spacing: 12) {
                    // Waveform icon placeholder
                    SkeletonBox(width: 50, height: 50, radius: 12)

                    // Text placeholders
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            SkeletonBox(width: 140, height: 14)
                            Spacer()
                            // Status badge placeholder
                            SkeletonBox(width: 60, height: 22, radius: 11)
                        }
                        SkeletonBox(width: 90, height: 12)
                    }

                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)

                if index < count - 1 {
                    Rectangle()
                        .fill(Color.coffeeSeparator)
                        .frame(height: 0.5)
                        .padding(.leading, 78)
                }
            }
        }
    }
}

// MARK: - Profile Skeleton
// Matches: avatar circle + name + email + 4 usage stat cells

struct ProfileSkeleton: View {
    var body: some View {
        VStack(spacing: 20) {
            // Avatar + name + email
            VStack(spacing: 12) {
                SkeletonCircle(size: 80)
                SkeletonBox(width: 140, height: 18)
                SkeletonBox(width: 180, height: 14)
                // Plan badge
                SkeletonBox(width: 100, height: 28, radius: 14)
            }
            .padding(.top, 16)

            // Usage stats section
            CoffeeCellGroup {
                ForEach(0..<4, id: \.self) { index in
                    HStack(spacing: 12) {
                        SkeletonBox(width: 44, height: 44, radius: 10)
                        SkeletonBox(width: 130, height: 14)
                        Spacer()
                        SkeletonBox(width: 40, height: 14)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .frame(minHeight: 44)

                    if index < 3 {
                        Rectangle()
                            .fill(Color.coffeeSeparator)
                            .frame(height: 0.5)
                            .padding(.leading, 72)
                    }
                }
            }
            .padding(.horizontal, 16)
        }
    }
}

// MARK: - Event Card Skeleton
// Matches: time column + color bar + title + discipline

struct EventCardSkeleton: View {
    var count: Int = 4

    var body: some View {
        VStack(spacing: 12) {
            ForEach(0..<count, id: \.self) { _ in
                HStack(spacing: 12) {
                    // Time column
                    SkeletonBox(width: 40, height: 14)

                    // Color bar
                    SkeletonBox(width: 4, height: 50, radius: 2)

                    // Content
                    VStack(alignment: .leading, spacing: 6) {
                        SkeletonBox(width: 180, height: 14)
                        SkeletonBox(width: 120, height: 12)
                    }

                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Color.coffeeCardBackground)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
    }
}

// MARK: - Preview

#Preview("Skeletons") {
    ScrollView {
        VStack(spacing: 24) {
            CoffeeSectionHeader(title: "Disciplinas")
            DisciplineCardSkeleton(count: 3)

            CoffeeSectionHeader(title: "Gravacoes")
            RecordingCardSkeleton(count: 3)

            CoffeeSectionHeader(title: "Perfil")
            ProfileSkeleton()

            CoffeeSectionHeader(title: "Eventos")
            EventCardSkeleton(count: 3)
        }
        .padding(16)
    }
    .background(Color.coffeeBackground)
}
