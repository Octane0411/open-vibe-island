import SwiftUI
import OpenIslandCore

struct AnimatedCompanionPet: View {
    let pet: CompanionPet
    let state: CompanionState

    /// Frame rate per state — slower for idle, faster for celebrating.
    private static func fps(for state: CompanionState) -> Double {
        switch state {
        case .idle:        return 2
        case .working:     return 6
        case .waiting:     return 3
        case .celebrating: return 8
        }
    }

    var body: some View {
        TimelineView(.animation) { timeline in
            let frames = PetSpriteData.frames(for: pet, state: state)
            let fps = Self.fps(for: state)
            let elapsed = timeline.date.timeIntervalSinceReferenceDate
            let frameIndex = Int(elapsed * fps) % max(frames.count, 1)
            let grid = frames[frameIndex]

            Canvas { ctx, size in
                guard let firstRow = grid.first else { return }
                let rows = grid.count
                let cols = firstRow.count
                let cellW = size.width / CGFloat(cols)
                let cellH = size.height / CGFloat(rows)
                for (y, row) in grid.enumerated() {
                    for (x, filled) in row.enumerated() where filled {
                        let rect = CGRect(
                            x: CGFloat(x) * cellW,
                            y: CGFloat(y) * cellH,
                            width: cellW,
                            height: cellH
                        )
                        ctx.fill(Path(rect), with: .color(.white.opacity(0.92)))
                    }
                }
            }
        }
        .frame(width: 16, height: 16)
        .accessibilityLabel("\(pet.displayName) — \(state.rawValue)")
    }
}
