import SwiftUI

/// v6 primary logo — "Bar + Dot" inside a notch-shape (flat-top,
/// rounded-bottom). Used by the menu bar extra and anywhere else the app
/// presents its brand mark.
///
/// Two styles:
/// - `.duotone`: renders the full paper/ink palette (notch-color fill + inverse
///   foreground). Use on light / dark surfaces.
/// - `.template`: single-color silhouette — pill filled with `tint`, bar + dot
///   knocked out via even-odd fill so the menu bar can show-through.
struct OpenIslandBrandMark: View {
    enum Style {
        case duotone
        case template
    }

    enum Tone { case paper, ink }

    let size: CGFloat
    var tint: Color = .primary
    /// For `.duotone`: chooses which end of the palette is background.
    ///   - `paper` (default): light background (#f1ead9), dark mark
    ///   - `ink`: dark background (#0d0d0f), light mark
    var tone: Tone = .paper
    var style: Style = .duotone

    // Canonical viewBox from the design handoff: 160×64.
    private static let designWidth: CGFloat = 160
    private static let designHeight: CGFloat = 64

    var body: some View {
        let h = size * Self.designHeight / Self.designWidth
        content()
            .frame(width: size, height: h)
    }

    @ViewBuilder
    private func content() -> some View {
        switch style {
        case .template:
            BarDotMarkShape()
                .fill(tint, style: FillStyle(eoFill: true))
        case .duotone:
            let bg: Color = tone == .paper ? V6Palette.ink : V6Palette.paper
            let fg: Color = tone == .paper ? V6Palette.paper : V6Palette.ink
            ZStack(alignment: .leading) {
                V6ClosedPillShape()
                    .fill(bg)

                GeometryReader { proxy in
                    let w = proxy.size.width
                    let h = proxy.size.height
                    // Bar — 70 wide × 7 tall, starting at x=30 in the 160-wide viewBox.
                    RoundedRectangle(
                        cornerRadius: (h * 7 / Self.designHeight) / 2,
                        style: .continuous
                    )
                    .fill(fg)
                    .frame(width: w * 70 / Self.designWidth, height: h * 7 / Self.designHeight)
                    .position(
                        x: w * (30 + 35) / Self.designWidth,
                        y: h / 2
                    )
                    // Trailing dot — r=5 at (118, 32).
                    Circle()
                        .fill(fg)
                        .frame(
                            width: h * 10 / Self.designHeight,
                            height: h * 10 / Self.designHeight
                        )
                        .position(
                            x: w * 118 / Self.designWidth,
                            y: h / 2
                        )
                }
            }
        }
    }
}

/// Combined outline of the Bar+Dot mark. Fills with an even-odd rule so the
/// interior bar + dot punch through to the background — used by the template
/// menu-bar rendering.
private struct BarDotMarkShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()

        // Outer pill (flat top, rounded bottom).
        path.addPath(V6ClosedPillShape().path(in: rect))

        // Bar: x=30..100, y=28.5..35.5 in the 160×64 viewBox.
        let barW = rect.width * 70 / 160
        let barH = rect.height * 7 / 64
        let barX = rect.minX + rect.width * 30 / 160
        let barY = rect.minY + (rect.height - barH) / 2
        path.addRoundedRect(
            in: CGRect(x: barX, y: barY, width: barW, height: barH),
            cornerSize: CGSize(width: barH / 2, height: barH / 2)
        )

        // Dot: r=5 at (118, 32).
        let dotR = rect.height * 5 / 64
        let dotCX = rect.minX + rect.width * 118 / 160
        let dotCY = rect.minY + rect.height / 2
        path.addEllipse(
            in: CGRect(x: dotCX - dotR, y: dotCY - dotR, width: dotR * 2, height: dotR * 2)
        )

        return path
    }
}
