import UIKit
import SwiftUI

// MARK: - PDF Export Service
// Generates PDFs for recording summaries and mind maps
// Uses UIGraphicsPDFRenderer for native PDF creation

struct PDFExportService {

    // MARK: - Summary PDF

    /// Generate a PDF from a recording's summary sections
    static func generateSummaryPDF(
        title: String,
        disciplineName: String,
        date: String,
        duration: String,
        sections: [SummarySection]
    ) -> Data {
        let pageWidth: CGFloat = 612  // US Letter
        let pageHeight: CGFloat = 792
        let margin: CGFloat = 50
        let contentWidth = pageWidth - margin * 2

        let renderer = UIGraphicsPDFRenderer(
            bounds: CGRect(x: 0, y: 0, width: pageWidth, height: pageHeight)
        )

        return renderer.pdfData { context in
            var yPosition: CGFloat = 0

            func startNewPage() {
                context.beginPage()
                yPosition = margin
            }

            func checkPage(needed: CGFloat) {
                if yPosition + needed > pageHeight - margin {
                    startNewPage()
                }
            }

            startNewPage()

            // Header: COFFEE logo text
            let headerAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 12, weight: .medium),
                .foregroundColor: UIColor(red: 113/255, green: 80/255, blue: 56/255, alpha: 1)
            ]
            let headerStr = NSAttributedString(string: "COFFEE", attributes: headerAttrs)
            headerStr.draw(at: CGPoint(x: margin, y: yPosition))
            yPosition += 28

