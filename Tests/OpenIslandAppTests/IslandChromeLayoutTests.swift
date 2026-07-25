import AppKit
import SwiftUI
import Testing
@testable import OpenIslandApp

/// Regression suite for AB-320's overlay-chrome seam.
///
/// The bug this pins: `OverlayPanelController` sized the overlay window (and
/// its hit-test rect) from the *live theme's* `IslandMetricsTokens`, while
/// `IslandPanelView` padded its content with the legacy `IslandChromeMetrics`
/// statics. For every theme whose insets differ from Classic's — Poured, whose
/// opened horizontal inset is 28 against Classic's 18 — the surface therefore
/// rendered 2 × 10pt wider than the window's interactive area, leaving a visible
/// but unclickable rim.
///
/// Both sides now derive from `IslandChromeLayout`, so the tests below assert
/// the two things that make that safe:
///
/// 1. the drawn surface (`surfaceRect`, SwiftUI's top-left-origin space) and the
///    interactive area (`contentRect`, AppKit's bottom-left-origin space) are
///    the same rectangle, for every registered theme, opened *and* closed; and
/// 2. `insets(forWindowWidth:metrics:)` is the exact inverse of
///    `windowSize(...)` in all three clamp regimes, which is what lets the view
///    recover the controller's padding from nothing but the geometry it is
///    handed.
struct IslandChromeLayoutTests {

    // MARK: - Fixtures

    /// A plausible opened content height: notch (32) + empty-state body (108).
    private static let contentHeight: CGFloat = 140

    /// A roomy screen — 14" MacBook Pro visible width — so no clamp is in play.
    private static let roomyWidth: CGFloat = 1_512

    /// Closed-pill hit-area widths `OverlayPanelController.closedPanelWidth`
    /// produces: `notch + 88` on a MacBook, a fixed 360 on an external display.
    private static let macbookClosedSize = CGSize(width: 224 + 88, height: 32)
    private static let externalClosedSize = CGSize(width: 360, height: 32)

    /// Reinterprets a SwiftUI-space surface rect (top-left origin, relative to
    /// the window) in the AppKit screen space the controller hit-tests in.
    private func screenRect(forSurface surface: CGRect, inPanelFrame frame: NSRect) -> NSRect {
        NSRect(
            x: frame.minX + surface.minX,
            y: frame.maxY - surface.maxY,
            width: surface.width,
            height: surface.height
        )
    }

    /// Every corner of `rect` lies inside `container`, edges counting as inside
    /// — the same predicate `OverlayPanelController` hit-tests with.
    private func isContained(_ rect: NSRect, in container: NSRect) -> Bool {
        let corners = [
            NSPoint(x: rect.minX, y: rect.minY),
            NSPoint(x: rect.maxX, y: rect.minY),
            NSPoint(x: rect.minX, y: rect.maxY),
            NSPoint(x: rect.maxX, y: rect.maxY),
        ]
        return corners.allSatisfy {
            OverlayPanelController.rectContainsIncludingEdges(container, point: $0)
        }
    }

    // MARK: - 1. Poured opened layout

    /// The headline number from the ticket: Poured declares a 28pt opened
    /// horizontal inset, so its 540pt opened surface needs a 596pt window —
    /// *not* the 576pt Classic's 18pt inset would produce, and not a 560pt
    /// surface inside a 596pt window, which is what the pre-AB-320 mismatch
    /// actually drew.
    @Test
    func pouredOpenedWindowWrapsA540SurfaceInTwentyEightPointsPerSide() {
        let metrics = IslandMetricsTokens.poured
        let reserved = IslandChromeLayout.reservedInsets(for: metrics)

        #expect(reserved.horizontal == 28)
        #expect(reserved.bottom == 34)

        let window = IslandChromeLayout.windowSize(
            preferredContentWidth: 540,
            contentHeight: Self.contentHeight,
            metrics: metrics,
            availableWidth: Self.roomyWidth
        )

        #expect(window.width == 596)
        #expect(window.height == Self.contentHeight + 34)

        let surface = IslandChromeLayout.surfaceRect(inWindowOfSize: window, metrics: metrics)
        #expect(surface.width == 540)
        #expect(surface.minX == 28)
        #expect(window.width - surface.maxX == 28)
        #expect(surface.height == Self.contentHeight)
    }

