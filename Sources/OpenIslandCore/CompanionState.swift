import Foundation

public enum CompanionState: String, Codable, Equatable, Sendable, CaseIterable {
    case idle
    case working
    case waiting
    case celebrating

    /// Window during which a `.completed` phase still maps to `.celebrating`.
    /// SwiftUI views observing this transition must trigger an explicit
    /// re-render at the boundary; otherwise the celebrating glyph can persist
    /// past the window if no other observed property changes in time.
    public static let celebratingWindow: TimeInterval = 8.0

    /// Pure-function check used by both view code (to compute current state)
    /// and tests (to assert boundary behavior). Returns `false` when
    /// `lastCompletion` is nil.
    public static func isWithinCelebratingWindow(
        now: Date,
        lastCompletion: Date?,
        window: TimeInterval = celebratingWindow
    ) -> Bool {
        guard let ts = lastCompletion else { return false }
        return now.timeIntervalSince(ts) < window
    }

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
