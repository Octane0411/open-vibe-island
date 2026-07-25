import AppKit
import SwiftUI
import OpenIslandCore

/// Mono typography roles for the Instrument theme.
///
/// The shared `IslandThemeTokens` layer deliberately carries no typography —
/// themes swap whole slot views, so per-view fonts belong to each theme. This
/// enum is Instrument's own small type table, kept in one place so every
/// Instrument view draws from the same monospaced roles and the ≥10pt floor is
/// enforceable in one spot (`InstrumentThemeTests`). Every role is
/// `.monospaced`; the sizes never dip below `floor`. The one intentional
/// exception is the closed-grid overflow "+N", which is a fitted micro-indicator
/// sized to its tick rather than a readable role, and so is not listed here.
enum InstrumentTypography {
    /// The lowest size any *readable* Instrument text may use. The mockup's
    /// 8.5px micro-type does not ship (AB-307): density comes from spacing.
    static let floor: CGFloat = 10

    static let microLabelSize: CGFloat = 10
    static let labelSize: CGFloat = 11
    static let countSize: CGFloat = 11
    static let bodySize: CGFloat = 12

    /// Every readable role's point size — the vector `InstrumentThemeTests`
    /// asserts stays at or above `floor`.
    static var readableRoleSizes: [CGFloat] {
        [microLabelSize, labelSize, countSize, bodySize]
    }

    /// Uppercase letterspaced micro-labels (section captions, unit tags).
    static let microLabel = Font.system(size: microLabelSize, weight: .semibold, design: .monospaced)

    /// Standard mono label (pill labels, chip text).
    static let label = Font.system(size: labelSize, weight: .medium, design: .monospaced)

    /// The "×N" count badge in the closed pill's right slot.
    static let count = Font.system(size: countSize, weight: .semibold, design: .monospaced)

    /// Body copy inside the opened panel.
    static let body = Font.system(size: bodySize, weight: .regular, design: .monospaced)
}

/// Script-aware helpers for Instrument's uppercase, letterspaced micro-labels.
///
/// The instrument idiom writes section captions and status tags as
/// `UPPERCASE` with a touch of `.tracking()`. That is precision on Latin text
/// and illegible noise on CJK (Han has no case, and letterspacing pries the
/// glyphs apart). Every Instrument micro-label routes its casing and tracking
/// through these two helpers so the neutralization lives in one place and is
/// pinned by `InstrumentThemeTests` (AB-308 §5).
enum InstrumentText {
    /// Uppercases Latin strings; passes CJK through unchanged.
    static func caps(_ string: String, lang: LanguageManager) -> String {
        lang.usesCJKScript ? string : string.uppercased()
    }

    /// The letterspacing for an uppercase micro-label — `base` on Latin,
    /// neutralized to `0` on CJK.
    static func tracking(_ base: CGFloat, lang: LanguageManager) -> CGFloat {
        lang.usesCJKScript ? 0 : base
    }
}

/// "Instrument" — a precision monospace console theme, built up across four
/// slices.
///
/// AB-307 (instrument 1/4) ships the theme's shell: the token identity (near-mono
/// palette that spends colour only on status, squared-off flat panel with no
/// vibrancy or fillet, crisp mechanical motion), the mono typography roles, the
/// theme's own squared-tick grid geometry, and the flat closed pill
/// (`InstrumentClosedPill`).
///
/// AB-308 (instrument 2/4) restyles the opened chrome: the header renders usage
/// as segmented tick-meters with numeric readouts and CRIT / HIGH / OK tags
/// (`InstrumentHeaderControls` / `InstrumentUsageSummary`), the session-list
/// summary becomes an uppercase state-distribution strip with section headers for
/// all four grouping modes and a status-line footer wired to the live session
/// count (`InstrumentSessionListScaffold`), and the empty / bootstrap / install
/// states move into squared hairline panels.
///
/// AB-309 (instrument 3/4) restyles the session rows themselves: every
/// non-actionable state (running, done, idle/stale) is typeset on one exact
/// column grid — state / workspace / agent tick / model / host / age — by
/// `InstrumentSessionRow`, with row rhythm (1-line done, 2-line running/idle)
/// standing in for decoration and not a single filled pill. Actionable rows
/// still delegate to Classic until AB-310.
///
/// Registered but **not** the default — Poured Island stays the product's face.
struct InstrumentTheme: IslandTheme {

