import SwiftUI

/// v6 `UnifiedBars` glyph — three vertical bars that share the same geometry
/// across all three notch states (idle / running / waiting), so transitions
/// animate bar heights smoothly instead of swapping glyphs.
///
/// Canonical geometry (from the design handoff): 24×24 box, 3 bars of width
/// 2.5 centered on columns x = 5.25 / 10.75 / 16.25, rounded to a pill.
struct UnifiedBars: View {
    enum Mode: Hashable {
        case idle       // rest — 3 short bars, middle breathes
        case running    // wave — heights 4→12→4, stagger 0.15s
        case waiting    // pause — outer bars tall, middle hidden, cross-pulse
    }

    var mode: Mode
    var size: CGFloat = 24
    var character: IslandCharacter = .dino
    /// Ink color for bars / tick. Defaults to the v6 paper ink.
    var tint: Color = Color(red: 0xf1 / 255.0, green: 0xea / 255.0, blue: 0xd9 / 255.0)

    private static let box: CGFloat = 24

    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { context, canvasSize in
                withScaledContext(context, canvasSize) { ctx in
                    drawCharacter(context: ctx, time: timeline.date.timeIntervalSinceReferenceDate)
                }
            }
        }
        .frame(width: size, height: size)
    }

    // MARK: - Drawing

    private func withScaledContext(
        _ context: GraphicsContext,
        _ canvasSize: CGSize,
        body: (GraphicsContext) -> Void
    ) {
        var ctx = context
        let side = min(canvasSize.width, canvasSize.height)
        let scale = side / Self.box
        let dx = (canvasSize.width - side) / 2
        let dy = (canvasSize.height - side) / 2
        ctx.translateBy(x: dx, y: dy)
        ctx.scaleBy(x: scale, y: scale)
        body(ctx)
    }

    private func drawCharacter(context: GraphicsContext, time: TimeInterval) {
        var frame = character.idleFrame
        let runningFrame = character.runningFrame
        let eyeCoordinate = character.eyeCoordinate

        var bounce: CGFloat = 0.0
        var opacity: Double = 1.0

        switch mode {
        case .running:
            let isEvenFrame = (Int(time * 5.0) % 2 == 0)
            if !isEvenFrame {
                frame = runningFrame
            }
            bounce = character.runningBounce(time: time)

        case .idle:
            let isBlinking = (time.truncatingRemainder(dividingBy: 3.0) < 0.15)
            if isBlinking, let eyeCoordinate {
                frame[eyeCoordinate.row][eyeCoordinate.column] = 1
            }

        case .waiting:
            let progress = time.truncatingRemainder(dividingBy: 1.8) / 1.8
            let wave = 0.5 - 0.5 * cos(progress * 2 * .pi)
            opacity = 0.45 + 0.55 * wave
        }

        let pixelSize: CGFloat = 1.6
        let gap: CGFloat = 0.35
        let totalSize = CGFloat(9) * pixelSize + CGFloat(8) * gap
        let startX = (Self.box - totalSize) / 2
        let startY = (Self.box - totalSize) / 2 - bounce

        if character == .pikachu && mode == .running {
            let loopDuration: TimeInterval = 0.8
            let progress = time.truncatingRemainder(dividingBy: loopDuration) / loopDuration
            let colOffset = progress * 12.0

            // Draw Pikachu Body (runningFrame has no tail)
            for r in 0..<9 {
                for c in 0..<9 {
                    if runningFrame[r][c] == 1 {
                        let rect = CGRect(
                            x: startX + CGFloat(c) * (pixelSize + gap),
                            y: startY + CGFloat(r) * (pixelSize + gap),
                            width: pixelSize,
                            height: pixelSize
                        )
                        let path = Path(
                            roundedRect: rect,
                            cornerSize: CGSize(width: 0.3, height: 0.3)
                        )
                        context.fill(path, with: .color(tint.opacity(opacity)))
                    }
                }
            }

            // Draw Tail shooting off
            let tailFrame: [[Int]] = [
                [0, 0, 0, 0, 0, 0, 0, 0, 0],
                [0, 0, 0, 0, 0, 0, 0, 0, 0],
                [0, 0, 0, 0, 0, 0, 0, 0, 0],
                [0, 0, 0, 0, 0, 0, 0, 0, 0],
                [1, 0, 0, 0, 0, 0, 0, 0, 0],
                [1, 1, 0, 0, 0, 0, 0, 0, 0],
                [0, 1, 1, 0, 0, 0, 0, 0, 0],
                [0, 0, 1, 0, 0, 0, 0, 0, 0],
                [0, 0, 0, 0, 0, 0, 0, 0, 0]
            ]
            for r in 0..<9 {
                for c in 0..<9 {
                    if tailFrame[r][c] == 1 {
                        let rect = CGRect(
                            x: startX + (CGFloat(c) + colOffset) * (pixelSize + gap),
                            y: startY + CGFloat(r) * (pixelSize + gap),
                            width: pixelSize,
                            height: pixelSize
                        )
                        let path = Path(
                            roundedRect: rect,
                            cornerSize: CGSize(width: 0.3, height: 0.3)
                        )
                        context.fill(path, with: .color(tint.opacity(opacity)))
                    }
                }
            }
        } else {
            for r in 0..<9 {
                for c in 0..<9 {
                    if frame[r][c] == 1 {
                        let rect = CGRect(
                            x: startX + CGFloat(c) * (pixelSize + gap),
                            y: startY + CGFloat(r) * (pixelSize + gap),
                            width: pixelSize,
                            height: pixelSize
                        )
                        let path = Path(
                            roundedRect: rect,
                            cornerSize: CGSize(width: 0.3, height: 0.3)
                        )
                        context.fill(path, with: .color(tint.opacity(opacity)))
                    }
                }
            }
        }
    }
}

