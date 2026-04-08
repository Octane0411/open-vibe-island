import Foundation
import Testing
@testable import OpenIslandCore

@Suite("TrackedSession")
struct TrackedSessionTests {

    // MARK: - Helpers

    private func makeSession(
        id: String = "abcdef123456",
        customTitle: String? = nil,
        workingDirectory: String? = nil,
        phase: SessionPhase = .running,
        processState: ProcessState = .unknown,
        origin: SessionOrigin? = nil,
        transcriptPath: String? = nil,
        lastActivityAt: Date = .now
    ) -> TrackedSession {
        TrackedSession(
            id: id,
            tool: .claudeCode,
            phase: phase,
            summary: "",
            startedAt: Date(timeIntervalSinceReferenceDate: 0),
            lastActivityAt: lastActivityAt,
            workingDirectory: workingDirectory,
            processState: processState,
            customTitle: customTitle,
            transcriptPath: transcriptPath,
            origin: origin
        )
    }

    // MARK: - displayName

    @Test("displayName prefers customTitle over workspace name")
    func displayNamePrefersCustomTitle() {
        let session = makeSession(
            customTitle: "My Custom Title",
            workingDirectory: "/Users/dan/projects/my-project"
        )
        #expect(session.displayName == "My Custom Title")
    }

    @Test("displayName falls back to last path component of workingDirectory")
    func displayNameFallsBackToWorkspaceName() {
        let session = makeSession(
            customTitle: nil,
            workingDirectory: "/Users/dan/projects/my-project"
        )
        #expect(session.displayName == "my-project")
    }

    @Test("displayName falls back to Session <id prefix> when both nil")
    func displayNameFallsBackToIDPrefix() {
        let session = makeSession(id: "abcdef12xyz", customTitle: nil, workingDirectory: nil)
        #expect(session.displayName == "Session abcdef12")
    }

    @Test("displayName falls back to id prefix when customTitle is empty string")
    func displayNameIgnoresEmptyCustomTitle() {
        let session = makeSession(id: "abcdef12xyz", customTitle: "", workingDirectory: nil)
        #expect(session.displayName == "Session abcdef12")
    }

    // MARK: - isVisible

    @Test("isVisible returns true for alive process")
    func isVisibleForAliveProcess() {
        let session = makeSession(processState: .alive)
        let ref = Date()
        #expect(session.isVisible(at: ref) == true)
    }

    @Test("isVisible returns false for gone process — no grace period")
    func isNotVisibleForGoneProcess() {
        let ref = Date()
        let goneSince = ref.addingTimeInterval(-5) // 5 seconds ago
        let session = makeSession(processState: .gone(since: goneSince))
        #expect(session.isVisible(at: ref) == false)
    }

    @Test("isVisible returns true for requiresAttention phase even when process gone")
    func isVisibleForRequiresAttentionPhase() {
        let ref = Date()
        let goneSince = ref.addingTimeInterval(-(60 * 60)) // 1 hour ago — well past grace period
        let approvalSession = makeSession(
            phase: .waitingForApproval,
            processState: .gone(since: goneSince)
        )
        let answerSession = makeSession(
            phase: .waitingForAnswer,
            processState: .gone(since: goneSince)
        )
        #expect(approvalSession.isVisible(at: ref) == true)
        #expect(answerSession.isVisible(at: ref) == true)
    }

    @Test("isVisible returns true for demo origin regardless of process state")
    func isVisibleForDemoOrigin() {
        let session = makeSession(processState: .unknown, origin: .demo)
        #expect(session.isVisible(at: Date()) == true)
    }

    // MARK: - ageBadge

    @Test("ageBadge shows <1m for age under 60 seconds")
    func ageBadgeLessThan1Minute() {
        let ref = Date()
        var session = makeSession()
        session = TrackedSession(
            id: session.id,
            tool: session.tool,
            phase: session.phase,
            summary: session.summary,
            startedAt: ref.addingTimeInterval(-30),
            lastActivityAt: session.lastActivityAt
        )
        #expect(session.ageBadge(at: ref) == "<1m")
    }

    @Test("ageBadge shows minutes for age under 1 hour")
    func ageBadge10Minutes() {
        let ref = Date()
        var session = makeSession()
        session = TrackedSession(
            id: session.id,
            tool: session.tool,
            phase: session.phase,
            summary: session.summary,
            startedAt: ref.addingTimeInterval(-(10 * 60)),
            lastActivityAt: session.lastActivityAt
        )
        #expect(session.ageBadge(at: ref) == "10m")
    }

    @Test("ageBadge shows hours for age under 1 day")
    func ageBadge1Hour() {
        let ref = Date()
        var session = makeSession()
        session = TrackedSession(
            id: session.id,
            tool: session.tool,
            phase: session.phase,
            summary: session.summary,
            startedAt: ref.addingTimeInterval(-(3600)),
            lastActivityAt: session.lastActivityAt
        )
        #expect(session.ageBadge(at: ref) == "1h")
    }

    @Test("ageBadge shows days for age of 1 day or more")
    func ageBadge1Day() {
        let ref = Date()
        var session = makeSession()
        session = TrackedSession(
            id: session.id,
            tool: session.tool,
            phase: session.phase,
            summary: session.summary,
            startedAt: ref.addingTimeInterval(-(86400)),
            lastActivityAt: session.lastActivityAt
        )
        #expect(session.ageBadge(at: ref) == "1d")
    }
}
