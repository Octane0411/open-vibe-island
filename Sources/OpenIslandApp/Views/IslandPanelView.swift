import AppKit
import SwiftUI
@preconcurrency import MarkdownUI
import OpenIslandCore

/// Measures the full (non-notification) opened surface — header, session
/// rows, and footer combined — so `OverlayPanelController` can size the
/// window from real rendered content instead of hand-estimated per-phase
/// heights (AB-228). Mirrors `NotificationContentHeightKey`, which does the
/// same job for the single-session notification card.
private struct OpenedContentHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private struct ContentHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

/// Auto-height container: renders content directly (auto-sizing).
/// When content exceeds maxHeight, wraps in ScrollView at fixed maxHeight.
///
/// AB-298: internal (not `private`) so the extracted `IslandSessionListScaffold`
/// slot component can reuse the same measured-height + capped-scroll container.
struct AutoHeightScrollView<Content: View>: View {
    let maxHeight: CGFloat
    @ViewBuilder let content: () -> Content
    @State private var contentHeight: CGFloat = 0

    private var isScrollable: Bool { contentHeight > maxHeight }

    var body: some View {
        // Always use ScrollView so the content gets unconstrained vertical
        // space for measurement.  Without this, a tight parent window can
        // cap the GeometryReader measurement, making long content appear
        // truncated instead of scrollable.
        ScrollView(.vertical) {
            content()
                .background(
                    GeometryReader { geo in
                        Color.clear.preference(key: ContentHeightKey.self, value: geo.size.height)
                    }
                )
                .onPreferenceChange(ContentHeightKey.self) { height in
                    if height > 0 { contentHeight = height }
                }
        }
        .scrollBounceBehavior(.basedOnSize)
        .scrollIndicators(isScrollable ? .automatic : .hidden)
        .frame(height: contentHeight > 0 ? min(contentHeight, maxHeight) : nil)
    }
}

/// Inline diff preview for Edit/Write permission requests (AB-235):
/// monospaced +/- lines with a "Updated (+N −N)" summary, inside a capped,
/// scrollable container so a long diff scrolls in place rather than
/// stretching the panel — the same measured-height + capped-scroll pattern
/// `AutoHeightScrollView` already establishes elsewhere on this card (AB-228).
/// AB-303: internal (not `private`) so Poured's actionable approval body can
/// reuse the exact same diff renderer — the 500-line / 180pt caps and the
/// token-driven +/− colours (already legible on glass) are shared, not
/// re-implemented.
struct PermissionDiffPreview: View {
    let result: PermissionDiffResult
    let lang: LanguageManager

    @Environment(\.islandTokens) private var tokens

    /// Caps rendered rows so a pathologically large `Write` (e.g. a
    /// generated file with tens of thousands of lines) can't force SwiftUI
    /// to build an enormous `VStack`. The +/- counts in the summary above
    /// always reflect the full diff; only the line-by-line render is capped.
    private static let maxRenderedLines = 500
    private static let maxHeight: CGFloat = 180

    private var renderedLines: [PermissionDiffLine] {
        Array(result.lines.prefix(Self.maxRenderedLines))
    }

    private var hiddenLineCount: Int {
        result.lines.count - renderedLines.count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Text(lang.t("approval.diffUpdated"))
                Text("(")
                Text("+\(result.addedCount)")
                    .foregroundStyle(tokens.colors.statusCompleted)
                Text("\u{2212}\(result.removedCount)")
                    .foregroundStyle(tokens.colors.statusFailed)
                Text(")")
            }
            .font(.system(size: 10.5, weight: .bold, design: .monospaced))
            .foregroundStyle(tokens.colors.paper.opacity(0.66))

            AutoHeightScrollView(maxHeight: Self.maxHeight) {
                VStack(alignment: .leading, spacing: 1) {
                    ForEach(Array(renderedLines.enumerated()), id: \.offset) { _, line in
                        PermissionDiffLineRow(line: line)
                    }

                    if hiddenLineCount > 0 {
                        Text(lang.t("approval.diffMoreLines", hiddenLineCount))
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(tokens.colors.paper.opacity(0.42))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                    }
                }
                .padding(.vertical, 4)
            }
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Color.white.opacity(0.03))
            )
        }
    }
}

private struct PermissionDiffLineRow: View {
    let line: PermissionDiffLine

    @Environment(\.islandTokens) private var tokens

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            Text(marker)
                .foregroundStyle(markerColor)
                .frame(width: 10, alignment: .leading)
            Text(line.text.isEmpty ? " " : line.text)
                .foregroundStyle(textColor)
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(.system(size: 10, design: .monospaced))
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 6)
        .padding(.vertical, 1)
        .background(backgroundColor)
    }

    private var marker: String {
        switch line.kind {
        case .added: "+"
        case .removed: "\u{2212}"
        case .unchanged: " "
        }
    }

    private var markerColor: Color {
        switch line.kind {
        case .added: tokens.colors.statusCompleted
        case .removed: tokens.colors.statusFailed
        case .unchanged: tokens.colors.paper.opacity(0.3)
        }
    }

    private var textColor: Color {
        switch line.kind {
        case .added, .removed: tokens.colors.paper.opacity(0.86)
        case .unchanged: tokens.colors.paper.opacity(0.42)
        }
    }

    private var backgroundColor: Color {
        switch line.kind {
        case .added: tokens.colors.statusCompleted.opacity(0.12)
        case .removed: tokens.colors.statusFailed.opacity(0.12)
        case .unchanged: Color.clear
        }
    }
}

private struct ConditionalDrawingGroup: ViewModifier {
    let enabled: Bool

    func body(content: Content) -> some View {
        if enabled {
            content.drawingGroup()
        } else {
            content
        }
    }
}

/// AB-244: attaches a named VoiceOver action (rotor entry) only when `name`
/// is non-nil — e.g. a session row's "Dismiss" action, which only exists
/// for rows that actually got a `RowActions.dismiss` closure.
private struct OptionalNamedAccessibilityAction: ViewModifier {
    let name: String?
    let action: () -> Void

    func body(content: Content) -> some View {
        if let name {
            content.accessibilityAction(named: Text(name), action)
        } else {
            content
        }
    }
}

// MARK: - Main island view

struct IslandPanelView: View {
    var model: AppModel
    private var lang: LanguageManager { model.lang }

    /// AB-242: drives the opened surface's Reduce Transparency fallback.
    /// SwiftUI keeps this current as the user toggles System Settings →
    /// Accessibility → Display → Reduce Transparency — no manual
    /// `NSWorkspace` observation needed, unlike a plain launch-time snapshot
    /// of `NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency`.
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    /// AB-243: gates the shape-driven notch morph. SwiftUI keeps this
    /// current as the user toggles System Settings → Accessibility →
    /// Display & Text Size → Reduce Motion, same as `reduceTransparency`
    /// above. When set, `islandSurfaceBody` falls back to the plain opacity
    /// crossfade this view used before this ticket instead of morphing the
    /// shape/frame and sliding the glyph.
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// AB-244: drives the Increase Contrast fallback for dim body text and
    /// hairline dividers (`tokens.colors`). No CoreAnimation surface in this
    /// view needs contrast (unlike `reduceMotion`, which also has to reach
    /// `UnifiedBars`' `NSView`), so the plain SwiftUI environment value is
    /// enough here.
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast

    /// AB-299: the whole overlay is composed from the model's active theme.
    /// `theme` supplies the slot factories, capability flags and grid strategy;
    /// `tokens` are its `IslandThemeTokens`. Both are read straight off the
    /// `@Observable` model rather than from `@Environment`, so this view sees
    /// the live selection (a self-injected environment value wouldn't reach the
    /// injecting view itself). The overlay root injects both into the
    /// environment for descendant slot components, which keep reading
    /// `\.islandTokens` / `\.islandTheme` as before (AB-293…298).
    private var theme: any IslandTheme { model.islandTheme }
    private var tokens: IslandThemeTokens { theme.tokens }

    private var increasesContrast: Bool { colorSchemeContrast == .increased }

    @State private var isHovering = false
    @State private var showingQuitConfirmation = false
    @State private var keepsOpenedSurfaceMounted = false
    @State private var openedSurfaceMountGeneration: UInt64 = 0

    private var isOpened: Bool {
        model.notchStatus == .opened
    }

    private var usesOpenedVisualState: Bool {
        isOpened
    }

    private var shouldRenderOpenedSurface: Bool {
        usesOpenedVisualState || keepsOpenedSurfaceMounted
    }

    private var isPopping: Bool {
        model.notchStatus == .popping
    }

    /// Single animation selection based on the current notch status.
    private var notchTransitionAnimation: Animation {
        switch model.notchStatus {
        case .opened:  return tokens.motion.openAnimation.animation
        case .closed:  return tokens.motion.closeAnimation.animation
        case .popping: return tokens.motion.popAnimation.animation
        }
    }