private extension IslandCharacter {
    typealias PixelFrame = [[Int]]

    var title: String {
        switch self {
        case .dino: "Dino"
        case .cat: "Cat"
        case .dog: "Dog"
        case .pikachu: "Pikachu"
        }
    }

    var idleFrame: PixelFrame {
        switch self {
        case .dino:
            [
            [0, 0, 0, 0, 1, 1, 1, 1, 1],
            [0, 0, 0, 0, 1, 0, 1, 1, 1], // Eye at col 5 (0 means open)
            [0, 0, 0, 0, 1, 1, 1, 1, 1],
            [0, 0, 1, 1, 1, 1, 1, 0, 0],
            [0, 1, 1, 1, 1, 1, 1, 1, 0], // Arm at col 7
            [1, 1, 1, 1, 1, 1, 1, 0, 0],
            [1, 0, 1, 1, 1, 1, 1, 0, 0], // tail curves up at col 0
            [0, 0, 0, 1, 0, 1, 0, 0, 0], // left leg down, right leg up
            [0, 0, 0, 1, 0, 0, 0, 0, 0]  // left foot
            ]
        case .cat:
            [
            [0, 0, 0, 0, 0, 0, 1, 0, 1],
            [1, 0, 0, 0, 0, 1, 1, 1, 1],
            [1, 0, 0, 1, 1, 1, 0, 1, 1],
            [1, 1, 1, 1, 1, 1, 1, 1, 0],
            [0, 1, 1, 1, 1, 1, 1, 0, 0],
            [0, 1, 1, 1, 1, 1, 0, 0, 0],
            [0, 0, 1, 1, 0, 1, 1, 0, 0],
            [0, 0, 0, 0, 0, 0, 0, 0, 0],
            [0, 0, 0, 0, 0, 0, 0, 0, 0],
            ]
        case .dog:
            [
            [0, 0, 0, 0, 0, 0, 1, 1, 0],
            [1, 0, 0, 0, 0, 1, 1, 1, 1],
            [1, 1, 0, 1, 1, 1, 0, 1, 1],
            [0, 1, 1, 1, 1, 1, 1, 1, 0],
            [0, 0, 1, 1, 1, 1, 1, 0, 0],
            [0, 0, 1, 1, 0, 1, 1, 0, 0],
            [0, 0, 1, 0, 0, 0, 1, 0, 0],
            [0, 0, 0, 0, 0, 0, 0, 0, 0],
            [0, 0, 0, 0, 0, 0, 0, 0, 0],
            ]
        case .pikachu:
            [
            [0, 0, 0, 1, 0, 0, 1, 0, 0],
            [0, 0, 0, 1, 0, 0, 1, 0, 0],
            [0, 0, 0, 1, 1, 1, 1, 1, 0],
            [0, 0, 0, 1, 0, 1, 0, 1, 0],
            [1, 0, 0, 1, 1, 1, 1, 1, 0],
            [1, 1, 0, 1, 1, 1, 1, 0, 0],
            [0, 1, 1, 1, 1, 1, 1, 0, 0],
            [0, 0, 1, 1, 1, 1, 1, 0, 0],
            [0, 0, 0, 1, 0, 1, 0, 0, 0]
            ]
        }
    }

