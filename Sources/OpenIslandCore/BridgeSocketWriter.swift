import Darwin
import Dispatch
import Foundation

/// All methods and callbacks run on the server queue. Socket writes never wait for a peer.
final class BridgeSocketWriter {
    private struct Pending {
        var data: Data
        let deadline: TimeInterval
        let completion: (Bool) -> Void
    }
    private let descriptor: Int32
    private let source: DispatchSourceWrite
    private var pending: [Pending] = []
    private var queuedBytes = 0
    private var suspended = true
    private var cancelled = false

    init(descriptor: Int32, queue: DispatchQueue) {
        self.descriptor = descriptor
        source = DispatchSource.makeWriteSource(fileDescriptor: descriptor, queue: queue)
        source.setEventHandler { [weak self] in self?.flush() }
    }

    func enqueue(_ data: Data, completion: @escaping (Bool) -> Void) {
        guard !cancelled, queuedBytes + data.count <= BridgeLimits.maximumFrameBytes else {
            completion(false)
            return
        }
        queuedBytes += data.count
        pending.append(Pending(data: data, deadline: ProcessInfo.processInfo.systemUptime + 1, completion: completion))
        if suspended { suspended = false; source.resume() }
    }

    func expire(at now: TimeInterval) {
        if let first = pending.first, now >= first.deadline { cancel() }
    }

    func cancel() {
        guard !cancelled else { return }
        cancelled = true
        if suspended { suspended = false; source.resume() }
        source.cancel()
        let callbacks = pending.map(\.completion)
        pending.removeAll()
        queuedBytes = 0
        for callback in callbacks { callback(false) }
    }

    private func flush() {
        guard !cancelled else { return }
        var budget = 65_536
        while !pending.isEmpty && budget > 0 {
            if ProcessInfo.processInfo.systemUptime >= pending[0].deadline { cancel(); return }
            let count = pending[0].data.withUnsafeBytes { bytes in
                Darwin.write(descriptor, bytes.baseAddress, min(bytes.count, budget))
            }
            if count > 0 {
                queuedBytes -= count
                budget -= count
                pending[0].data.removeFirst(count)
                if pending[0].data.isEmpty {
                    let callback = pending.removeFirst().completion
                    callback(true)
                    if cancelled { return }
                }
            } else if count < 0 && errno == EINTR {
                continue
            } else if count < 0 && (errno == EAGAIN || errno == EWOULDBLOCK) {
                return
            } else { cancel(); return }
        }
        if pending.isEmpty && !suspended { suspended = true; source.suspend() }
    }
}
