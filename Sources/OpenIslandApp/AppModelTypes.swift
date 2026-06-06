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
enum IslandRightSlot: String, CaseIterable, Identifiable, Sendable {
    case count   // "×N" badge
    case agents  // colored dot stack, one per active agent tool
    case none    // pill collapses — useful if you just want the bars

    var id: String { rawValue }
}

/// What the closed island renders in the center label (external displays
/// only — on MacBook the physical notch covers this space so we suppress
/// the label regardless).
enum IslandCenterLabel: String, CaseIterable, Identifiable, Sendable {
    case sessionName  // e.g. "open-island"
    case agentAction  // e.g. "Claude · editing"
    case off

    var id: String { rawValue }
}

// MARK: - v8 island preferences

enum IslandAppearanceDisplayProfile: String, CaseIterable, Identifiable, Sendable {
    case notch
    case topBar

    var id: String { rawValue }
}

struct IslandAppearancePreferences: Equatable, Sendable {
    var rightSlot: IslandRightSlot = .count
    var centerLabel: IslandCenterLabel = .agentAction
    var usageDisplay: IslandUsageDisplay = .compact
    var sessionStateIndicator: IslandSessionStateIndicator = .animatedDot
    var sessionGroup: IslandSessionGroup = .none
    var sessionSort: IslandSessionSort = .attention
    var sessionListLimitMode: IslandSessionListLimitMode = .activeWindow
    var sessionListFixedCount: IslandSessionListFixedCount = .three
    var sessionListActivityWindowMinutes: Int = 60
    var completedStaleThreshold: IslandCompletedStaleThreshold = .fiveMinutes
    var animationSpeed: IslandAnimationSpeed = .normal
}

enum IslandAnimationSpeed: String, CaseIterable, Identifiable, Sendable {
    case fast
    case normal
    case slow

    var id: String { rawValue }

    var durationMultiplier: TimeInterval {
        switch self {
        case .fast:
            return 0.82
        case .normal:
            return 1.0
        case .slow:
            return 1.25
        }
    }
}

enum IslandUsageDisplay: String, CaseIterable, Identifiable, Sendable {
    case hidden
    case compact

    var id: String { rawValue }
}

enum IslandSessionStateIndicator: String, CaseIterable, Identifiable, Sendable {
    case animatedDot
    case bar
    case glyph
    case tint

    var id: String { rawValue }
}

enum IslandSessionGroup: String, CaseIterable, Identifiable, Sendable {
    case none
    case state
    case agent
    case project

    var id: String { rawValue }
}

enum IslandSessionSort: String, CaseIterable, Identifiable, Sendable {
    case attention
    case lastUpdate

    var id: String { rawValue }
}

enum IslandSessionListLimitMode: String, CaseIterable, Identifiable, Sendable {
    case activeWindow
    case fixedCount

    var id: String { rawValue }
}

enum IslandSessionListFixedCount: String, CaseIterable, Identifiable, Sendable {
    case three
    case five
    case eight
    case twelve

    var id: String { rawValue }

    var count: Int {
        switch self {
        case .three: return 3
        case .five: return 5
        case .eight: return 8
        case .twelve: return 12
        }
    }
}

enum IslandSessionActivityWindow: String, CaseIterable, Identifiable, Sendable {
    case fifteenMinutes
    case oneHour
    case sixHours
    case oneDay

    var id: String { rawValue }

    var seconds: TimeInterval {
        switch self {
        case .fifteenMinutes: return 15 * 60
        case .oneHour: return 60 * 60
        case .sixHours: return 6 * 60 * 60
        case .oneDay: return 24 * 60 * 60
        }
    }
}

extension IslandSessionActivityWindow {
    init?(minutesRawValue: String?) {
        guard let minutesRawValue, !minutesRawValue.isEmpty else {
            return nil
        }
        self.init(rawValue: minutesRawValue)
    }
}

enum IslandCompletedStaleThreshold: String, CaseIterable, Identifiable, Sendable {
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