    // MARK: Identity

    let id = "instrument"

    func name(_ lang: LanguageManager) -> String {
        lang.t("theme.instrument.name")
    }

    func descriptor(_ lang: LanguageManager) -> String {
        lang.t("theme.instrument.descriptor")
    }

    // MARK: Styling

    var tokens: IslandThemeTokens { .instrument }

    // MARK: Capability flags

    /// Instrument's rows are flat — squared ticks, hairline rules, mono type,
    /// no glow or blur that a `.drawingGroup()` off-screen render would clip or
    /// flatten — so they stay safe to rasterize (AB-309). Only the actionable
    /// rows, which route to Classic, ever consult this flag, and they disable
    /// the group regardless (`!isActionable`).
    let rowIsDrawingGroupSafe = true

    /// Instrument is a flat panel, not glass: the opened surface takes the opaque
    /// `surfaceInk` path (`OpenedSurfaceBackground` never builds a vibrancy view),
    /// which also makes Reduce Transparency a no-op for this theme.
    let usesVibrancy = false

    // MARK: Geometry strategy

    /// Instrument reuses Classic's balanced matrix and cell/gap sizing (so the
    /// pill width math and morph frame are unchanged) but squares the tick
    /// corners. Because the corner radius deviates, this is the theme's own
    /// strategy, pinned by `InstrumentThemeTests` — Classic's
    /// `AgentsGridLayoutTests` are untouched.
    var agentsGridGeometry: IslandAgentsGridGeometry {
        IslandAgentsGridGeometry(
            balancedRows: { InstrumentAgentsGrid.balancedRows($0) },
            cellGeometry: { InstrumentAgentsGrid.cellGeometry(rowCount: $0) }
        )
    }

    // MARK: Slot factories

    /// The flat instrument closed pill (AB-307).
    func closedPill(
        mode: UnifiedBars.Mode,
        label: String?,
        rightSlot: IslandRightSlotContent?,
        layout: V6ClosedLayout,
        height: CGFloat,
        physicalNotchWidth: CGFloat,
        minWidth: CGFloat,
        showsGlyph: Bool
    ) -> AnyView {
        AnyView(
            InstrumentClosedPill(
                mode: mode,
                label: label,
                rightSlot: rightSlot,
                layout: layout,
                height: height,
                physicalNotchWidth: physicalNotchWidth,
                minWidth: minWidth,
                showsGlyph: showsGlyph
            )
        )
    }

    // MARK: Instrument opened header + tick-meter usage (AB-308)

    /// The opened header: usage as segmented tick-meters with numeric readouts
    /// and CRIT / HIGH / OK tags, and flat squared instrument control buttons, on
    /// the shared notch-split / single-lane layout.
    func openedHeader(
        providers: [UsageProviderPresentation],
        usesNotchAwareLayout: Bool,
        targetScreen: NSScreen?,
        isSoundMuted: Bool,
        lang: LanguageManager,
        onToggleMute: @escaping () -> Void,
        onShowSettings: @escaping () -> Void,
        onQuit: @escaping () -> Void
    ) -> AnyView {
        AnyView(
            InstrumentHeaderControls(
                providers: providers,
                usesNotchAwareLayout: usesNotchAwareLayout,
                targetScreen: targetScreen,
                isSoundMuted: isSoundMuted,
                lang: lang,
                onToggleMute: onToggleMute,
                onShowSettings: onShowSettings,
                onQuit: onQuit
            )
        )
    }

    // MARK: Instrument tabular session rows (AB-309)

