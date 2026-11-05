import Foundation

public enum CodexLiveSessionPolicy {
    public static func shouldShow(_ thread: CodexThread, now: Date = .now, lastActiveAt: Date? = nil, completedWindow: TimeInterval = 300) -> Bool {
        guard !thread.ephemeral, thread.source?.isSubagent != true else { return false }
        switch thread.status.type {
        case .active: return true
        case .idle, .systemError:
            let activity = max(Double(thread.updatedAt), lastActiveAt?.timeIntervalSince1970 ?? 0)
            return now.timeIntervalSince1970 - activity <= completedWindow
        case .notLoaded: return false
        }
    }

    public static func phase(for status: CodexThreadStatus) -> SessionPhase {
        if status.isWaitingOnApproval { return .waitingForApproval }
        if status.isWaitingOnUserInput { return .waitingForAnswer }
        return status.type == .active ? .running : .completed
    }
}
