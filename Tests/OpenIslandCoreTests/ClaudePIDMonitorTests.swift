import Darwin
import Foundation
import Testing
@testable import OpenIslandCore

struct ClaudePIDMonitorTests {
    @Test
    func tracksLiveProcessAndFiresExitCallback() throws {
        let monitor = ClaudePIDMonitor(gracePeriod: 0)
        let process = try spawnSleep(duration: 0.3)
        let pid = process.processIdentifier

        let semaphore = DispatchSemaphore(value: 0)
        let captured = CapturedExit()

        monitor.track(sessionID: "s1", pid: pid) { event in
            captured.store(event)
            semaphore.signal()
        }

        let result = semaphore.wait(timeout: .now() + .seconds(3))
        #expect(result == .success)
        #expect(captured.event?.sessionID == "s1")
        #expect(captured.event?.pid == pid)

        process.ensureExited()
    }

    @Test
    func untrackCancelsCallback() throws {
        let monitor = ClaudePIDMonitor(gracePeriod: 0)
        let process = try spawnSleep(duration: 0.2)
        let pid = process.processIdentifier

        let counter = CallCounter()
        monitor.track(sessionID: "s1", pid: pid) { _ in
            counter.increment()
        }
        monitor.untrack(sessionID: "s1")

        #expect(monitor.isTracking(sessionID: "s1") == false)

        // Wait well past the process lifetime to be sure no late callback slipped through.
        Thread.sleep(forTimeInterval: 2.0)
        #expect(counter.value == 0)

        process.ensureExited()
    }

    @Test
    func retrackWithDifferentPIDDuringGraceCancelsFirstExit() throws {
        let monitor = ClaudePIDMonitor(gracePeriod: 1.0)
        let first = try spawnSleep(duration: 0.2)
        let firstPID = first.processIdentifier

        let counter = CallCounter()
        monitor.track(sessionID: "s1", pid: firstPID) { _ in
            counter.increment()
        }

        // Wait for the first process to actually exit (grace is now ticking).
        first.waitUntilExit()
        Thread.sleep(forTimeInterval: 0.2)

        let second = try spawnSleep(duration: 10)
        let secondPID = second.processIdentifier
        monitor.track(sessionID: "s1", pid: secondPID) { _ in
            counter.increment()
        }

        // Wait past when the first grace would have fired (1.0s).
        Thread.sleep(forTimeInterval: 2.5)
        #expect(counter.value == 0)
        #expect(monitor.currentPID(for: "s1") == secondPID)

        monitor.untrack(sessionID: "s1")
        second.terminate()
        second.waitUntilExit()
    }

    @Test
    func retrackWithSamePIDIsIdempotent() throws {
        let monitor = ClaudePIDMonitor(gracePeriod: 0)
        let process = try spawnSleep(duration: 10)
        let pid = process.processIdentifier

        let counter = CallCounter()
        let semaphore = DispatchSemaphore(value: 0)

        monitor.track(sessionID: "s1", pid: pid) { _ in
            counter.increment()
            semaphore.signal()
        }
        #expect(monitor.currentPID(for: "s1") == pid)

        // Re-track with the same PID; must not replace the existing monitor.
        monitor.track(sessionID: "s1", pid: pid) { _ in
            counter.increment()
            semaphore.signal()
        }
        #expect(monitor.isTracking(sessionID: "s1") == true)
        #expect(monitor.currentPID(for: "s1") == pid)

        process.terminate()

        let result = semaphore.wait(timeout: .now() + .seconds(3))
        #expect(result == .success)

        // Give any spurious extra callback a chance to land.
        Thread.sleep(forTimeInterval: 0.5)
        #expect(counter.value == 1)

        process.ensureExited()
    }

