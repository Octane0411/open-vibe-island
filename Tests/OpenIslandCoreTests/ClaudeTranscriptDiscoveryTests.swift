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
    func missingDesktopEntrypointStaysUnknown() throws {
        // A terminal (`cli`) session has no claude-desktop entrypoint and must
        // keep the "Unknown" sentinel — the terminal resolver handles it later.
        let line = #"{"type":"attachment","sessionId":"def67890","cwd":"/Users/test/project","entrypoint":"cli","timestamp":"2026-07-22T18:00:00Z"}"#
        let (discovery, root) = try makeDiscovery(line: line)
        defer { try? FileManager.default.removeItem(at: root) }

        let sessions = discovery.discoverRecentSessions()

        #expect(sessions.count == 1)
        #expect(sessions.first?.jumpTarget?.terminalApp == "Unknown")
    }
}