    private var targetOverlayScreen: NSScreen? {
        if let targetScreenID = model.overlayPlacementDiagnostics?.targetScreenID,
           let screen = NSScreen.screens.first(where: { OverlayDisplayResolver.screenID(for: $0) == targetScreenID }) {
            return screen
        }

        return NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 }) ?? NSScreen.main
    }

    private var usesNotchAwareOpenedHeader: Bool {
        model.overlayPlacementDiagnostics?.mode == .notch
            || targetOverlayScreen?.safeAreaInsets.top ?? 0 > 0
    }

    /// True when the closed island sits on an external (non-notched) display.
    /// The central black rectangle is otherwise aligned with the physical
    /// notch, so center content is only useful here.
    private var isExternalDisplayPlacement: Bool {
        if let mode = model.overlayPlacementDiagnostics?.mode {
            return mode == .topBar
        }
        // Fallback when diagnostics haven't been populated yet.
        return (targetOverlayScreen?.safeAreaInsets.top ?? 0) == 0
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .top) {
                Color.clear

                notchContent(availableSize: geometry.size)
                    .frame(maxWidth: .infinity, alignment: .top)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        // AB-299: inject the active theme (and its tokens) so every descendant
        // slot component resolves its look through the current selection.
        .environment(\.islandTheme, theme)
        .environment(\.islandTokens, tokens)
        // AB-312: expose the live bridge-socket state so a theme's opened chrome
        // can wire a status readout to the truth of the connection (Flight Deck's
        // "BRIDGE LINK" footer). Themes that don't consume it are unaffected.
        .environment(\.islandBridgeIsLive, model.isBridgeReady)
        .ignoresSafeArea()
        .preferredColorScheme(.dark)
        .alert(model.lang.t("island.quit.confirmTitle"), isPresented: $showingQuitConfirmation) {
            Button(model.lang.t("island.quit.confirmAction"), role: .destructive) {
                model.quitApplication()
            }
            Button(model.lang.t("settings.general.cancel"), role: .cancel) {}
        } message: {
            Text(model.lang.t("island.quit.confirmMessage"))
        }
        .onAppear {
            syncOpenedSurfaceMount(with: model.notchStatus, immediate: true)
        }
        .onChange(of: model.notchStatus) { _, status in
            syncOpenedSurfaceMount(with: status)
        }
    }

    @ViewBuilder
    private func notchContent(availableSize: CGSize) -> some View {
        // AB-320: the window is always at opened size, and the headroom the
        // surface has to leave inside it comes from the *live theme's* metric
        // tokens — the same `IslandChromeLayout` math `OverlayPanelController`
        // sized the window with, inverted back out of the geometry we're handed.
        // Reading the legacy `IslandChromeMetrics` statics here instead meant
        // any theme with non-Classic insets drew a surface wider than the
        // controller's hit-test rect.
        let chromeInsets = IslandChromeLayout.insets(
            forWindowWidth: availableSize.width,
            metrics: tokens.metrics
        )
        let panelShadowHorizontalInset = chromeInsets.horizontal
        let panelShadowBottomInset = chromeInsets.bottom
        // The surface rect the padding below carves out, taken from the same
        // seam rather than recomputed here — it is `contentRect(in:metrics:)`
        // (what the controller hit-tests against) with the vertical axis
        // flipped, so the drawn surface and the interactive area cannot drift.
        let surfaceRect = IslandChromeLayout.surfaceRect(
            inWindowOfSize: availableSize,
            metrics: tokens.metrics
        )
        let layoutWidth = surfaceRect.width
        let layoutHeight = surfaceRect.height

        let outerHorizontalPadding: CGFloat = 0
        let outerBottomPadding: CGFloat = 0
        let openedWidth = max(0, layoutWidth - outerHorizontalPadding)
        let openedHeight = max(closedNotchHeight, layoutHeight - outerBottomPadding)

        VStack(spacing: 0) {
            islandSurfaceBody(openedWidth: openedWidth, openedHeight: openedHeight)
                .frame(maxWidth: .infinity, alignment: .top)
        }
        .scaleEffect(usesOpenedVisualState ? 1 : (isHovering ? tokens.metrics.closedHoverScale : 1), anchor: .top)
        .padding(.horizontal, panelShadowHorizontalInset)
        .padding(.bottom, panelShadowBottomInset)
        .animation(notchTransitionAnimation, value: model.notchStatus)
        .contentShape(Rectangle())
        .onHover { hovering in
            withAnimation(.spring(response: 0.38, dampingFraction: 0.8)) {
                isHovering = hovering
            }
        }
        .onTapGesture {
            if model.notchStatus != .opened {
                model.notchOpen(reason: .click)
            }
        }
    }

    private func syncOpenedSurfaceMount(with status: NotchStatus, immediate: Bool = false) {
        openedSurfaceMountGeneration &+= 1
        let generation = openedSurfaceMountGeneration

        switch status {
        case .opened:
            keepsOpenedSurfaceMounted = true
        case .closed, .popping:
            guard !immediate else {
                keepsOpenedSurfaceMounted = false
                return
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + tokens.motion.openedSurfaceUnmountDelay) {
                guard openedSurfaceMountGeneration == generation,
                      model.notchStatus != .opened else {
                    return
                }
                keepsOpenedSurfaceMounted = false
            }
        }
    }

    // MARK: - v6 closed surface

    /// Closed island per v6 spec. Renders the flat-top pill with the
    /// UnifiedBars glyph, respecting the user's right-slot / center-label
    /// preferences. AppModel is @Observable so any change to sessions /
    /// preferences re-renders this automatically; UnifiedBars runs its own
    /// TimelineView internally for bar animation.
    ///
    /// `showsGlyph: false` is used by `morphingIslandSurface` (AB-243), which
    /// renders the glyph itself as a separate, continuously-mounted overlay
    /// so it can travel into the opened header instead of fading in place —
    /// the pop-bump scale used to live here too but now lives one level up,
    /// in `islandSurfaceBody`, so it applies identically whether the morph
    /// or the Reduce Motion crossfade is active.
    @ViewBuilder
    private func v6ClosedSurface(showsGlyph: Bool = true) -> some View {
        let layout: V6ClosedLayout = isExternalDisplayPlacement ? .external : .macbook
        let physicalNotchWidth: CGFloat = targetOverlayScreen?.notchSize.width ?? 180
        theme.closedPill(
            mode: model.islandClosedMode,
            label: model.islandClosedLabel(),
            rightSlot: model.islandClosedRightSlotContent(),
            layout: layout,
            height: closedNotchHeight,
            physicalNotchWidth: layout == .macbook ? physicalNotchWidth : 0,
            minWidth: 70,
            showsGlyph: showsGlyph
        )
    }

    // MARK: - Opened surface

    /// Header + session-list content only — no background, shape, shadow, or
    /// stroke. Shared by `openedSurface` (the Reduce Motion crossfade, which
    /// draws its own chrome around this) and `morphingIslandSurface` (which
    /// draws chrome once, shared with the closed state, around whichever
    /// content is currently crossfading — AB-243).
    @ViewBuilder
    private func openedSurfaceContent(width openedWidth: CGFloat, height openedHeight: CGFloat) -> some View {
        VStack(spacing: 0) {
            openedHeaderContent
                .frame(height: closedNotchHeight)

            openedContent
                .frame(width: openedWidth)
                // AB-228: no `.clipped()` here anymore. The panel window
                // is now sized from `openedContent`'s own SwiftUI-measured
                // height (see `OverlayPanelController.openedContentHeight`),
                // so in steady state this frame already matches the
                // content exactly — clipping was only ever masking a
                // stale/wrong estimate. The intentional scroll cap for
                // long session lists lives in `AutoHeightScrollView`
                // inside `sessionList`, which scrolls instead of clipping.
                .frame(maxHeight: max(0, openedHeight - closedNotchHeight), alignment: .top)
        }
        .frame(width: openedWidth, height: openedHeight, alignment: .top)
    }

    /// Reduce Motion path only (also the shape this ticket's morph replaces
    /// for everyone else — see `morphingIslandSurface`). Draws its own full
    /// chrome (vibrancy background, shape clip, shadow, stroke) since it's
    /// never composited against a shared shape the way the morph is.
    @ViewBuilder
    private func openedSurface(width openedWidth: CGFloat, height openedHeight: CGFloat) -> some View {
        let surfaceShape = OpenedIslandSurfaceShape(
            topProfile: usesNotchAwareOpenedHeader ? .notch : .topBar,
            topCornerRadius: tokens.metrics.openedTopRadius,
            bottomCornerRadius: tokens.metrics.openedBottomRadius,
            filletRadius: tokens.metrics.filletRadius
        )
        let shadow = tokens.metrics.surfaceShadow

        ZStack(alignment: .top) {
            // AB-242: native vibrancy base + a soft shadow (the real overlay
            // used to be a flat opaque fill with neither). AB-305 routes the
            // Settings appearance preview through this same surface, so the two
            // can no longer drift. Falls back to a flat ink fill under Reduce
            // Transparency.
            OpenedSurfaceBackground(reduceTransparency: reduceTransparency || !theme.usesVibrancy)
                .frame(width: openedWidth, height: openedHeight)
                .clipShape(surfaceShape)
                .shadow(color: shadow.resolvedColor, radius: shadow.radius, y: shadow.yOffset)
                .animation(.easeInOut(duration: 0.2), value: reduceTransparency)

            openedSurfaceContent(width: openedWidth, height: openedHeight)
                .clipShape(surfaceShape)
                .overlay {
                    surfaceShape
                        .stroke(Color.white.opacity(0.07), lineWidth: 1)
                }
        }
        .frame(width: openedWidth, height: openedHeight, alignment: .top)
    }

    // MARK: - AB-243: shape-driven notch morph

    /// Leading inset (from the surface's own leading edge) where the
    /// traveling glyph lands once opened, on notch-aware layouts. Chosen to
    /// sit comfortably inside the header's reserved notch-safety gutter
    /// (`notchHeaderHorizontalPadding` = 46) so it never collides with the
    /// usage lane / header buttons, which only start rendering past that
    /// padding.
    private static let openedGlyphLeadingInset: CGFloat = 26

    /// Whether the glyph has anywhere safe to travel to once opened. The
    /// external/top-bar header reserves far less leading padding
    /// (`headerHorizontalPadding` = 18) before its own content starts — not
    /// enough room for a persistent glyph without colliding with the usage
    /// summary — so there it just fades out with the rest of the closed
    /// content instead, exactly as it did before this ticket.
    private var travelsGlyphOnOpen: Bool { usesNotchAwareOpenedHeader }

    /// The `UnifiedBars` glyph, mounted once and continuously, whose leading
    /// inset (and, on layouts with nowhere safe to land, opacity) is driven
    /// straight off `opened` — the same boolean driving the shape/frame
    /// below. A single stable view identity is enough to get free, fully
    /// interruptible position animation from SwiftUI's layout system, so
    /// there's no need for `matchedGeometryEffect`'s separate source/
    /// destination bookkeeping (and no risk of the ambiguity that comes with
    /// it if both branches were ever simultaneously mounted).
    @ViewBuilder
    private func islandGlyphOverlay(opened: Bool, closedLeadingInset: CGFloat) -> some View {
        UnifiedBars(mode: model.islandClosedMode, size: 24)
            .frame(width: 24, height: 24)
            .padding(.leading, opened && travelsGlyphOnOpen ? Self.openedGlyphLeadingInset : closedLeadingInset)
            .padding(.top, max(0, (closedNotchHeight - 24) / 2))
            .opacity(opened && !travelsGlyphOnOpen ? 0 : 1)
            .allowsHitTesting(false)
    }

    /// Single entry point choosing between the true morph and its Reduce
    /// Motion fallback, plus the completion "pop" bump (AB-243) — applied
    /// here, once, so it looks identical whichever path is active. Under
    /// Reduce Motion the scale bump becomes a brief opacity dip instead, in
    /// keeping with the ticket's "simple fade" guidance for reduced motion.
    @ViewBuilder
    private func islandSurfaceBody(openedWidth: CGFloat, openedHeight: CGFloat) -> some View {
        Group {
            if reduceMotion {
                legacyCrossfadeSurface(openedWidth: openedWidth, openedHeight: openedHeight)
            } else {
                morphingIslandSurface(openedWidth: openedWidth, openedHeight: openedHeight)
            }
        }
        .scaleEffect(reduceMotion ? 1 : (isPopping ? 1.04 : 1), anchor: .top)
        .opacity(reduceMotion && isPopping ? 0.7 : 1)
        .animation(reduceMotion ? .easeInOut(duration: 0.18) : tokens.motion.popAnimation.animation, value: isPopping)
    }

    /// Pre-AB-243 behavior, kept verbatim as the Reduce Motion fallback: an
    /// opacity crossfade between the two independent, unrelated shapes
    /// (`V6ClosedPillShape` and `OpenedIslandSurfaceShape`) rather than one
    /// surface morphing between them.
    @ViewBuilder
    private func legacyCrossfadeSurface(openedWidth: CGFloat, openedHeight: CGFloat) -> some View {
        ZStack(alignment: .top) {
            if shouldRenderOpenedSurface {
                openedSurface(width: openedWidth, height: openedHeight)
                    .opacity(usesOpenedVisualState ? 1 : 0)
                    .allowsHitTesting(usesOpenedVisualState)
            }

            v6ClosedSurface()
                // AB-320: mirrors the morph path's closed-state shadow so a
                // theme that declares a closed glow keeps it under Reduce
                // Motion. Applied only when the theme opts in, so the Classic
                // (and every other shipped theme's) render tree is untouched.
                .modifier(OptionalShadow(token: tokens.metrics.closedSurfaceShadow))
                .opacity(usesOpenedVisualState ? 0 : 1)
                .allowsHitTesting(!usesOpenedVisualState)
        }
    }

    /// The true morph (AB-243): a single `OpenedIslandSurfaceShape` instance
    /// whose `topCornerRadius`/`bottomCornerRadius` and this container's own
    /// frame width/height are the *only* source of transition progress — all
    /// fed straight from `usesOpenedVisualState` (in turn just
    /// `model.notchStatus`), with no separate `@State` progress value. The
    /// single `notchTransitionAnimation` on `notchContent` interpolates
    /// shape, frame, and content opacity together, so the spring is free to
    /// retarget mid-flight like any other SwiftUI-animated value —
    /// interrupting a hover-open with a quick exit just reverses whatever
    /// point the shared shape/frame had already reached, instead of jumping.
    ///
    /// At rest this reproduces today's exact pixel output: `NotchShape`'s
    /// concave top curve degenerates to a flat edge at `topCornerRadius ==
    /// 0` (the closed pill's flat top), and its quadratic bottom-corner
    /// curve deviates from `V6ClosedPillShape`'s true arc by well under a
    /// point at these radii — imperceptible, and only ever in play
    /// mid-transition anyway. Content (labels / session list) crossfades via
    /// opacity *inside* the one continuously-growing shape — never two
    /// independently shaped surfaces stacked and cross-dissolving past each
    /// other — so there's no double-image at any point mid-gesture.
    @ViewBuilder
    private func morphingIslandSurface(openedWidth: CGFloat, openedHeight: CGFloat) -> some View {
        let layout: V6ClosedLayout = isExternalDisplayPlacement ? .external : .macbook
        let physicalNotchWidth: CGFloat = targetOverlayScreen?.notchSize.width ?? 180
        let label = model.islandClosedLabel()
        let rightSlot = model.islandClosedRightSlotContent()

        let closedWidth = layout == .macbook
            ? V6ClosedPill.macbookOuterWidth(
                label: label,
                physicalNotchWidth: physicalNotchWidth,
                height: closedNotchHeight
            )
            : V6ClosedPill.externalOuterWidth(
                label: label,
                rightSlot: rightSlot,
                minWidth: 70,
                height: closedNotchHeight
            )

        let topProfile: OpenedIslandSurfaceShape.TopProfile = usesNotchAwareOpenedHeader ? .notch : .topBar
        let opened = usesOpenedVisualState

        let surfaceWidth = opened ? openedWidth : closedWidth
        let surfaceHeight = opened ? openedHeight : closedNotchHeight
        let shape = OpenedIslandSurfaceShape(
            topProfile: topProfile,
            topCornerRadius: opened ? tokens.metrics.openedTopRadius : 0,
            bottomCornerRadius: opened ? tokens.metrics.openedBottomRadius : (closedNotchHeight / 2),
            filletRadius: tokens.metrics.filletRadius
        )
        // AB-320: the closed end of the morph is no longer hard-zeroed. It
        // interpolates towards whatever the theme declares for the closed state
        // (`closedSurfaceShadow`), which defaults to an inert same-hue shadow —
        // byte-identical to the old `opacity/radius/y = 0` behaviour for every
        // shipped theme, but the seam a colour-glow theme opts into.
        let shadow = opened ? tokens.metrics.surfaceShadow : tokens.metrics.resolvedClosedSurfaceShadow
        let closedLeadingInset = closedNotchHeight / 2

        ZStack(alignment: .top) {
            // One clip shape drives the whole transition. The fill
            // crossfades between the closed pill's flat ink and the opened
            // surface's vibrancy, but the silhouette — the thing that
            // actually reads as "growing" — never doubles up, because
            // there's only ever one shape instance underneath.
            ZStack {
                OpenedSurfaceBackground(reduceTransparency: reduceTransparency || !theme.usesVibrancy)
                    .opacity(opened ? 1 : 0)
                tokens.colors.surfaceInk
                    .opacity(opened ? 0 : 1)
            }
            .frame(width: surfaceWidth, height: surfaceHeight)
            .clipShape(shape)
            .shadow(color: shadow.resolvedColor, radius: shadow.radius, y: shadow.yOffset)
            .animation(.easeInOut(duration: 0.2), value: reduceTransparency)

            ZStack(alignment: .top) {
                // `showsGlyph: false` — the glyph is rendered once, below,
                // as its own overlay so it can travel instead of fading.
                v6ClosedSurface(showsGlyph: false)
                    .opacity(opened ? 0 : 1)
                    .allowsHitTesting(!opened)

                if shouldRenderOpenedSurface {
                    openedSurfaceContent(width: openedWidth, height: openedHeight)
                        .opacity(opened ? 1 : 0)
                        .allowsHitTesting(opened)
                }
            }
            .frame(width: surfaceWidth, height: surfaceHeight, alignment: .top)
            .clipShape(shape)
            .overlay {
                shape.stroke(Color.white.opacity(opened ? 0.07 : 0), lineWidth: 1)
            }
        }
        .frame(width: surfaceWidth, height: surfaceHeight, alignment: .top)
        .overlay(alignment: .topLeading) {
            islandGlyphOverlay(opened: opened, closedLeadingInset: closedLeadingInset)
        }
    }

    // MARK: - Closed state

    private var closedNotchWidth: CGFloat {
        (targetOverlayScreen ?? NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 }))?.notchSize.width ?? NSScreen.externalDisplayNotchWidth
    }

    private var closedNotchHeight: CGFloat {
        (targetOverlayScreen ?? NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 }))?.islandClosedHeight ?? 24
    }

    /// AB-298: the header row is now the `IslandHeaderControls` slot component.
    /// The usage providers and layout inputs are computed here (where `model`
    /// lives) and passed in by value; the three buttons emit through closures,
    /// with quit still routed to this view's `showingQuitConfirmation` state.
    private var openedHeaderContent: some View {
        theme.openedHeader(
            providers: openedUsageProviders,
            usesNotchAwareLayout: usesNotchAwareOpenedHeader,
            targetScreen: targetOverlayScreen,
            isSoundMuted: model.isSoundMuted,
            lang: lang,
            onToggleMute: { model.toggleSoundMuted() },
            onShowSettings: { model.showSettings() },
            onQuit: { showingQuitConfirmation = true }
        )
    }

    private var openedContent: some View {
        VStack(spacing: 8) {
            if !model.hasAnyInstalledAgent {
                theme.installHint(lang: lang, onTap: { model.showOnboarding() })
                    .padding(.horizontal, 18)
                    .padding(.top, 8)
            }

            if model.shouldShowSessionBootstrapPlaceholder {
                theme.bootstrapPlaceholder(lang: lang)
                    .padding(.horizontal, 18)
                    .padding(.top, 8)
            } else if model.islandListSessions.isEmpty {
                theme.emptyState(lang: lang, hasRecentSessions: !model.recentSessions.isEmpty)
                    .padding(.horizontal, 18)
                    .padding(.top, 8)
            } else {
                sessionList
            }
        }
        .padding(.bottom, 0)
        // AB-228: measure the real, rendered height of the opened surface
        // (hint banner + list/placeholder/empty state, all included) and
        // feed it to `OverlayPanelController` via `AppModel`, replacing the
        // old hand-estimated per-phase heights. Notification mode publishes
        // its own narrower measurement inside `sessionList` instead (a
        // single actionable card, not the full list chrome), so this is
        // skipped there to avoid two measurements fighting each other.
        .background(
            GeometryReader { geo in
                Color.clear.preference(key: OpenedContentHeightKey.self, value: geo.size.height)
            }
        )
        .onPreferenceChange(OpenedContentHeightKey.self) { height in
            guard height > 0, !isNotificationMode else { return }
            model.measuredOpenedContentHeight = height
        }
    }

    private var actionableSessionID: String? {
        model.islandSurface.sessionID
    }

    /// Whether the panel was opened by a notification (show only actionable session + footer).
    private var isNotificationMode: Bool {
        model.notchOpenReason == .notification && actionableSessionID != nil
    }

    private var sessionListSideInset: CGFloat {
        usesNotchAwareOpenedHeader ? 46 : 16
    }

    /// AB-298: per-row action surface for the notification card. Built here,
    /// where `model` lives, and handed to `IslandNotificationCard` via its
    /// `makeActions` closure. No `dismiss` — the notification card isn't
    /// dismissible.
    private func notificationRowActions(for session: AgentSession) -> RowActions {
        RowActions(
            approve: { model.approvePermission(for: session.id, action: $0) },
            answer: { model.answerQuestion(for: session.id, answer: $0) },
            reply: TerminalTextSender.canReply(to: session, enabled: model.completionReplyEnabled)
                ? { model.replyToSession(session, text: $0) } : nil,
            jump: { model.jumpToSession(session) }
        )
    }

    /// AB-298: per-row action surface for the session list. Same as the
    /// notification card's, plus `dismiss` — available on every list row.
    private func listRowActions(for session: AgentSession) -> RowActions {
        RowActions(
            approve: { model.approvePermission(for: session.id, action: $0) },
            answer: { model.answerQuestion(for: session.id, answer: $0) },
            reply: TerminalTextSender.canReply(to: session, enabled: model.completionReplyEnabled)
                ? { model.replyToSession(session, text: $0) } : nil,
            jump: { model.jumpToSession(session) },
            // AB-237: dismiss is available on every session row (previously
            // gated to `isRemote` even though `dismissSession` already works
            // for any session id — see `SessionState.dismissSession` /
            // `isDismissedByUser` for the undo-safe suppress-not-tombstone
            // semantics).
            dismiss: { model.dismissSession(session.id) }
        )
    }

    /// AB-298: routes to the extracted `IslandNotificationCard` (single
    /// actionable session, opened by a notification) or the extracted
    /// `IslandSessionListScaffold` (the full grouped list). Every model read
    /// is resolved here and handed in by value; each surface builds its rows
    /// from the `makeActions` closures above.
    private var sessionList: some View {
        Group {
            if isNotificationMode {
                theme.notificationCard(
                    session: model.activeIslandCardSession,
                    isInteractive: model.notchStatus == .opened,
                    stateIndicator: model.islandSessionStateIndicator,
                    completedStaleThreshold: model.completedStaleThreshold.seconds,
                    sideInset: sessionListSideInset,
                    totalSessionCount: model.allSessions.count,
                    lang: lang,
                    keyboardCoordinator: model.overlay,
                    pulseClock: model.pulseClock,
                    makeActions: { notificationRowActions(for: $0) },
                    onShowAll: { session in
                        let isCompletion = session.phase == .completed
                        model.expandNotificationToSessionList(clearExpansion: isCompletion)
                    },
                    onPointerInside: { model.notePointerInsideIslandSurface() },
                    onPointerExited: { model.handlePointerExitedIslandSurface() },
                    onMeasuredHeight: { model.measuredNotificationContentHeight = $0 }
                )
            } else {
                theme.sessionList(
                    sessions: model.islandListSessions,
                    sections: model.islandSessionSections,
                    group: model.islandSessionGroup,
                    stateIndicator: model.islandSessionStateIndicator,
                    completedStaleThreshold: model.completedStaleThreshold.seconds,
                    sideInset: sessionListSideInset,
                    isInteractive: model.notchStatus == .opened,
                    actionableSessionID: actionableSessionID,
                    lang: lang,
                    keyboardCoordinator: model.overlay,
                    pulseClock: model.pulseClock,
                    makeActions: { listRowActions(for: $0) }
                )
            }
        }
    }

    // MARK: - Helpers

    /// AB-322: the derivation moved to `AppModel.islandUsageProviders` so the
    /// closed pill's usage badge and these header chips read the same windows.
    private var openedUsageProviders: [UsageProviderPresentation] {
        model.islandUsageProviders
    }

}

