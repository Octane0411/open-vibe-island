import AppKit
import CoreGraphics
import Foundation

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

enum TrackedEventIngress: Equatable {
    case bridge
    case rolloutBootstrap
    case rolloutLive

    static var rollout: Self {
        .rolloutLive
    }

    var isBridge: Bool {
        self == .bridge
    }

    var isRollout: Bool {
        self == .rolloutBootstrap || self == .rolloutLive
    }

    var refreshesRolloutLiveness: Bool {
        self == .rolloutLive
    }
}

// MARK: - Island appearance

enum IslandAppearanceMode: String, CaseIterable, Identifiable {
    case `default`
    case custom

    var id: String { rawValue }
}

enum IslandClosedDisplayStyle: String, CaseIterable, Identifiable {
    case minimal
    case detailed

    var id: String { rawValue }
}

enum IslandPixelShapeStyle: String, CaseIterable, Identifiable {
    case bars
    case steps
    case blocks
    case custom

    var id: String { rawValue }
}