    /// Hit-test parity for that exact layout: the rendered surface and the
    /// controller's interactive rect are the same rectangle, so no drawn pixel
    /// is unclickable and no click lands outside anything drawn.
    @Test
    func pouredRenderedSurfaceExactlyFillsTheHitTestRect() {
        let metrics = IslandMetricsTokens.poured
        let window = IslandChromeLayout.windowSize(
            preferredContentWidth: 540,
            contentHeight: Self.contentHeight,
            metrics: metrics,
            availableWidth: Self.roomyWidth
        )
        // Panel is pinned to the top of the screen and centred horizontally.
        let panelFrame = NSRect(
            x: 1_512 / 2 - window.width / 2,
            y: 982 - window.height,
            width: window.width,
            height: window.height
        )

        let surface = IslandChromeLayout.surfaceRect(inWindowOfSize: window, metrics: metrics)
        let drawn = screenRect(forSurface: surface, inPanelFrame: panelFrame)
        let hit = IslandChromeLayout.contentRect(in: panelFrame, metrics: metrics)

        #expect(drawn == hit)
        #expect(isContained(drawn, in: hit))

        // A point just outside the drawn surface is outside the hit rect too —
        // the rim that used to be drawn-but-dead is now simply not drawn.
        #expect(!OverlayPanelController.rectContainsIncludingEdges(
            hit,
            point: NSPoint(x: drawn.minX - 1, y: drawn.midY)
        ))
        #expect(!OverlayPanelController.rectContainsIncludingEdges(
            hit,
            point: NSPoint(x: drawn.maxX + 1, y: drawn.midY)
        ))
        #expect(!OverlayPanelController.rectContainsIncludingEdges(
            hit,
            point: NSPoint(x: drawn.midX, y: drawn.minY - 1)
        ))
    }

    // MARK: - 2. Window vs surface, every registered theme

    /// The generalization of the above across the whole registry: whatever a
    /// theme declares, the surface the view draws is contained in the rect the
    /// controller hit-tests — opened *and* closed.
    @MainActor
    @Test
    func everyThemeRendersItsSurfaceInsideTheHitTestRect() {
        for theme in ThemeRegistry.all {
            let metrics = theme.tokens.metrics
            let window = IslandChromeLayout.windowSize(
                preferredContentWidth: 540,
                contentHeight: Self.contentHeight,
                metrics: metrics,
                availableWidth: Self.roomyWidth
            )
            let panelFrame = NSRect(
                x: 1_512 / 2 - window.width / 2,
                y: 982 - window.height,
                width: window.width,
                height: window.height
            )
            let hit = IslandChromeLayout.contentRect(in: panelFrame, metrics: metrics)

            // Opened: the surface fills the hit rect exactly.
            let opened = screenRect(
                forSurface: IslandChromeLayout.surfaceRect(inWindowOfSize: window, metrics: metrics),
                inPanelFrame: panelFrame
            )
            #expect(isContained(opened, in: hit), "\(theme.id) opened surface escapes the hit rect")
            #expect(opened == hit, "\(theme.id) opened surface is not the hit rect")

            // Closed: the pill is narrower and shorter, centred, flush to the
            // top of the content area — comfortably inside the same rect. The
            // window never resizes, so this is the *opened*-size window.
            for closedSize in [Self.macbookClosedSize, Self.externalClosedSize] {
                let closed = screenRect(
                    forSurface: IslandChromeLayout.closedSurfaceRect(
                        inWindowOfSize: window,
                        closedSize: closedSize
                    ),
                    inPanelFrame: panelFrame
                )
                #expect(
                    isContained(closed, in: hit),
                    "\(theme.id) closed pill (\(closedSize.width)pt) escapes the hit rect"
                )
            }
        }
    }

    /// Closed-glow headroom for the shipping themes: the pill is centred inside
    /// an opened-size window, so the free space beside and below it comfortably
    /// contains the theme's declared closed shadow insets.
    @MainActor
    @Test
    func everyThemeLeavesRoomForItsDeclaredClosedShadow() {
        for theme in ThemeRegistry.all {
            let metrics = theme.tokens.metrics
            let window = IslandChromeLayout.windowSize(
                preferredContentWidth: 540,
                contentHeight: Self.contentHeight,
                metrics: metrics,
                availableWidth: Self.roomyWidth
            )

            for closedSize in [Self.macbookClosedSize, Self.externalClosedSize] {
                let headroom = IslandChromeLayout.closedSurfaceHeadroom(
                    windowSize: window,
                    closedSize: closedSize
                )
                #expect(headroom.top == 0)
                #expect(
                    headroom.horizontal >= metrics.closedShadowHorizontalInset,
                    "\(theme.id) clips its closed glow sideways"
                )
                #expect(
                    headroom.bottom >= metrics.closedShadowBottomInset,
                    "\(theme.id) clips its closed glow below"
                )
            }
        }
    }

    // MARK: - 3. Closed insets consume window space

    /// Pinned on a synthetic fixture, deliberately *not* on a shipping theme:
    /// every theme in the registry today declares closed insets smaller than
    /// its opened ones, so the `max()` in `reservedInsets(for:)` is invisible
    /// from their values alone. A theme opting into a loud closed-pill glow —
    /// `SPEC-halo` §1b — must grow the window rather than have the glow clipped.
    @Test
    func closedInsetsLargerThanOpenedGrowTheWindow() {
        var quiet = IslandMetricsTokens.classic
        quiet.closedShadowHorizontalInset = 0
        quiet.closedShadowBottomInset = 0

        var glowing = quiet
        glowing.closedShadowHorizontalInset = 44
        glowing.closedShadowBottomInset = 52

        // Sanity: the fixture really is closed-dominant on both axes.
        #expect(glowing.closedShadowHorizontalInset > glowing.openedShadowHorizontalInset)
        #expect(glowing.closedShadowBottomInset > glowing.openedShadowBottomInset)

        #expect(IslandChromeLayout.reservedInsets(for: quiet) == IslandChromeInsets(horizontal: 18, bottom: 22))
        #expect(IslandChromeLayout.reservedInsets(for: glowing) == IslandChromeInsets(horizontal: 44, bottom: 52))

        let quietWindow = IslandChromeLayout.windowSize(
            preferredContentWidth: 540,
            contentHeight: Self.contentHeight,
            metrics: quiet,
            availableWidth: Self.roomyWidth
        )
        let glowingWindow = IslandChromeLayout.windowSize(
            preferredContentWidth: 540,
            contentHeight: Self.contentHeight,
            metrics: glowing,
            availableWidth: Self.roomyWidth
        )

        #expect(quietWindow == CGSize(width: 540 + 36, height: Self.contentHeight + 22))
        #expect(glowingWindow == CGSize(width: 540 + 88, height: Self.contentHeight + 52))

        // The content itself is untouched — only the reserved ring grew.
        let quietSurface = IslandChromeLayout.surfaceRect(inWindowOfSize: quietWindow, metrics: quiet)
        let glowingSurface = IslandChromeLayout.surfaceRect(inWindowOfSize: glowingWindow, metrics: glowing)
        #expect(quietSurface.width == 540)
        #expect(glowingSurface.width == 540)
        #expect(glowingSurface.minX == 44)
    }

    /// …and the extra width is actually where the glow needs it: a shadow whose
    /// radius is at most the declared closed insets fits between the centred
    /// pill and every window edge it can bleed towards.
    ///
    /// `top` is structurally 0 — the window's top edge is the physical screen
    /// top, so nothing can bleed above the pill; a closed glow spreads sideways
    /// and down, which is exactly what the two other axes assert.
    @Test
    func closedGlowFitsBetweenThePillAndTheWindowEdges() {
        var glowing = IslandMetricsTokens.classic
        glowing.closedShadowHorizontalInset = 44
        glowing.closedShadowBottomInset = 52
        glowing.closedSurfaceShadow = IslandShadowToken(
            color: .white,
            opacity: 0.6,
            radius: 40,
            yOffset: 6
        )

        let window = IslandChromeLayout.windowSize(
            preferredContentWidth: 540,
            contentHeight: Self.contentHeight,
            metrics: glowing,
            availableWidth: Self.roomyWidth
        )

        for closedSize in [Self.macbookClosedSize, Self.externalClosedSize] {
            let rect = IslandChromeLayout.closedSurfaceRect(
                inWindowOfSize: window,
                closedSize: closedSize
            )
            // Centred horizontally, flush with the top of the window.
            #expect(rect.midX == window.width / 2)
            #expect(rect.minY == 0)

            let headroom = IslandChromeLayout.closedSurfaceHeadroom(
                windowSize: window,
                closedSize: closedSize
            )
            #expect(headroom.top == 0)
            #expect(headroom.horizontal >= glowing.closedShadowHorizontalInset)
            #expect(headroom.bottom >= glowing.closedShadowBottomInset)

            // The declared shadow itself — radius plus its downward offset —
            // stays inside that headroom.
            let shadow = glowing.resolvedClosedSurfaceShadow
            #expect(shadow.radius <= headroom.horizontal)
            #expect(shadow.radius + shadow.yOffset <= headroom.bottom)
        }
    }

    // MARK: - 4. Screen-width clamp

    /// The three regimes, with the exact numbers for Poured (reserved
    /// horizontal 28, preferred content 540):
    ///
    /// | available | content | insets | window |
    /// |-----------|---------|--------|--------|
    /// | 1512      | 540     | 28     | 596    |
    /// | 500       | 444     | 28     | 500    |
    /// | 400       | 360     | 20     | 400    |
    ///
    /// Reserving comes first, so the *window* fits on screen before the content
    /// gives way; only once the content hits its 360pt floor do the insets get
    /// trimmed, symmetrically.
    @Test
    func clampRegimesTrimContentThenInsets() {
        let metrics = IslandMetricsTokens.poured
        let fixtures: [(available: CGFloat, content: CGFloat, inset: CGFloat, window: CGFloat)] = [
            (1_512, 540, 28, 596),
            (500, 444, 28, 500),
            (400, 360, 20, 400),
        ]

        for fixture in fixtures {
            let content = IslandChromeLayout.contentWidth(
                preferred: 540,
                metrics: metrics,
                availableWidth: fixture.available
            )
            #expect(content == fixture.content, "content @\(fixture.available)")

            let window = IslandChromeLayout.windowSize(
                preferredContentWidth: 540,
                contentHeight: Self.contentHeight,
                metrics: metrics,
                availableWidth: fixture.available
            )
            #expect(window.width == fixture.window, "window @\(fixture.available)")
            #expect(window.width <= fixture.available, "window overflows screen @\(fixture.available)")

            // Round trip: the window carries enough information to recover the
            // insets it was built with, trimmed cases included.
            let insets = IslandChromeLayout.insets(forWindowWidth: window.width, metrics: metrics)
            #expect(insets == IslandChromeInsets(horizontal: fixture.inset, bottom: 34), "insets @\(fixture.available)")

            // …and the surface the view derives from those insets is the
            // clamped content width, inset symmetrically.
            let surface = IslandChromeLayout.surfaceRect(inWindowOfSize: window, metrics: metrics)
            #expect(surface.width == fixture.content)
            #expect(surface.minX == fixture.inset)
            #expect(window.width - surface.maxX == fixture.inset)
            #expect(surface.width >= IslandChromeLayout.minimumContentWidth)
        }
    }

    /// The clamp invariants as properties rather than fixtures, swept across
    /// every registered theme and every plausible screen width: the window
    /// never exceeds the screen, the content never drops below its floor, the
    /// trim is symmetric, and `insets(forWindowWidth:)` inverts `windowSize`
    /// everywhere in between.
    @MainActor
    @Test
    func clampInvariantsHoldAcrossThemesAndScreenWidths() {
        for theme in ThemeRegistry.all {
            let metrics = theme.tokens.metrics
            let reserved = IslandChromeLayout.reservedInsets(for: metrics)

            for available in stride(from: CGFloat(360), through: CGFloat(3_840), by: 7) {
                for preferred in [CGFloat(520), 540] {
                    let window = IslandChromeLayout.windowSize(
                        preferredContentWidth: preferred,
                        contentHeight: Self.contentHeight,
                        metrics: metrics,
                        availableWidth: available
                    )
                    let content = IslandChromeLayout.contentWidth(
                        preferred: preferred,
                        metrics: metrics,
                        availableWidth: available
                    )
                    let insets = IslandChromeLayout.insets(forWindowWidth: window.width, metrics: metrics)

                    #expect(window.width <= available, "\(theme.id) window > screen @\(available)")
                    #expect(content >= IslandChromeLayout.minimumContentWidth, "\(theme.id) content below floor @\(available)")
                    #expect(insets.horizontal <= reserved.horizontal, "\(theme.id) insets exceed reserved @\(available)")
                    #expect(window.width == content + insets.horizontal * 2, "\(theme.id) round trip @\(available)")

                    // Symmetric trim: the surface sits with equal gaps either side.
                    let surface = IslandChromeLayout.surfaceRect(inWindowOfSize: window, metrics: metrics)
                    #expect(surface.minX == window.width - surface.maxX, "\(theme.id) asymmetric trim @\(available)")
                    #expect(surface.width == content, "\(theme.id) surface != content @\(available)")
                }
            }
        }
    }

    /// The one deliberate exception: on a screen narrower than the 360pt content
    /// floor there is nothing left to trim, so the window spills past the screen
    /// edge rather than squeezing the island into unusability. Pinned so the
    /// behaviour is a decision rather than an accident — and the round trip
    /// still holds (the insets are gone entirely).
    @Test
    func belowTheContentFloorTheWindowSpillsRatherThanSqueezingContent() {
        let metrics = IslandMetricsTokens.poured
        let window = IslandChromeLayout.windowSize(
            preferredContentWidth: 540,
            contentHeight: Self.contentHeight,
            metrics: metrics,
            availableWidth: 300
        )

        #expect(window.width == IslandChromeLayout.minimumContentWidth)
        #expect(window.width > 300)

        let insets = IslandChromeLayout.insets(forWindowWidth: window.width, metrics: metrics)
        #expect(insets.horizontal == 0)

        let surface = IslandChromeLayout.surfaceRect(inWindowOfSize: window, metrics: metrics)
        #expect(surface.width == IslandChromeLayout.minimumContentWidth)
        #expect(surface.minX == 0)
    }

    // MARK: - 5. Classic is unchanged

    /// AB-320 must be a pure no-op for Classic. Its tokens equal the legacy
    /// `IslandChromeMetrics` statics (pinned in `IslandThemeTokensTests`), so
    /// routing the window, the padding and the hit rect through
    /// `IslandChromeLayout` has to reproduce the pre-ticket arithmetic exactly:
    /// window = content + 2 × 18 wide, content height + 22 tall.
    @Test
    func classicWindowMathMatchesTheLegacyConstants() {
        let metrics = IslandMetricsTokens.classic
        let reserved = IslandChromeLayout.reservedInsets(for: metrics)

        #expect(reserved.horizontal == IslandChromeMetrics.openedShadowHorizontalInset)
        #expect(reserved.bottom == IslandChromeMetrics.openedShadowBottomInset)

        let window = IslandChromeLayout.windowSize(
            preferredContentWidth: 540,
            contentHeight: Self.contentHeight,
            metrics: metrics,
            availableWidth: Self.roomyWidth
        )

        #expect(window.width == 540 + (IslandChromeMetrics.openedShadowHorizontalInset * 2))
        #expect(window.height == Self.contentHeight + IslandChromeMetrics.openedShadowBottomInset)

        let insets = IslandChromeLayout.insets(forWindowWidth: window.width, metrics: metrics)
        #expect(insets.horizontal == IslandChromeMetrics.openedShadowHorizontalInset)
        #expect(insets.bottom == IslandChromeMetrics.openedShadowBottomInset)

        // The closed pill casts nothing, so the morph and the Reduce Motion
        // path are both no-ops for Classic.
        #expect(metrics.closedSurfaceShadow == nil)
        #expect(metrics.resolvedClosedSurfaceShadow.opacity == 0)
        #expect(metrics.resolvedClosedSurfaceShadow.radius == 0)
        #expect(metrics.resolvedClosedSurfaceShadow.yOffset == 0)
    }
}
