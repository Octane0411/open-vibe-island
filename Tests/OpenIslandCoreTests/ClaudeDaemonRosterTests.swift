import Foundation
import Testing
@testable import OpenIslandCore

struct ClaudeDaemonRosterTests {
    @Test
    func unclaimedSparesAreReportedAndClaimedSessionsAreNot() {
        let roster = Data("""
        {
          "proto": 1,
          "workers": {
            "4224385d": {"sessionId": "4224385D-7E48-4983-A472-424799717F5B", "dispatch": {"source": "spare", "launch": {"mode": "prompt"}}},
            "c89909c8": {"sessionId": "c89909c8-0000-4000-8000-000000000000", "dispatch": {"source": "fleet", "launch": {"mode": "resume"}}},
            "1a8e43d4": {"sessionId": "1a8e43d4-12a2-4ad8-be58-cc337ea2d5f8", "dispatch": {"source": "shell", "launch": {"mode": "prompt"}}},
            "e7590e17": {"dispatch": {"source": "spare", "sessionId": "e7590e17-0000-4000-8000-000000000000"}},
            "broken": "not an object"
          }
        }
        """.utf8)

        #expect(ClaudeDaemonRoster.unclaimedSpareSessionIDs(rosterData: roster) == [
            "4224385d-7e48-4983-a472-424799717f5b",
            "e7590e17-0000-4000-8000-000000000000",
        ])
    }

    @Test
    func unreadableRosterFailsOpen() throws {
        #expect(ClaudeDaemonRoster.unclaimedSpareSessionIDs(rosterData: Data("{".utf8)).isEmpty)
        #expect(ClaudeDaemonRoster.unclaimedSpareSessionIDs(rosterData: Data(#"{"workers": []}"#.utf8)).isEmpty)
        #expect(ClaudeDaemonRoster.unclaimedSpareSessionIDs(
            at: FileManager.default.temporaryDirectory.appendingPathComponent("missing-\(UUID().uuidString).json")
        ).isEmpty)
    }

    @Test
    func rosterLivesUnderTheClaudeConfigDirectory() {
        let url = ClaudeDaemonRoster.rosterURL(environment: ["CLAUDE_CONFIG_DIR": "/tmp/claude-config"])
        if ClaudeConfigDirectory.customDirectory == nil {
            #expect(url.path == "/tmp/claude-config/daemon/roster.json")
        }
        #expect(url.lastPathComponent == "roster.json")
    }
}
