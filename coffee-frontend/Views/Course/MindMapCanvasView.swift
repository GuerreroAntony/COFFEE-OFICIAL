import SwiftUI

// MARK: - Mind Map Canvas View
// Horizontal tree: central node left, branches middle, children right.
// Pinch-to-zoom, drag-to-pan, fullscreen support.

struct MindMapCanvasView: View {
    let mindMap: MindMap
    var isFullscreen: Bool = false
    var onFullscreen: (() -> Void)? = nil

    private let branchColors: [Color] = [
        Color(hex: "8B6914"),  // Dourado escuro
        Color(hex: "A0522D"),  // Terracotta
        Color(hex: "5B7553"),  // Verde oliva
        Color(hex: "4A5568"),  // Cinza azulado
        Color(hex: "8B4557"),  // Vinho rosado
        Color(hex: "6B5B3E"),  // Marrom quente
    ]

    @State private var scale: CGFloat = 0.3
    @GestureState private var pinchScale: CGFloat = 1.0

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            toolbar

            // Map content in ScrollView
            ScrollView([.horizontal, .vertical], showsIndicators: false) {
                mapContent
                    .scaleEffect(scale * pinchScale, anchor: .topLeading)
                    .frame(
                        width: canvasSize.width * scale * pinchScale,
                        height: canvasSize.height * scale * pinchScale,
                        alignment: .topLeading
                    )
                    .gesture(
                        MagnificationGesture()
                            .updating($pinchScale) { value, state, _ in
                                state = value
                            }
                            .onEnded { value in
                                scale = min(max(scale * value, 0.3), 3.0)
                            }
                    )
            }
            .frame(maxWidth: .infinity)
            .frame(height: isFullscreen ? nil : 400)
        }
        .background(Color.coffeeCardBackground)
        .clipShape(RoundedRectangle(cornerRadius: isFullscreen ? 0 : 16, style: .continuous))
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack {
            Spacer()
            Button { withAnimation { scale = max(0.3, scale - 0.2) } } label: {
                Image(systemName: "minus.magnifyingglass")
                    .font(.system(size: 15))
                    .foregroundStyle(Color.coffeeTextSecondary)
                    .frame(width: 32, height: 32)
            }
            Button { withAnimation { scale = 1.0 } } label: {
                Text("\(Int(scale * pinchScale * 100))%")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.coffeeTextSecondary)
                    .frame(width: 44, height: 32)
            }
            Button { withAnimation { scale = min(3.0, scale + 0.2) } } label: {
                Image(systemName: "plus.magnifyingglass")
                    .font(.system(size: 15))
                    .foregroundStyle(Color.coffeeTextSecondary)
                    .frame(width: 32, height: 32)
            }
            if let onFullscreen {
                Divider().frame(height: 16)
                Button { onFullscreen() } label: {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.system(size: 14))
                        .foregroundStyle(Color.coffeePrimary)
                        .frame(width: 32, height: 32)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .padding(.bottom, 4)
    }

    // MARK: - Map Content (unscaled)

    private var mapContent: some View {
        ZStack(alignment: .topLeading) {
            // Lines layer
            Canvas { context, size in
                drawConnections(context: context, size: size)
            }
            .frame(width: canvasSize.width, height: canvasSize.height)
            .allowsHitTesting(false)

            // Central node
            centralNodeView

            // Branch + child nodes
            ForEach(Array(mindMap.branches.enumerated()), id: \.offset) { i, branch in
                let color = branchColors[i % branchColors.count]
                let bPos = branchPosition(index: i)
                let bSize = branchMeasured(index: i)

                // Branch node
                Text(branch.topic)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(color)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(color.opacity(0.08))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .strokeBorder(color.opacity(0.3), lineWidth: 1.5)
                            )
                            .shadow(color: color.opacity(0.1), radius: 4, y: 2)
                    )
                    .fixedSize()
                    .position(x: bPos.x + bSize.width / 2, y: bPos.y + bSize.height / 2)

                // Children
                ForEach(Array(branch.children.enumerated()), id: \.offset) { j, child in
                    let cPos = childPosition(branchIndex: i, childIndex: j)
                    let cSize = childMeasured(branchIndex: i, childIndex: j)

                    Text(child)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color.coffeeTextPrimary.opacity(0.85))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(Color.coffeeCardBackground)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .strokeBorder(color.opacity(0.2), lineWidth: 1)
                                )
                                .shadow(color: Color.black.opacity(0.04), radius: 2, y: 1)
                        )
                        .fixedSize()
                        .position(x: cPos.x + cSize.width / 2, y: cPos.y + cSize.height / 2)
                }
            }
        }
        .frame(width: canvasSize.width, height: canvasSize.height)
    }

    // MARK: - Central Node

    private var centralNodeView: some View {
        let pos = centralPosition
        let size = centralMeasured
        return Text(mindMap.topic)
            .font(.system(size: 16, weight: .bold))
            .foregroundStyle(.white)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Color.coffeePrimary, Color(hex: "8B6B4A")],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .shadow(color: Color.coffeePrimary.opacity(0.3), radius: 8, y: 3)
            )
            .fixedSize()
            .position(x: pos.x + size.width / 2, y: pos.y + size.height / 2)
    }

    // MARK: - Connection Drawing

    private func drawConnections(context: GraphicsContext, size: CGSize) {
        let cPos = centralPosition
        let cSize = centralMeasured
        let centralRight = CGPoint(x: cPos.x + cSize.width, y: cPos.y + cSize.height / 2)

        for i in 0..<mindMap.branches.count {
            let color = branchColors[i % branchColors.count]
            let bPos = branchPosition(index: i)
            let bSize = branchMeasured(index: i)
            let branchLeft = CGPoint(x: bPos.x, y: bPos.y + bSize.height / 2)
            let branchRight = CGPoint(x: bPos.x + bSize.width, y: bPos.y + bSize.height / 2)

            // Central → Branch curve
            var mainPath = Path()
            mainPath.move(to: centralRight)
            let midX1 = (centralRight.x + branchLeft.x) / 2
            mainPath.addCurve(
                to: branchLeft,
                control1: CGPoint(x: midX1, y: centralRight.y),
                control2: CGPoint(x: midX1, y: branchLeft.y)
            )
            context.stroke(mainPath, with: .color(color.opacity(0.4)), lineWidth: 2.5)

            // Branch → Children curves
            for j in 0..<mindMap.branches[i].children.count {
                let cChildPos = childPosition(branchIndex: i, childIndex: j)
                let cChildSize = childMeasured(branchIndex: i, childIndex: j)
                let childLeft = CGPoint(x: cChildPos.x, y: cChildPos.y + cChildSize.height / 2)

                var childPath = Path()
                childPath.move(to: branchRight)
                let midX2 = (branchRight.x + childLeft.x) / 2
                childPath.addCurve(
                    to: childLeft,
                    control1: CGPoint(x: midX2, y: branchRight.y),
                    control2: CGPoint(x: midX2, y: childLeft.y)
                )
                context.stroke(childPath, with: .color(color.opacity(0.25)), lineWidth: 1.5)
            }
        }
    }

    // MARK: - Layout Calculations

    private let padding: CGFloat = 30
    private let hGap: CGFloat = 40
    private let vGapBranch: CGFloat = 24
    private let vGapChild: CGFloat = 8

    // Text measurement cache via computed properties

    private var centralMeasured: CGSize {
        let t = measureText(mindMap.topic, font: .systemFont(ofSize: 16, weight: .bold), maxWidth: 180)
        return CGSize(width: t.width + 40, height: t.height + 28)
    }

    private func branchMeasured(index: Int) -> CGSize {
        let t = measureText(mindMap.branches[index].topic, font: .systemFont(ofSize: 14, weight: .semibold), maxWidth: 180)
        return CGSize(width: t.width + 32, height: t.height + 20)
    }

    private func childMeasured(branchIndex: Int, childIndex: Int) -> CGSize {
        let text = mindMap.branches[branchIndex].children[childIndex]
        let t = measureText(text, font: .systemFont(ofSize: 12, weight: .medium), maxWidth: 160)
        return CGSize(width: t.width + 24, height: t.height + 16)
    }

    private func branchGroupHeight(index: Int) -> CGFloat {
        let branch = mindMap.branches[index]
        let bH = branchMeasured(index: index).height
        var childrenH: CGFloat = 0
        for j in 0..<branch.children.count {
            childrenH += childMeasured(branchIndex: index, childIndex: j).height + vGapChild
        }
        childrenH -= vGapChild
        return max(bH, childrenH)
    }

    private var totalBranchHeight: CGFloat {
        var h: CGFloat = 0
        for i in 0..<mindMap.branches.count {
            h += branchGroupHeight(index: i)
            if i < mindMap.branches.count - 1 { h += vGapBranch }
        }
        return h
    }

    private var maxBranchWidth: CGFloat {
        (0..<mindMap.branches.count).map { branchMeasured(index: $0).width }.max() ?? 140
    }

    private var maxChildWidth: CGFloat {
        var maxW: CGFloat = 100
        for i in 0..<mindMap.branches.count {
            for j in 0..<mindMap.branches[i].children.count {
                maxW = max(maxW, childMeasured(branchIndex: i, childIndex: j).width)
            }
        }
        return maxW
    }

    private var canvasSize: CGSize {
        let w = padding * 2 + centralMeasured.width + hGap + maxBranchWidth + hGap + maxChildWidth
        let h = padding * 2 + max(totalBranchHeight, centralMeasured.height + 40)
        return CGSize(width: w, height: h)
    }

    private var centralPosition: CGPoint {
        let y = (canvasSize.height - centralMeasured.height) / 2
        return CGPoint(x: padding, y: y)
    }

    private func branchPosition(index: Int) -> CGPoint {
        let x = padding + centralMeasured.width + hGap
        var y = padding + (canvasSize.height - padding * 2 - totalBranchHeight) / 2

        for i in 0..<index {
            y += branchGroupHeight(index: i) + vGapBranch
        }

        let groupH = branchGroupHeight(index: index)
        let bH = branchMeasured(index: index).height
        y += (groupH - bH) / 2

        return CGPoint(x: x, y: y)
    }

    private func childPosition(branchIndex: Int, childIndex: Int) -> CGPoint {
        let x = padding + centralMeasured.width + hGap + maxBranchWidth + hGap
        var groupStartY = padding + (canvasSize.height - padding * 2 - totalBranchHeight) / 2

        for i in 0..<branchIndex {
            groupStartY += branchGroupHeight(index: i) + vGapBranch
        }

        let groupH = branchGroupHeight(index: branchIndex)
        let branch = mindMap.branches[branchIndex]
        var childrenTotalH: CGFloat = 0
        for j in 0..<branch.children.count {
            childrenTotalH += childMeasured(branchIndex: branchIndex, childIndex: j).height + vGapChild
        }
        childrenTotalH -= vGapChild

        var y = groupStartY + (groupH - childrenTotalH) / 2
        for j in 0..<childIndex {
            y += childMeasured(branchIndex: branchIndex, childIndex: j).height + vGapChild
        }

        return CGPoint(x: x, y: y)
    }

    private func measureText(_ text: String, font: UIFont, maxWidth: CGFloat) -> CGSize {
        let constraintSize = CGSize(width: maxWidth, height: .greatestFiniteMagnitude)
        let boundingBox = (text as NSString).boundingRect(
            with: constraintSize,
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: font],
            context: nil
        )
        return CGSize(width: ceil(boundingBox.width), height: ceil(boundingBox.height))
    }

    // MARK: - Export as Image

    /// Renders the mind map at full scale (1.0) as a UIImage for sharing/export
    @MainActor
    func renderAsImage() -> UIImage? {
        let exportView = mapContent
            .environment(\.colorScheme, .light)

        let renderer = ImageRenderer(content: exportView)
        renderer.scale = 2.0  // Retina quality
        renderer.proposedSize = .init(canvasSize)
        return renderer.uiImage
    }
}

// MARK: - Fullscreen Mind Map Sheet

struct MindMapFullscreenSheet: View {
    let mindMap: MindMap
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(mindMap.topic)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Color.coffeeTextPrimary)
                    .lineLimit(1)
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 24))
                        .foregroundStyle(Color.coffeeTextSecondary.opacity(0.6))
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(Color.coffeeCardBackground)

            Divider()

            MindMapCanvasView(mindMap: mindMap, isFullscreen: true)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color.coffeeBackground)
    }
}
