import Darwin
import Foundation

/// Kernel-level PID exit monitor for Claude sessions.
///
/// Wraps `DispatchSource.makeProcessSource(eventMask: .exit)` per tracked PID
/// and exposes a small, session-keyed API. A short grace period absorbs
/// `claude --resume`-style restarts where the old PID exits just before a
/// new PID re-registers for the same session.
public final class ClaudePIDMonitor: @unchecked Sendable {
    public struct ExitEvent: Sendable {
        public let sessionID: String
        public let pid: Int32
        public let exitedAt: Date

        public init(sessionID: String, pid: Int32, exitedAt: Date) {
            self.sessionID = sessionID
            self.pid = pid
            self.exitedAt = exitedAt
        }
    }

    private final class MonitorRecord {
        let pid: Int32
        var source: DispatchSourceProcess?
        var onExit: (ExitEvent) -> Void
        var pendingGrace: DispatchWorkItem?

        init(pid: Int32, source: DispatchSourceProcess?, onExit: @escaping (ExitEvent) -> Void) {
            self.pid = pid
            self.source = source
            self.onExit = onExit
            self.pendingGrace = nil
        }
    }

    private let gracePeriod: TimeInterval
    private let queue: DispatchQueue
    private let stateQueue = DispatchQueue(label: "OpenIsland.ClaudePIDMonitor.state")
    private var records: [String: MonitorRecord] = [:]

    public init(gracePeriod: TimeInterval = 5.0, queue: DispatchQueue = .global(qos: .utility)) {
        self.gracePeriod = gracePeriod
        self.queue = queue
    }

    deinit {
        // Cancel all sources and pending work so nothing fires into a released self.
        for (_, record) in records {
            record.pendingGrace?.cancel()
            record.source?.cancel()
        }
        records.removeAll()
    }

    public func track(sessionID: String, pid: Int32, onExit: @escaping (ExitEvent) -> Void) {
        performSync {
            if let existing = self.records[sessionID] {
                if existing.pid == pid {
                    // Idempotent for same PID; keep existing monitor intact.
                    return
                }
                existing.pendingGrace?.cancel()
                existing.source?.cancel()
                self.records.removeValue(forKey: sessionID)
            }
            self.installLocked(sessionID: sessionID, pid: pid, onExit: onExit)
        }
    }

    public func untrack(sessionID: String) {
        performSync {
            guard let record = self.records.removeValue(forKey: sessionID) else { return }
            record.pendingGrace?.cancel()
            record.source?.cancel()
        }
    }

    public func untrackAll() {
        performSync {
            for (_, record) in self.records {
                record.pendingGrace?.cancel()
                record.source?.cancel()
            }
            self.records.removeAll()
        }
    }

    public func isTracking(sessionID: String) -> Bool {
        performSync { self.records[sessionID] != nil }
    }

    public func isAlive(sessionID: String) -> Bool {
        guard let pid = currentPID(for: sessionID) else { return false }
        return kill(pid, 0) == 0
    }

    public func currentPID(for sessionID: String) -> Int32? {
        performSync { self.records[sessionID]?.pid }
    }

    // MARK: - Private

    private func performSync<T>(_ work: () -> T) -> T {
        stateQueue.sync(execute: work)
    }

    /// Must be called on `stateQueue`.
    private func installLocked(sessionID: String, pid: Int32, onExit: @escaping (ExitEvent) -> Void) {
        if kill(pid, 0) != 0 && errno == ESRCH {
            // PID is already dead; schedule a grace-delayed callback without a source.
            let record = MonitorRecord(pid: pid, source: nil, onExit: onExit)
            records[sessionID] = record
            scheduleGraceLocked(sessionID: sessionID, record: record)
            return
        }

        let source = DispatchSource.makeProcessSource(identifier: pid_t(pid), eventMask: .exit, queue: queue)
        let record = MonitorRecord(pid: pid, source: source, onExit: onExit)
        records[sessionID] = record

        source.setEventHandler { [weak self] in
            guard let self else { return }
            self.performSync {
                // Only schedule if this record is still the current one for the session.
                guard let current = self.records[sessionID], current === record else { return }
                self.scheduleGraceLocked(sessionID: sessionID, record: current)
            }
        }
        source.resume()
    }

    /// Must be called on `stateQueue`.
    private func scheduleGraceLocked(sessionID: String, record: MonitorRecord) {
        record.pendingGrace?.cancel()
        let pid = record.pid
        let item = DispatchWorkItem { [weak self] in
            guard let self else { return }
            let callback: ((ExitEvent) -> Void)? = self.performSync {
                guard let current = self.records[sessionID], current === record else { return nil }
                current.source?.cancel()
                self.records.removeValue(forKey: sessionID)
                return current.onExit
            }
            callback?(ExitEvent(sessionID: sessionID, pid: pid, exitedAt: Date()))
        }
        record.pendingGrace = item
        if gracePeriod <= 0 {
            queue.async(execute: item)
        } else {
            queue.asyncAfter(deadline: .now() + gracePeriod, execute: item)
        }
    }
}