// MARK: - Session row (opened state)

/// The animated-dot visual, shared by the static (`pulse: 0`) case in
/// `IslandSessionRow.statusIndicator(for:)` and by `PulsingStatusDot` below.
/// Kept as a free function (rather than a method on `IslandSessionRow`) so
/// both callers — a distinct `View` type for the pulsing case — can use it.
private func islandStatusDotView(tint: Color, presence: IslandSessionPresence, pulse: Double) -> some View {
    Circle()
        .fill(tint)
        .frame(width: 9, height: 9)
        .scaleEffect(1 + (pulse * 0.18))
        .shadow(color: tint.opacity(presence == .inactive ? 0 : 0.36 + (pulse * 0.26)), radius: 4 + (pulse * 3))
        .padding(.top, 6)
}

/// Leaf view for the animated status dot (AB-228). Reading `pulseClock.phase`
/// here — inside its own `View` type, distinct from `IslandSessionRow` — means
/// Observation's per-view access tracking invalidates only this small dot at
/// 15fps, not the row (markdown, buttons, todos, ...) it sits inside or the
/// session list around it. `acquire`/`release` ref-count the shared clock's
/// underlying timer so it only runs while at least one dot is visible.
private struct PulsingStatusDot: View {
    let pulseClock: PulseClock
    let tint: Color
    let presence: IslandSessionPresence

    /// AB-244: under Reduce Motion this never acquires the shared clock at
    /// all, so the 15fps timer doesn't even run for this dot — the static
    /// (`pulse: 0`) rendering already used for non-pulsing rows.
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if reduceMotion {
            islandStatusDotView(tint: tint, presence: presence, pulse: 0)
        } else {
            islandStatusDotView(tint: tint, presence: presence, pulse: pulseClock.phase)
                .onAppear { pulseClock.acquire() }
                .onDisappear { pulseClock.release() }
        }
    }
}

/// AB-298: internal (not `private`) so the extracted `IslandNotificationCard`
/// and `IslandSessionListScaffold` slot components can render session rows.
struct IslandSessionRow: View {
    let session: AgentSession
    var stateIndicator: IslandSessionStateIndicator = .animatedDot
    var completedStaleThreshold: TimeInterval = AgentSession.staleCompletedDisplayThreshold
    var isActionable: Bool = false
    var useDrawingGroup: Bool = true
    var isInteractive: Bool = true
    /// Hover highlight, owned by the enclosing `SessionRowContainer` (AB-297).
    let isHighlighted: Bool
    var presentation: IslandSessionRowPresentation = .list
    var sideInset: CGFloat = 16
    var lang: LanguageManager = .shared
    let actions: RowActions
    /// Lets the visible question card register its option-selection state
    /// with `OverlayPanelController`'s keyboard shortcut handler (AB-227).
    var keyboardCoordinator: OverlayUICoordinator?
    /// Shared 15fps clock for the animated status dot (AB-228). Passed
    /// through to `PulsingStatusDot`; rows that don't animate never touch it.
    var pulseClock: PulseClock?

    @State private var detailOverride: Bool?
    @State private var replyText: String = ""

    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    private var increasesContrast: Bool { colorSchemeContrast == .increased }

    /// AB-296: every status tint, paper tone and text/hairline opacity below
    /// resolves from here. One read on the row covers all of its `private
    /// func`/`private var` builders; the separate types it composes
    /// (`PermissionDiffPreview`, `StructuredQuestionPromptView`, and the
    /// `IslandActionButtonStyle` its buttons use) declare their own.
    @Environment(\.islandTokens) private var tokens

