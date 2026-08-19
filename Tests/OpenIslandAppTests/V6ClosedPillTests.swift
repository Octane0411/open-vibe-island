import Testing
@testable import OpenIslandApp

struct V6ClosedPillTests {
    @Test
    @MainActor
    func reportsRenderedWidthForPanelMorphing() {
        let macbookPill = V6ClosedPill(
            mode: .idle,
            label: nil,
            rightSlot: nil,
            layout: .macbook,
            height: 32,
            physicalNotchWidth: 224
        )
        let externalPill = V6ClosedPill(
            mode: .idle,
            label: nil,
            rightSlot: nil,
            layout: .external,
            height: 32
        )

        #expect(macbookPill.resolvedWidth == 312)
        #expect(externalPill.resolvedWidth == 70)
    }
}
