import Foundation
import SwiftUI
import Testing
@testable import OpenIslandApp
import OpenIslandCore

@MainActor
struct AgentsGridRightSlotTests {
    /// At bulk first observation (e.g. app launch) ties are broken by
    /// session.firstSeenAt so historical order is preserved.
    @Test
    func bulkFirstObservationOrdersByHistoricalFirstSeenAt() {
        let model = AppModel()
        model.islandRightSlot = .agents

        let now = Date(timeIntervalSince1970: 100_000)
        let sessionA = makeSession(id: "A", firstSeenAt: now,                       updatedAt: now.addingTimeInterval(60))
        let sessionB = makeSession(id: "B", firstSeenAt: now.addingTimeInterval(10), updatedAt: now.addingTimeInterval(5))
        let sessionC = makeSession(id: "C", firstSeenAt: now.addingTimeInterval(20), updatedAt: now.addingTimeInterval(120))

        // Insertion order differs from historical order — the grid must still
        // present A, B, C.
        model.state = SessionState(sessions: [sessionC, sessionA, sessionB])
        guard case let .agents(cells)? = model.islandClosedRightSlotContent() else {
            Issue.record("Expected .agents right-slot content")
            return
        }
        #expect(cells.count == 3)

        // A panel-sort signal (updatedAt) churn must not reshuffle the grid.
        var bumped = sessionB
        bumped.updatedAt = now.addingTimeInterval(1_000)
        model.state = SessionState(sessions: [sessionC, sessionA, bumped])
        guard case let .agents(cells2)? = model.islandClosedRightSlotContent() else {
            Issue.record("Expected .agents right-slot content after bump")
            return
        }
        #expect(cells == cells2)
    }

    /// The critical "user adds a new session" case: whatever the newcomer's
    /// session.firstSeenAt value is (could be earlier than existing peers
    /// when the session was discovered from rollout / cache), the tile must
    /// still land at the end of the grid — because it's the newcomer in
    /// observation-time.
    @Test
    func newlyObservedSessionAlwaysLandsAtTheEndRegardlessOfHistoricalTime() {
        let model = AppModel()
        model.islandRightSlot = .agents

        let now = Date(timeIntervalSince1970: 200_000)
        let sessionA = makeSession(id: "A", firstSeenAt: now,                       updatedAt: now)
        let sessionB = makeSession(id: "B", firstSeenAt: now.addingTimeInterval(10), updatedAt: now.addingTimeInterval(10))
        let sessionC = makeSession(id: "C", firstSeenAt: now.addingTimeInterval(20), updatedAt: now.addingTimeInterval(20))

        model.state = SessionState(sessions: [sessionA, sessionB, sessionC])
        _ = model.islandClosedRightSlotContent()

        // Later: a fourth session is discovered, but its historical
        // firstSeenAt pre-dates everything (e.g. found in a rollout tail).
        let sessionD = makeSession(
            id: "D",
            firstSeenAt: now.addingTimeInterval(-500),
            updatedAt: now.addingTimeInterval(40)
        )
        model.state = SessionState(sessions: [sessionA, sessionB, sessionC, sessionD])
        guard case let .agents(cells)? = model.islandClosedRightSlotContent() else {
            Issue.record("Expected .agents right-slot content")
            return
        }
        #expect(cells.count == 4)
        #expect(cells.first == Self.cellFor(sessionA))
        #expect(cells.last == Self.cellFor(sessionD))
    }

    /// A session that leaves the surfaced set for a moment (e.g. attachment
    /// flip, transient stale) must return to its original slot when visible
    /// again — not re-observed as a newcomer.
    @Test
    func returningSessionKeepsItsOriginalSlot() {
        let model = AppModel()
        model.islandRightSlot = .agents

        let now = Date(timeIntervalSince1970: 300_000)
        let sessionA = makeSession(id: "A", firstSeenAt: now,                       updatedAt: now)
        let sessionB = makeSession(id: "B", firstSeenAt: now.addingTimeInterval(10), updatedAt: now.addingTimeInterval(10))
        let sessionC = makeSession(id: "C", firstSeenAt: now.addingTimeInterval(20), updatedAt: now.addingTimeInterval(20))

        model.state = SessionState(sessions: [sessionA, sessionB, sessionC])
        _ = model.islandClosedRightSlotContent()

        // B transiently leaves the surfaced set.
        model.state = SessionState(sessions: [sessionA, sessionC])
        _ = model.islandClosedRightSlotContent()

        // B returns. Its ticket is preserved → order is still A, B, C.
        model.state = SessionState(sessions: [sessionA, sessionB, sessionC])
        guard case let .agents(cells)? = model.islandClosedRightSlotContent() else {
            Issue.record("Expected .agents right-slot content")
            return
        }
        #expect(cells.count == 3)
        #expect(cells[0] == Self.cellFor(sessionA))
        #expect(cells[1] == Self.cellFor(sessionB))
        #expect(cells[2] == Self.cellFor(sessionC))
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

        guard case let .agents(cells)? = model.islandClosedRightSlotContent() else {
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

        guard case let .agents(cells)? = model.islandClosedRightSlotContent() else {
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

    private static func cellFor(_ session: AgentSession) -> AgentGridCell {
        let color = Color(hex: session.tool.brandColorHex) ?? .gray
        let state: AgentGridCellState
        if session.phase.requiresAttention {
            state = .waiting
        } else if session.phase == .running {
            state = .running
        } else {
            state = .idle
        }
        return .session(color: color, state: state)
    }

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
