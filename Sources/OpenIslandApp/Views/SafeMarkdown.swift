import MarkdownUI
import SwiftUI

/// Agent-authored Markdown may contain tracking URLs or local file paths.
/// Neither provider reads the URL. Links still open only when the user clicks them.
struct SafeMarkdown: View {
    let content: String
    var body: some View {
        Markdown(content)
            .markdownImageProvider(SafeBlockImageProvider())
            .markdownInlineImageProvider(SafeInlineImageProvider())
    }
}

struct SafeBlockImageProvider: ImageProvider {
    func makeImage(url: URL?) -> some View {
        Label("Image hidden", systemImage: "photo")
            .font(.caption).foregroundStyle(.secondary)
    }
}

struct SafeInlineImageProvider: InlineImageProvider, Sendable {
    func image(with url: URL, label: String) async throws -> Image {
        Image(systemName: "photo")
    }
}
