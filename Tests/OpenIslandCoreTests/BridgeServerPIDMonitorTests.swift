import Darwin
import Dispatch
import Foundation
import Testing
@testable import OpenIslandCore

struct BridgeServerPIDMonitorTests {
    @Test
    func sessionStartWithAgentPIDRegistersMonitor() async throws {
        let socketURL = BridgeSocketLocation.uniqueTestURL()
        let monitor = ClaudePIDMonitor(gracePeriod: 0)
        let server = BridgeServer(socketURL: socketURL, claudePIDMonitor: monitor)
        try server.start()
        defer { server.stop() }

        let process = try spawnSleep(duration: 10)
        defer { process.ensureExited() }

        let payload = ClaudeHookPayload(
            cwd: "/tmp/demo",
            hookEventName: .sessionStart,
            sessionID: "claude-pid-1",
            agentPID: process.processIdentifier
        )

        let response = try await sendOnBackgroundQueue(.processClaudeHook(payload), socketURL: socketURL)
        #expect(response == .acknowledged)

        #expect(monitor.isTracking(sessionID: "claude-pid-1") == true)
        #expect(monitor.currentPID(for: "claude-pid-1") == process.processIdentifier)
    }

    @Test
    func sessionStartWithoutAgentPIDDoesNotRegisterMonitor() async throws {
        let socketURL = BridgeSocketLocation.uniqueTestURL()
        let monitor = ClaudePIDMonitor(gracePeriod: 0)
        let server = BridgeServer(socketURL: socketURL, claudePIDMonitor: monitor)
        try server.start()
        defer { server.stop() }

        let payload = ClaudeHookPayload(
            cwd: "/tmp/demo",
            hookEventName: .sessionStart,
            sessionID: "claude-pid-legacy"
        )

        let response = try await sendOnBackgroundQueue(.processClaudeHook(payload), socketURL: socketURL)
        #expect(response == .acknowledged)

        #expect(monitor.isTracking(sessionID: "claude-pid-legacy") == false)
    }

    @Test
    func sessionEndUntracksMonitor() async throws {
        let socketURL = BridgeSocketLocation.uniqueTestURL()
        let monitor = ClaudePIDMonitor(gracePeriod: 0)
        let server = BridgeServer(socketURL: socketURL, claudePIDMonitor: monitor)
        try server.start()
        defer { server.stop() }

        let process = try spawnSleep(duration: 10)
        defer { process.ensureExited() }

        let startPayload = ClaudeHookPayload(
            cwd: "/tmp/demo",
            hookEventName: .sessionStart,
            sessionID: "claude-pid-end",
            agentPID: process.processIdentifier
        )
        _ = try await sendOnBackgroundQueue(.processClaudeHook(startPayload), socketURL: socketURL)
        #expect(monitor.isTracking(sessionID: "claude-pid-end") == true)

        let endPayload = ClaudeHookPayload(
            cwd: "/tmp/demo",
            hookEventName: .sessionEnd,
            sessionID: "claude-pid-end",
            agentPID: process.processIdentifier
        )
        let endResponse = try await sendOnBackgroundQueue(.processClaudeHook(endPayload), socketURL: socketURL)
        #expect(endResponse == .acknowledged)

        #expect(monitor.isTracking(sessionID: "claude-pid-end") == false)
    }

    @Test
    func kernelExitEmitsClaudeProcessExited() async throws {
        let socketURL = BridgeSocketLocation.uniqueTestURL()
        let monitor = ClaudePIDMonitor(gracePeriod: 0)
        let server = BridgeServer(socketURL: socketURL, claudePIDMonitor: monitor)
        try server.start()
        defer { server.stop() }

        let observer = LocalBridgeClient(socketURL: socketURL)
        let stream = try observer.connect()
        defer { observer.disconnect() }
        try await observer.send(.registerClient(role: .observer))

        // Long enough to register the hook first, short enough to exit during the test.
        let process = try spawnSleep(duration: 0.5)
        let pid = process.processIdentifier

        let payload = ClaudeHookPayload(
            cwd: "/tmp/demo",
            hookEventName: .sessionStart,
            sessionID: "claude-pid-exit",
            agentPID: pid
        )
        _ = try await sendOnBackgroundQueue(.processClaudeHook(payload), socketURL: socketURL)
        #expect(monitor.isTracking(sessionID: "claude-pid-exit") == true)

        var iterator = stream.makeAsyncIterator()
        let exitEvent = try await nextMatchingEvent(from: &iterator, maxEvents: 12) { event in
            if case .claudeProcessExited = event { return true }
            return false
        }

        if case let .claudeProcessExited(info) = exitEvent {
            #expect(info.sessionID == "claude-pid-exit")
            #expect(info.pid == pid)
        } else {
            Issue.record("Expected a claudeProcessExited event")
        }

        #expect(monitor.isTracking(sessionID: "claude-pid-exit") == false)

        process.ensureExited()
    }

