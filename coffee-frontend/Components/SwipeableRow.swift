import SwiftUI

// MARK: - Swipeable Row
// Custom swipe-to-delete for ScrollView+ForEach (`.swipeActions` only works in List).
//
// Architecture:
// - When onTap is provided: content has `.allowsHitTesting(false)` and ALL taps
//   are routed via SpatialTapGesture on the container (original behavior).
// - When onTap is nil: content keeps hit testing so internal controls (Toggle,
//   Button) work normally. Only drag + swiped-state taps are handled by container.

struct SwipeableRow<Content: View>: View {
    var onTap: (() -> Void)? = nil
    let onDelete: () -> Void
    @ViewBuilder let content: () -> Content

    @State private var offset: CGFloat = 0
    @State private var isSwiped = false
    @State private var rowWidth: CGFloat = 0

    private let deleteWidth: CGFloat = 80
    private let threshold: CGFloat = 40

    /// When onTap is nil, let content handle its own taps (Toggle, Button, etc.)
    private var contentHitTesting: Bool { onTap == nil && !isSwiped }

    var body: some View {
        ZStack(alignment: .trailing) {
            // Delete action — only visible when swiping (prevents flash on tap)
            if offset < 0 {
                Color.coffeeDanger
                    .frame(width: deleteWidth)
                    .overlay {
                        VStack(spacing: 4) {
                            Image(systemName: "trash.fill")
                                .font(.system(size: 20))
                            Text("Apagar")
                                .font(.system(size: 11, weight: .medium))
                        }
                        .foregroundStyle(.white)
                    }
                    .allowsHitTesting(false)
            }

            // Content
            content()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.coffeeCardBackground)
                .offset(x: offset)
                .allowsHitTesting(contentHitTesting)
        }
        .background(
            GeometryReader { proxy in
                Color.clear
                    .onAppear { rowWidth = proxy.size.width }
                    .onChange(of: proxy.size.width) { _, new in rowWidth = new }
            }
        )
        .contentShape(Rectangle())
        .clipped()
        // Gesture 1: Drag for swipe
        .simultaneousGesture(
            DragGesture(minimumDistance: 20, coordinateSpace: .local)
                .onChanged { value in
                    // Only handle horizontal drags (let vertical scroll work)
                    let h = abs(value.translation.width)
                    let v = abs(value.translation.height)
                    guard h > v else { return }

                    let translation = value.translation.width

                    if isSwiped {
                        let newOffset = -deleteWidth + translation
                        offset = min(0, max(-deleteWidth, newOffset))
                    } else {
                        if translation < 0 {
                            offset = max(translation, -deleteWidth)
                        }
                    }
                }
                .onEnded { value in
                    withAnimation(.easeOut(duration: 0.2)) {
                        if isSwiped {
                            if value.translation.width > threshold {
                                offset = 0
                                isSwiped = false
                            } else {
                                offset = -deleteWidth
                            }
                        } else {
                            if value.translation.width < -threshold {
                                offset = -deleteWidth
                                isSwiped = true
                            } else {
                                offset = 0
                            }
                        }
                    }
                }
        )
        // Gesture 2: Spatial tap for location-based routing
        .simultaneousGesture(
            SpatialTapGesture()
                .onEnded { value in
                    if isSwiped {
                        let deleteStart = rowWidth - deleteWidth
                        if value.location.x >= deleteStart {
                            // Tapped on the delete button area
                            close()
                            onDelete()
                        } else {
                            // Tapped on content area → close swipe
                            close()
                        }
                    } else if onTap != nil {
                        // Only forward tap when onTap is set (content has no hit testing)
                        onTap?()
                    }
                }
        )
    }

    private func close() {
        withAnimation(.easeOut(duration: 0.2)) {
            offset = 0
            isSwiped = false
        }
    }

}
