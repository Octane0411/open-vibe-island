import Foundation
import Observation

/// Caches per-session ContextUsage values for SwiftUI views. The reader
/// closure is injected so tests don't touch the file system. File-watching
/// is added in a follow-up task.
@MainActor
@Observable
public final class ContextUsageRegistry {
    private var cache: [String: ContextUsage] = [:]
    private var paths: [String: String] = [:]
    private let reader: (String) -> ContextUsage?

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
    }

    public func usage(for sessionID: String) -> ContextUsage? {
        cache[sessionID]
    }

    /// Drops the cached value (forcing the next `recordUsage` to re-read).
    public func invalidate(sessionID: String) {
        cache.removeValue(forKey: sessionID)
    }

    /// Removes any entries not present in the active set.
    public func prune(activeSessionIDs: Set<String>) {
        cache = cache.filter { activeSessionIDs.contains($0.key) }
        paths = paths.filter { activeSessionIDs.contains($0.key) }
    }
}
