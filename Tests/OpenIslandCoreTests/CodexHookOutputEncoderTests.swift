import Foundation
import Testing
@testable import OpenIslandCore

/// Pins the stdout shape of every `CodexHookDirective` branch because
/// Codex parses the hook's stdout strictly — a misnamed field or wrong
/// decision value silently reverts to default-continue, defeating the
/// whole approval pipeline.
struct CodexHookOutputEncoderTests {
    @Test
    func acknowledgedResponseProducesNoOutput() throws {
        let output = try CodexHookOutputEncoder.standardOutput(for: .acknowledged)
        #expect(output == nil)
    }

    @Test
    func denyDirectiveProducesBlockEnvelope() throws {
        let output = try CodexHookOutputEncoder.standardOutput(
            for: .codexHookDirective(.deny(reason: "User denied"))
        )
        let payload = try decodedPayload(from: output)

        #expect(payload["decision"] as? String == "block")
        #expect(payload["reason"] as? String == "User denied")
    }

    @Test
    func allowDirectiveProducesPermissionAllowEnvelope() throws {
        // Codex currently rejects `decision:"approve"` on PreToolUse, so
        // allow intentionally omits the top-level `decision` and relies
        // on `continue:true` + `permissionDecision:"allow"` — the shape
        // documented by Codex's bundled PreToolUse schema.
        let output = try CodexHookOutputEncoder.standardOutput(
            for: .codexHookDirective(.allow)
        )
        let payload = try decodedPayload(from: output)

        #expect(payload["continue"] as? Bool == true)
        #expect(payload["decision"] == nil)
        let hookSpecific = try #require(payload["hookSpecificOutput"] as? [String: Any])
        #expect(hookSpecific["hookEventName"] as? String == "PreToolUse")
        #expect(hookSpecific["permissionDecision"] as? String == "allow")
    }

    @Test
    func outputAlwaysEndsWithNewline() throws {
        // Codex reads hook stdout line-by-line; a missing trailing
        // newline has historically caused intermittent "no output"
        // misreads for small payloads.
        let output = try CodexHookOutputEncoder.standardOutput(
            for: .codexHookDirective(.allow)
        )
        let data = try #require(output)
        #expect(data.last == UInt8(ascii: "\n"))
    }

    // MARK: - Helpers

    private func decodedPayload(from output: Data?) throws -> [String: Any] {
        let data = try #require(output)
        let object = try JSONSerialization.jsonObject(with: data)
        return try #require(object as? [String: Any])
    }
}