    /// AB-299: gates the `ConditionalDrawingGroup` rasterization in `rowBody`.
    /// Only themes that declare `rowIsDrawingGroupSafe` (Classic does) get the
    /// off-screen render; a blur/glow theme it would flatten opts out.
    @Environment(\.islandTheme) private var theme

    /// AB-244: coarse type ramp for this row's core reading content
    /// (headline, prompt/activity lines, badges, age). `@ScaledMetric`
    /// tracks the system Dynamic Type / "Larger Text" setting; every literal
    /// point size below is expressed relative to this one reference value
    /// via `scaledFont(_:weight:design:)` rather than re-declaring a
    /// `ScaledMetric` per size, so the whole row scales together off one
    /// measurement. Deliberately NOT applied to the closed-pill/notch glyph
    /// fonts (`V6CenterLabelView`, `V6NotchLaneLabelView`, `UnifiedBars`) —
    /// those sizes are baked into hard-coded intrinsic-width math against
    /// the physical notch cutout, so scaling them would desync the layout
    /// from the actual hardware notch; nor to compact side-badges (SSH,
    /// PLAN, model name) which are already redundantly conveyed by this
    /// row's grouped VoiceOver summary and would be the first thing to
    /// overflow the fixed-width row at larger sizes.
    @ScaledMetric(relativeTo: .body) private var typeScaleReference: CGFloat = 13

    private var typeScale: CGFloat {
        typeScaleReference / 13
    }

    private func scaledFont(_ size: CGFloat, weight: Font.Weight = .regular, design: Font.Design = .default) -> Font {
        .system(size: size * typeScale, weight: weight, design: design)
    }

    /// Age badges and staleness (`islandPresence`/`isStaleCompletedForIsland`)
    /// are time-driven and were previously refreshed by a single
    /// `TimelineView` wrapping the ENTIRE session list, forcing a full
    /// list/header rebuild every 30s just to keep a few relative-time
    /// strings current. Each row now owns that refresh itself (AB-228), so
    /// a tick only invalidates this one row, not its siblings or the header.
    private static let ageRefreshInterval: TimeInterval = 30

    var body: some View {
        TimelineView(.periodic(from: .now, by: Self.ageRefreshInterval)) { context in
            rowBody(referenceDate: context.date)
        }
    }

    private func rowBody(referenceDate: Date) -> some View {
        let rawPresence = session.islandPresence(at: referenceDate)
        let isStaleCompleted = session.isStaleCompletedForIsland(
            at: referenceDate,
            threshold: completedStaleThreshold
        )
        let defaultShowsDetail = !isStaleCompleted && (rawPresence != .inactive || isActionable)
        let showsDetail = detailOverride ?? defaultShowsDetail
        let presence = isStaleCompleted
            ? .inactive
            : ((showsDetail && rawPresence == .inactive) ? .active : rawPresence)
        return VStack(alignment: .leading, spacing: 0) {
            rowSummary(presence: presence, showsDetail: showsDetail, referenceDate: referenceDate)

            if showsDetail {
                rowAuxiliaryDetails(presence: presence)

                if shouldShowEmbeddedDetailBody {
                    embeddedDetailBody
                        .padding(.leading, detailLeadingInset)
                        .padding(.trailing, sideInset)
                        .padding(.bottom, 13)
                }
            }
        }
        .background(rowFillColor(for: presence))
        .overlay(alignment: .top) {
            Rectangle()
                .fill(.white.opacity(tokens.colors.hairline(increaseContrast: increasesContrast)))
                .frame(height: 1)
        }
        .overlay(alignment: .leading) {
            if showsLeadingStatusBar {
                RoundedRectangle(cornerRadius: 999, style: .continuous)
                    .fill(statusTint(for: presence))
                    .frame(width: 3)
                    .padding(.vertical, showsDetail ? 10 : 8)
                    .padding(.leading, 14)
            }
        }
        .opacity(isStaleCompleted ? 0.7 : 1)
        .modifier(ConditionalDrawingGroup(enabled: useDrawingGroup && !isActionable && theme.rowIsDrawingGroupSafe))
        .contentShape(Rectangle())
        .animation(.easeInOut(duration: 0.15), value: isHighlighted)
        // AB-242: status tint (dot fill, leading bar, tinted row background,
        // title color) used to snap the instant a session's phase/outcome/
        // presence changed. These three cover the tint-driving inputs
        // (`statusTint(for:)` / `tokens.colors.statusTint`) so a
        // running → waiting → completed transition crossfades instead.
        .animation(.easeInOut(duration: 0.2), value: session.phase)
        .animation(.easeInOut(duration: 0.2), value: session.outcome)
        .animation(.easeInOut(duration: 0.2), value: presence)
        .onTapGesture(perform: handlePrimaryTap)
        .onChange(of: isInteractive) { _, interactive in
            if !interactive {
                detailOverride = nil
            }
        }
    }

