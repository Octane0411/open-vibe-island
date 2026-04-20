import Foundation
import SwiftUI
import Testing
@testable import OpenIslandApp
import OpenIslandCore

@MainActor
struct AgentsGridRightSlotTests {
    /// The right-slot grid must sort sessions by firstSeenAt ascending, so
    /// its order stays stable even when panel-sort signals (e.g. updatedAt)
    /// churn.
    @Test
    func rightSlotCellsAreSortedByFirstSeenAtNotUpdatedAt() {
        let model = AppModel()
        model.islandRightSlot = .agents

        let now = Date(timeIntervalSince1970: 100_000)
        // Three Claude sessions. firstSeenAt order: A < B < C.
        // updatedAt order (what panel typically sorts by): C > A > B.
        // The right-slot grid should still render A, B, C regardless.
        let sessionA = makeSession(id: "A", firstSeenAt: now,                     updatedAt: now.addingTimeInterval(60))
        let sessionB = makeSession(id: "B", firstSeenAt: now.addingTimeInterval(10), updatedAt: now.addingTimeInterval(5))
        let sessionC = makeSession(id: "C", firstSeenAt: now.addingTimeInterval(20), updatedAt: now.addingTimeInterval(120))

        model.state = SessionState(sessions: [sessionC, sessionA, sessionB])

        guard case let .agents(cells)? = model.islandClosedRightSlotContent(now: now.addingTimeInterval(130)) else {
            Issue.record("Expected .agents right-slot content")
            return
        }
        #expect(cells.count == 3)

        // Nudge B's updatedAt so the panel-sort would shuffle it to the front.
        var bumped = sessionB
        bumped.updatedAt = now.addingTimeInterval(1_000)
        model.state = SessionState(sessions: [sessionC, sessionA, bumped])

        guard case let .agents(cells2)? = model.islandClosedRightSlotContent(now: now.addingTimeInterval(1_100)) else {
            Issue.record("Expected .agents right-slot content after bump")
            return
        }
        // Grid order must still be A, B, C (firstSeenAt ascending) even though
        // B is now the most recently updated.
        #expect(cells == cells2)
    }

    /// Sessions beyond the 9-slot threshold collapse into a single trailing
    /// overflow cell showing the remainder count.
    @Test
    func moreThanNineSessionsFoldIntoOverflow() {
        let model = AppModel()
        model.islandRightSlot = .agents
        let now = Date(timeIntervalSince1970: 200_000)

        var sessions: [AgentSession] = []
        for i in 0..<12 {
            sessions.append(makeSession(
                id: "s-\(i)",
                firstSeenAt: now.addingTimeInterval(Double(i)),
                updatedAt: now.addingTimeInterval(Double(i) + 100)
            ))
        }
        model.state = SessionState(sessions: sessions)

        guard case let .agents(cells)? = model.islandClosedRightSlotContent(now: now.addingTimeInterval(500)) else {
            Issue.record("Expected .agents right-slot content")
            return
        }
        #expect(cells.count == 8)
        if case let .overflow(n) = cells[7] {
            #expect(n == 5) // 12 total - 7 visible session cells = 5
        } else {
            Issue.record("Expected last cell to be .overflow")
        }
    }

    /// Per-session state derives from `SessionPhase`: waiting-for-approval /
    /// waiting-for-answer map to `.waiting`, running to `.running`, and
    /// everything else (completed, stale) to `.idle`.
    @Test
    func cellStateReflectsSessionPhase() {
        let model = AppModel()
        model.islandRightSlot = .agents
        let now = Date(timeIntervalSince1970: 300_000)

        let running  = makeSession(id: "r", firstSeenAt: now,                         updatedAt: now, phase: .running)
        let waitingA = makeSession(
            id: "w",
            firstSeenAt: now.addingTimeInterval(1),
            updatedAt: now,
            phase: .waitingForApproval,
            permissionRequest: PermissionRequest(title: "edit", summary: "edit", affectedPath: "/tmp/x")
        )
        let completed = makeSession(id: "c", firstSeenAt: now.addingTimeInterval(2), updatedAt: now, phase: .completed)

        model.state = SessionState(sessions: [running, waitingA, completed])

        guard case let .agents(cells)? = model.islandClosedRightSlotContent(now: now.addingTimeInterval(10)) else {
            Issue.record("Expected .agents right-slot content")
            return
        }
        #expect(cells.count == 3)

        guard cells.count == 3,
              case let .session(_, s0) = cells[0],
              case let .session(_, s1) = cells[1],
              case let .session(_, s2) = cells[2]
        else {
            Issue.record("Expected three session cells")
            return
        }
        #expect(s0 == .running)
        #expect(s1 == .waiting)
        #expect(s2 == .idle)
    }

    // MARK: - helpers

    private func makeSession(
        id: String,
        firstSeenAt: Date,
        updatedAt: Date,
        phase: SessionPhase = .running,
        permissionRequest: PermissionRequest? = nil
    ) -> AgentSession {
        var session = AgentSession(
            id: id,
            title: "Claude · \(id)",
            tool: .claudeCode,
            origin: .live,
            attachmentState: .attached,
            phase: phase,
            summary: "",
            updatedAt: updatedAt,
            firstSeenAt: firstSeenAt,
            permissionRequest: permissionRequest,
            jumpTarget: JumpTarget(
                terminalApp: "Ghostty",
                workspaceName: id,
                paneTitle: "claude ~/\(id)",
                workingDirectory: "/tmp/\(id)",
                terminalSessionID: "ghostty-\(id)"
            ),
            claudeMetadata: ClaudeSessionMetadata(
                transcriptPath: "/tmp/\(id).jsonl",
                currentTool: "Task"
            )
        )
        session.isProcessAlive = true
        session.isHookManaged = true
        return session
    }
}
