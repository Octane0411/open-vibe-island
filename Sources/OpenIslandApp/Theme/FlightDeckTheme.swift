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

/// Flight Deck's layered surface hierarchy (AB-335).
///
/// SPEC-flight-deck §1a declares a whole EICAS surface stack the shipped theme
/// never had a name for — an opened panel body *lighter* than the cockpit
/// ground, explicit tile / hover / recessed-well tones, a cool blue-grey
/// hairline base with three tiers, and dim / faint legend inks. Like
/// `FlightDeckTypography`, this is a **theme-local** paint table, deliberately
/// kept out of the shared `IslandColorTokens` layer: those tokens are the
/// cross-theme contract (surfaceInk, paper, the status palette, the single
/// `hairlineOpacity`), and Flight Deck's near-black tile/well tones and its
/// `#9AB0BC` hairline recolor are *its* paint, not values any other theme
/// consumes. The shared `flightDeck` colour tokens (`surfaceInk` #08090A ground,
/// `hairlineOpacity` 0.13) are untouched by this enum — the closed pill and the
/// cockpit ground still draw from them.
///
/// Every constant is pinned by `FlightDeckThemeTests` with exact 8-bit
/// component equality so a drift in any tone fails the build. Later FD tickets
/// (T17–T20) build their glow, gauges and sub-panels on these tones instead of
/// ad-hoc paper washes.
enum FlightDeckSurfaces {

    // MARK: Surface tones (opaque near-blacks)

    /// The opened panel body — a distinct tone *lighter* than the `surfaceInk`
    /// cockpit ground, so the opened surface reads as a lit panel seated over
    /// the darker ground. (SPEC `--surface`.)
    static let panel = Color(red: 0x0E / 255.0, green: 0x11 / 255.0, blue: 0x13 / 255.0)

    /// Tiles / sub-panels — the summary annunciator tiles, the completion card,
    /// the engine cluster (T20). One step above the panel body. (SPEC
    /// `--surface-2`.)
    static let tile = Color(red: 0x10 / 255.0, green: 0x15 / 255.0, blue: 0x19 / 255.0)

    /// Raised / hovered surface — a lit row or tile on pointer hover, replacing
    /// the shipped `paper.opacity(0.05)` hover wash. (SPEC `--surface-hi`.)
    static let hover = Color(red: 0x16 / 255.0, green: 0x1C / 255.0, blue: 0x22 / 255.0)

    /// Recessed wells — code / command boxes, the diff area, and the tape
    /// tracks (T19). *Darker* than the ground so the content reads as sunk into
    /// the panel, not raised off a light wash. (SPEC `--well`.)
    static let well = Color(red: 0x06 / 255.0, green: 0x07 / 255.0, blue: 0x08 / 255.0)

    // MARK: Hairline tiers

    /// The cool blue-grey hairline base (SPEC `#9AB0BC`) — the recolor of the
    /// shipped `paper`-derived rules into the instrument's cool bezel grey.
    /// FD-local paint: the shared `hairlineOpacity` token (0.13) still governs
    /// every rule that draws from `paper`; this base + tiers are the new avionics
    /// bezel palette the panel's tiers draw from.
    static let hairlineBase = Color(red: 0x9A / 255.0, green: 0xB0 / 255.0, blue: 0xBC / 255.0)

    /// Faint rules (row / section dividers). (SPEC `--hair`.)
    static let hairlineTier1Opacity: Double = 0.14
    /// Bezel housings — lamp housings, tile frames. (SPEC `--hair2`.) Replaces
    /// the shipped inline `hairlineOpacity * 2`.
    static let hairlineTier2Opacity: Double = 0.26
    /// Strong bezels / gauge ticks (consumed by T19). (SPEC `--hair3`.)
    static let hairlineTier3Opacity: Double = 0.40

    /// The Increase-Contrast brightening applied to a hairline tier, mirroring
    /// the shared token's `hairlineOpacity 0.13 → 0.32` lift (≈ +0.19) so the FD
    /// tiers strengthen under Increase Contrast exactly as the shared rules do.
    static let hairlineIncreasedContrastBoost: Double = 0.19

    /// Tier-1 hairline colour (row / section dividers).
    static var hairline1: Color { hairlineBase.opacity(hairlineTier1Opacity) }
    /// Tier-2 hairline colour (bezel housings).
    static var hairline2: Color { hairlineBase.opacity(hairlineTier2Opacity) }
    /// Tier-3 hairline colour (strong bezels / ticks).
    static var hairline3: Color { hairlineBase.opacity(hairlineTier3Opacity) }

    /// A hairline tier, brightened under Increase Contrast per the shared
    /// token's IC pattern. `tier` is 1…3; out-of-range clamps to tier 1.
    static func hairline(tier: Int, increaseContrast: Bool = false) -> Color {
        let base: Double
        switch tier {
        case 2: base = hairlineTier2Opacity
        case 3: base = hairlineTier3Opacity
        default: base = hairlineTier1Opacity
        }
        let opacity = increaseContrast ? min(1, base + hairlineIncreasedContrastBoost) : base
        return hairlineBase.opacity(opacity)
    }

    // MARK: Legend inks

    /// Dim legend ink (SPEC `--dim #8A97A0`) — an explicit cooler grey for
    /// de-emphasised-but-informative labels, replacing `paper.opacity(0.6)`
    /// derivations. Available for T18's type/column split.
    static let dimInk = Color(red: 0x8A / 255.0, green: 0x97 / 255.0, blue: 0xA0 / 255.0)

    /// Faint legend ink (SPEC `--faint #5B656C`) — the dimmest legible tier,
    /// replacing `paper.opacity(0.5)` derivations. Available for T18.
    static let faintInk = Color(red: 0x5B / 255.0, green: 0x65 / 255.0, blue: 0x6C / 255.0)
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

    /// AB-336: the row status lane is now a self-lit phosphor lamp whose halo
    /// bleeds *outside* the row silhouette (breathe halo to 11pt, the success
    /// settle flash to 18pt). A `.drawingGroup()` off-screen render flattens the
    /// row to its own bounds and would clip that out-of-bounds bleed — the same
    /// reason Poured is drawing-group-unsafe — so the row opts out of the
    /// rasterization Classic's flat views can take. (Flight Deck's own row does
    /// not currently apply `ConditionalDrawingGroup`, so this is a truthful
    /// capability declaration: any shared rasterization path that consults it must
    /// not flatten these rows.)
    let rowIsDrawingGroupSafe = false

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

    /// The closed-pill attention bloom seam (AB-336). Folds the spotlight into
    /// `FlightDeckPillBloom`; for the two attention states (held permission /
    /// open question) it returns the `FlightDeckClosedGlow` seam so the coloured
    /// bloom bleeds *outside* the morph's content clip (mockup `.attn-perm` /
    /// `.attn-caut`). Every other state casts no glow — `nil`, the flat-hardware
    /// default — so the closed-surface render tree stays byte-identical there.
    func closedSurfaceGlow(
        mode: UnifiedBars.Mode,
        rightSlot: IslandRightSlotContent?,
        activity: IslandClosedPillActivity?,
        width: CGFloat,
        height: CGFloat
    ) -> AnyView? {
        guard let bloom = FlightDeckPillBloom.resolve(activity: activity, mode: mode, rightSlot: rightSlot) else {
            return nil
        }
        return AnyView(FlightDeckClosedGlow(bloom: bloom, width: width, height: height))
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
