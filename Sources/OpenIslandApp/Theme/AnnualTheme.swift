import AppKit
import SwiftUI
import OpenIslandCore

/// Typography roles for the Annual theme.
///
/// The shared `IslandThemeTokens` layer deliberately carries no typography —
/// themes swap whole slot views, so per-view fonts belong to each theme. This
/// enum is Annual's own small type table, kept in one place so every Annual view
/// draws from the same roles and the type floor is enforceable in one spot
/// (`AnnualThemeTests`).
///
/// Annual is a Swiss editorial theme: its readable labels are a quiet
/// **lowercase monospace** (the mono grid is the theme's structural rhythm), and
/// its signature is an **oversized light numeral** — the hero figure a usage
/// readout or a session count is set in. That numeral role is defined here now,
/// in the shell, even though the header that spends it lands in the next slice
/// (AB-316), so the type scale is complete and pinned from the start. No readable
/// role dips below `floor`; the closed-grid overflow "+N" is a fitted
/// micro-indicator sized to its square rather than a readable role, so it is not
/// listed here.
enum AnnualTypography {
    /// The lowest size any *readable* Annual text may use. Editorial calm comes
    /// from scale, weight, case and whitespace — never from sub-10pt micro-type.
    static let floor: CGFloat = 10

    static let microLabelSize: CGFloat = 10
    static let labelSize: CGFloat = 11
    static let countSize: CGFloat = 11
    static let bodySize: CGFloat = 12
    /// The oversized light-numeral role — the editorial hero figure (a usage
    /// percentage, a session count). Large and set in a light weight so the
    /// figure reads as a display numeral rather than body text; consumed by the
    /// header in AB-316.
    static let numeralSize: CGFloat = 34

    /// Every readable role's point size — the vector `AnnualThemeTests` asserts
    /// stays at or above `floor` (the oversized numeral included: it is large,
    /// never small).
    static var readableRoleSizes: [CGFloat] {
        [microLabelSize, labelSize, countSize, bodySize, numeralSize]
    }

    /// Lowercase letterspaced micro-labels (section captions, unit tags).
    static let microLabel = Font.system(size: microLabelSize, weight: .medium, design: .monospaced)

    /// Standard quiet mono label (closed-pill labels, chip text).
    static let label = Font.system(size: labelSize, weight: .regular, design: .monospaced)

    /// The count badge in the closed pill's right slot.
    static let count = Font.system(size: countSize, weight: .regular, design: .monospaced)

    /// Body copy inside the opened panel.
    static let body = Font.system(size: bodySize, weight: .regular, design: .monospaced)

    /// The oversized light numeral, built at `numeralSize` in a light weight.
    static let numeral = Font.system(size: numeralSize, weight: .light, design: .default)
}

/// Hairline weights for the Annual theme.
///
/// Annual builds hierarchy from hairline rules, not from fills or chrome. The
/// design language calls for two weights — a `hairline` for ordinary dividers
/// and structure, and a `rule` at double the weight for the load-bearing
/// separators (a section rule, an emphasis underline). They live here as named
/// constants so every Annual view draws the same two weights and the 1px / 2px
/// pair is pinned in one spot (`AnnualThemeTests`).
enum AnnualHairline {
    /// The 1px ordinary hairline — row and structure dividers, the closed-pill
    /// bezel.
    static let hairline: CGFloat = 1
    /// The 2px emphasis rule — the load-bearing separators.
    static let rule: CGFloat = 2
}

/// Script-aware helpers for Annual's quiet lowercase labels.
///
/// The editorial idiom sets Latin labels in `lowercase` with a hair of
/// `.tracking()`. Lowercasing is meaningful only on cased (Latin) scripts — Han
/// has no case — and letterspacing pries CJK glyphs apart into noise. Every
/// Annual label routes its casing and tracking through these two helpers so the
/// neutralization lives in one place and is pinned by `AnnualThemeTests`.
/// Mirrors Flight Deck's `FlightDeckText` (which uppercases); kept per-theme so
/// the two rules can diverge without touching each other.
enum AnnualText {
    /// Lowercases Latin strings; passes CJK through unchanged. Note that
    /// `String.lowercased()` already lowercases only cased characters and leaves
    /// Han untouched, so this helper is for the fully-translated *micro-labels*
    /// where a CJK translation should be skipped wholesale; free-form activity
    /// labels lowercase per-character instead (see `AnnualCenterLabelView`).
    static func lower(_ string: String, lang: LanguageManager) -> String {
        lang.usesCJKScript ? string : string.lowercased()
    }

