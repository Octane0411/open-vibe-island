import Foundation
import Testing
@testable import OpenIslandApp

struct MarkdownPrivacyTests {
    @Test
    func inlineImageProducesPlaceholderWithoutAnImageServer() async throws {
        // No image server exists here. The network provider throws; the restricted provider
        // produces its local placeholder without a connection, DNS lookup, or disk cache.
        _ = try await SafeInlineImageProvider().image(with: URL(string: "http://127.0.0.1:9/private-prompt.png")!, label: "Agent image")
    }
}
