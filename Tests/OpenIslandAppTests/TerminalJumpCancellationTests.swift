import Foundation
import Testing
@testable import OpenIslandApp
import OpenIslandCore

@MainActor
struct TerminalJumpCancellationTests {
    @Test
    func selectingAnotherSessionDuringDismissalRunsOnlyTheLatestJump() async throws {
        let environment = AppModelTestEnvironment()
        let delay = JumpDelayGate()
        let calls = JumpCallLog()
        let model = environment.makeModel(
            terminalJumpAction: { target in calls.record(target.workspaceName); return target.workspaceName },
            jumpDismissDelay: { await delay.wait() }
        )
        model.notchStatus = .opened
        let obsolete = model.jumpToSession(session("A"))
        try await waitUntil { await delay.isWaiting }
        let latest = model.jumpToSession(session("B"))
        await latest?.value
        await delay.release()
        await obsolete?.value

        #expect(calls.values == ["B"])
        #expect(model.lastActionMessage == "B")
    }

    @Test
    func anInFlightJumpFinishesBeforeTheNextPlatformAction() async throws {
        let environment = AppModelTestEnvironment()
        let calls = JumpCallLog()
        let releaseFirst = DispatchSemaphore(value: 0)
        let model = environment.makeModel(terminalJumpAction: { target in
            calls.record("start \(target.workspaceName)")
            if target.workspaceName == "A" {
                // Always bounded, including if the test fails before releasing it.
                _ = releaseFirst.wait(timeout: .now() + 3)
            }
            calls.record("finish \(target.workspaceName)")
            return target.workspaceName
        })
        let first = model.jumpToSession(session("A"))
        try await waitUntil { calls.values.contains("start A") }
        let second = model.jumpToSession(session("B"))
        try await Task.sleep(for: .milliseconds(100))
        #expect(calls.values == ["start A"])
        releaseFirst.signal()
        await first?.value
        await second?.value

        #expect(calls.values == ["start A", "finish A", "start B", "finish B"])
        #expect(model.lastActionMessage == "B")
    }

    private func session(_ id: String) -> AgentSession {
        AgentSession(id: id, title: id, tool: .codex, phase: .running, summary: "", updatedAt: .now,
                     jumpTarget: JumpTarget(terminalApp: "Ghostty", workspaceName: id, paneTitle: id, workingDirectory: "/tmp"))
    }

    private func waitUntil(_ condition: () async -> Bool) async throws {
        let deadline = ContinuousClock.now + .seconds(3)
        while !(await condition()), ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(1))
        }
        #expect(await condition())
    }
}

private actor JumpDelayGate {
    private var continuation: CheckedContinuation<Void, Never>?
    var isWaiting: Bool { continuation != nil }
    func wait() async { await withCheckedContinuation { continuation = $0 } }
    func release() { continuation?.resume(); continuation = nil }
}

private final class JumpCallLog: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [String] = []
    var values: [String] { lock.withLock { storage } }
    func record(_ value: String) { lock.withLock { storage.append(value) } }
}
