import Foundation

/// Translates Codex.app `app-server` notifications into observations.
///
/// This is the only channel that can watch a desktop thread through its whole
/// life — it reports turn boundaries as they happen and says explicitly when a
/// thread closes. That makes it authoritative for run phase and for liveness,
/// and it is why the rollout transcript is barred from both: a transcript that
/// disappears means Codex.app archived the thread, not that the thread ended,
/// and treating the two as the same left desktop rows stranded in a running
/// state forever.
///
/// It knows nothing about terminals, so it never writes placement.
public final class CodexAppServerSource: @unchecked Sendable {
    private let lock = NSLock()
    private var nextSeq: UInt64 = 0

    public init() {}

    private func allocateSeq() -> UInt64 {
        lock.lock()
        defer { lock.unlock() }
        nextSeq += 1
        return nextSeq
    }

    /// Convert one app-server notification into an observation.
    ///
    /// Returns `nil` for notifications that carry no session state — including
    /// methods this build does not recognize, which are reported as drift by
    /// the caller rather than silently ignored here.
    public func observe(
        _ notification: CodexAppServerNotification,
        at timestamp: Date = .now
    ) -> CodexObservation? {
        switch notification {
        case let .threadStarted(thread):
            var patch = CodexFacetPatch()
            patch.lifecycle = CodexLifecycle(phase: .running)
            patch.liveness = CodexLiveness(state: .alive)
            // A desktop thread has no terminal; placement is synthesized by the
            // projector from the surface instead.
            patch.surface = .desktopApp
            if let name = thread.name, !name.isEmpty {
                patch.narrative = CodexNarrative(title: name)
            }
            return make(ref: .threadID(thread.id), patch: patch, at: timestamp)

        case let .threadStatusChanged(threadId, status):
            var patch = CodexFacetPatch()
            patch.lifecycle = CodexLifecycle(phase: Self.phase(for: status.type))
            patch.liveness = CodexLiveness(state: .alive)
            return make(ref: .threadID(threadId), patch: patch, at: timestamp)

        case let .threadClosed(threadId):
            var patch = CodexFacetPatch()
            // The definitive end signal for a desktop session.
            patch.liveness = CodexLiveness(state: .ended(reason: .threadClosed))
            patch.actionable = nil
            return make(ref: .threadID(threadId), patch: patch, at: timestamp)

        case let .threadNameUpdated(threadId, name):
            guard let name, !name.isEmpty else { return nil }
            var patch = CodexFacetPatch()
            // A name the user assigned outranks anything scraped from the
            // transcript, which is what stopped injected context from becoming
            // the visible session title.
            patch.narrative = CodexNarrative(title: name)
            return make(ref: .threadID(threadId), patch: patch, at: timestamp)

        case let .turnStarted(threadId, _):
            var patch = CodexFacetPatch()
            patch.lifecycle = CodexLifecycle(phase: .running)
            patch.liveness = CodexLiveness(state: .alive)
            return make(ref: .threadID(threadId), patch: patch, at: timestamp)

        case let .turnCompleted(threadId, _):
            var patch = CodexFacetPatch()
            patch.lifecycle = CodexLifecycle(phase: .completed)
            patch.liveness = CodexLiveness(state: .alive)
            return make(ref: .threadID(threadId), patch: patch, at: timestamp)

        case .unknown:
            return nil
        }
    }

    /// Convert a thread listed at connection time into an observation, so a
    /// restart recovers desktop sessions without waiting for new activity.
    public func observeLoadedThread(
        _ thread: CodexThread,
        at timestamp: Date = .now
    ) -> CodexObservation {
        var patch = CodexFacetPatch()
        patch.surface = .desktopApp
        patch.lifecycle = CodexLifecycle(phase: .running)
        patch.liveness = CodexLiveness(state: .alive)
        if let name = thread.name, !name.isEmpty {
            patch.narrative = CodexNarrative(title: name)
        }
        return make(ref: .threadID(thread.id), patch: patch, at: timestamp)
    }

    private func make(
        ref: CodexIdentityRef,
        patch: CodexFacetPatch,
        at timestamp: Date
    ) -> CodexObservation {
        CodexObservation(
            ref: ref,
            source: .appServer,
            seq: allocateSeq(),
            observedAt: timestamp,
            patch: patch
        )
    }

    static func phase(for status: CodexThreadStatusType) -> SessionPhase {
        switch status {
        case .active: .running
        case .idle: .completed
        case .systemError: .completed
        case .notLoaded: .completed
        }
    }
}