    var runningFrame: PixelFrame {
        switch self {
        case .dino:
            [
            [0, 0, 0, 0, 1, 1, 1, 1, 1],
            [0, 0, 0, 0, 1, 0, 1, 1, 1],
            [0, 0, 0, 0, 1, 1, 1, 1, 1],
            [0, 0, 1, 1, 1, 1, 1, 1, 0], // Arm wiggles up to col 7
            [0, 1, 1, 1, 1, 1, 1, 0, 0], // Arm at col 7 is empty
            [1, 1, 1, 1, 1, 1, 1, 0, 0],
            [1, 0, 1, 1, 1, 1, 1, 0, 0],
            [0, 0, 0, 0, 0, 1, 0, 0, 0], // left leg up, right leg down
            [0, 0, 0, 0, 0, 1, 0, 0, 0]  // right foot
            ]
        case .cat:
            [
            [0, 0, 0, 0, 0, 0, 1, 0, 1],
            [0, 0, 0, 0, 0, 1, 1, 1, 1],
            [0, 1, 0, 1, 1, 1, 0, 1, 1],
            [1, 1, 1, 1, 1, 1, 1, 1, 0],
            [0, 1, 1, 1, 1, 1, 1, 0, 0],
            [0, 1, 1, 1, 1, 1, 0, 0, 0],
            [0, 0, 1, 1, 0, 1, 1, 0, 0],
            [0, 0, 0, 0, 0, 0, 0, 0, 0],
            [0, 0, 0, 0, 0, 0, 0, 0, 0],
            ]
        case .dog:
            [
            [0, 0, 0, 0, 0, 0, 1, 1, 0],
            [1, 0, 0, 0, 0, 1, 1, 1, 1],
            [1, 1, 0, 1, 1, 1, 0, 1, 1],
            [0, 1, 1, 1, 1, 1, 1, 1, 0],
            [0, 0, 1, 1, 1, 1, 1, 0, 0],
            [0, 0, 0, 1, 1, 0, 1, 0, 0],
            [0, 0, 0, 1, 0, 0, 1, 1, 0],
            [0, 0, 0, 0, 0, 0, 0, 0, 0],
            [0, 0, 0, 0, 0, 0, 0, 0, 0],
            ]
        case .pikachu:
            [
            [0, 0, 0, 1, 0, 0, 1, 0, 0],
            [0, 0, 0, 1, 0, 0, 1, 0, 0],
            [0, 0, 0, 1, 1, 1, 1, 1, 0],
            [0, 0, 0, 1, 0, 1, 0, 1, 0],
            [0, 0, 0, 1, 1, 1, 1, 1, 0],
            [0, 0, 0, 1, 1, 1, 1, 0, 0],
            [0, 0, 0, 1, 1, 1, 1, 0, 0],
            [0, 0, 0, 1, 1, 1, 1, 0, 0],
            [0, 0, 0, 1, 0, 1, 0, 0, 0]
            ]
        }
    }

    var eyeCoordinate: (row: Int, column: Int)? {
        switch self {
        case .dino: (1, 5)
        case .cat: (2, 6)
        case .dog: (2, 6)
        case .pikachu: (3, 4)
        }
    }

    func runningBounce(time: TimeInterval) -> CGFloat {
        switch self {
        case .dino:
            abs(sin(time * .pi * 5.0)) * 1.2
        case .cat:
            0
        case .dog:
            abs(sin(time * .pi * 5.0)) * 0.6
        case .pikachu:
            abs(sin(time * .pi * 5.0)) * 1.0
        }
    }
}