    /// The tabular-grid session row: every non-actionable state (running, done,
    /// idle/stale) is typeset on one exact column grid by `InstrumentSessionRow`.
    /// Actionable approval / question / completion rows still delegate to Classic
    /// from inside that view (a thin seam) until AB-310 restyles those interiors.
    func sessionRow(
        session: AgentSession,
        stateIndicator: IslandSessionStateIndicator,
        completedStaleThreshold: TimeInterval,
        isActionable: Bool,
        useDrawingGroup: Bool,
        isInteractive: Bool,
        isHighlighted: Bool,
        presentation: IslandSessionRowPresentation,
        sideInset: CGFloat,
        lang: LanguageManager,
        actions: RowActions,
        keyboardCoordinator: OverlayUICoordinator?,
        pulseClock: PulseClock?
    ) -> AnyView {
        AnyView(
            InstrumentSessionRow(
                session: session,
                stateIndicator: stateIndicator,
                completedStaleThreshold: completedStaleThreshold,
                isActionable: isActionable,
                useDrawingGroup: useDrawingGroup,
                isInteractive: isInteractive,
                isHighlighted: isHighlighted,
                presentation: presentation,
                sideInset: sideInset,
                lang: lang,
                actions: actions,
                keyboardCoordinator: keyboardCoordinator,
                pulseClock: pulseClock
            )
        )
    }

    /// The instrument session-list chrome (AB-308): the uppercase state-
    /// distribution summary strip, the section headers for all four grouping
    /// modes, and a status-line footer wired to the live session count. Rows
    /// inside it route through `sessionRow` above — the tabular
    /// `InstrumentSessionRow` since AB-309.
    func sessionList(
        sessions: [AgentSession],
        sections: [IslandSessionSection],
        group: IslandSessionGroup,
        stateIndicator: IslandSessionStateIndicator,
        completedStaleThreshold: TimeInterval,
        sideInset: CGFloat,
        isInteractive: Bool,
        actionableSessionID: String?,
        lang: LanguageManager,
        keyboardCoordinator: OverlayUICoordinator?,
        pulseClock: PulseClock?,
        makeActions: @escaping (AgentSession) -> RowActions
    ) -> AnyView {
        AnyView(
            InstrumentSessionListScaffold(
                sessions: sessions,
                sections: sections,
                group: group,
                stateIndicator: stateIndicator,
                completedStaleThreshold: completedStaleThreshold,
                sideInset: sideInset,
                isInteractive: isInteractive,
                actionableSessionID: actionableSessionID,
                lang: lang,
                keyboardCoordinator: keyboardCoordinator,
                pulseClock: pulseClock,
                makeActions: makeActions
            )
        )
    }

    func notificationCard(
        session: AgentSession?,
        isInteractive: Bool,
        stateIndicator: IslandSessionStateIndicator,
        completedStaleThreshold: TimeInterval,
        sideInset: CGFloat,
        totalSessionCount: Int,
        lang: LanguageManager,
        keyboardCoordinator: OverlayUICoordinator?,
        pulseClock: PulseClock?,
        makeActions: @escaping (AgentSession) -> RowActions,
        onShowAll: @escaping (AgentSession) -> Void,
        onPointerInside: @escaping () -> Void,
        onPointerExited: @escaping () -> Void,
        onMeasuredHeight: @escaping (CGFloat) -> Void
    ) -> AnyView {
        AnyView(
            IslandNotificationCard(
                session: session,
                isInteractive: isInteractive,
                stateIndicator: stateIndicator,
                completedStaleThreshold: completedStaleThreshold,
                sideInset: sideInset,
                totalSessionCount: totalSessionCount,
                lang: lang,
                keyboardCoordinator: keyboardCoordinator,
                pulseClock: pulseClock,
                makeActions: makeActions,
                onShowAll: onShowAll,
                onPointerInside: onPointerInside,
                onPointerExited: onPointerExited,
                onMeasuredHeight: onMeasuredHeight
            )
        )
    }

    // MARK: Instrument empty / bootstrap / install states (AB-308)

    func emptyState(lang: LanguageManager, hasRecentSessions: Bool) -> AnyView {
        AnyView(InstrumentEmptyState(lang: lang, hasRecentSessions: hasRecentSessions))
    }

    func bootstrapPlaceholder(lang: LanguageManager) -> AnyView {
        AnyView(InstrumentBootstrapPlaceholder(lang: lang))
    }

    func installHint(lang: LanguageManager, onTap: @escaping () -> Void) -> AnyView {
        AnyView(InstrumentInstallHooksHint(lang: lang, onTap: onTap))
    }
}
