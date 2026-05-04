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

enum LabsClosedQuotaWindowMode: String, CaseIterable, Identifiable {
    case all
    case fiveHourOnly
    case weeklyOnly
    case closestToZeroUsed

    var id: String { rawValue }
}

enum LabsClosedQuotaValueMode: String, CaseIterable, Identifiable {
    case usedPercent
    case remainingPercent

    var id: String { rawValue }
}

enum LabsClosedQuotaPlacement: String, CaseIterable, Identifiable {
    case rightBadge
    case leftNearGlyph

    var id: String { rawValue }
}