    @Test
    func subagentHookDoesNotRegisterMonitor() async throws {
        let socketURL = BridgeSocketLocation.uniqueTestURL()
        let monitor = ClaudePIDMonitor(gracePeriod: 0)
        let server = BridgeServer(socketURL: socketURL, claudePIDMonitor: monitor)
        try server.start()
        defer { server.stop() }

        let process = try spawnSleep(duration: 10)
        defer { process.ensureExited() }

        let payload = ClaudeHookPayload(
            cwd: "/tmp/demo",
            hookEventName: .userPromptSubmit,
            sessionID: "claude-pid-subagent",
            agentID: "subagent-1",
            agentPID: process.processIdentifier
        )

        _ = try await sendOnBackgroundQueue(.processClaudeHook(payload), socketURL: socketURL)

        #expect(monitor.isTracking(sessionID: "claude-pid-subagent") == false)
    }

    @Test
    func resumeFlowReplacesMonitor() async throws {
        let socketURL = BridgeSocketLocation.uniqueTestURL()
        let monitor = ClaudePIDMonitor(gracePeriod: 0)
        let server = BridgeServer(socketURL: socketURL, claudePIDMonitor: monitor)
        try server.start()
        defer { server.stop() }

        let first = try spawnSleep(duration: 10)
        let firstPID = first.processIdentifier
        let second = try spawnSleep(duration: 10)
        let secondPID = second.processIdentifier
        defer {
            first.ensureExited()
            second.ensureExited()
        }

        let startPayload = ClaudeHookPayload(
            cwd: "/tmp/demo",
            hookEventName: .sessionStart,
            sessionID: "claude-pid-resume",
            agentPID: firstPID
        )
        _ = try await sendOnBackgroundQueue(.processClaudeHook(startPayload), socketURL: socketURL)
        #expect(monitor.currentPID(for: "claude-pid-resume") == firstPID)

        let resumePayload = ClaudeHookPayload(
            cwd: "/tmp/demo",
            hookEventName: .userPromptSubmit,
            sessionID: "claude-pid-resume",
            agentPID: secondPID
        )
        _ = try await sendOnBackgroundQueue(.processClaudeHook(resumePayload), socketURL: socketURL)
        #expect(monitor.currentPID(for: "claude-pid-resume") == secondPID)

        // Kill the first (now-stale) PID. Its DispatchSource fired inside the
        // monitor was cancelled when the second track() replaced the record,
        // so no handleClaudeProcessExit should occur for firstPID. Even if
        // the cancellation races, the bridge's race guard drops stale exits
        // whose pid != currentPID. Assert the monitor remains anchored to
        // the new PID after any in-flight exit has had a chance to land.
        first.terminate()
        first.waitUntilExit()

        try await Task.sleep(nanoseconds: 500_000_000)

        #expect(monitor.isTracking(sessionID: "claude-pid-resume") == true)
        #expect(monitor.currentPID(for: "claude-pid-resume") == secondPID)
    }
}

// MARK: - Helpers

private enum BridgeServerPIDMonitorTestError: Error {
    case streamEnded
    case noMatchingEvent
}

private func nextEvent(
    from iterator: inout AsyncThrowingStream<AgentEvent, Error>.AsyncIterator
) async throws -> AgentEvent {
    guard let event = try await iterator.next() else {
        throw BridgeServerPIDMonitorTestError.streamEnded
    }
    return event
}

private func nextMatchingEvent(
    from iterator: inout AsyncThrowingStream<AgentEvent, Error>.AsyncIterator,
    maxEvents: Int,
    predicate: (AgentEvent) -> Bool
) async throws -> AgentEvent {
    for _ in 0..<maxEvents {
        let event = try await nextEvent(from: &iterator)
        if predicate(event) {
            return event
        }
    }
    throw BridgeServerPIDMonitorTestError.noMatchingEvent
}

private func sendOnBackgroundQueue(
    _ command: BridgeCommand,
    socketURL: URL
) async throws -> BridgeResponse? {
    try await withCheckedThrowingContinuation { continuation in
        DispatchQueue.global().async {
            do {
                let response = try BridgeCommandClient(socketURL: socketURL).send(command)
                continuation.resume(returning: response)
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
}

private func spawnSleep(duration: Double) throws -> Process {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/bin/sleep")
    process.arguments = [String(duration)]
    try process.run()
    return process
}

private extension Process {
    func ensureExited() {
        if isRunning {
            terminate()
            waitUntilExit()
        }
    }
}
