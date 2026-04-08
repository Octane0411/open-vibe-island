import MarkdownUI
import SwiftUI

extension MarkdownUI.Theme {
    @MainActor static let completionCard = Theme()
        .text {
            ForegroundColor(.white.opacity(0.88))
            FontSize(13.5)
            FontWeight(.medium)
        }
        .link {
            ForegroundColor(.blue)
        }
        .strong {
            FontWeight(.bold)
        }
        .code {
            FontFamilyVariant(.monospaced)
            FontSize(12.5)
            ForegroundColor(.white.opacity(0.88))
            BackgroundColor(.white.opacity(0.08))
        }
        .codeBlock { configuration in
            configuration.label
                .markdownTextStyle {
                    FontFamilyVariant(.monospaced)
                    FontSize(12.5)
                    ForegroundColor(.white.opacity(0.88))
                }
                .padding(10)
                .background(Color.white.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .heading1 { configuration in
            configuration.label
                .markdownTextStyle {
                    FontSize(16)
                    FontWeight(.bold)
                    ForegroundColor(.white.opacity(0.88))
                }
                .markdownMargin(top: 8, bottom: 4)
        }
        .heading2 { configuration in
            configuration.label
                .markdownTextStyle {
                    FontSize(15)
                    FontWeight(.bold)
                    ForegroundColor(.white.opacity(0.88))
                }
                .markdownMargin(top: 8, bottom: 4)
        }
        .heading3 { configuration in
            configuration.label
                .markdownTextStyle {
                    FontSize(14)
                    FontWeight(.semibold)
                    ForegroundColor(.white.opacity(0.88))
                }
                .markdownMargin(top: 6, bottom: 2)
        }
        .blockquote { configuration in
            configuration.label
                .markdownTextStyle {
                    ForegroundColor(.white.opacity(0.6))
                    FontSize(13.5)
                }
                .padding(.leading, 12)
                .overlay(alignment: .leading) {
                    Rectangle()
                        .fill(Color.white.opacity(0.2))
                        .frame(width: 3)
                }
        }
        .listItem { configuration in
            configuration.label
                .markdownMargin(top: 2, bottom: 2)
        }
}
