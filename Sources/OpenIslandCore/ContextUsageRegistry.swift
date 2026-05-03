import Foundation
import Observation

/// Caches per-session ContextUsage values for SwiftUI views. The reader
/// closure is injected so tests don't touch the file system. A
/// `DispatchSourceFileSystemObject` watches each transcript and re-reads
/// usage on change, debounced by 200ms.
@MainActor
@Observable
public final class ContextUsageRegistry {
    private var cache: [String: ContextUsage] = [:]
    private var paths: [String: String] = [:]
    private let reader: (String) -> ContextUsage?
    private var watchers: [String: DispatchSourceFileSystemObject] = [:]
    private var debounceTasks: [String: Task<Void, Never>] = [:]

    public init(reader: @escaping (String) -> ContextUsage? = ContextUsageReader.read(transcriptPath:)) {
        self.reader = reader
    }

    /// Reads the transcript at `transcriptPath` and stores the result for
    /// `sessionID`. If the read returns nil, no entry is stored.
    public func recordUsage(sessionID: String, transcriptPath: String) {
        paths[sessionID] = transcriptPath
        if let usage = reader(transcriptPath) {
            cache[sessionID] = usage
        }
        installWatcher(sessionID: sessionID, transcriptPath: transcriptPath)
    }

    public func usage(for sessionID: String) -> ContextUsage? {
        cache[sessionID]
    }

    /// Drops the cached value (forcing the next `recordUsage` to re-read).
    public func invalidate(sessionID: String) {
        cache.removeValue(forKey: sessionID)
        cancelWatcher(sessionID: sessionID)
    }

    /// Removes any entries not present in the active set.
    public func prune(activeSessionIDs: Set<String>) {
        let removed = Set(cache.keys).union(paths.keys).subtracting(activeSessionIDs)
        for id in removed { cancelWatcher(sessionID: id) }
        cache = cache.filter { activeSessionIDs.contains($0.key) }
        paths = paths.filter { activeSessionIDs.contains($0.key) }
    }

    private func installWatcher(sessionID: String, transcriptPath: String) {
        cancelWatcher(sessionID: sessionID)
        guard FileManager.default.fileExists(atPath: transcriptPath) else { return }
        let fd = open(transcriptPath, O_EVTONLY)
        guard fd >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .extend, .delete, .rename],
            queue: .global(qos: .utility)
        )
        let weakBox = WeakBox(value: self)
        let capturedSessionID = sessionID
        let capturedTranscriptPath = transcriptPath
        source.setEventHandler { @Sendable in
            Task { @MainActor in
                weakBox.value?.scheduleRefresh(
                    sessionID: capturedSessionID,
                    transcriptPath: capturedTranscriptPath
                )
            }
        }
        source.setCancelHandler { @Sendable in close(fd) }
        source.resume()
        watchers[sessionID] = source
    }

    private func cancelWatcher(sessionID: String) {
        watchers.removeValue(forKey: sessionID)?.cancel()
        debounceTasks.removeValue(forKey: sessionID)?.cancel()
    }

    private func scheduleRefresh(sessionID: String, transcriptPath: String) {
        debounceTasks.removeValue(forKey: sessionID)?.cancel()
        debounceTasks[sessionID] = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 200_000_000)
            guard !Task.isCancelled, let self else { return }
            if let usage = self.reader(transcriptPath) {
                self.cache[sessionID] = usage
            }
        }
    }

    private struct WeakBox: @unchecked Sendable {
        weak var value: ContextUsageRegistry?
    }
}
