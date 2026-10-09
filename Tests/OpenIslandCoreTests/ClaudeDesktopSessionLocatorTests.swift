import Foundation
import Testing
@testable import OpenIslandCore

struct ClaudeDesktopSessionLocatorTests {
    private func makeSessionsDirectory() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("open-island-claude-desktop-sessions-\(UUID().uuidString)", isDirectory: true)
        // Mirrors Claude.app's layout: <org>/<user>/local_<id>.json
        let leaf = root
            .appendingPathComponent("2632a112-47c7-468a-a12a-a41e6c642309", isDirectory: true)
            .appendingPathComponent("9d7e875a-9906-4612-8690-07158fc594c7", isDirectory: true)
        try FileManager.default.createDirectory(at: leaf, withIntermediateDirectories: true)
        return root
    }

    private func writeRecord(in root: URL, desktopSessionID: String, cliSessionID: String) throws {
        let leaf = root
            .appendingPathComponent("2632a112-47c7-468a-a12a-a41e6c642309", isDirectory: true)
            .appendingPathComponent("9d7e875a-9906-4612-8690-07158fc594c7", isDirectory: true)
        let payload = """
        {
          "sessionId": "\(desktopSessionID)",
          "cliSessionId": "\(cliSessionID)",
          "cwd": "/Users/test/project",
          "title": "Example session",
          "isArchived": false
        }
        """
        try payload.write(
            to: leaf.appendingPathComponent("\(desktopSessionID).json"),
            atomically: true,
            encoding: .utf8
        )
    }

    @Test
    func resolvesDesktopSessionIDFromCLISessionID() throws {
        let root = try makeSessionsDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try writeRecord(
            in: root,
            desktopSessionID: "local_eb34f765-d478-44a2-8280-f581778da379",
            cliSessionID: "ef3908a9-1149-44fb-9616-8bf003f93daa"
        )
        try writeRecord(
            in: root,
            desktopSessionID: "local_87dd1a88-e8a1-4164-9a1f-96f1de7e3973",
            cliSessionID: "a5484c04-b4f8-482c-95d9-6c21f72c1926"
        )

        let resolved = ClaudeDesktopSessionLocator.desktopSessionID(
            forCLISessionID: "A5484C04-B4F8-482C-95D9-6C21F72C1926",
            sessionsDirectory: root
        )

        #expect(resolved == "local_87dd1a88-e8a1-4164-9a1f-96f1de7e3973")
    }

    @Test
    func returnsNilWhenNoRecordMatches() throws {
        let root = try makeSessionsDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try writeRecord(
            in: root,
            desktopSessionID: "local_eb34f765-d478-44a2-8280-f581778da379",
            cliSessionID: "ef3908a9-1149-44fb-9616-8bf003f93daa"
        )

        #expect(ClaudeDesktopSessionLocator.desktopSessionID(
            forCLISessionID: "00000000-0000-0000-0000-000000000000",
            sessionsDirectory: root
        ) == nil)
        #expect(ClaudeDesktopSessionLocator.desktopSessionID(
            forCLISessionID: "   ",
            sessionsDirectory: root
        ) == nil)
    }

    @Test
    func continueURLRejectsIDsOutsideClaudeAppPattern() {
        #expect(ClaudeDesktopSessionLocator.continueURL(forDesktopSessionID: "local_abc-123")
            == "claude://code/continue?session=local_abc-123")
        #expect(ClaudeDesktopSessionLocator.continueURL(forDesktopSessionID: "ef3908a9-1149-44fb-9616-8bf003f93daa") == nil)
        #expect(ClaudeDesktopSessionLocator.continueURL(forDesktopSessionID: "local_bad id") == nil)
    }
}
