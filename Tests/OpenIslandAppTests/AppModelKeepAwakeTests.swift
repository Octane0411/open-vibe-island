import Foundation
import Testing
@testable import OpenIslandApp
import OpenIslandCore

@MainActor
@Suite(.serialized)
struct AppModelKeepAwakeTests {
    init() {
        [
            "app.keepAwakeWhileAgentsBusy",
            "overlay.sound.muted",
        ].forEach(UserDefaults.standard.removeObject(forKey:))
    }

    private func makeSession(id: String, phase: SessionPhase, now: Date) -> AgentSession {
        var session = AgentSession(
            id: id,
            title: "Claude · test",
            tool: .claudeCode,
            origin: .live,
            attachmentState: .attached,
            phase: phase,
            summary: "Test",
            updatedAt: now,
            jumpTarget: JumpTarget(
                terminalApp: "Ghostty",
                workspaceName: "keepawake",
                paneTitle: "claude ~/keepawake",
                workingDirectory: "/tmp/keepawake",
                terminalSessionID: "ghostty-keepawake"
            ),
            claudeMetadata: ClaudeSessionMetadata(
                transcriptPath: "/tmp/keepawake-\(id).jsonl"
            )
        )
        session.isProcessAlive = true
        return session
    }

    @Test
    func autoModeHoldsAssertionWhileSessionRuns() {
        let model = AppModel()
        #expect(model.keepAwakeWhileAgentsBusy)

        model.state = SessionState(sessions: [
            makeSession(id: "running", phase: .running, now: Date(timeIntervalSince1970: 2_000))
        ])

        #expect(model.isKeepAwakeActive)
        #expect(model.sleepPrevention.isActive)

        model.sleepPrevention.stop()
    }

    @Test
    func completedSessionsDoNotHoldAssertion() {
        let model = AppModel()

        model.state = SessionState(sessions: [
            makeSession(id: "done", phase: .completed, now: Date(timeIntervalSince1970: 2_000))
        ])

        #expect(!model.isKeepAwakeActive)
        #expect(!model.sleepPrevention.isActive)
    }

    @Test
    func disablingAutoModeReleasesAssertion() {
        let model = AppModel()

        model.state = SessionState(sessions: [
            makeSession(id: "running", phase: .running, now: Date(timeIntervalSince1970: 2_000))
        ])
        #expect(model.sleepPrevention.isActive)

        model.keepAwakeWhileAgentsBusy = false
        #expect(!model.isKeepAwakeActive)
        #expect(!model.sleepPrevention.isActive)
    }

    @Test
    func manualToggleHoldsAssertionWithoutSessions() {
        let model = AppModel()
        model.state = SessionState()
        #expect(!model.isKeepAwakeActive)

        model.toggleManualKeepAwake()
        #expect(model.isManualKeepAwakeEnabled)
        #expect(model.isKeepAwakeActive)
        #expect(model.sleepPrevention.isActive)

        model.toggleManualKeepAwake()
        #expect(!model.isKeepAwakeActive)
        #expect(!model.sleepPrevention.isActive)
    }

    @Test
    func manualToggleOverridesDisabledAutoMode() {
        let model = AppModel()
        model.keepAwakeWhileAgentsBusy = false
        model.state = SessionState(sessions: [
            makeSession(id: "running", phase: .running, now: Date(timeIntervalSince1970: 2_000))
        ])
        #expect(!model.isKeepAwakeActive)

        model.toggleManualKeepAwake()
        #expect(model.isKeepAwakeActive)
        model.toggleManualKeepAwake()
        #expect(!model.isKeepAwakeActive)
    }

    @Test
    func sleepPreventionServiceStartStopIsIdempotent() {
        let service = SleepPreventionService()
        #expect(!service.isActive)

        service.start(reason: "Open Island tests")
        service.start(reason: "Open Island tests")
        #expect(service.isActive)

        service.stop()
        service.stop()
        #expect(!service.isActive)
    }
}
