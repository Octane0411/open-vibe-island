import Foundation

public enum CompanionState: String, Equatable, Sendable {
    case idle
    case working
    case waiting
    case celebrating

    public static func derive(
        spotlightPhase: SessionPhase?,
        recentlyCompleted: Bool
    ) -> CompanionState {
        guard let phase = spotlightPhase else { return .idle }
        switch phase {
        case .running:
            return .working
        case .waitingForApproval, .waitingForAnswer:
            return .waiting
        case .completed:
            return recentlyCompleted ? .celebrating : .idle
        }
    }
}
