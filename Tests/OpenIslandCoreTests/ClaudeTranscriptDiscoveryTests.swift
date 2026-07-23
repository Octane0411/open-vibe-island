import Foundation
import Testing
@testable import OpenIslandCore

struct ClaudeTranscriptDiscoveryTests {
    /// Writes a single-line jsonl transcript into a throwaway root and returns
    /// the discovery instance pointed at it. Caller is responsible for cleanup
    /// via the returned root URL.
    private func makeDiscovery(
        line: String,
        fileName: String = "\(UUID().uuidString).jsonl"
    ) throws -> (discovery: ClaudeTranscriptDiscovery, root: URL) {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("open-island-transcript-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try line.write(
            to: root.appendingPathComponent(fileName),
            atomically: true,
            encoding: .utf8
        )
        return (ClaudeTranscriptDiscovery(rootURL: root), root)
    }

    @Test
    func desktopEntrypointTagsSessionAsClaudeApp() throws {
        let line = #"{"type":"attachment","sessionId":"abc12345","cwd":"/Users/test/project","entrypoint":"claude-desktop","timestamp":"2026-07-22T18:00:00Z"}"#
        let (discovery, root) = try makeDiscovery(line: line)
        defer { try? FileManager.default.removeItem(at: root) }

        let sessions = discovery.discoverRecentSessions()

        #expect(sessions.count == 1)
        #expect(sessions.first?.jumpTarget?.terminalApp == "Claude.app")
    }

    @Test
    func cliEntrypointStaysUnknown() throws {
        // A terminal (`cli`) session has no claude-desktop entrypoint and must
        // keep the "Unknown" sentinel — the terminal resolver handles it later.
        let line = #"{"type":"attachment","sessionId":"def67890","cwd":"/Users/test/project","entrypoint":"cli","timestamp":"2026-07-22T18:00:00Z"}"#
        let (discovery, root) = try makeDiscovery(line: line)
        defer { try? FileManager.default.removeItem(at: root) }

        let sessions = discovery.discoverRecentSessions()

        #expect(sessions.count == 1)
        #expect(sessions.first?.jumpTarget?.terminalApp == "Unknown")
    }

    @Test
    func absentEntrypointFieldStaysUnknown() throws {
        // Older transcripts predate the entrypoint field entirely; they must
        // still resolve to "Unknown" rather than crashing or misclassifying.
        let line = #"{"type":"attachment","sessionId":"aaa11111","cwd":"/Users/test/project","timestamp":"2026-07-22T18:00:00Z"}"#
        let (discovery, root) = try makeDiscovery(line: line)
        defer { try? FileManager.default.removeItem(at: root) }

        let sessions = discovery.discoverRecentSessions()

        #expect(sessions.count == 1)
        #expect(sessions.first?.jumpTarget?.terminalApp == "Unknown")
    }

    @Test
    func firstNonEmptyEntrypointIsLatched() throws {
        // An empty earlier entrypoint is skipped, the first non-empty value is
        // latched ("claude-desktop"), and a later record ("cli") must not
        // overwrite it.
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("open-island-transcript-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let lines = [
            #"{"type":"attachment","sessionId":"bbb22222","cwd":"/Users/test/project","entrypoint":"","timestamp":"2026-07-22T17:55:00Z"}"#,
            #"{"type":"attachment","sessionId":"bbb22222","entrypoint":"claude-desktop","timestamp":"2026-07-22T18:00:00Z"}"#,
            #"{"type":"attachment","sessionId":"bbb22222","entrypoint":"cli","timestamp":"2026-07-22T18:05:00Z"}"#,
        ].joined(separator: "\n") + "\n"
        try lines.write(
            to: root.appendingPathComponent("bbb22222.jsonl"),
            atomically: true,
            encoding: .utf8
        )

        let sessions = ClaudeTranscriptDiscovery(rootURL: root).discoverRecentSessions()

        #expect(sessions.count == 1)
        #expect(sessions.first?.jumpTarget?.terminalApp == "Claude.app")
    }
}