    private func rowSummary(presence: IslandSessionPresence, showsDetail: Bool, referenceDate: Date) -> some View {
        HStack(alignment: .top, spacing: 10) {
            if showsLeadingStatusIndicator {
                statusIndicator(for: presence)
                    .frame(width: 20, alignment: .top)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(summaryHeadlineText)
                    .font(scaledFont(summaryTitleFontSize, weight: .semibold))
                    .foregroundStyle(titleColor(for: presence))
                    .lineLimit(1)
                    .truncationMode(.tail)

                if showsDetail,
                   let promptLine = summaryPromptLineText {
                    Text(promptLine)
                        .font(scaledFont(11.2, weight: .medium))
                        .foregroundStyle(summaryPromptColor(for: presence))
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }

            Spacer(minLength: 10)

            HStack(spacing: IslandSessionRowMetrics.badgeSpacing) {
                agentBadge
                if let modelBadge = session.displayModelName {
                    sideBadge(modelBadge)
                }
                if let permissionChip = permissionModeBadgeKind {
                    permissionModeChip(permissionChip)
                }
                if session.isRemote {
                    sideBadge("SSH")
                }
                if let terminalBadge = session.spotlightTerminalBadge {
                    sideBadge(terminalBadge)
                }
                Text(ageBadgeText(at: referenceDate))
                    .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                    .foregroundStyle(summaryAgeColor(for: presence))
                    .frame(minWidth: IslandSessionRowMetrics.ageColumnWidth, alignment: .trailing)
                detailToggleButton(isOpen: showsDetail)
                if let dismiss = actions.dismiss {
                    DismissButton(action: dismiss, lang: lang)
                }
            }
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
        }
        .padding(.leading, rowLeadingInset)
        .padding(.trailing, sideInset)
        .padding(.top, 11)
        .padding(.bottom, showsDetail ? 8 : 11)
        // AB-244: the status dot/bar/glyph, headline, prompt line, and
        // badges above are individually undescribed (a bare colored shape,
        // several adjacent `Text`s) — combined here into the one grouped
        // summary VoiceOver reads for the whole row ("Claude Code,
        // open-vibe-island, waiting for permission, 3 minutes ago").
        // `detailToggleButton`/`DismissButton` are real `Button`s nested
        // inside this same subtree, so `.ignore` hides their *own*
        // accessibility elements — recreated below as named actions
        // (VoiceOver's rotor) so both stay reachable/activatable without
        // splitting the row into a dozen swipe stops. Approve/deny/answer/
        // jump-in-terminal controls live in the sibling
        // `rowAuxiliaryDetails`/`embeddedDetailBody` views, outside this
        // `.ignore`d subtree, so they're unaffected and stay independently
        // reachable.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityRowSummaryText(referenceDate: referenceDate))
        .accessibilityAddTraits(isInteractive ? .isButton : [])
        .accessibilityAction {
            guard isInteractive else { return }
            actions.jump()
        }
        .accessibilityAction(named: Text(lang.t(showsDetail ? "a11y.session.collapseDetail" : "a11y.session.expandDetail"))) {
            toggleDetail(currentlyOpen: showsDetail)
        }
        .modifier(OptionalNamedAccessibilityAction(name: actions.dismiss != nil ? lang.t("a11y.session.dismiss") : nil, action: { actions.dismiss?() }))
    }

    // MARK: - Accessibility (AB-244)

    /// The one grouped VoiceOver summary for this row — agent, workspace,
    /// phase, and elapsed time — e.g. "Claude Code, open-vibe-island,
    /// waiting for permission, 3 minutes ago". Doubles as the "text
    /// equivalent of the color" the status dot/bar/glyph otherwise conveys
    /// only visually: `accessibilityPhaseText` spells out exactly what the
    /// status tint means.
    private func accessibilityRowSummaryText(referenceDate: Date) -> String {
        lang.t(
            "a11y.session.summary",
            session.tool.displayName,
            session.spotlightWorkspaceName,
            accessibilityPhaseText,
            accessibilityElapsedText(at: referenceDate)
        )
    }

    private var accessibilityPhaseText: String {
        switch session.phase {
        case .running:
            lang.t("a11y.phase.running")
        case .waitingForApproval:
            lang.t("a11y.phase.waitingForApproval")
        case .waitingForAnswer:
            lang.t("a11y.phase.waitingForAnswer")
        case .completed:
            switch session.outcome {
            case .success: lang.t("a11y.phase.completed")
            case .interrupted: lang.t("a11y.phase.interrupted")
            case .failed: lang.t("a11y.phase.failed")
            }
        }
    }

    /// Relative time reads naturally in whichever language the app is
    /// currently displaying — `RelativeDateTimeFormatter` is locale-driven,
    /// so it's pointed at `lang`'s resolved code rather than the system
    /// locale, which may differ from the in-app language toggle.
    private func accessibilityElapsedText(at referenceDate: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale(identifier: lang.language.resolvedCode)
        formatter.unitsStyle = .full
        let reference = session.phase == .running ? session.firstSeenAt : session.islandActivityDate
        return formatter.localizedString(for: reference, relativeTo: referenceDate)
    }

    @ViewBuilder
    private func rowAuxiliaryDetails(presence: IslandSessionPresence) -> some View {
        if !shouldShowEmbeddedDetailBody,
           let activityLine = session.spotlightActivityLineText ?? expandedActivityLineText {
            Text(activityLine)
                .font(scaledFont(11, weight: .medium))
                .foregroundStyle(activityColor(for: presence).opacity(0.94))
                .lineLimit(2)
                .padding(.leading, detailLeadingInset)
                .padding(.trailing, sideInset)
                .padding(.bottom, 10)
        }

        if let subagents = session.claudeMetadata?.activeSubagents,
           !subagents.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 5) {
                    Image(systemName: "arrow.triangle.branch")
                        .font(.system(size: 9, weight: .medium))
                        .accessibilityHidden(true)
                    Text(lang.t("subagents.title", subagents.count))
                        .font(.system(size: 10.5, weight: .medium))
                }
                .foregroundStyle(.cyan.opacity(0.8))

                ForEach(subagents, id: \.agentID) { sub in
                    HStack(spacing: 6) {
                        Circle()
                            .fill(sub.summary != nil
                                ? tokens.colors.statusCompleted
                                : tokens.colors.statusRunning)
                            .frame(width: 6, height: 6)
                            .accessibilityLabel(lang.t(sub.summary != nil ? "subagents.completed" : "a11y.subagent.running"))
                        Text(sub.agentType ?? sub.agentID)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.white.opacity(0.8))
                            .lineLimit(1)
                        if let desc = sub.taskDescription {
                            Text("(\(desc))")
                                .font(.system(size: 10.5))
                                .foregroundStyle(.white.opacity(0.5))
                                .lineLimit(1)
                        }
                        Spacer(minLength: 0)
                        if sub.summary != nil {
                            Text(lang.t("subagents.completed"))
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(.white.opacity(0.4))
                        } else if let started = sub.startedAt {
                            TimelineView(.periodic(from: .now, by: 1)) { timeline in
                                Text(subagentElapsed(since: started, at: timeline.date))
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundStyle(.white.opacity(0.4))
                            }
                        }
                    }
                    // AB-244: status dot + name + description + trailing
                    // elapsed/"Completed" all read as one row instead of
                    // four separate stops.
                    .accessibilityElement(children: .combine)
                }
            }
            .padding(.leading, detailLeadingInset)
            .padding(.trailing, sideInset)
            .padding(.bottom, 10)
        }

        if let tasks = session.claudeMetadata?.activeTasks,
           !tasks.isEmpty {
            VStack(alignment: .leading, spacing: 3) {
                Text(taskSummary(tasks))
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(.white.opacity(0.45))
                ForEach(tasks) { task in
                    HStack(spacing: 5) {
                        taskStatusIcon(task.status)
                        Text(task.title)
                            .font(.system(size: 10.5, weight: .medium))
                            .foregroundStyle(task.status == .completed
                                ? .white.opacity(0.4)
                                : .white.opacity(0.7))
                            .strikethrough(task.status == .completed)
                            .lineLimit(1)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
            .padding(.leading, detailLeadingInset)
            .padding(.trailing, sideInset)
            .padding(.bottom, 10)
        }

        // AB-237: `trackingTranscriptPath` used to be tracked but never
        // rendered anywhere — no click-to-open affordance existed. Shown
        // only when a transcript path is actually known.
        if let transcriptPath = session.trackingTranscriptPath?.trimmingCharacters(in: .whitespacesAndNewlines),
           !transcriptPath.isEmpty {
            TranscriptAffordance(
                path: transcriptPath,
                workspace: session.spotlightWorkspaceName,
                lang: lang
            )
            .padding(.leading, detailLeadingInset)
            .padding(.trailing, sideInset)
            .padding(.bottom, 10)
        }
    }

    private var agentBadge: some View {
        let tint = Color(hex: session.tool.brandColorHex) ?? tokens.colors.paper
        return Text(agentBadgeTitle)
            .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
            .foregroundStyle(tint.opacity(notificationChromeOpacity))
            .frame(minWidth: IslandSessionRowMetrics.agentTitleWidth)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(tint.opacity(notificationBadgeFillOpacity), in: Capsule())
            .overlay(Capsule().stroke(tint.opacity(notificationBadgeStrokeOpacity), lineWidth: 1))
    }

    private func sideBadge(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 10.5, weight: .medium, design: .monospaced))
            .foregroundStyle(tokens.colors.paper.opacity(presentation == .notification ? 0.52 : 0.7))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(.white.opacity(presentation == .notification ? 0.045 : 0.06), in: Capsule())
    }

    /// `plan` gets the same neutral treatment as `sideBadge`; `bypass` gets a
    /// warning tint since a bypass-permissions session behaves very
    /// differently from the default (AB-230).
    private enum PermissionModeBadgeKind {
        case plan
        case bypass
    }

    private var permissionModeBadgeKind: PermissionModeBadgeKind? {
        switch session.claudeMetadata?.permissionMode {
        case .plan:
            .plan
        case .bypassPermissions:
            .bypass
        default:
            nil
        }
    }

    @ViewBuilder
    private func permissionModeChip(_ kind: PermissionModeBadgeKind) -> some View {
        switch kind {
        case .plan:
            sideBadge(lang.t("badge.planMode"))
        case .bypass:
            Text(lang.t("badge.bypassPermissions"))
                .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                .foregroundStyle(tokens.colors.statusWarning.opacity(0.94))
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(tokens.colors.statusWarning.opacity(0.16), in: Capsule())
                .overlay(Capsule().stroke(tokens.colors.statusWarning.opacity(0.4), lineWidth: 1))
        }
    }

    /// The trailing badge shows time-since-last-update for most sessions, but
    /// that's nearly always "<1m" for a running session and doesn't answer
    /// the question that actually matters: how long has it been running?
    /// For running sessions, show elapsed time since `firstSeenAt` instead.
    /// Reuses the row's existing 30s tick (`referenceDate`, from AB-228)
    /// rather than a new per-row high-frequency timer.
    private func ageBadgeText(at referenceDate: Date) -> String {
        if session.phase == .running {
            return session.elapsedRunningLabel(at: referenceDate)
        }
        return session.spotlightAgeBadge
    }

    private var summaryPromptLineText: String? {
        if presentation == .notification {
            if session.phase == .completed {
                return notificationCompletedPromptLineText
            }
            return session.notificationHeaderPromptLineText
        }

        return session.spotlightPromptLineText ?? expandedPromptLineText
    }

    private var summaryHeadlineText: String {
        if presentation == .notification, session.phase == .completed {
            return notificationWorkspaceHeadlineText
        }

        return session.spotlightHeadlineText
    }

    private var notificationWorkspaceHeadlineText: String {
        let workspace = session.spotlightWorkspaceName.trimmedForNotificationCard
        let title = workspace.isEmpty ? session.tool.displayName : workspace
        guard let branch = session.spotlightWorktreeBranch?.trimmedForNotificationCard,
              !branch.isEmpty else {
            return title
        }

        return "\(title) (\(branch))"
    }

    private var notificationCompletedPromptLineText: String? {
        if let prompt = session.latestUserPromptText?.trimmedForNotificationCard, !prompt.isEmpty {
            return "You: \(prompt)"
        }

        if let prompt = session.initialUserPromptText?.trimmedForNotificationCard, !prompt.isEmpty {
            return "You: \(prompt)"
        }

        return nil
    }

    private var agentBadgeTitle: String {
        switch session.tool {
        case .claudeCode:
            "claude"
        case .geminiCLI:
            "gemini"
        case .qwenCode:
            "qwen"
        case .kimiCLI:
            "kimi"
        default:
            session.tool.shortName.lowercased()
        }
    }

    private var rowLeadingInset: CGFloat {
        if presentation == .notification {
            return sideInset
        }

        return switch stateIndicator {
        case .bar:
            max(28, sideInset)
        case .tint:
            sideInset
        case .animatedDot, .glyph:
            sideInset
        }
    }

    private var detailLeadingInset: CGFloat {
        if presentation == .notification {
            return sideInset
        }

        return switch stateIndicator {
        case .bar:
            max(28, sideInset)
        case .tint:
            sideInset
        case .animatedDot, .glyph:
            sideInset + 30
        }
    }

    private var showsLeadingStatusIndicator: Bool {
        presentation == .list && stateIndicator != .tint && stateIndicator != .bar
    }

    private var showsLeadingStatusBar: Bool {
        presentation == .list && stateIndicator == .bar
    }

    private var summaryTitleFontSize: CGFloat {
        presentation == .notification ? 13.2 : (isActionable ? 13.8 : 13.2)
    }

    private func summaryPromptColor(for presence: IslandSessionPresence) -> Color {
        if presentation == .notification {
            return tokens.colors.paper.opacity(contrastText(session.phase == .completed ? tokens.colors.tertiaryTextOpacity : tokens.colors.secondaryTextOpacity))
        }

        return tokens.colors.paper.opacity(contrastText(presence == .inactive ? tokens.colors.tertiaryTextOpacity : tokens.colors.secondaryTextOpacity))
    }

    private func summaryAgeColor(for presence: IslandSessionPresence) -> Color {
        if presentation == .notification {
            return tokens.colors.paper.opacity(contrastText(tokens.colors.tertiaryTextOpacity))
        }

        return tokens.colors.paper.opacity(contrastText(presence == .inactive ? tokens.colors.tertiaryTextOpacity : tokens.colors.secondaryTextOpacity))
    }

    private func contrastText(_ base: Double) -> Double {
        tokens.colors.text(base, increaseContrast: increasesContrast)
    }

    private var notificationChromeOpacity: Double {
        presentation == .notification ? 0.82 : 1
    }

    private var notificationBadgeFillOpacity: Double {
        presentation == .notification ? 0.08 : 0.13
    }

    private var notificationBadgeStrokeOpacity: Double {
        presentation == .notification ? 0.24 : 0.35
    }

    private func titleColor(for presence: IslandSessionPresence) -> Color {
        if stateIndicator == .tint && presence != .inactive {
            return statusTint(for: presence)
        }

        if presentation == .notification, session.phase == .completed {
            return .white.opacity(0.78)
        }

        return headlineColor(for: presence)
    }

    private var actionableBorderColor: Color {
        if isActionable {
            return actionableStatusTint.opacity(isHighlighted ? 0.45 : 0.28)
        }
        return isHighlighted ? .white.opacity(0.24) : .white.opacity(0.04)
    }

    private var actionableStatusTint: Color {
        tokens.colors.statusTint(for: session.phase, outcome: session.outcome)
    }

    @ViewBuilder
    private var actionableBody: some View {
        switch session.phase {
        case .waitingForApproval:
            approvalActionBody
        case .waitingForAnswer:
            questionActionBody
        case .completed:
            completionActionBody
        case .running:
            EmptyView()
        }
    }

    private var shouldShowEmbeddedDetailBody: Bool {
        if session.phase.requiresAttention {
            return true
        }
        if session.phase == .completed {
            return isActionable && completionHasExpandedBody
        }
        return session.phase == .running && runningDetailText != nil
    }

    private var completionHasExpandedBody: Bool {
        // A non-success outcome always earns the expanded card — even with
        // no message body — so an interrupted/failed completion isn't
        // silently indistinguishable from a plain "Completed" row.
        session.outcome != .success
            || !completionMessageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || actions.reply != nil
    }

    @ViewBuilder
    private var embeddedDetailBody: some View {
        switch session.phase {
        case .waitingForApproval, .waitingForAnswer, .completed:
            actionableBody
        case .running:
            runningDetailBody
        }
    }

    private var runningDetailBody: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let runningDetailText {
                Text(runningDetailText)
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.82))
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(Color.white.opacity(0.045))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .strokeBorder(.white.opacity(0.06))
                    )
            }
        }
        .padding(.vertical, 2)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Approval action area

    private var approvalActionBody: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(lang.t("approval.toolPermissionRequested"))
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(tokens.colors.paper.opacity(0.86))

            VStack(alignment: .leading, spacing: 8) {
                Text(commandPreviewText)
                    .font(.system(size: 11.5, weight: .semibold, design: .monospaced))
                    .foregroundStyle(tokens.colors.paper.opacity(0.78))
                    .fixedSize(horizontal: false, vertical: true)

                if let path = session.permissionRequest?.affectedPath.trimmedForNotificationCard,
                   !path.isEmpty {
                    Text(path)
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(tokens.colors.paper.opacity(0.42))
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Color.white.opacity(0.045))
            )

            // AB-235: only rendered for Edit/Write requests whose `tool_input`
            // carried enough to compute a diff (`permissionDiffResult` is nil
            // otherwise) — everyone else sees exactly the card they saw before.
            if let diffResult = permissionDiffResult {
                PermissionDiffPreview(result: diffResult, lang: lang)
            }

            if session.permissionRequest?.requiresTerminalApproval == true {
                terminalApprovalCTA
            } else {
                HStack(spacing: 8) {
                    Button(session.permissionRequest?.secondaryActionTitle ?? lang.t("approval.deny")) { actions.approve?(.deny) }
                        .buttonStyle(IslandActionButtonStyle(kind: .secondary, expands: true))
                        // AB-244: the visible label is often just "No" —
                        // unambiguous on screen next to "Yes", but not out of
                        // context to VoiceOver. Falls back to the same
                        // clarifying text only when the request didn't
                        // supply its own custom title (which stays as-is).
                        .accessibilityLabel(session.permissionRequest?.secondaryActionTitle ?? lang.t("a11y.approval.deny"))
                    Button(session.permissionRequest?.primaryActionTitle ?? lang.t("approval.allowOnce")) { actions.approve?(.allowOnce) }
                        .buttonStyle(IslandActionButtonStyle(kind: .warning, expands: true))
                        .accessibilityLabel(session.permissionRequest?.primaryActionTitle ?? lang.t("a11y.approval.allowOnce"))
                }

                alwaysAllowOptions
            }
        }
    }

    /// AB-235: `suggestedUpdates` carries Claude's actual scoped always-allow
    /// options (session / project / global settings, or a permission-mode
    /// change) with ready-made human `displayLabel`s — rendered as one
    /// stacked button per option so choosing one sends exactly that
    /// `ClaudePermissionUpdate` back over the bridge and the rule is applied
    /// at the scope the user picked. Falls back to the original single
    /// session-scoped "Always allow <tool>" button when the payload carried
    /// no suggestions at all (e.g. non-Claude agents).
    @ViewBuilder
    private var alwaysAllowOptions: some View {
        if let updates = session.permissionRequest?.suggestedUpdates, !updates.isEmpty {
            VStack(spacing: 6) {
                ForEach(Array(updates.enumerated()), id: \.offset) { _, update in
                    Button(update.displayLabel) {
                        actions.approve?(.allowWithUpdates([update]))
                    }
                    .buttonStyle(IslandActionButtonStyle(kind: .primary, expands: true))
                }
            }
        } else if let toolName = session.permissionRequest?.toolName {
            Button(lang.t("approval.alwaysAllow", toolName)) {
                let rule = ClaudePermissionRuleValue(toolName: toolName)
                let update = ClaudePermissionUpdate.addRules(
                    destination: .session,
                    rules: [rule],
                    behavior: .allow
                )
                actions.approve?(.allowWithUpdates([update]))
            }
            .buttonStyle(IslandActionButtonStyle(kind: .primary, expands: true))
        }
    }

    /// AB-235: shown instead of Deny/Allow/Always-allow when
    /// `requiresTerminalApproval` is set on the request — the decision can't
    /// be round-tripped through the bridge (see
    /// `CodexAppServerCoordinator.handleNotification`, the current concrete
    /// case: a Codex.app approval surfaced purely as an app-server status
    /// notification with no matching "submit decision" RPC), so Allow/Deny
    /// here would silently do nothing. `actions.jump` already knows how to reach
    /// wherever the request actually lives (terminal pane or, for Codex.app,
    /// the `codex://threads/<id>` URL scheme) via the same jump mechanism
    /// used everywhere else on this row.
    private var terminalApprovalCTA: some View {
        Button {
            actions.jump()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "arrow.up.forward.app")
                    .font(.system(size: 11, weight: .semibold))
                    .accessibilityHidden(true)
                Text(lang.t("approval.respondInTerminal"))
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(IslandActionButtonStyle(kind: .primary, expands: true))
    }

    /// Computes the diff lazily from the permission request's captured
    /// old/new text (AB-235). `nil` when there's nothing to diff (no
    /// `fileDiffSource`, e.g. non-edit tools) or when old/new text are
    /// identical.
    private var permissionDiffResult: PermissionDiffResult? {
        guard let source = session.permissionRequest?.fileDiffSource else {
            return nil
        }
        let result = PermissionDiff.compute(oldText: source.oldText, newText: source.newText)
        return result.isEmpty ? nil : result
    }

    // MARK: - Question action area

    private var questionActionBody: some View {
        StructuredQuestionPromptView(
            prompt: session.questionPrompt,
            lang: lang,
            keyboardCoordinator: keyboardCoordinator,
            onAnswer: { actions.answer?($0) }
        )
    }

    // MARK: - Completion action area

    private var completionActionBody: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !completionMessageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                if session.outcome != .success {
                    completionOutcomeBanner
                }

                AutoHeightScrollView(maxHeight: 160) {
                    Markdown(completionMessageText)
                        .markdownTheme(.completionCard(tokens.colors))
                        .markdownImageProvider(.noNetwork)
                        .markdownInlineImageProvider(.noNetwork)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                }
            } else {
                completionEmptyState
            }

            if actions.reply != nil {
                Rectangle()
                    .fill(.white.opacity(completionDividerOpacity))
                    .frame(height: 1)

                completionReplyInput
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.white.opacity(completionCardFillOpacity))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(.white.opacity(completionCardStrokeOpacity))
        )
    }

    private var completionDoneOpacity: Double {
        presentation == .notification ? 0.82 : 0.96
    }

    private var completionDividerOpacity: Double {
        presentation == .notification ? 0.035 : 0.04
    }

    private var completionCardFillOpacity: Double {
        presentation == .notification ? 0.035 : 0.045
    }

    private var completionCardStrokeOpacity: Double {
        presentation == .notification ? 0.06 : 0.08
    }

    /// Shown above the completion message body whenever the session didn't
    /// finish cleanly — the message text alone (an error string, or nothing)
    /// isn't a reliable enough signal on its own.
    private var completionOutcomeBanner: some View {
        HStack(spacing: 6) {
            Image(systemName: completionOutcomeGlyphName)
                .font(.system(size: 10.5, weight: .bold))
                .accessibilityHidden(true)
            Text(completionOutcomeLabel)
                .font(.system(size: 11, weight: .bold))
            Spacer(minLength: 0)
        }
        .foregroundStyle(completionOutcomeTint.opacity(completionDoneOpacity))
        .padding(.horizontal, 14)
        .padding(.top, 10)
        .padding(.bottom, 4)
    }

    /// Only ever rendered from `completionOutcomeBanner`, which is gated on
    /// `session.outcome != .success` — "stop" is just the glyph for the
    /// remaining `.interrupted` case.
    private var completionOutcomeGlyphName: String {
        session.outcome == .failed ? "xmark.circle.fill" : "stop.circle.fill"
    }

    private var completionOutcomeTint: Color {
        tokens.colors.statusTint(for: .completed, outcome: session.outcome)
    }

    private var completionOutcomeLabel: String {
        switch session.outcome {
        case .success:
            lang.t("completion.done")
        case .interrupted:
            lang.t("completion.interrupted")
        case .failed:
            lang.t("completion.failed")
        }
    }

    private var completionEmptyState: some View {
        HStack {
            Text(completionOutcomeLabel)
                .font(.system(size: 11.5, weight: .bold))
                .foregroundStyle(completionOutcomeTint.opacity(completionDoneOpacity))

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private var completionReplyInput: some View {
        HStack(spacing: 8) {
            ReplyTextField(
                placeholder: lang.t("completion.replyPlaceholder", session.completionReplyRecipientName),
                text: $replyText,
                onSubmit: { submitReply() }
            )
            .frame(height: 32)

            Button {
                submitReply()
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 24))
                    .foregroundColor(replyText.trimmingCharacters(in: .whitespaces).isEmpty
                        ? .white.opacity(0.2) : .white.opacity(0.9))
            }
            .buttonStyle(.plain)
            .disabled(replyText.trimmingCharacters(in: .whitespaces).isEmpty)
            .accessibilityLabel(lang.t("a11y.completion.sendReply"))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private func submitReply() {
        let text = replyText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        replyText = ""
        actions.reply?(text)
    }

    // MARK: - Actionable helpers

    private var completionMessageText: String {
        if let text = session.completionAssistantMessageText?.trimmedForNotificationCard, !text.isEmpty {
            return text
        }
        let summary = session.summary.trimmedForNotificationCard
        return summary == SessionPhase.completed.displayName ? "" : summary
    }

    private var commandLabel: String {
        switch session.currentToolName {
        case "exec_command", "Bash": return "Bash"
        case "AskUserQuestion": return "Question"
        case "ExitPlanMode": return "Plan"
        case "apply_patch": return "Patch"
        case "write_stdin": return "Input"
        case let value?: return AgentSession.currentToolDisplayName(for: value)
        case nil: return "Command"
        }
    }

    private var commandPreviewText: String {
        let preview = session.currentCommandPreviewText?.trimmedForNotificationCard
        if let preview, !preview.isEmpty {
            return "$ \(preview)"
        }
        return session.permissionRequest?.summary.trimmedForNotificationCard ?? session.summary.trimmedForNotificationCard
    }

    private var runningDetailText: String? {
        if let preview = session.currentCommandPreviewText?.trimmedForNotificationCard,
           !preview.isEmpty {
            return "$ \(preview)"
        }

        if let activity = session.spotlightActivityLineText?.trimmedForNotificationCard,
           !activity.isEmpty {
            return activity
        }

        let summary = session.summary.trimmedForNotificationCard
        return summary.isEmpty ? nil : summary
    }

    private func subagentElapsed(since start: Date, at now: Date) -> String {
        let seconds = Int(now.timeIntervalSince(start))
        if seconds < 60 { return "\(seconds)s" }
        let minutes = seconds / 60
        let secs = seconds % 60
        return "\(minutes)m \(secs)s"
    }

    private func taskSummary(_ tasks: [ClaudeTaskInfo]) -> String {
        let done = tasks.filter { $0.status == .completed }.count
        let prog = tasks.filter { $0.status == .inProgress }.count
        let pend = tasks.filter { $0.status == .pending }.count
        return lang.t("tasks.summary", done, prog, pend)
    }

    @ViewBuilder
    private func taskStatusIcon(_ status: ClaudeTaskInfo.Status) -> some View {
        switch status {
        case .completed:
            Image(systemName: "checkmark.square.fill")
                .font(.system(size: 9))
                .foregroundStyle(.white.opacity(0.35))
                .accessibilityLabel(lang.t("a11y.task.completed"))
        case .inProgress:
            Circle()
                .fill(tokens.colors.statusRunning)
                .frame(width: 6, height: 6)
                .accessibilityLabel(lang.t("a11y.task.inProgress"))
        case .pending:
            Circle()
                .strokeBorder(.white.opacity(0.3), lineWidth: 1)
                .frame(width: 6, height: 6)
                .accessibilityLabel(lang.t("a11y.task.pending"))
        }
    }

    @ViewBuilder
    private func statusIndicator(for presence: IslandSessionPresence) -> some View {
        let tint = statusTint(for: presence)
        switch stateIndicator {
        case .animatedDot:
            if let pulseClock, stateIndicator.pulses(presence: presence, isActionable: isActionable) {
                PulsingStatusDot(pulseClock: pulseClock, tint: tint, presence: presence)
                    .frame(width: 10, height: 24, alignment: .top)
            } else {
                islandStatusDotView(tint: tint, presence: presence, pulse: 0)
                    .frame(width: 10, height: 24, alignment: .top)
            }
        case .bar:
            RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                .fill(tint)
                .frame(width: 4, height: isActionable ? 34 : 28)
                .padding(.top, 2)
        case .glyph:
            Image(systemName: statusGlyphName)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 14, height: 20)
                .padding(.top, 1)
        case .tint:
            Circle()
                .fill(tint.opacity(presence == .inactive ? 0.54 : 0.92))
                .frame(width: 8, height: 8)
                .padding(.top, 6)
        }
    }

    private func rowFillColor(for presence: IslandSessionPresence) -> Color {
        if presentation == .notification {
            return Color.clear
        }

        let base = isHighlighted ? Color.white.opacity(isActionable ? 0.06 : 0.04) : Color.clear
        guard stateIndicator == .tint else { return base }

        let tintOpacity: Double
        if isHighlighted {
            tintOpacity = isActionable ? 0.16 : 0.11
        } else {
            tintOpacity = presence == .inactive ? 0.035 : 0.075
        }
        return statusTint(for: presence).opacity(tintOpacity)
    }

    private var statusGlyphName: String {
        switch session.phase {
        case .waitingForApproval:
            "exclamationmark.triangle.fill"
        case .waitingForAnswer:
            "questionmark.circle.fill"
        case .running:
            "circle.dashed"
        case .completed:
            switch session.outcome {
            case .success:
                "checkmark.circle.fill"
            case .interrupted:
                "stop.circle.fill"
            case .failed:
                "xmark.circle.fill"
            }
        }
    }

    /// Prompt line for manually expanded inactive rows (bypasses time-based filter).
    private var expandedPromptLineText: String? {
        guard detailOverride == true, let prompt = session.spotlightPromptText else { return nil }
        return "You: \(prompt)"
    }

    /// Activity line for manually expanded inactive rows (bypasses time-based filter).
    private var expandedActivityLineText: String? {
        guard detailOverride == true else { return nil }
        let trimmed = session.lastAssistantMessageText?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let assistantMessage = trimmed, !assistantMessage.isEmpty {
            return assistantMessage
        }
        return session.jumpTarget != nil ? "Ready" : "Completed"
    }

    private func handlePrimaryTap() {
        guard isInteractive else { return }
        actions.jump()
    }

    private func detailToggleButton(isOpen: Bool) -> some View {
        Button {
            toggleDetail(currentlyOpen: isOpen)
        } label: {
            Image(systemName: "chevron.down")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(isOpen || isHighlighted ? .white.opacity(0.68) : .white.opacity(0.42))
                .frame(
                    width: IslandSessionRowMetrics.detailToggleColumnWidth,
                    height: IslandSessionRowMetrics.trailingControlHeight
                )
                .background(
                    Circle()
                        .fill(.white.opacity(detailToggleFillOpacity(isOpen: isOpen)))
                )
                .rotationEffect(.degrees(isOpen ? 180 : 0))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // AB-244: this button's own accessibility element is normally
        // suppressed (its parent `rowSummary` sets `.accessibilityElement
        // (children: .ignore)` and exposes the same toggle as a named
        // action instead), but the label is kept correct and `lang.t`-routed
        // here too in case this view is ever used standalone.
        .accessibilityLabel(lang.t(isOpen ? "a11y.session.collapseDetail" : "a11y.session.expandDetail"))
    }

    /// Shared by the visible chevron `Button` and `rowSummary`'s named
    /// VoiceOver action so both toggle paths agree exactly.
    private func toggleDetail(currentlyOpen: Bool) {
        guard isInteractive else { return }
        withAnimation(.easeInOut(duration: 0.2)) {
            detailOverride = !currentlyOpen
        }
    }

    private func detailToggleFillOpacity(isOpen: Bool) -> Double {
        if isHighlighted {
            return isOpen ? 0.075 : 0.055
        }

        return isOpen ? 0.045 : 0.02
    }

    private func compactBadge(
        _ title: String,
        presence: IslandSessionPresence,
        icon: String? = nil
    ) -> some View {
        HStack(spacing: 3) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 7.5, weight: .semibold))
            }
            Text(title)
                .font(.system(size: 9, weight: .semibold))
        }
        .foregroundStyle(badgeTextColor(for: presence))
        .padding(.horizontal, 7)
        .padding(.vertical, 3.5)
        .background(Color(red: 0.14, green: 0.14, blue: 0.15), in: Capsule())
    }

    private func headlineColor(for presence: IslandSessionPresence) -> Color {
        presence == .inactive ? .white.opacity(0.78) : .white
    }

    private func badgeTextColor(for presence: IslandSessionPresence) -> Color {
        presence == .inactive ? .white.opacity(0.42) : .white.opacity(0.56)
    }

    private func statusTint(for presence: IslandSessionPresence) -> Color {
        tokens.colors.statusTint(for: session.phase, presence: presence, outcome: session.outcome)
    }

    private func activityColor(for presence: IslandSessionPresence) -> Color {
        switch session.spotlightActivityTone {
        case .attention:
            tokens.colors.statusTint(for: session.phase)
        case .live:
            statusTint(for: presence)
        case .idle:
            .white.opacity(contrastText(tokens.colors.secondaryTextOpacity))
        case .ready:
            presence == .inactive ? .white.opacity(contrastText(tokens.colors.secondaryTextOpacity)) : statusTint(for: presence)
        }
    }
}

