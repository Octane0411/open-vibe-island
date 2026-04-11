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

enum TrackedEventIngress {
    case bridge
    case rollout
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

/// Which screen edge the island panel is docked to.
enum IslandDockEdge: String, CaseIterable, Identifiable {
    case top
    case left
    case right

    var id: String { rawValue }

    var isVertical: Bool { self == .left || self == .right }
}
