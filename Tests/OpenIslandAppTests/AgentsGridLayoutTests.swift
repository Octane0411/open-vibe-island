import Foundation
import SwiftUI
import Testing
@testable import OpenIslandApp
import OpenIslandCore

@MainActor
struct AgentsGridLayoutTests {
    @Test
    func balancedRowsTableMatchesDesignSpec() {
        #expect(V6RightSlotView.balancedRows(0) == [])
        #expect(V6RightSlotView.balancedRows(1) == [1])
        #expect(V6RightSlotView.balancedRows(2) == [2])
        #expect(V6RightSlotView.balancedRows(3) == [3])
        #expect(V6RightSlotView.balancedRows(4) == [2, 2])
        #expect(V6RightSlotView.balancedRows(5) == [3, 2])
        #expect(V6RightSlotView.balancedRows(6) == [3, 3])
        #expect(V6RightSlotView.balancedRows(7) == [4, 3])
        #expect(V6RightSlotView.balancedRows(8) == [4, 4])
        #expect(V6RightSlotView.balancedRows(9) == [3, 3, 3])
        #expect(V6RightSlotView.balancedRows(10) == [4, 4])
        #expect(V6RightSlotView.balancedRows(20) == [4, 4])
    }

    @Test
    func cellGeometryShrinksWhenMatrixNeedsThreeRows() {
        let twoRow = V6RightSlotView.cellGeometry(rowCount: 2)
        let threeRow = V6RightSlotView.cellGeometry(rowCount: 3)
        #expect(twoRow.cell == 8)
        #expect(threeRow.cell == 6)
        #expect(threeRow.cell < twoRow.cell)
    }

    @Test
    func intrinsicWidthMatchesWidestRow() {
        let claude = Color(hex: AgentTool.claudeCode.brandColorHex)!
        func cells(_ n: Int) -> [AgentGridCell] {
            (0..<n).map { _ in .session(color: claude, state: .running) }
        }
        // n=5 → [3, 2]: max row is 3 cells → 3*8 + 2*2 = 28
        #expect(V6RightSlotView.intrinsicWidth(of: .agents(cells(5))) == 28)
        // n=8 → [4, 4]: 4*8 + 3*2 = 38
        #expect(V6RightSlotView.intrinsicWidth(of: .agents(cells(8))) == 38)
        // n=9 → [3, 3, 3] with cell 6 / gap 1.5: 3*6 + 2*1.5 = 21
        #expect(V6RightSlotView.intrinsicWidth(of: .agents(cells(9))) == 21)
        // empty grid collapses to zero
        #expect(V6RightSlotView.intrinsicWidth(of: .agents([])) == 0)
    }

    @Test
    func splitIntoRowsDistributesCellsByRowSizes() {
        let claude = Color(hex: AgentTool.claudeCode.brandColorHex)!
        let cells: [AgentGridCell] = (0..<5).map { _ in .session(color: claude, state: .running) }
        let rows = V6RightSlotView.splitIntoRows(cells, rowSizes: [3, 2])
        #expect(rows.count == 2)
        #expect(rows[0].count == 3)
        #expect(rows[1].count == 2)
    }
}
