import Darwin
import Dispatch
import Foundation

/// Low-overhead file change delivery backed by vnode dispatch sources.
///
/// Missing or atomically replaced files can be re-armed with `refresh()`; the
/// caller may invoke it from a coarse fallback timer without polling contents.
public final class FileChangeMonitor: @unchecked Sendable {
    public typealias Handler = @Sendable (URL) -> Void

    private let urls: [URL]
    private let handler: Handler
    private let queue: DispatchQueue
    private let queueKey = DispatchSpecificKey<UInt8>()
    private var sources: [String: DispatchSourceFileSystemObject] = [:]
    private var isStopped = true

    public init(
        urls: [URL],
        queueLabel: String,
        handler: @escaping Handler
    ) {
        self.urls = urls
        self.handler = handler
        queue = DispatchQueue(label: queueLabel, qos: .utility)
        queue.setSpecific(key: queueKey, value: 1)
    }

    deinit {
        stop()
    }

    public func start() {
        performSync {
            isStopped = false
            urls.forEach(armIfPossible)
        }
    }

    public func refresh() {
        queue.async { [weak self] in
            guard let self, !self.isStopped else { return }
            self.urls.forEach(self.armIfPossible)
        }
    }

    public func stop() {
        performSync {
            isStopped = true
            sources.values.forEach { $0.cancel() }
            sources.removeAll()
        }
    }

    private func armIfPossible(_ url: URL) {
        let path = url.path
        guard sources[path] == nil else { return }

        let descriptor = open(path, O_EVTONLY)
        guard descriptor >= 0 else { return }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.write, .extend, .rename, .delete, .revoke],
            queue: queue
        )
        source.setEventHandler { [weak self] in
            self?.handleEvent(for: url)
        }
        source.setCancelHandler {
            close(descriptor)
        }
        sources[path] = source
        source.resume()
    }

    private func handleEvent(for url: URL) {
        let path = url.path
        guard let source = sources[path] else { return }
        let event = source.data

        handler(url)

        guard event.contains(.rename)
            || event.contains(.delete)
            || event.contains(.revoke) else { return }

        source.cancel()
        sources[path] = nil
        queue.asyncAfter(deadline: .now() + .milliseconds(100)) { [weak self] in
            guard let self, !self.isStopped else { return }
            self.armIfPossible(url)
        }
    }

    private func performSync(_ operation: () -> Void) {
        if DispatchQueue.getSpecific(key: queueKey) != nil {
            operation()
        } else {
            queue.sync(execute: operation)
        }
    }
}