/// AB-303: internal (not `private`) so Poured's actionable question body can
/// reuse the same structured prompt — the numbered option rows, 1–9 / Enter
/// keyboard wiring, multi-select toggles, freeform + quick-reply fields and
/// submit are contract-level behaviour, driven by tokens that already read on
/// glass, so they're shared rather than re-implemented.
struct StructuredQuestionPromptView: View {
    let prompt: QuestionPrompt?
    var lang: LanguageManager = .shared
    /// When set, registers this card's option-select/submit actions so
    /// `OverlayPanelController`'s keyboard monitor can drive them (1–9 /
    /// ⌘1–9 select, Enter submits — AB-227). Only wired for single-question
    /// prompts, the overwhelmingly common case; multi-question prompts fall
    /// back to mouse-only selection for v1.
    var keyboardCoordinator: OverlayUICoordinator?
    let onAnswer: (QuestionPromptResponse) -> Void

    @State private var selections: [String: Set<String>] = [:]
    @State private var freeformTexts: [String: String] = [:]
    @State private var typedReply: String = ""
    @State private var hoveredOptionKey: String?

    @Environment(\.islandTokens) private var tokens

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if showsPromptTitle {
                Text(promptTitle)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(tokens.colors.statusWaitingForAnswer)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if structuredQuestions.isEmpty {
                freeformAnswerBody
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(structuredQuestions, id: \.question) { question in
                        questionRow(question)
                    }
                }

                quickReplyField

                Button(submitButtonTitle) {
                    submitAnswer()
                }
                .buttonStyle(IslandActionButtonStyle(kind: canSubmit ? .primary : .secondary, expands: true))
                .disabled(!canSubmit)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.white.opacity(0.03))
        )
        .onAppear { registerKeyboardHandlersIfNeeded() }
        .onChange(of: prompt?.id) { _, _ in registerKeyboardHandlersIfNeeded() }
        .onDisappear { keyboardCoordinator?.clearQuestionCardKeyboardHandlers() }
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(.white.opacity(0.05))
        )
    }

    // MARK: - Per-question row

    /// Renders a single question with its header, text, and vertical option list.
    @ViewBuilder
    private func questionRow(_ question: QuestionPromptItem) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if structuredQuestions.count > 1 {
                Text(question.header)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white.opacity(0.5))
            }

            Text(question.question)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(0.88))
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(question.options.enumerated()), id: \.element.id) { index, option in
                    optionRow(option, optionIndex: index, question: question)
                }
            }
        }
    }

    // MARK: - Option row (vertical, CLI-style)

    @ViewBuilder
    private func optionRow(
        _ option: QuestionOption,
        optionIndex: Int,
        question: QuestionPromptItem
    ) -> some View {
        let isSelected = selectedLabels(for: question).contains(option.label)
        let key = optionKey(for: question, option: option)
        let isHovered = hoveredOptionKey == key
        let showsFreeform = option.allowsFreeform && isSelected
        VStack(alignment: .leading, spacing: 0) {
            Button {
                toggle(option: option.label, for: question)
            } label: {
                HStack(spacing: 10) {
                    Text("\(optionIndex + 1)")
                        .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                        .foregroundStyle(isSelected ? .black.opacity(0.82) : tokens.colors.paper.opacity(0.42))
                        .frame(width: 22, height: 20)
                        .background(
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .fill(isSelected ? tokens.colors.paper.opacity(0.88) : Color.white.opacity(0.045))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .strokeBorder(.white.opacity(isSelected ? 0 : 0.08))
                        )

                    VStack(alignment: .leading, spacing: 1) {
                        Text(option.label)
                            .font(.system(size: 12.2, weight: .medium))
                            .foregroundStyle(.white.opacity(isSelected ? 1 : 0.78))

                        if !option.description.isEmpty {
                            Text(option.description)
                                .font(.system(size: 10.5))
                                .foregroundStyle(.white.opacity(isHovered || isSelected ? 0.48 : 0.38))
                                .lineLimit(1)
                        }
                    }

                    Spacer(minLength: 0)

                    if isSelected {
                        Image(systemName: "checkmark")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(tokens.colors.statusCompleted)
                            .accessibilityHidden(true)
                    }
                }
                .contentShape(Rectangle())
                .padding(.vertical, 5)
                .padding(.horizontal, 11)
            }
            .buttonStyle(.plain)
            // AB-244: selection state conveyed via the `.isSelected` trait
            // (VoiceOver appends "selected") rather than folding the
            // checkmark glyph's name into the button's spoken label.
            .accessibilityAddTraits(isSelected ? .isSelected : [])

            if showsFreeform {
                Divider()
                    .overlay(Color.white.opacity(0.08))
                freeformField(for: option, question: question)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(optionFillColor(isSelected: isSelected, isHovered: isHovered))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(optionStrokeColor(isSelected: isSelected, isHovered: isHovered))
        )
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.12)) {
                hoveredOptionKey = hovering ? key : (hoveredOptionKey == key ? nil : hoveredOptionKey)
            }
        }
    }

    @ViewBuilder
    private func freeformField(for option: QuestionOption, question: QuestionPromptItem) -> some View {
        let key = freeformKey(for: question, option: option)
        ReplyTextField(
            placeholder: lang.t("question.otherPlaceholder"),
            text: Binding(
                get: { freeformTexts[key] ?? "" },
                set: { freeformTexts[key] = $0 }
            ),
            onSubmit: {
                if hasCompleteSelection {
                    onAnswer(QuestionPromptResponse(answers: answerMap))
                }
            }
        )
        .frame(height: 22)
        .padding(.vertical, 6)
        .padding(.horizontal, 10)
    }

    private var freeformAnswerBody: some View {
        VStack(alignment: .leading, spacing: 8) {
            quickReplyField

            Button(lang.t("question.submit")) {
                submitAnswer()
            }
            .buttonStyle(IslandActionButtonStyle(kind: canSubmit ? .primary : .secondary, expands: true))
            .disabled(!canSubmit)
        }
    }

    @ViewBuilder
    private var quickReplyField: some View {
        if showsGlobalReplyField {
            HStack(spacing: 6) {
                ReplyTextField(
                    placeholder: lang.t("question.otherPlaceholder"),
                    text: $typedReply,
                    onSubmit: {
                        if canSubmit {
                            submitAnswer()
                        }
                    }
                )
                .frame(height: 30)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.white.opacity(0.035))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(.white.opacity(0.055))
            )
        }
    }

    // MARK: - Helpers

    private var structuredQuestions: [QuestionPromptItem] {
        if let questions = prompt?.questions, !questions.isEmpty {
            return questions
        }

        guard let prompt, !prompt.options.isEmpty else {
            return []
        }

        return [
            QuestionPromptItem(
                question: prompt.title,
                header: lang.t("question.answerNeeded"),
                options: prompt.options.map { QuestionOption(label: $0) }
            ),
        ]
    }

    private var promptTitle: String {
        prompt?.title.trimmedForNotificationCard ?? lang.t("question.answerNeeded")
    }

    private var showsPromptTitle: Bool {
        guard !promptTitle.isEmpty else {
            return false
        }

        guard structuredQuestions.count == 1,
              let questionTitle = structuredQuestions.first?.question.trimmedForNotificationCard else {
            return true
        }

        return questionTitle.caseInsensitiveCompare(promptTitle) != .orderedSame
    }

    private var answerMap: [String: String] {
        Dictionary(uniqueKeysWithValues: structuredQuestions.compactMap { question in
            let values = resolvedAnswers(for: question)
            guard !values.isEmpty else {
                return nil
            }
            return (question.question, values.joined(separator: ", "))
        })
    }

    private var trimmedReply: String {
        typedReply.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var showsGlobalReplyField: Bool {
        structuredQuestions.isEmpty || !structuredQuestions.contains { question in
            question.options.contains { $0.allowsFreeform }
        }
    }

    private var primarySelectedAnswer: String? {
        guard structuredQuestions.count == 1,
              let question = structuredQuestions.first else {
            return nil
        }

        let values = resolvedAnswers(for: question)
        guard !values.isEmpty else {
            return nil
        }

        return values.joined(separator: ", ")
    }

    private var canSubmit: Bool {
        !trimmedReply.isEmpty || (!structuredQuestions.isEmpty && hasCompleteSelection)
    }

    private var submitButtonTitle: String {
        if !trimmedReply.isEmpty {
            return lang.t("question.sendReply")
        }

        if let primarySelectedAnswer, !primarySelectedAnswer.isEmpty {
            return lang.t("question.sendAnswer")
        }

        return lang.t("question.submit")
    }

    private func submitAnswer() {
        if !trimmedReply.isEmpty {
            onAnswer(QuestionPromptResponse(answer: trimmedReply))
            return
        }

        onAnswer(
            QuestionPromptResponse(
                rawAnswer: primarySelectedAnswer,
                answers: answerMap
            )
        )
    }

    private var hasCompleteSelection: Bool {
        structuredQuestions.allSatisfy { question in
            let selected = selectedLabels(for: question)
            guard !selected.isEmpty else {
                return false
            }
            // When a freeform option is selected, require non-empty text.
            for option in question.options where option.allowsFreeform && selected.contains(option.label) {
                if trimmedFreeform(for: question, option: option).isEmpty {
                    return false
                }
            }
            return true
        }
    }

    private func selectedLabels(for question: QuestionPromptItem) -> Set<String> {
        selections[question.question] ?? []
    }

    private func resolvedAnswers(for question: QuestionPromptItem) -> [String] {
        let selected = selectedLabels(for: question)
        guard !selected.isEmpty else { return [] }

        let optionOrder = question.options
        var answers: [String] = []
        for option in optionOrder where selected.contains(option.label) {
            if option.allowsFreeform {
                let text = trimmedFreeform(for: question, option: option)
                answers.append(text.isEmpty ? option.label : text)
            } else {
                answers.append(option.label)
            }
        }
        return answers
    }

    private func freeformKey(for question: QuestionPromptItem, option: QuestionOption) -> String {
        "\(question.question)|\(option.label)"
    }

    private func optionKey(for question: QuestionPromptItem, option: QuestionOption) -> String {
        "\(question.question)|\(option.label)"
    }

    private func optionFillColor(isSelected: Bool, isHovered: Bool) -> Color {
        if isSelected {
            return tokens.colors.paper.opacity(0.10)
        }
        if isHovered {
            return Color.white.opacity(0.065)
        }
        return Color.white.opacity(0.028)
    }

    private func optionStrokeColor(isSelected: Bool, isHovered: Bool) -> Color {
        if isSelected {
            return tokens.colors.paper.opacity(0.36)
        }
        if isHovered {
            return .white.opacity(0.13)
        }
        return .white.opacity(0.045)
    }

    private func trimmedFreeform(for question: QuestionPromptItem, option: QuestionOption) -> String {
        (freeformTexts[freeformKey(for: question, option: option)] ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func toggle(option: String, for question: QuestionPromptItem) {
        var selected = selections[question.question] ?? []

        if question.multiSelect {
            if selected.contains(option) {
                selected.remove(option)
            } else {
                selected.insert(option)
            }
        } else {
            if selected.contains(option) {
                selected.removeAll()
            } else {
                selected = [option]
            }
        }

        typedReply = ""
        selections[question.question] = selected
    }

    // MARK: - Keyboard shortcuts (AB-227)

    /// Registers (or clears) this card's number-key/Enter handlers with the
    /// shared overlay coordinator. Called on appear and whenever the prompt
    /// identity changes, so a fresh question always gets fresh handlers.
    private func registerKeyboardHandlersIfNeeded() {
        guard let keyboardCoordinator else {
            return
        }

        // Multi-question prompts have no single flat 1–9 numbering (each
        // question restarts at 1), so keyboard selection is scoped to the
        // common single-question case for v1; mouse selection still works.
        guard structuredQuestions.count == 1 else {
            keyboardCoordinator.clearQuestionCardKeyboardHandlers()
            return
        }

        keyboardCoordinator.registerQuestionCardKeyboardHandlers(
            OverlayUICoordinator.QuestionCardKeyboardHandlers(
                optionCount: { structuredQuestions.first?.options.count ?? 0 },
                toggleOption: { index in
                    guard let question = structuredQuestions.first,
                          question.options.indices.contains(index) else {
                        return
                    }
                    toggle(option: question.options[index].label, for: question)
                },
                submit: {
                    if canSubmit {
                        submitAnswer()
                    }
                }
            )
        )
    }
}

// MARK: - Reply TextField (NSTextField wrapper for IME-safe Enter handling)

/// NSTextField wrapper that fires `onSubmit` only when the IME composition
/// is finished — pressing Enter during Chinese/Japanese IME composition
/// confirms the candidate instead of submitting.
/// AB-303: internal (not `private`) so Poured's actionable completion / question
/// bodies can reuse the same IME-safe reply field.
struct ReplyTextField: NSViewRepresentable {
    var placeholder: String
    @Binding var text: String
    var onSubmit: () -> Void

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField()
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = .systemFont(ofSize: 13)
        field.textColor = .white
        field.placeholderAttributedString = NSAttributedString(
            string: placeholder,
            attributes: [
                .foregroundColor: NSColor.white.withAlphaComponent(0.35),
                .font: NSFont.systemFont(ofSize: 13),
            ]
        )
        field.delegate = context.coordinator
        field.cell?.lineBreakMode = .byTruncatingTail
        field.cell?.usesSingleLineMode = true
        return field
    }

    func updateNSView(_ nsView: NSTextField, context: Context) {
        if nsView.stringValue != text {
            nsView.stringValue = text
        }
        context.coordinator.onSubmit = onSubmit
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, onSubmit: onSubmit)
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var text: Binding<String>
        var onSubmit: () -> Void

        init(text: Binding<String>, onSubmit: @escaping () -> Void) {
            self.text = text
            self.onSubmit = onSubmit
        }

        func controlTextDidChange(_ obj: Notification) {
            guard let field = obj.object as? NSTextField else { return }
            text.wrappedValue = field.stringValue
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                // Let AppKit handle Enter during IME composition (e.g. confirming
                // a Chinese/Japanese candidate). Only submit when no marked text.
                guard !textView.hasMarkedText() else { return false }
                onSubmit()
                return true
            }
            return false
        }
    }
}

