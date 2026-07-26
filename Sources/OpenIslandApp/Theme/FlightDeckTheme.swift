import AppKit
import SwiftUI
import OpenIslandCore

/// Mono typography roles for the Flight Deck theme.
///
/// The shared `IslandThemeTokens` layer deliberately carries no typography —
/// themes swap whole slot views, so per-view fonts belong to each theme. This
/// enum is Flight Deck's own small type table, kept in one place so every
/// Flight Deck view draws from the same monospaced roles and the ≥10pt floor is
/// enforceable in one spot (`FlightDeckThemeTests`). Every role is
/// `.monospaced` — the mono legend of an instrument panel — and no readable role
/// dips below `floor`. The one intentional exception is the closed-grid overflow
/// "+N", a fitted micro-indicator sized to its annunciator light rather than a
/// readable role, so it is not listed here.
enum FlightDeckTypography {
    /// The lowest size any *readable* Flight Deck text may use. The ticket pins a
    /// ≥10pt type floor: density comes from letterspacing and rules, never from
    /// sub-10pt micro-type.
    static let floor: CGFloat = 10

    static let microLabelSize: CGFloat = 10
    static let labelSize: CGFloat = 11
    static let countSize: CGFloat = 11
    static let bodySize: CGFloat = 12

    /// Every readable role's point size — the vector `FlightDeckThemeTests`
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

/// Script-aware helpers for Flight Deck's uppercase, letterspaced micro-labels.
///
/// The avionics idiom writes section captions and status tags as `UPPERCASE`
/// with a touch of `.tracking()`. That is precision on Latin text and illegible
/// noise on CJK (Han has no case, and letterspacing pries the glyphs apart).
/// Every Flight Deck micro-label routes its casing and tracking through these
/// two helpers so the neutralization lives in one place and is pinned by
/// `FlightDeckThemeTests`. Mirrors Instrument's `InstrumentText`; kept per-theme
/// so a later slice can diverge one theme's rule without touching the other's.
enum FlightDeckText {
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

/// "Flight Deck" — an avionics annunciator-panel theme (EICAS-style cockpit
/// instrument), built up across four slices.
///
/// AB-314 (flightdeck 4/4) closes the theme: the actionable interiors move into
/// the Flight Deck idiom — the permission request becomes the MASTER CAUTION
/// alarm (a full-width chamfered block with a pulsing caution glow, a stenciled
/// `MASTER CAUTION` / `PERMISSION REQUIRED` header, and chamfered ALLOW / DENY
/// switches carrying the real ⌘Y / ⌘⇧Y / ⌘N key hints), the question reuses the
/// shared `StructuredQuestionPromptView`, and the completion is a chamfered mono
/// card — all drawn by `FlightDeckSessionRow` / `FlightDeckApprovalCard`.
///
/// AB-311 (flightdeck 1/4) ships the theme's shell: the token identity (a
/// near-black cockpit ground lit only by the phosphor status palette — cyan-green
/// nominal, muted blue complete, amber caution, warning red, dim grey idle — a
/// tightly-cut flat panel with no vibrancy or fillet, and a hard mechanical
/// snap), the mono typography roles, the theme's own square-annunciator-light
/// grid geometry, and the flat closed pill (`FlightDeckClosedPill`).
///
/// AB-312 (flightdeck 2/4) restyles the opened chrome: the header renders usage
/// as 12-tick segmented gauges with numeric readouts and CRIT / CAUT / NOM
/// placards and switches the controls to panel switches (`FlightDeckHeaderControls`
/// / `FlightDeckUsageSummary`); the session-list summary becomes a strip of
/// annunciator tiles (ATTN / RUN / DONE / IDLE, lit when non-zero) over a
/// SESSION / MODEL / APP / TIME column-caption strip, with section headers for
/// all four grouping modes and a BRIDGE LINK footer wired to the live bridge
/// socket (`FlightDeckSessionListScaffold`), and the empty / bootstrap / install
/// states move into squared hairline panels. The session rows still reuse
/// Classic's flat views until AB-313 restyles them onto the column grid.
///
/// Registered but **not** the default — Poured Island stays the product's face.
struct FlightDeckTheme: IslandTheme {