    @Test
    func alreadyDeadPIDFiresExitCallback() throws {
        let monitor = ClaudePIDMonitor(gracePeriod: 0)
        let process = try spawnSleep(duration: 0.05)
        let pid = process.processIdentifier
        process.waitUntilExit()
        // Extra safety — make sure the kernel has reaped the PID.
        Thread.sleep(forTimeInterval: 0.1)

        let semaphore = DispatchSemaphore(value: 0)
        let captured = CapturedExit()

        monitor.track(sessionID: "s1", pid: pid) { event in
            captured.store(event)
            semaphore.signal()
        }

        let result = semaphore.wait(timeout: .now() + .seconds(3))
        #expect(result == .success)
        #expect(captured.event?.sessionID == "s1")
        #expect(captured.event?.pid == pid)
    }

    @Test
    func isAliveReflectsProcessLiveness() throws {
        let monitor = ClaudePIDMonitor(gracePeriod: 5.0)
        let process = try spawnSleep(duration: 10)
        let pid = process.processIdentifier

        monitor.track(sessionID: "s1", pid: pid) { _ in }
        #expect(monitor.isAlive(sessionID: "s1") == true)
        #expect(monitor.isAlive(sessionID: "nope") == false)

        process.terminate()
        process.waitUntilExit()

        let deadline = Date().addingTimeInterval(2.0)
        while Date() < deadline {
            if !monitor.isAlive(sessionID: "s1") { break }
            Thread.sleep(forTimeInterval: 0.05)
        }
        #expect(monitor.isAlive(sessionID: "s1") == false)

        monitor.untrack(sessionID: "s1")
    }

    @Test
    func untrackAllCancelsEveryPendingCallback() throws {
        let monitor = ClaudePIDMonitor(gracePeriod: 0)
        let first = try spawnSleep(duration: 0.2)
        let second = try spawnSleep(duration: 0.2)

        let counter = CallCounter()
        monitor.track(sessionID: "s1", pid: first.processIdentifier) { _ in
            counter.increment()
        }
        monitor.track(sessionID: "s2", pid: second.processIdentifier) { _ in
            counter.increment()
        }

        #expect(monitor.isTracking(sessionID: "s1") == true)
        #expect(monitor.isTracking(sessionID: "s2") == true)

        monitor.untrackAll()

        #expect(monitor.isTracking(sessionID: "s1") == false)
        #expect(monitor.isTracking(sessionID: "s2") == false)

        // Let both subprocesses exit; any surviving dispatch source would fire now.
        Thread.sleep(forTimeInterval: 1.0)
        #expect(counter.value == 0)

        first.ensureExited()
        second.ensureExited()
    }

    @Test
    func deinitCancelsEverythingCleanly() throws {
        let process = try spawnSleep(duration: 10)
        let pid = process.processIdentifier

        do {
            let monitor = ClaudePIDMonitor(gracePeriod: 0)
            monitor.track(sessionID: "s1", pid: pid) { _ in
                // If this fires after the monitor is gone, we want to know.
                Issue.record("onExit must not fire after monitor is deallocated")
            }
            #expect(monitor.isTracking(sessionID: "s1") == true)
        }

        // Monitor is gone. Kill the process; if deinit didn't cancel, this would crash.
        process.terminate()
        process.waitUntilExit()
        Thread.sleep(forTimeInterval: 0.3)
    }

    // MARK: - Helpers

    private func spawnSleep(duration: Double) throws -> Process {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sleep")
        process.arguments = [String(duration)]
        try process.run()
        return process
    }
}

private final class CapturedExit: @unchecked Sendable {
    private let lock = NSLock()
    private var _event: ClaudePIDMonitor.ExitEvent?

    var event: ClaudePIDMonitor.ExitEvent? {
        lock.lock(); defer { lock.unlock() }
        return _event
    }

    func store(_ event: ClaudePIDMonitor.ExitEvent) {
        lock.lock(); defer { lock.unlock() }
        _event = event
    }
}

private final class CallCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    var value: Int {
        lock.lock(); defer { lock.unlock() }
        return count
    }

    func increment() {
        lock.lock(); defer { lock.unlock() }
        count += 1
    }
}

private extension Process {
    func ensureExited() {
        if isRunning {
            terminate()
            waitUntilExit()
        }
    }
}