private extension String {
    var trimmedForNotificationCard: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - Compact button style

private struct IslandCompactButtonStyle: ButtonStyle {
    var tint: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(tint == .secondary ? .white.opacity(0.7) : tint)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                (tint == .secondary ? Color.white.opacity(0.08) : tint.opacity(0.15)),
                in: Capsule()
            )
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

/// AB-303: internal (not `private`) so Poured's actionable bodies drive their
/// Allow / Deny / always-allow / terminal-CTA / submit buttons through the same
/// token-styled button style — a filled `primary`/`warning` and a quiet
/// `secondary`, resolved from `\.islandTokens`, so the buttons re-tint to
/// `.poured` without a parallel style.
struct IslandActionButtonStyle: ButtonStyle {
    enum Kind {
        case primary
        case secondary
        case warning
    }

    let kind: Kind
    var expands = false

    @Environment(\.isEnabled) private var isEnabled

    /// AB-296: same route `isEnabled` already takes — SwiftUI updates a
    /// `ButtonStyle`'s dynamic properties from the surrounding environment
    /// before calling `makeBody`, so the tokens arrive without threading them
    /// through every call site.
    @Environment(\.islandTokens) private var tokens

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11.8, weight: .semibold))
            .foregroundStyle(foregroundColor)
            .lineLimit(1)
            .frame(maxWidth: expands ? .infinity : nil)
            .padding(.horizontal, 13)
            .padding(.vertical, 8)
            .background(backgroundColor(configuration.isPressed), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(strokeColor, lineWidth: 1)
            )
            .opacity(configuration.isPressed ? 0.82 : 1)
    }

    private var foregroundColor: Color {
        guard isEnabled else {
            return tokens.colors.paper.opacity(0.42)
        }

        switch kind {
        case .primary:
            return .black.opacity(0.88)
        case .warning:
            return .white
        case .secondary:
            return tokens.colors.paper.opacity(0.78)
        }
    }

    private var strokeColor: Color {
        guard isEnabled else {
            return .white.opacity(0.07)
        }

        switch kind {
        case .primary:
            return tokens.colors.paper.opacity(0.86)
        case .warning:
            return tokens.colors.statusWarning.opacity(0.42)
        case .secondary:
            return .white.opacity(0.07)
        }
    }

    private func backgroundColor(_ isPressed: Bool) -> Color {
        guard isEnabled else {
            return Color.white.opacity(0.055)
        }

        let pressedFactor: Double = isPressed ? 0.78 : 1
        switch kind {
        case .primary:
            return tokens.colors.paper.opacity(pressedFactor)
        case .warning:
            return tokens.colors.statusWarning.opacity(pressedFactor)
        case .secondary:
            return Color.white.opacity(isPressed ? 0.11 : 0.065)
        }
    }
}