    /// The letterspacing for a lowercase micro-label — `base` on Latin,
    /// neutralized to `0` on CJK.
    static func tracking(_ base: CGFloat, lang: LanguageManager) -> CGFloat {
        lang.usesCJKScript ? 0 : base
    }
}

/// "Annual" — an editorial Swiss typographic theme, built up across four slices.
///
/// AB-315 (annual 1/4) ships the theme's shell: the token identity (a warm
/// near-black ground and warm off-white ink, a warm grayscale secondary scale,
/// and **one** orange-red accent reserved exclusively for attention and critical
/// states — so a calm state carries zero accent pixels apart from the agent brand
/// squares), the typography roles including the oversized light numeral, the 1px
/// / 2px hairline weights, the theme's own square-brand-mark grid geometry, and
/// the quiet closed pill (`AnnualClosedPill`). The design forbids any
/// pill / chip / capsule: hierarchy comes from type scale, weight, case and
/// hairline rules, agent identity is only a 6px colored square, and status reads
/// through three dot grammars (filled = running, ring = done, dim = idle,
/// pulsing accent = attention).
///
/// Later slices restyle the opened surfaces — the oversized-numeral header,
/// summary and list states (AB-316), the session rows (AB-317), and the
/// actionable interiors (AB-318) — into the same editorial idiom. Until they do,
/// each un-restyled slot falls back to the shared Classic component through the
/// factories below, exactly like the other themes' first slice did; those
/// fallbacks already read the Annual tokens from the environment, so they inherit
/// the warm ground, the calm palette and the stronger hairlines for free.
///
/// Registered but **not** the default — Poured Island stays the product's face.
struct AnnualTheme: IslandTheme {

    // MARK: Identity

    let id = "annual"

    func name(_ lang: LanguageManager) -> String {
        lang.t("theme.annual.name")
    }

    func descriptor(_ lang: LanguageManager) -> String {
        lang.t("theme.annual.descriptor")
    }

    // MARK: Styling

    var tokens: IslandThemeTokens { .annual }

    // MARK: Capability flags

    /// The shell's rows are still Classic's flat views, which are safe to
    /// rasterize. A later slice that adds motion to the editorial rows can flip
    /// this alongside that change.
    let rowIsDrawingGroupSafe = true

    /// Annual is a printed page, not glass: the opened surface takes the opaque
    /// `surfaceInk` path (`OpenedSurfaceBackground` never builds a vibrancy
    /// view), which also makes Reduce Transparency a no-op for this theme.
    let usesVibrancy = false

    // MARK: Geometry strategy

    /// Annual reuses Classic's balanced matrix and cell/gap sizing (so the pill
    /// width math and the closed↔opened morph frame are unchanged) but squares
    /// the cells' corners into the design's 6px brand marks. Because the corner
    /// radius deviates from Classic, this is the theme's own strategy, pinned by
    /// `AnnualThemeTests` — Classic's `AgentsGridLayoutTests` are untouched.
    var agentsGridGeometry: IslandAgentsGridGeometry {
        IslandAgentsGridGeometry(
            balancedRows: { AnnualAgentsGrid.balancedRows($0) },
            cellGeometry: { AnnualAgentsGrid.cellGeometry(rowCount: $0) }
        )
    }

    // MARK: Slot factories

    /// The quiet editorial closed pill (AB-315).
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
            AnnualClosedPill(
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

    // MARK: Fallback slots (restyled in AB-316 · AB-317 · AB-318)

    /// Opened header — falls back to the shared control row until AB-316 brings
    /// the oversized-numeral usage header. It already reads the Annual tokens, so
    /// it renders on the warm ground with the calm palette.
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

    /// Session row — falls back to the shared row until AB-317 typesets the rows
    /// on Annual's editorial dot grammar.
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

    /// Session list — falls back to the shared scaffold until AB-316 brings the
    /// editorial summary and section structure.
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