            // Title
            let titleAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 22, weight: .bold),
                .foregroundColor: UIColor.label
            ]
            let titleRect = CGRect(x: margin, y: yPosition, width: contentWidth, height: 60)
            let titleStr = NSAttributedString(string: title, attributes: titleAttrs)
            titleStr.draw(in: titleRect)
            let titleSize = titleStr.boundingRect(with: CGSize(width: contentWidth, height: .greatestFiniteMagnitude), options: .usesLineFragmentOrigin, context: nil)
            yPosition += titleSize.height + 8

            // Subtitle: discipline + date + duration
            let subAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 12),
                .foregroundColor: UIColor.secondaryLabel
            ]
            let subStr = NSAttributedString(string: "\(disciplineName)  ·  \(date)  ·  \(duration)", attributes: subAttrs)
            subStr.draw(at: CGPoint(x: margin, y: yPosition))
            yPosition += 24

            // Separator line
            let separatorPath = UIBezierPath()
            separatorPath.move(to: CGPoint(x: margin, y: yPosition))
            separatorPath.addLine(to: CGPoint(x: pageWidth - margin, y: yPosition))
            UIColor.separator.setStroke()
            separatorPath.lineWidth = 0.5
            separatorPath.stroke()
            yPosition += 20

            // Sections
            let sectionTitleAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 16, weight: .bold),
                .foregroundColor: UIColor.label
            ]

            let bulletAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 13),
                .foregroundColor: UIColor.label
            ]

            let bulletColor = UIColor(red: 113/255, green: 80/255, blue: 56/255, alpha: 1)

            for section in sections {
                // Section title
                let sectionTitle = NSAttributedString(string: section.title, attributes: sectionTitleAttrs)
                let sectionTitleSize = sectionTitle.boundingRect(with: CGSize(width: contentWidth, height: .greatestFiniteMagnitude), options: .usesLineFragmentOrigin, context: nil)
                checkPage(needed: sectionTitleSize.height + 30)
                sectionTitle.draw(in: CGRect(x: margin, y: yPosition, width: contentWidth, height: sectionTitleSize.height + 4))
                yPosition += sectionTitleSize.height + 12

                // Bullets
                for bullet in section.bullets {
                    let bulletText = NSAttributedString(string: bullet, attributes: bulletAttrs)
                    let bulletSize = bulletText.boundingRect(with: CGSize(width: contentWidth - 20, height: .greatestFiniteMagnitude), options: .usesLineFragmentOrigin, context: nil)
                    checkPage(needed: bulletSize.height + 10)

                    // Bullet dot
                    let dotRect = CGRect(x: margin + 2, y: yPosition + 6, width: 5, height: 5)
                    bulletColor.setFill()
                    UIBezierPath(ovalIn: dotRect).fill()

                    // Bullet text
                    bulletText.draw(in: CGRect(x: margin + 16, y: yPosition, width: contentWidth - 20, height: bulletSize.height + 4))
                    yPosition += bulletSize.height + 10
                }

                yPosition += 12
            }

            // Footer
            drawFooter(context: context, pageWidth: pageWidth, pageHeight: pageHeight, margin: margin)
        }
    }

    // MARK: - Mind Map PDF

    /// Generate a PDF from a recording's mind map
    static func generateMindMapPDF(
        title: String,
        disciplineName: String,
        date: String,
        mindMap: MindMap
    ) -> Data {
        let pageWidth: CGFloat = 612
        let pageHeight: CGFloat = 792
        let margin: CGFloat = 50
        let contentWidth = pageWidth - margin * 2

        let branchColors: [UIColor] = [
            .systemBlue, .systemGreen, .systemOrange, .systemPurple
        ]

        let renderer = UIGraphicsPDFRenderer(
            bounds: CGRect(x: 0, y: 0, width: pageWidth, height: pageHeight)
        )

        return renderer.pdfData { context in
            var yPosition: CGFloat = 0

            func startNewPage() {
                context.beginPage()
                yPosition = margin
            }

            func checkPage(needed: CGFloat) {
                if yPosition + needed > pageHeight - margin {
                    startNewPage()
                }
            }

            startNewPage()

            // Header
            let headerAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 12, weight: .medium),
                .foregroundColor: UIColor(red: 113/255, green: 80/255, blue: 56/255, alpha: 1)
            ]
            NSAttributedString(string: "COFFEE", attributes: headerAttrs)
                .draw(at: CGPoint(x: margin, y: yPosition))
            yPosition += 28

            // Title
            let titleAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 22, weight: .bold),
                .foregroundColor: UIColor.label
            ]
            let titleStr = NSAttributedString(string: "Mapa Mental: \(title)", attributes: titleAttrs)
            let titleSize = titleStr.boundingRect(with: CGSize(width: contentWidth, height: .greatestFiniteMagnitude), options: .usesLineFragmentOrigin, context: nil)
            titleStr.draw(in: CGRect(x: margin, y: yPosition, width: contentWidth, height: titleSize.height + 4))
            yPosition += titleSize.height + 8

            // Subtitle
            let subAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 12),
                .foregroundColor: UIColor.secondaryLabel
            ]
            NSAttributedString(string: "\(disciplineName)  ·  \(date)", attributes: subAttrs)
                .draw(at: CGPoint(x: margin, y: yPosition))
            yPosition += 24

            // Separator
            let separatorPath = UIBezierPath()
            separatorPath.move(to: CGPoint(x: margin, y: yPosition))
            separatorPath.addLine(to: CGPoint(x: pageWidth - margin, y: yPosition))
            UIColor.separator.setStroke()
            separatorPath.lineWidth = 0.5
            separatorPath.stroke()
            yPosition += 28

            // Central topic
            let topicAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 18, weight: .bold),
                .foregroundColor: UIColor(red: 113/255, green: 80/255, blue: 56/255, alpha: 1)
            ]
            let topicStr = NSAttributedString(string: mindMap.topic, attributes: topicAttrs)
            let topicSize = topicStr.boundingRect(with: CGSize(width: contentWidth, height: .greatestFiniteMagnitude), options: .usesLineFragmentOrigin, context: nil)

            // Topic background pill
            let pillRect = CGRect(
                x: margin,
                y: yPosition - 4,
                width: topicSize.width + 32,
                height: topicSize.height + 16
            )
            let pillPath = UIBezierPath(roundedRect: pillRect, cornerRadius: pillRect.height / 2)
            UIColor(red: 113/255, green: 80/255, blue: 56/255, alpha: 0.1).setFill()
            pillPath.fill()

            topicStr.draw(at: CGPoint(x: margin + 16, y: yPosition + 4))
            yPosition += pillRect.height + 24

            // Branches
            let branchTitleAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 15, weight: .semibold),
                .foregroundColor: UIColor.label
            ]

            let childAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 13),
                .foregroundColor: UIColor.secondaryLabel
            ]

            for (index, branch) in mindMap.branches.enumerated() {
                let color = branchColors[index % branchColors.count]

                // Branch title with colored dot
                checkPage(needed: 30 + CGFloat(branch.children.count * 22))

                // Colored dot
                let dotRect = CGRect(x: margin + 2, y: yPosition + 5, width: 8, height: 8)
                color.setFill()
                UIBezierPath(ovalIn: dotRect).fill()

                // Branch name
                NSAttributedString(string: branch.topic, attributes: branchTitleAttrs)
                    .draw(at: CGPoint(x: margin + 18, y: yPosition))
                yPosition += 24

                // Children
                for child in branch.children {
                    checkPage(needed: 22)

                    // Vertical line segment
                    let lineRect = CGRect(x: margin + 5, y: yPosition, width: 2, height: 16)
                    color.withAlphaComponent(0.3).setFill()
                    UIBezierPath(rect: lineRect).fill()

                    // Child text
                    let childStr = NSAttributedString(string: child, attributes: childAttrs)
                    let childSize = childStr.boundingRect(with: CGSize(width: contentWidth - 40, height: .greatestFiniteMagnitude), options: .usesLineFragmentOrigin, context: nil)
                    childStr.draw(in: CGRect(x: margin + 24, y: yPosition, width: contentWidth - 40, height: childSize.height + 4))
                    yPosition += childSize.height + 8
                }

                yPosition += 16
            }

            // Footer
            drawFooter(context: context, pageWidth: pageWidth, pageHeight: pageHeight, margin: margin)
        }
    }

    // MARK: - Footer

    private static func drawFooter(
        context: UIGraphicsPDFRendererContext,
        pageWidth: CGFloat,
        pageHeight: CGFloat,
        margin: CGFloat
    ) {
        let footerAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 9),
            .foregroundColor: UIColor.tertiaryLabel
        ]
        let footerStr = NSAttributedString(
            string: "Gerado pelo COFFEE · coffee.app",
            attributes: footerAttrs
        )
        let footerSize = footerStr.boundingRect(with: CGSize(width: 300, height: 20), options: .usesLineFragmentOrigin, context: nil)
        footerStr.draw(at: CGPoint(
            x: (pageWidth - footerSize.width) / 2,
            y: pageHeight - margin + 10
        ))
    }

    // MARK: - Share

    /// Present a share sheet with text content (for sharing recordings)
    @MainActor
    static func shareText(_ text: String) {
        let activityVC = UIActivityViewController(
            activityItems: [text],
            applicationActivities: nil
        )

        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let rootVC = windowScene.windows.first?.rootViewController {
            var topVC = rootVC
            while let presented = topVC.presentedViewController {
                topVC = presented
            }
            if let popover = activityVC.popoverPresentationController {
                popover.sourceView = topVC.view
                popover.sourceRect = CGRect(x: topVC.view.bounds.midX, y: topVC.view.bounds.midY, width: 0, height: 0)
            }
            topVC.present(activityVC, animated: true)
        }
    }

    /// Present a share sheet with the PDF data
    @MainActor
    static func sharePDF(data: Data, fileName: String) {
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        try? data.write(to: tempURL)

        let activityVC = UIActivityViewController(
            activityItems: [tempURL],
            applicationActivities: nil
        )

        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let rootVC = windowScene.windows.first?.rootViewController {
            // Find the topmost presented controller
            var topVC = rootVC
            while let presented = topVC.presentedViewController {
                topVC = presented
            }
            if let popover = activityVC.popoverPresentationController {
                popover.sourceView = topVC.view
                popover.sourceRect = CGRect(x: topVC.view.bounds.midX, y: topVC.view.bounds.midY, width: 0, height: 0)
            }
            topVC.present(activityVC, animated: true)
        }
    }
}