// MARK: - Menu bar content (unchanged)

// MARK: - MarkdownUI Theme

extension MarkdownUI.Theme {
    /// AB-296: a `Theme` is a value, not a `View`, so it can't read the
    /// environment itself — the colour tokens are handed in by the one call
    /// site (`IslandSessionRow.completionActionBody`) that renders a
    /// completion message. Every foreground and wash below was a hardcoded
    /// `.white`; they now resolve from `surfaceText`.
    @MainActor static func completionCard(_ colors: IslandColorTokens) -> Theme {
        Theme()
        .text {
            ForegroundColor(colors.surfaceText.opacity(0.88))
            FontSize(13.5)
            FontWeight(.medium)
        }
        .link {
            ForegroundColor(.blue)
        }
        .strong {
            FontWeight(.bold)
        }
        .code {
            FontFamilyVariant(.monospaced)
            FontSize(12.5)
            ForegroundColor(colors.surfaceText.opacity(0.88))
            BackgroundColor(colors.surfaceText.opacity(0.08))
        }
        .codeBlock { configuration in
            configuration.label
                .markdownTextStyle {
                    FontFamilyVariant(.monospaced)
                    FontSize(12.5)
                    ForegroundColor(colors.surfaceText.opacity(0.88))
                }
                .padding(10)
                .background(colors.surfaceText.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .heading1 { configuration in
            configuration.label
                .markdownTextStyle {
                    FontSize(16)
                    FontWeight(.bold)
                    ForegroundColor(colors.surfaceText.opacity(0.88))
                }
                .markdownMargin(top: 8, bottom: 4)
        }
        .heading2 { configuration in
            configuration.label
                .markdownTextStyle {
                    FontSize(15)
                    FontWeight(.bold)
                    ForegroundColor(colors.surfaceText.opacity(0.88))
                }
                .markdownMargin(top: 8, bottom: 4)
        }
        .heading3 { configuration in
            configuration.label
                .markdownTextStyle {
                    FontSize(14)
                    FontWeight(.semibold)
                    ForegroundColor(colors.surfaceText.opacity(0.88))
                }
                .markdownMargin(top: 6, bottom: 2)
        }
        .blockquote { configuration in
            configuration.label
                .markdownTextStyle {
                    ForegroundColor(colors.surfaceText.opacity(0.6))
                    FontSize(13.5)
                }
                .padding(.leading, 12)
                .overlay(alignment: .leading) {
                    Rectangle()
                        .fill(colors.surfaceText.opacity(0.2))
                        .frame(width: 3)
                }
        }
        .listItem { configuration in
            configuration.label
                .markdownMargin(top: 2, bottom: 2)
        }
        .table { configuration in
            configuration.label
                .fixedSize(horizontal: false, vertical: true)
                .markdownTableBorderStyle(.init(.allBorders, color: colors.surfaceText.opacity(0.15), strokeStyle: .init(lineWidth: 1)))
                .markdownTableBackgroundStyle(
                    .alternatingRows(colors.surfaceText.opacity(0.04), colors.surfaceText.opacity(0.08))
                )
                .markdownMargin(top: 4, bottom: 8)
        }
        .tableCell { configuration in
            configuration.label
                .markdownTextStyle {
                    if configuration.row == 0 {
                        FontWeight(.semibold)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
                .padding(.vertical, 6)
                .padding(.horizontal, 12)
                .relativeLineSpacing(.em(0.25))
        }
    }
}

/// AB-302: internal (not `private`) so the extracted `PouredSessionRow` slot
/// component can reuse the same trailing-rail dismiss glyph as Classic's row.
struct DismissButton: View {
    let action: () -> Void
    var lang: LanguageManager = .shared
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(isHovered ? 0.8 : 0.4))
                .frame(
                    width: IslandSessionRowMetrics.dismissColumnWidth,
                    height: IslandSessionRowMetrics.trailingControlHeight
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        // AB-244: normally suppressed by the parent's `.accessibilityElement
        // (children: .ignore)` in favor of a named action, same as
        // `detailToggleButton` — kept correct here too for standalone use.
        .accessibilityLabel(lang.t("a11y.session.dismiss"))
    }
}

/// AB-237: renders the session's JSONL transcript as a clickable affordance.
/// A plain click opens the transcript in the default editor; the context menu
/// additionally offers "Reveal in Finder" and "Copy Path". Callers only
/// instantiate this when a transcript path is actually known.
///
/// AB-285: the visible label is a localized "Transcript" rather than the
/// `<session-id>.jsonl` filename — the row headline already carries the
/// workspace, and a 36-character UUID read as developer debris. The full
/// path stays one hover (tooltip) or one context-menu click away.
///
/// AB-302: internal (not `private`) so `PouredSessionRow` renders the same
/// Transcript affordance in its expanded body as Classic's row.
struct TranscriptAffordance: View {
    let path: String
    let workspace: String
    let lang: LanguageManager
    @State private var isHovered = false

    var body: some View {
        Button {
            openTranscriptFile(at: path)
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "doc.text")
                    .font(.system(size: 9.5, weight: .medium))
                    .accessibilityHidden(true)
                Text(lang.t("island.transcript.label"))
                    .font(.system(size: 10.5, weight: .medium))
                    .lineLimit(1)
            }
            .foregroundStyle(.white.opacity(isHovered ? 0.62 : 0.4))
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help(path)
        // The visible label is now the same word on every row, so VoiceOver
        // gets the workspace too — otherwise several expanded rows all
        // announce an identical "Transcript".
        .accessibilityLabel(lang.t("a11y.transcript", workspace))
        .contextMenu {
            Button(lang.t("island.transcript.open")) {
                openTranscriptFile(at: path)
            }
            Button(lang.t("island.transcript.reveal")) {
                revealTranscriptFileInFinder(at: path)
            }
            Button(lang.t("island.transcript.copyPath")) {
                copyTranscriptPath(path)
            }
        }
    }
}

/// Opens the transcript JSONL file in whatever app the user has set as
/// default for that file type — mirrors the plain `NSWorkspace.shared.open`
/// pattern used elsewhere in the app (e.g. `CodexAppServerCoordinator`).
private func openTranscriptFile(at path: String) {
    NSWorkspace.shared.open(URL(fileURLWithPath: path))
}

/// Reveals the transcript file in Finder, falling back to its containing
/// directory if the file itself is already gone — same fallback pattern as
/// `GeneralSettingsPane.revealInFinder` in `SettingsView.swift`.
private func revealTranscriptFileInFinder(at path: String) {
    let fileManager = FileManager.default
    let url = URL(fileURLWithPath: path).standardizedFileURL

    if fileManager.fileExists(atPath: url.path) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
        return
    }

    let directoryURL = url.deletingLastPathComponent()
    if fileManager.fileExists(atPath: directoryURL.path) {
        NSWorkspace.shared.open(directoryURL)
    }
}

/// Puts the full transcript path — session-id filename included — on the
/// clipboard, so the identifier the label no longer spells out stays one
/// click away for debugging. Same pasteboard pattern as the copyable command
/// rows in `SettingsView.swift`.
private func copyTranscriptPath(_ path: String) {
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(path, forType: .string)
}
