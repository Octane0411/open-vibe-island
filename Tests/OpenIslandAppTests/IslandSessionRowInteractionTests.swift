import Testing
@testable import OpenIslandApp

struct IslandSessionRowInteractionTests {
    @Test
    func compactIdleRowFirstTapExpandsDetailBeforeJumping() {
        #expect(
            IslandSessionRowInteraction.primaryTapAction(
                isInteractive: true,
                usesCompactIdleRow: true,
                showsDetail: false,
                canToggleDetail: true
            ) == .expandDetail
        )

        #expect(
            IslandSessionRowInteraction.primaryTapAction(
                isInteractive: true,
                usesCompactIdleRow: true,
                showsDetail: true,
                canToggleDetail: true
            ) == .jump
        )
    }

    @Test
    func runningRowsDoNotToggleDetailHeight() {
        #expect(
            IslandSessionRowInteraction.primaryTapAction(
                isInteractive: true,
                usesCompactIdleRow: false,
                showsDetail: true,
                canToggleDetail: false
            ) == .jump
        )
    }
}
