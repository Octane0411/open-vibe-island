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

/// "Instrument" — a precision monospace console theme, built up across four
/// slices.
///
/// AB-307 (instrument 1/4) ships the theme's shell: the token identity (near-mono
/// palette that spends colour only on status, squared-off flat panel with no
/// vibrancy or fillet, crisp mechanical motion), the mono typography roles, the
/// theme's own squared-tick grid geometry, and the flat closed pill
/// (`InstrumentClosedPill`). The opened chrome regions, session rows, header and
/// list states reuse Classic's shared slot views for now; later slices
/// (AB-308…) restyle them into the instrument-panel language.
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

    /// The shell's rows are still Classic's flat views, which are safe to
    /// rasterize. A later slice that adds glow/motion to the instrument rows can
    /// flip this alongside that change.
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

    // MARK: Slots reused from Classic until later slices restyle them (AB-308…)

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
            IslandHeaderControls(
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
            IslandSessionRow(
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
            IslandSessionListScaffold(
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

    func emptyState(lang: LanguageManager, hasRecentSessions: Bool) -> AnyView {
        AnyView(IslandEmptyState(lang: lang, hasRecentSessions: hasRecentSessions))
    }

    func bootstrapPlaceholder(lang: LanguageManager) -> AnyView {
        AnyView(IslandBootstrapPlaceholder(lang: lang))
    }

    func installHint(lang: LanguageManager, onTap: @escaping () -> Void) -> AnyView {
        AnyView(IslandInstallHooksHint(lang: lang, onTap: onTap))
    }
}