    // MARK: Identity

    let id = "flightDeck"

    func name(_ lang: LanguageManager) -> String {
        lang.t("theme.flightDeck.name")
    }

    func descriptor(_ lang: LanguageManager) -> String {
        lang.t("theme.flightDeck.descriptor")
    }

    // MARK: Styling

    var tokens: IslandThemeTokens { .flightDeck }

    // MARK: Capability flags

    /// The shell's rows are still Classic's flat views, which are safe to
    /// rasterize. A later slice that adds glow/motion to the annunciator rows can
    /// flip this alongside that change.
    let rowIsDrawingGroupSafe = true

    /// Flight Deck is unlit hardware, not glass: the opened surface takes the
    /// opaque `surfaceInk` path (`OpenedSurfaceBackground` never builds a vibrancy
    /// view), which also makes Reduce Transparency a no-op for this theme.
    let usesVibrancy = false

    // MARK: Geometry strategy

    /// Flight Deck reuses Classic's balanced matrix and cell/gap sizing (so the
    /// pill width math and morph frame are unchanged) but squares the corners into
    /// annunciator lights. Because the corner radius deviates, this is the theme's
    /// own strategy, pinned by `FlightDeckThemeTests` — Classic's
    /// `AgentsGridLayoutTests` are untouched.
    var agentsGridGeometry: IslandAgentsGridGeometry {
        IslandAgentsGridGeometry(
            balancedRows: { FlightDeckAgentsGrid.balancedRows($0) },
            cellGeometry: { FlightDeckAgentsGrid.cellGeometry(rowCount: $0) }
        )
    }

    // MARK: Slot factories

    /// The flat annunciator-panel closed pill (AB-311).
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
            FlightDeckClosedPill(
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

    // MARK: Flight Deck opened header + 12-tick gauge usage (AB-312)

    /// The opened header: usage as 12-tick segmented gauges with numeric readouts
    /// and CRIT / CAUT / NOM placards, and flat squared panel-switch control
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
            FlightDeckHeaderControls(
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

    // MARK: Flight Deck session row (AB-313 annunciator · AB-314 actionable)

    /// Session row — the annunciator re-skin (`FlightDeckSessionRow`): every
    /// non-actionable row carries a colored status lane on the SESSION / MODEL /
    /// APP / TIME column grid, and the actionable interiors are now drawn in the
    /// Flight Deck idiom too (AB-314) — the MASTER CAUTION alarm block for a
    /// permission request, the shared question prompt, and a chamfered mono
    /// completion card, all by `FlightDeckSessionRow`. The shared
    /// `IslandNotificationCard` inherits the treatment through this factory.
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
            FlightDeckSessionRow(
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

    /// Session list (AB-312) — the annunciator-tile summary strip, the SESSION /
    /// MODEL / APP / TIME column captions, the section headers for all four
    /// grouping modes, and a BRIDGE LINK footer wired to the live bridge socket.
    /// Rows inside it route through `sessionRow` above — Classic's flat row for
    /// the shell until AB-313 restyles the rows onto the column grid.
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
            FlightDeckSessionListScaffold(
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

    // MARK: Flight Deck empty / bootstrap / install states (AB-312)

    func emptyState(
        lang: LanguageManager,
        hasRecentSessions: Bool,
        workspaceCount: Int,
        installedAgentNames: [String]
    ) -> AnyView {
        // Flight Deck ignores `workspaceCount` / `installedAgentNames` — its
        // empty copy is unchanged.
        AnyView(FlightDeckEmptyState(lang: lang, hasRecentSessions: hasRecentSessions))
    }

    func bootstrapPlaceholder(lang: LanguageManager) -> AnyView {
        AnyView(FlightDeckBootstrapPlaceholder(lang: lang))
    }

    func installHint(lang: LanguageManager, onTap: @escaping () -> Void) -> AnyView {
        AnyView(FlightDeckInstallHooksHint(lang: lang, onTap: onTap))
    }
}
