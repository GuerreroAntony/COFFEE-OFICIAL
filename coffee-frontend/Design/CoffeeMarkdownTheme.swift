import SwiftUI
import MarkdownUI

// MARK: - Coffee Markdown Theme
// Custom MarkdownUI theme matching the Coffee design system
// Used in AI chat bubbles for rendered markdown responses

extension Theme {
    static let coffee = Theme()
        // Base text
        .text {
            ForegroundColor(Color.coffeeTextPrimary)
            FontSize(15.5)
        }
        // Inline code
        .code {
            FontFamilyVariant(.monospaced)
            FontSize(.em(0.88))
            ForegroundColor(Color.coffeePrimary)
            BackgroundColor(Color.coffeePrimary.opacity(0.08))
        }
        // Bold
        .strong {
            FontWeight(.semibold)
        }
        // Links
        .link {
            ForegroundColor(Color.coffeePrimary)
        }
        // H1
        .heading1 { configuration in
            configuration.label
                .markdownTextStyle {
                    FontWeight(.bold)
                    FontSize(20)
                    ForegroundColor(Color.coffeeTextPrimary)
                }
                .relativeLineSpacing(.em(0.1))
                .markdownMargin(top: 16, bottom: 8)
        }
        // H2
        .heading2 { configuration in
            configuration.label
                .markdownTextStyle {
                    FontWeight(.bold)
                    FontSize(18)
                    ForegroundColor(Color.coffeeTextPrimary)
                }
                .relativeLineSpacing(.em(0.1))
                .markdownMargin(top: 28, bottom: 12)
        }
        // H3
        .heading3 { configuration in
            configuration.label
                .markdownTextStyle {
                    FontWeight(.semibold)
                    FontSize(16.5)
                    ForegroundColor(Color.coffeeTextPrimary)
                }
                .markdownMargin(top: 24, bottom: 10)
        }
        // Paragraphs
        .paragraph { configuration in
            configuration.label
                .relativeLineSpacing(.em(0.4))
                .markdownMargin(top: 0, bottom: 16)
        }
        // Blockquotes
        .blockquote { configuration in
            HStack(spacing: 0) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.coffeePrimaryLight)
                    .frame(width: 3)

                configuration.label
                    .markdownTextStyle {
                        ForegroundColor(Color.coffeeTextSecondary)
                        FontSize(14.5)
                    }
                    .relativePadding(.leading, length: .em(1))
            }
            .fixedSize(horizontal: false, vertical: true)
            .markdownMargin(top: 16, bottom: 16)
        }
        // Code blocks
        .codeBlock { configuration in
            ScrollView(.horizontal) {
                configuration.label
                    .markdownTextStyle {
                        FontFamilyVariant(.monospaced)
                        FontSize(13)
                        ForegroundColor(Color.coffeeTextPrimary)
                    }
            }
            .padding(12)
            .background(Color.coffeeCardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color.coffeeSeparator, lineWidth: 0.5)
            )
            .markdownMargin(top: 8, bottom: 8)
        }
        // List items
        .listItem { configuration in
            configuration.label
                .markdownMargin(top: 8, bottom: 8)
        }
        // Bullet markers
        .bulletedListMarker { _ in
            Circle()
                .fill(Color.coffeePrimary)
                .frame(width: 5, height: 5)
        }
        // Horizontal rule
        .thematicBreak {
            Divider()
                .markdownMargin(top: 24, bottom: 24)
        }
}
