import Foundation
import Testing
@testable import OpenIslandCore

struct ClaudeSessionRegistryTests {
    @Test
    func claudeSessionRegistryRoundTripsTrackedSessions() throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("open-island-claude-registry-\(UUID().uuidString)", isDirectory: true)
        let fileURL = rootURL.appendingPathComponent("claude-session-registry.json")
        let registry = ClaudeSessionRegistry(fileURL: fileURL)

        defer {
            try? FileManager.default.removeItem(at: rootURL)
        }

        let records = [
            ClaudeTrackedSessionRecord(
                sessionID: "claude-session-1",
                title: "Claude · open-island",
                origin: .live,
                attachmentState: .attached,
                summary: "Working on the registry.",
                phase: .running,
                updatedAt: Date(timeIntervalSince1970: 1_000),
                jumpTarget: JumpTarget(
                    terminalApp: "Ghostty",
                    workspaceName: "open-island",
                    paneTitle: "claude ~/Personal/open-island",
                    workingDirectory: "/tmp/open-island",
                    terminalSessionID: "ghostty-claude",
                    terminalTTY: "/dev/ttys002"
                ),
                claudeMetadata: ClaudeSessionMetadata(
                    transcriptPath: "/tmp/claude.jsonl",
                    initialUserPrompt: "Start with Claude recovery.",
                    lastUserPrompt: "Tighten Claude restart recovery.",
                    lastAssistantMessage: "Implementing the registry.",
                    currentTool: "Task",
                    currentToolInputPreview: "Implement ClaudeSessionRegistry",
                    model: "sonnet"
                )
            ),
        ]

        try registry.save(records)
        let reloaded = try registry.load()

        #expect(reloaded == records)
        #expect(reloaded.first?.session.claudeMetadata?.transcriptPath == "/tmp/claude.jsonl")
        #expect(reloaded.first?.session.jumpTarget?.terminalTTY == "/dev/ttys002")
    }

    @Test
    func recordRoundTripsWithAgentPID() throws {
        let record = ClaudeTrackedSessionRecord(
            sessionID: "claude-session-pid",
            title: "Claude · pid",
            summary: "",
            phase: .running,
            updatedAt: Date(timeIntervalSince1970: 1_500),
            agentPID: 9876
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(record)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(ClaudeTrackedSessionRecord.self, from: data)

        #expect(decoded.agentPID == 9876)
        #expect(decoded == record)
    }

    @Test
    func recordDecodesLegacyJSONWithoutAgentPIDAsNil() throws {
        let legacyJSON = """
        {
            "sessionID": "legacy",
            "title": "Legacy",
            "attachmentState": "stale",
            "summary": "",
            "phase": "completed",
            "updatedAt": "2026-01-01T00:00:00Z"
        }
        """

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(
            ClaudeTrackedSessionRecord.self,
            from: Data(legacyJSON.utf8)
        )

        #expect(decoded.agentPID == nil)
    }

    @Test
    func initFromSessionPullsAgentPIDFromClaudeMetadata() {
        let session = AgentSession(
            id: "claude-session-from-session",
            title: "Claude",
            tool: .claudeCode,
            origin: .live,
            attachmentState: .attached,
            phase: .running,
            summary: "",
            updatedAt: Date(timeIntervalSince1970: 1_000),
            claudeMetadata: ClaudeSessionMetadata(agentPID: 4321)
        )

        let record = ClaudeTrackedSessionRecord(session: session)

        #expect(record.agentPID == 4321)
    }

    @Test
    func restorableSessionPutsAgentPIDBackOnMetadata() {
        let record = ClaudeTrackedSessionRecord(
            sessionID: "claude-session-restore",
            title: "Claude",
            summary: "",
            phase: .running,
            updatedAt: Date(timeIntervalSince1970: 1_000),
            claudeMetadata: ClaudeSessionMetadata(transcriptPath: "/tmp/claude.jsonl"),
            agentPID: 4321
        )

        let restored = record.restorableSession

        #expect(restored.claudeMetadata?.agentPID == 4321)
        #expect(restored.claudeMetadata?.transcriptPath == "/tmp/claude.jsonl")
    }

    @Test
    func claudeTrackedSessionRecordRestoresAsStale() {
        let record = ClaudeTrackedSessionRecord(
            sessionID: "claude-session-1",
            title: "Claude · open-island",
            origin: .live,
            attachmentState: .attached,
            summary: "Working on the registry.",
            phase: .running,
            updatedAt: .now,
            jumpTarget: JumpTarget(
                terminalApp: "Ghostty",
                workspaceName: "open-island",
                paneTitle: "claude ~/Personal/open-island",
                workingDirectory: "/tmp/open-island",
                terminalSessionID: "ghostty-claude",
                terminalTTY: "/dev/ttys002"
            )
        )

        #expect(record.session.attachmentState == .attached)
        #expect(record.restorableSession.attachmentState == .stale)
        #expect(record.restorableSession.jumpTarget?.terminalSessionID == "ghostty-claude")
    }
}
