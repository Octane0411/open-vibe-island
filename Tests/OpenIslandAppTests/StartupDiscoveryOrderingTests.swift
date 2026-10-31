import Foundation
import Testing
@testable import OpenIslandApp
import OpenIslandCore

@MainActor
struct StartupDiscoveryOrderingTests {
    @Test(arguments: [true, false])
    func liveSessionAndApprovalSurviveEitherStartupOrdering(discoveryFinishesLast: Bool) {
        let environment = AppModelTestEnvironment()
        let model = environment.makeModel()
        let payload = startupPayload(cached: [record("cached")])
        if !discoveryFinishesLast { model.discovery.applyStartupDiscoveryPayload(payload) }

        let request = PermissionRequest(title: "Approve edit", summary: "main.swift", affectedPath: "/tmp/main.swift")
        model.applyTrackedEvent(.sessionStarted(SessionStarted(
            sessionID: "live", title: "Live Claude", tool: .claudeCode, summary: "Running", timestamp: .now
        )), ingress: .bridge)
        model.applyTrackedEvent(.permissionRequested(PermissionRequested(
            sessionID: "live", request: request, timestamp: .now
        )), ingress: .bridge)
        if discoveryFinishesLast { model.discovery.applyStartupDiscoveryPayload(payload) }

        #expect(Set(model.state.sessions.map(\.id)) == ["live", "cached"])
        #expect(model.state.session(id: "live")?.permissionRequest == request)
        #expect(model.state.session(id: "live")?.phase == .waitingForApproval)
        #expect(model.state.session(id: "live")?.attachmentState == .attached)
    }

    @Test
    func startupRecordsCannotOverwriteLiveActivityEvenWithLaterTimestamps() {
        let environment = AppModelTestEnvironment()
        let model = environment.makeModel()
        let request = PermissionRequest(title: "Approve", summary: "Live request", affectedPath: "/tmp/live")
        let live = AgentSession(id: "same", title: "Live", tool: .codex, attachmentState: .attached,
                                phase: .waitingForApproval, summary: "Live request", updatedAt: .now,
                                permissionRequest: request)
        model.state = SessionState(sessions: [live])
        // Clock skew must not give a cached snapshot authority over live ingress.
        let stale = record("same", updatedAt: .now.addingTimeInterval(3_600))
        model.discovery.applyStartupDiscoveryPayload(startupPayload(cached: [stale], discovered: [stale]))

        #expect(model.state.session(id: "same") == live)
        #expect(model.state.sessions.count == 1)
    }

    @Test
    func startupCannotResurrectAnEndedSession() {
        let environment = AppModelTestEnvironment()
        let model = environment.makeModel()
        var ended = AgentSession(id: "ended", title: "Finished", tool: .codex, attachmentState: .detached,
                                 phase: .completed, summary: "Done", updatedAt: .now)
        ended.isSessionEnded = true
        model.state = SessionState(sessions: [ended])
        model.discovery.applyStartupDiscoveryPayload(startupPayload(cached: [record("ended")]))

        #expect(model.state.session(id: "ended") == ended)
    }

    private func record(_ id: String, updatedAt: Date = .now) -> CodexTrackedSessionRecord {
        CodexTrackedSessionRecord(sessionID: id, title: "Cached", summary: "Old snapshot",
                                  phase: .running, updatedAt: updatedAt)
    }

    private func startupPayload(
        cached: [CodexTrackedSessionRecord], discovered: [CodexTrackedSessionRecord] = []
    ) -> SessionDiscoveryCoordinator.StartupDiscoveryPayload {
        .init(codexRecords: cached, codexRecordsNeedPrune: false,
              claudeRecords: [], claudeRecordsNeedPrune: false,
              openCodeRecords: [], openCodeRecordsNeedPrune: false,
              cursorRecords: [], cursorRecordsNeedPrune: false,
              piRecords: [], piRecordsNeedPrune: false,
              discoveredCodexRecords: discovered, discoveredClaudeSessions: [], hooksBinaryURL: nil)
    }
}
