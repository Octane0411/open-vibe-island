import SwiftUI

/// v6 `UnifiedBars` glyph — three vertical bars that share the same geometry
/// across all three notch states (idle / running / waiting), so transitions
/// animate bar heights smoothly instead of swapping glyphs.
///
/// Canonical geometry (from the design handoff): 24×24 box, 3 bars of width
/// 2.5 centered on columns x = 5.25 / 10.75 / 16.25, rounded to a pill.
struct UnifiedBars: View {
    enum Mode: Equatable {
        case idle       // rest — 3 short bars, middle breathes
        case running    // wave — heights 4→12→4, stagger 0.15s
        case waiting    // pause — outer bars tall, middle hidden, cross-pulse
    }

    var mode: Mode
    var size: CGFloat = 24
    /// Ink color for bars / tick. Defaults to the v6 paper ink.
    var tint: Color = Color(red: 0xf1 / 255.0, green: 0xea / 255.0, blue: 0xd9 / 255.0)
    /// When false, the resting `.idle` glyph is drawn statically instead of
    /// breathing — a user-facing battery option. `.running` / `.waiting` always
    /// animate, since they signal live activity worth showing.
    var idleAnimated: Bool = true

    private static let box: CGFloat = 24
    private static let barWidth: CGFloat = 2.5
    private static let center: CGFloat = 12

    private static let columns: [Column] = [
        Column(x: 5.25,  idleH: 3, waveCycle: [4, 12, 4], waveDelay: 0.00, waitH: 10),
        Column(x: 10.75, idleH: 5, waveCycle: [6, 14, 6], waveDelay: 0.15, waitH: 0),
        Column(x: 16.25, idleH: 3, waveCycle: [4, 10, 4], waveDelay: 0.30, waitH: 10),
    ]

    var body: some View {
        Group {
            if isAnimated {
                // Cap the redraw cadence per mode instead of riding the
                // display's native refresh rate. This glyph lives in the notch
                // and is visible 24/7 — on a 120 Hz ProMotion display an
                // uncapped `.animation` schedule redraws the Canvas up to
                // 120×/sec forever, even in the resting `.idle` state, which
                // dominates energy use. The animations here are slow (0.9–2.8 s
                // periods), so a modest frame cap is visually indistinguishable
                // while cutting wakeups several-fold.
                TimelineView(.animation(minimumInterval: frameInterval)) { timeline in
                    barsCanvas(time: timeline.date.timeIntervalSinceReferenceDate)
                }
            } else {
                // Static resting frame — zero continuous redraws. `staticTime`
                // is chosen so the idle breath sits at its full-opacity rest.
                barsCanvas(time: Self.staticIdleTime)
            }
        }
        .frame(width: size, height: size)
    }

    private func barsCanvas(time: TimeInterval) -> some View {
        Canvas { context, canvasSize in
            withScaledContext(context, canvasSize) { ctx in
                drawBars(context: ctx, time: time)
            }
        }
    }

    /// Whether this glyph should drive a live animation. `.running` / `.waiting`
    /// always do; `.idle` only when the user hasn't opted into a static glyph.
    private var isAnimated: Bool {
        mode != .idle || idleAnimated
    }

    /// Time offset whose idle breath evaluates to full opacity (sin peak at
    /// period/4 of the 2.8 s cycle), giving a clean resting glyph when static.
    private static let staticIdleTime: TimeInterval = 0.7

    /// Minimum interval between Canvas redraws, chosen per mode so each
    /// animation stays smooth at the lowest cadence its period allows.
    private var frameInterval: Double {
        switch mode {
        case .idle:    return 1.0 / 12.0   // 2.8 s breath — 12 fps is ample
        case .running: return 1.0 / 30.0   // 0.9 s wave — fastest motion
        case .waiting: return 1.0 / 15.0   // 1.8 s cross-pulse
        }
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

    private func drawBars(context: GraphicsContext, time: TimeInterval) {
        for column in Self.columns {
            let (height, y, opacity) = barGeometry(for: column, time: time)
            guard opacity > 0, height > 0 else { continue }
            let rect = CGRect(
                x: column.x,
                y: y,
                width: Self.barWidth,
                height: height
            )
            let path = Path(
                roundedRect: rect,
                cornerSize: CGSize(width: Self.barWidth / 2, height: Self.barWidth / 2)
            )
            context.fill(path, with: .color(tint.opacity(opacity)))
        }
    }

    private func barGeometry(
        for column: Column,
        time: TimeInterval
    ) -> (height: CGFloat, y: CGFloat, opacity: Double) {
        switch mode {
        case .idle:
            let h = column.idleH
            let isMiddle = column.x == Self.columns[1].x
            let breath = isMiddle
                ? 0.7 + 0.3 * abs(sin(time * 2 * .pi / 2.8))
                : 1.0
            return (h, Self.center - h / 2, breath)
        case .running:
            let cycle = column.waveCycle
            let period: TimeInterval = 0.9
            let raw = (time - column.waveDelay)
                .truncatingRemainder(dividingBy: period) / period
            let phase = raw < 0 ? raw + 1 : raw
            let h: CGFloat
            if phase < 0.5 {
                let t = phase / 0.5
                h = cycle[0] + (cycle[1] - cycle[0]) * t
            } else {
                let t = (phase - 0.5) / 0.5
                h = cycle[1] + (cycle[2] - cycle[1]) * t
            }
            return (h, Self.center - h / 2, 1.0)
        case .waiting:
            let h = column.waitH
            guard h > 0 else { return (0, Self.center, 0) }
            let isLeading = column.x < Self.center
            let period: TimeInterval = 1.8
            let offset = isLeading ? 0.0 : period / 2
            let progress = ((time + offset)
                .truncatingRemainder(dividingBy: period)) / period
            let wave = 0.5 - 0.5 * cos(progress * 2 * .pi)
            let opacity = 0.55 + 0.45 * wave
            return (h, Self.center - h / 2, opacity)
        }
    }

    private struct Column: Equatable {
        let x: CGFloat
        let idleH: CGFloat
        let waveCycle: [CGFloat]
        let waveDelay: TimeInterval
        let waitH: CGFloat
    }
}
