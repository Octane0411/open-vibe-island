import AppKit
import SwiftUI
import OpenIslandCore

/// "Poured Island" — the liquid-glass theme, built up across five slices.
///
/// AB-300 (poured 1/5) shipped the theme's skeleton: the token identity (cool
/// ink/paper, filleted opened shape, deep soft shadow, lighter vibrancy +
/// specular top edge, softer "poured" motion), the themed `NSVisualEffectView`
/// configuration carried by `IslandMaterialTokens`, the fillet-stem silhouette
/// driven by `metrics.filletRadius`, and the glass closed pill
/// (`PouredClosedPill`).
///
/// AB-301 (poured 2/5) adds the panel-chrome glass: the opened header with
/// conic-gradient usage rings and glass control buttons (`PouredHeaderControls`
/// / `PouredUsageSummary`), the session-list summary strip / section headers /
/// footer (`PouredSessionListScaffold`), and the glass empty / bootstrap /
/// install states.
///
/// AB-302 (poured 3/5) re-skins the session rows themselves for glass:
/// `PouredSessionRow` renders every non-actionable state (collapsed, running,
/// done, idle/stale) as luminous-glow glass across the list and notification
/// presentations.
///
/// AB-303 (poured 4/5) completes the row: the actionable approval / question /
/// completion interiors are now fully Poured too — the permission request is
/// the hero, an amber-glow card that radiates a pulsing warm glow above the
/// glass (static under Reduce Motion). The single-actionable notification card
/// reuses the shared `IslandNotificationCard` chrome, whose one row is drawn
/// through this theme's `sessionRow` factory, so it inherits the Poured
/// actionable surfaces automatically.
///
/// Registered but **not** the default: the default flips in Poured 5/5.
struct PouredIslandTheme: IslandTheme {

    // MARK: Identity

    let id = "poured"

    func name(_ lang: LanguageManager) -> String {
        lang.t("theme.poured.name")
    }

    func descriptor(_ lang: LanguageManager) -> String {
        lang.t("theme.poured.descriptor")
    }

    // MARK: Styling

    var tokens: IslandThemeTokens { .poured }

    // MARK: Capability flags

    /// `false` since AB-302: `PouredSessionRow` expresses status as luminous
    /// glow (soft `.shadow` bleeds around the status dot / bar / glyph). A
    /// `.drawingGroup()` off-screen render would flatten those glows and clip
    /// them to the row bounds, so the row opts out of the rasterization
    /// Classic's flat views are safe to take.
    let rowIsDrawingGroupSafe = false

    /// The opened slab is a frosted `NSVisualEffectView` surface, so vibrancy
    /// is on — it falls back to a flat `surfaceInk` fill under Reduce
    /// Transparency, the same path Classic takes.
    let usesVibrancy = true

    // MARK: Geometry strategy

    /// Poured's closed grid does not deviate from Classic's, so it reuses the
    /// same `V6RightSlotView` statics (pinned by `AgentsGridLayoutTests`) — no
    /// new geometry, no new layout vectors. Only the per-tile glass styling
    /// differs, which lives in `PouredClosedPill`, not in the geometry.
    var agentsGridGeometry: IslandAgentsGridGeometry {
        IslandAgentsGridGeometry(
            balancedRows: { V6RightSlotView.balancedRows($0) },
            cellGeometry: { V6RightSlotView.cellGeometry(rowCount: $0) }
        )
    }

    // MARK: Slot factories

    /// The glass closed pill (AB-300).
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
            PouredClosedPill(
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

    // MARK: Slots restyled for glass (AB-301)

    /// The opened header: usage as conic-gradient rings and glass control
    /// buttons, on the shared notch-split / single-lane layout.
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
            PouredHeaderControls(
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

    /// The glass session row (AB-302 · AB-303): every state — collapsed,
    /// running, done, idle/stale, and the actionable approval / question /
    /// completion interiors — is rendered by `PouredSessionRow`.
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
            PouredSessionRow(
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

    /// The glass session-list chrome: summary strip, section headers (all four
    /// grouping modes) and footer. Rows inside it route through `sessionRow`
    /// above — the glass `PouredSessionRow` since AB-302.
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
            PouredSessionListScaffold(
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

    /// The single-actionable notification card (AB-303). The chrome — the
    /// "Show all N" affordance and the auto-collapse timing — is shared with
    /// Classic via `IslandNotificationCard` and reads through the token layer;
    /// the card's one row is drawn by this theme's `sessionRow` factory, so it
    /// picks up the Poured actionable surfaces (incl. the amber-glow approval
    /// hero) without a parallel card.
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

    // MARK: Glass empty / bootstrap / install states (AB-301)

    func emptyState(lang: LanguageManager, hasRecentSessions: Bool) -> AnyView {
        AnyView(PouredEmptyState(lang: lang, hasRecentSessions: hasRecentSessions))
    }

    func bootstrapPlaceholder(lang: LanguageManager) -> AnyView {
        AnyView(PouredBootstrapPlaceholder(lang: lang))
    }

    func installHint(lang: LanguageManager, onTap: @escaping () -> Void) -> AnyView {
        AnyView(PouredInstallHooksHint(lang: lang, onTap: onTap))
    }
}
