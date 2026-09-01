import Foundation

/// Holds a single macOS power assertion that prevents idle system sleep.
/// The automatic trigger (an agent session is running) and the manual
/// coffee-cup toggle in the island header both feed this one assertion, so
/// it exists exactly while either source asks for it — mirroring what the
/// `caffeinate` CLI wraps, without spawning a child process.
@MainActor
final class SleepPreventionService {
    private(set) var isActive = false

    private var activityToken: NSObjectProtocol?

    /// Idempotent: repeated calls while active keep the single assertion.
    func start(reason: String) {
        guard !isActive else { return }
        activityToken = ProcessInfo.processInfo.beginActivity(
            options: .idleSystemSleepDisabled,
            reason: reason
        )
        isActive = true
    }

    /// Idempotent: safe to call when nothing is held.
    func stop() {
        guard isActive else { return }
        if let activityToken {
            ProcessInfo.processInfo.endActivity(activityToken)
        }
        activityToken = nil
        isActive = false
    }
}
