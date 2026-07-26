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
    /// The oversized light-numeral role — the editorial hero figure (a session
    /// count in the summary). Large and set in a light weight so the figure reads
    /// as a display numeral rather than body text; spent by the sessions summary
    /// in AB-316.
    static let numeralSize: CGFloat = 34
    /// A scaled light numeral for the opened header's usage percentages. The
    /// header is height-capped to the physical notch (`closedNotchHeight`), so the
    /// full 34pt hero cannot fit there — the header spends this fitted light
    /// numeral, still oversized against the 10–11pt labels beside it, while the
    /// full `numeral` role stays the summary's hero figure.
    static let headerNumeralSize: CGFloat = 20

    /// Every readable role's point size — the vector `AnnualThemeTests` asserts
    /// stays at or above `floor` (the oversized numerals included: they are large,
    /// never small).
    static var readableRoleSizes: [CGFloat] {
        [microLabelSize, labelSize, countSize, bodySize, headerNumeralSize, numeralSize]
    }

    /// Lowercase letterspaced micro-labels (section captions, unit tags).
    static let microLabel = Font.system(size: microLabelSize, weight: .medium, design: .monospaced)

    /// The small-caps eyebrow role — verdicts, state labels and section titles set
    /// in true small capitals. Built on the `.default` design (whose SF face
    /// carries the small-caps OpenType feature) rather than the mono grid, so the
    /// caps actually render as small capitals; fed lowercased Latin through
    /// `AnnualText.lower`, it renders Latin as small caps and passes CJK through
    /// untouched (the feature is a no-op on Han).
    static let smallCaps = Font.system(size: microLabelSize, weight: .medium, design: .default).smallCaps()

    /// A slightly larger small-caps role for the summary's state labels.
    static let smallCapsLabel = Font.system(size: labelSize, weight: .medium, design: .default).smallCaps()

    /// Standard quiet mono label (closed-pill labels, chip text).
    static let label = Font.system(size: labelSize, weight: .regular, design: .monospaced)

    /// The count badge in the closed pill's right slot.
    static let count = Font.system(size: countSize, weight: .regular, design: .monospaced)

    /// Body copy inside the opened panel.
    static let body = Font.system(size: bodySize, weight: .regular, design: .monospaced)

    /// The oversized light numeral, built at `numeralSize` in a light weight.
    static let numeral = Font.system(size: numeralSize, weight: .light, design: .default)

    /// The header's fitted light numeral (`headerNumeralSize`), for the usage
    /// percentages that must sit inside the notch-height header row.
    static let headerNumeral = Font.system(size: headerNumeralSize, weight: .light, design: .default)
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
/// AB-316 (annual 2/4) restyles the opened chrome into the editorial idiom: the
/// header renders usage as fitted light numerals with small-caps
/// healthy / elevated / critical verdicts and 2px hairline meters, and swaps the
/// controls to quiet glyph buttons (`AnnualHeaderControls` / `AnnualUsageSummary`);
/// the sessions summary becomes a large light hero numeral over small-caps
/// state-label counts with hairline-ruled section headers for all four grouping
/// modes and a quiet footer (`AnnualSessionListScaffold`); and the empty /
/// bootstrap / install states are set purely typographically with no boxes or
/// pills (`AnnualEmptyState` / `AnnualBootstrapPlaceholder` /
/// `AnnualInstallHooksHint`). The accent still appears only on the critical usage
/// figure and on genuine attention states, never on a calm surface.
///
/// AB-317 (annual 3/4) typesets the **non-actionable** session rows on the dot
/// grammar (`AnnualSessionRow`): a workspace headline over a lowercase mono meta
/// line behind a 6px brand square, a single right-aligned time lane, filled /
/// ring / dim / accent-pulse status dots with an interrupted / failed glyph swap,
/// and a marginalia-rail expanded interior — all with zero pills and the accent
/// spent only on attention.
///
/// AB-318 (annual 4/4) — the final slice of the theme and the last ticket of the
/// whole theme program — replaces the last seam: the **actionable** interiors now
/// draw in the Annual editorial idiom (`AnnualActionableRowContent`). A permission
/// request is the typographic alarm — a 2px accent rule, a small-caps
/// `permission required` kicker, a left-ruled mono command quote, and understated
/// `allow` / `deny` text buttons carrying the real ⌘Y / ⌘⇧Y / ⌘N key-hints with
/// strong contrast on `allow` (`AnnualApprovalCard`); the question reuses the
/// shared, token-driven `StructuredQuestionPromptView`; and the completion is a
/// quiet editorial markdown card. The accent still appears only on the alarm and
/// the pending question — never on a completion or a calm surface. The
/// notification card needs no fork: `IslandNotificationCard` routes its single row
/// through `sessionRow(isActionable: true)`, so it inherits the same alarm.
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

    /// This flag only gates the shared Classic row body's off-screen rasterization
    /// (`ConditionalDrawingGroup` in `IslandSessionRow`). Annual's non-actionable
    /// rows are drawn by `AnnualSessionRow`, which never takes that path, and its
    /// actionable rows route to Classic with `isActionable == true` (which also
    /// bypasses it) — so the value is moot for Annual. Kept `true`, matching the
    /// other re-skinned themes (Instrument / Flight Deck).
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

    // MARK: Annual opened header + usage numerals (AB-316)

    /// The opened header: usage as fitted light numerals with small-caps
    /// verdicts and 2px hairline meters, and quiet glyph control buttons, on the
    /// shared notch-split / single-lane layout.
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
            AnnualHeaderControls(
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

    // MARK: Annual session rows (AB-317 · actionable AB-318)

    /// Session row — the editorial dot-grammar re-skin for the non-actionable
    /// states and the typographic alarm / question / completion surfaces for the
    /// actionable states (`AnnualSessionRow`); nothing routes to Classic anymore.
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
            AnnualSessionRow(
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

    /// Session list (AB-316) — the large-numeral sessions summary, the
    /// hairline-ruled small-caps section headers for all four grouping modes, the
    /// scrollable list of rows, and a quiet footer. Rows inside it route through
    /// `sessionRow` above — the editorial dot-grammar `AnnualSessionRow` (AB-317).
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
            AnnualSessionListScaffold(
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

    /// Notification card (AB-318) — the shared, theme-agnostic
    /// `IslandNotificationCard`, which routes its single actionable session through
    /// `sessionRow(isActionable: true)`. That means the card inherits Annual's
    /// typographic alarm / question / completion surfaces for free, with no
    /// card-specific fork; the "show all N" affordance and the auto-collapse
    /// behaviour are unchanged from the shared component.
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

    // MARK: Annual empty / bootstrap / install states (AB-316)

    func emptyState(
        lang: LanguageManager,
        hasRecentSessions: Bool,
        workspaceCount: Int,
        installedAgentNames: [String]
    ) -> AnyView {
        // Annual ignores `workspaceCount` / `installedAgentNames` — its empty
        // copy is unchanged.
        AnyView(AnnualEmptyState(lang: lang, hasRecentSessions: hasRecentSessions))
    }

    func bootstrapPlaceholder(lang: LanguageManager) -> AnyView {
        AnyView(AnnualBootstrapPlaceholder(lang: lang))
    }

    func installHint(lang: LanguageManager, onTap: @escaping () -> Void) -> AnyView {
        AnyView(AnnualInstallHooksHint(lang: lang, onTap: onTap))
    }
}
