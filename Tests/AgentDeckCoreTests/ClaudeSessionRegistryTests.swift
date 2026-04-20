import Foundation
import Testing
@testable import AgentDeckCore

struct ClaudeSessionRegistryTests {
    @Test
    func claudeSessionRegistryRoundTripsTrackedSessions() throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("agent-deck-claude-registry-\(UUID().uuidString)", isDirectory: true)
        let fileURL = rootURL.appendingPathComponent("claude-session-registry.json")
        let registry = ClaudeSessionRegistry(fileURL: fileURL)

        defer {
            try? FileManager.default.removeItem(at: rootURL)
        }

        let records = [
            ClaudeTrackedSessionRecord(
                sessionID: "claude-session-1",
                title: "Claude · agent-deck",
                origin: .live,
                attachmentState: .attached,
                summary: "Working on the registry.",
                phase: .running,
                updatedAt: Date(timeIntervalSince1970: 1_000),
                jumpTarget: JumpTarget(
                    terminalApp: "Ghostty",
                    workspaceName: "agent-deck",
                    paneTitle: "claude ~/Personal/agent-deck",
                    workingDirectory: "/tmp/agent-deck",
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
    func claudeTrackedSessionRecordRestoresAsStale() {
        let record = ClaudeTrackedSessionRecord(
            sessionID: "claude-session-1",
            title: "Claude · agent-deck",
            origin: .live,
            attachmentState: .attached,
            summary: "Working on the registry.",
            phase: .running,
            updatedAt: .now,
            jumpTarget: JumpTarget(
                terminalApp: "Ghostty",
                workspaceName: "agent-deck",
                paneTitle: "claude ~/Personal/agent-deck",
                workingDirectory: "/tmp/agent-deck",
                terminalSessionID: "ghostty-claude",
                terminalTTY: "/dev/ttys002"
            )
        )

        #expect(record.session.attachmentState == .attached)
        #expect(record.restorableSession.attachmentState == .stale)
        #expect(record.restorableSession.jumpTarget?.terminalSessionID == "ghostty-claude")
    }
}
