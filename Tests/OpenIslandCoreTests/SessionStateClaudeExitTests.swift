import Foundation
import Testing
@testable import OpenIslandCore

struct SessionStateClaudeExitTests {
    private func hookManagedClaudeSession(
        id: String = "claude-session",
        phase: SessionPhase = .running,
        updatedAt: Date
    ) -> AgentSession {
        var session = AgentSession(
            id: id,
            title: "Claude · repo",
            tool: .claudeCode,
            origin: .live,
            attachmentState: .attached,
            phase: phase,
            summary: "Working",
            updatedAt: updatedAt
        )
        session.isHookManaged = true
        session.isSessionEnded = false
        session.isProcessAlive = true
        session.processNotSeenCount = 0
        return session
    }

    private func hookManagedOpenCodeSession(
        id: String = "opencode-session",
        updatedAt: Date
    ) -> AgentSession {
        var session = AgentSession(
            id: id,
            title: "OpenCode · repo",
            tool: .openCode,
            origin: .live,
            attachmentState: .attached,
            phase: .running,
            summary: "Working",
            updatedAt: updatedAt
        )
        session.isHookManaged = true
        session.isSessionEnded = false
        session.isProcessAlive = true
        session.processNotSeenCount = 0
        return session
    }

    @Test
    func claudeProcessExitedFlipsSessionToCompleted() {
        let startedAt = Date(timeIntervalSince1970: 10_000)
        var state = SessionState(sessions: [
            hookManagedClaudeSession(updatedAt: startedAt)
        ])

        let exitedAt = startedAt.addingTimeInterval(30)
        state.apply(
            .claudeProcessExited(
                ClaudeProcessExited(
                    sessionID: "claude-session",
                    pid: 4242,
                    timestamp: exitedAt
                )
            )
        )

        let session = state.session(id: "claude-session")
        #expect(session?.phase == .completed)
        #expect(session?.isSessionEnded == true)
        #expect(session?.isProcessAlive == false)
        #expect(session?.processNotSeenCount == 0)
        #expect(session?.updatedAt == exitedAt)
    }

    @Test
    func claudeProcessExitedIsNoOpWhenSessionAlreadyEnded() {
        let startedAt = Date(timeIntervalSince1970: 11_000)
        var session = hookManagedClaudeSession(phase: .completed, updatedAt: startedAt)
        session.isSessionEnded = true
        var state = SessionState(sessions: [session])

        let before = state.session(id: "claude-session")

        state.apply(
            .claudeProcessExited(
                ClaudeProcessExited(
                    sessionID: "claude-session",
                    pid: 4242,
                    timestamp: startedAt.addingTimeInterval(60)
                )
            )
        )

        let after = state.session(id: "claude-session")
        #expect(before == after)
    }

    @Test
    func claudeProcessExitedIsNoOpWhenSessionUnknown() {
        var state = SessionState()

        state.apply(
            .claudeProcessExited(
                ClaudeProcessExited(
                    sessionID: "missing",
                    pid: 1,
                    timestamp: Date(timeIntervalSince1970: 12_000)
                )
            )
        )

        #expect(state.sessions.isEmpty)
    }

    @Test
    func claudeProcessExitedRoundTripsThroughCodable() throws {
        let event = AgentEvent.claudeProcessExited(
            ClaudeProcessExited(
                sessionID: "claude-session",
                pid: 9876,
                timestamp: Date(timeIntervalSince1970: 13_000)
            )
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(event)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(AgentEvent.self, from: data)

        #expect(decoded == event)
    }

    @Test
    func markProcessLivenessDoesNotEvictHookManagedClaudeSession() {
        let startedAt = Date(timeIntervalSince1970: 14_000)
        var state = SessionState(sessions: [
            hookManagedClaudeSession(id: "claude-session", updatedAt: startedAt),
            hookManagedOpenCodeSession(id: "opencode-session", updatedAt: startedAt)
        ])

        for _ in 0..<10 {
            _ = state.markProcessLiveness(aliveSessionIDs: [])
        }

        let claude = state.session(id: "claude-session")
        #expect(claude?.isSessionEnded == false)
        #expect(claude?.phase == .running)

        let openCode = state.session(id: "opencode-session")
        #expect(openCode?.isSessionEnded == true)
        #expect(openCode?.phase == .completed)
    }
}
