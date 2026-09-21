import AppKit
import CoreGraphics
import Foundation
import OpenIslandCore

enum NotchStatus: Equatable {
    case closed
    case opened
    case popping
}

enum NotchOpenReason: Equatable {
    case click
    case hover
    case notification
    case boot
}

enum TrackedEventIngress {
    case bridge
    case rollout
}

// MARK: - v6 island preferences

/// What the closed island renders in the right slot. Chosen in the
/// Personalization tab; the pill layout only varies by content width.
enum IslandRightSlot: String, CaseIterable, Identifiable, Codable, Sendable {
    case count   // "×N" badge
    case agents  // colored dot stack, one per active agent tool
    case none    // pill collapses — useful if you just want the bars

    var id: String { rawValue }
}

/// What the closed island renders in the center label (external displays
/// only — on MacBook the physical notch covers this space so we suppress
/// the label regardless).
enum IslandCenterLabel: String, CaseIterable, Identifiable, Codable, Sendable {
    case sessionName  // e.g. "open-island"
    case agentAction  // e.g. "Claude · editing"
    case off

    var id: String { rawValue }
}

// MARK: - v8 island preferences

/// The display context that owns an independent island appearance preference.
enum IslandAppearanceDisplayProfile: String, CaseIterable, Identifiable, Codable, Sendable {
    case notch
    case topBar

    var id: String { rawValue }
}

/// Persisted appearance choices for one island display profile.
///
/// All fields are codable so profile preferences can be stored or transferred
/// as one stable value in addition to the current per-key defaults storage.
struct IslandAppearancePreferences: Equatable, Codable, Sendable {
    var rightSlot: IslandRightSlot = .count
    var centerLabel: IslandCenterLabel = .agentAction
    var usageDisplay: IslandUsageDisplay = .compact
    var sessionStateIndicator: IslandSessionStateIndicator = .animatedDot
    var sessionGroup: IslandSessionGroup = .none
    var sessionSort: IslandSessionSort = .attention
    var completedStaleThreshold: IslandCompletedStaleThreshold = .fiveMinutes
    var showIdleSessions: Bool = false
}

/// Controls whether the compact Codex usage indicator is visible.
enum IslandUsageDisplay: String, CaseIterable, Identifiable, Codable, Sendable {
    case hidden
    case compact

    var id: String { rawValue }
}

/// Selects the visual treatment for a session's state in the island.
enum IslandSessionStateIndicator: String, CaseIterable, Identifiable, Codable, Sendable {
    case animatedDot
    case bar
    case glyph
    case tint

    var id: String { rawValue }

    func timelineInterval(presence: IslandSessionPresence, isActionable: Bool) -> TimeInterval? {
        guard self == .animatedDot else { return nil }
        return presence == .running || isActionable ? 1.0 / 15.0 : nil
    }
}

/// Defines how sessions are grouped in the expanded island list.
enum IslandSessionGroup: String, CaseIterable, Identifiable, Codable, Sendable {
    case none
    case state
    case agent
    case project

    var id: String { rawValue }
}

/// Defines the ordering of sessions within an island list group.
enum IslandSessionSort: String, CaseIterable, Identifiable, Codable, Sendable {
    case attention
    case lastUpdate

    var id: String { rawValue }
}

/// Defines when a completed session is treated as idle by the island.
enum IslandCompletedStaleThreshold: String, CaseIterable, Identifiable, Codable, Sendable {
    case twoMinutes
    case fiveMinutes
    case tenMinutes
    case twentyMinutes
    case never

    var id: String { rawValue }

    var seconds: TimeInterval {
        switch self {
        case .twoMinutes:    return 2 * 60
        case .fiveMinutes:   return 5 * 60
        case .tenMinutes:    return 10 * 60
        case .twentyMinutes: return 20 * 60
        case .never:         return .infinity
        }
    }
}

struct IslandSessionSection: Identifiable {
    let id: String
    let title: String
    let sessions: [AgentSession]
}
