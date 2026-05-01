import SwiftUI
import OpenIslandCore

struct CelebrationParticles: View {
    let tint: ProjectColor?
    let startedAt: Date
    let count: Int

    static let duration: TimeInterval = 2.0
    static let gravity: CGFloat = 350

    var body: some View {
        TimelineView(.animation) { timeline in
            let elapsed = timeline.date.timeIntervalSince(startedAt)
            if elapsed < Self.duration {
                Canvas { ctx, size in
                    let alpha = Self.opacity(elapsed: elapsed)
                    let color = tint.map { Color(red: $0.red, green: $0.green, blue: $0.blue) }
                        ?? Color.gray.opacity(0.6)
                    let anchor = CGPoint(x: size.width * 0.15, y: size.height * 0.5)

                    for seed in 0..<count {
                        let pos = Self.position(seed: seed, elapsed: elapsed, anchor: anchor)
                        let rotation = Self.rotation(seed: seed, elapsed: elapsed)
                        let rect = CGRect(x: pos.x - 2, y: pos.y - 2, width: 4, height: 4)

                        ctx.translateBy(x: pos.x, y: pos.y)
                        ctx.rotate(by: .radians(rotation))
                        ctx.translateBy(x: -pos.x, y: -pos.y)

                        ctx.fill(
                            Path(roundedRect: rect, cornerRadius: 1),
                            with: .color(color.opacity(alpha))
                        )

                        ctx.translateBy(x: pos.x, y: pos.y)
                        ctx.rotate(by: .radians(-rotation))
                        ctx.translateBy(x: -pos.x, y: -pos.y)
                    }
                }
            } else {
                Color.clear
            }
        }
        .allowsHitTesting(false)
    }

    // MARK: - Pure math (unit-testable)

    static func opacity(elapsed: TimeInterval) -> Double {
        max(0, 1 - elapsed / duration)
    }

    static func position(seed: Int, elapsed: TimeInterval, anchor: CGPoint) -> CGPoint {
        let s = Double(seed)
        let vx = (sin(s * 7.3) * 60)
        let vy = -120 - (s.truncatingRemainder(dividingBy: 4)) * 30
        let t = elapsed
        let x = anchor.x + CGFloat(vx * t)
        let y = anchor.y + CGFloat(vy * t + 0.5 * Double(gravity) * t * t)
        return CGPoint(x: x, y: y)
    }

    static func rotation(seed: Int, elapsed: TimeInterval) -> Double {
        let s = Double(seed)
        return s * .pi / 2 + elapsed * .pi * 4
    }
}
