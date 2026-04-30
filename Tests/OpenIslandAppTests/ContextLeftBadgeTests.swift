import Foundation
import SwiftUI
import Testing
@testable import OpenIslandApp
@testable import OpenIslandCore

@MainActor
struct ContextLeftBadgeTests {
    @Test
    func fillWidthIsZeroWhenNothingUsed() {
        let b = ContextLeftBadge(usage: ContextUsage(used: 0, window: 200_000))
        #expect(b.fillWidth == 0)
    }

    @Test
    func fillWidthHasMinimumSliverWhenAnyUsed() {
        let b = ContextLeftBadge(usage: ContextUsage(used: 100, window: 200_000))
        #expect(b.fillWidth >= 2)
    }

    @Test
    func fillWidthIsBarWidthAtFull() {
        let b = ContextLeftBadge(usage: ContextUsage(used: 200_000, window: 200_000))
        #expect(b.fillWidth == 18)
    }

    @Test
    func colorIsGreenAbove50PercentLeft() {
        let b = ContextLeftBadge(usage: ContextUsage(used: 60_000, window: 200_000))
        #expect(b.fillColor == .green)
    }

    @Test
    func colorIsYellowBetween20And50() {
        let b = ContextLeftBadge(usage: ContextUsage(used: 140_000, window: 200_000))
        #expect(b.fillColor == .yellow)
    }

    @Test
    func colorIsOrangeBetween10And20() {
        let b = ContextLeftBadge(usage: ContextUsage(used: 175_000, window: 200_000))
        #expect(b.fillColor == .orange)
    }

    @Test
    func colorIsRedAtOrBelow10PercentLeft() {
        let b = ContextLeftBadge(usage: ContextUsage(used: 195_000, window: 200_000))
        #expect(b.fillColor == .red)
    }
}
