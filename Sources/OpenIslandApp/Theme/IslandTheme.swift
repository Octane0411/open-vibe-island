import AppKit
import SwiftUI
import OpenIslandCore

/// A complete visual identity for the island overlay.
///
/// The theme-arch series (AB-293…298) moved styling into `IslandThemeTokens`,
/// routed every overlay surface through those tokens, formalized `RowActions`
/// and the hover container, and extracted the panel-shell surfaces into
/// standalone slot components. This protocol is the capstone (AB-299): it
/// gathers those tokens, the capability flags and grid strategy, and a factory
/// per slot into one type, so `IslandPanelView` composes the overlay purely
/// from `@Environment(\.islandTheme)` and never names a concrete component.
/// After this, a new theme is "implement the protocol + register it".
///
/// **Granularity.** The Scope for AB-299 lists the theme's slots more finely
/// than there are seams in the view tree — e.g. "sessions summary", "section
/// header" and "footer" are the three regions of the one `sessionList` slot,
/// and "approval / question / completion body" are the actionable bodies drawn
/// inside the one `sessionRow` slot. Each factory below therefore owns a group
/// of Scope slots, noted in its doc comment; a theme controls a bundled slot by
/// swapping the factory that renders it. The shared invariants that are *not*
/// theme-swappable (presentation/display rules, `RowActions` wiring, keyboard
/// shortcuts, hover container, accessibility gates, the attention-is-loudest
/// hierarchy) live in `SessionState` / `AgentSession+Presentation` / the slot
/// components and are documented in `docs/architecture.md`.
///
/// `@MainActor` because every factory builds SwiftUI views; the identity,
/// tokens and capability flags are read on the main actor too (overlay render,
/// panel sizing, Settings). Conformers are stateless value types, so they stay
/// `Sendable` and can be handed around freely.
@MainActor
protocol IslandTheme: Sendable {

    // MARK: Identity

    /// Stable identifier persisted to `UserDefaults` and used for registry
    /// lookup. Never localized — it's data, not display text.
    var id: String { get }

    /// Localized display name (e.g. "Classic"), resolved through `lang.t`.
    func name(_ lang: LanguageManager) -> String

    /// Localized one-line descriptor shown under the name in the picker.
    func descriptor(_ lang: LanguageManager) -> String

    // MARK: Styling

    /// The colour / metric / motion tokens injected into `\.islandTokens` for
    /// every descendant surface.
    var tokens: IslandThemeTokens { get }

    // MARK: Capability flags

    /// Whether this theme's rows are safe to rasterize with `.drawingGroup()`.
    /// Classic returns `true`; blur/glow themes that would be flattened by the
    /// off-screen render return `false`, and `IslandSessionRow` drops the
    /// `ConditionalDrawingGroup` accordingly.
    var rowIsDrawingGroupSafe: Bool { get }

    /// Whether the opened surface draws a native vibrancy base. Classic returns
    /// `true`; a flat-ink theme returns `false` and the surface falls back to a
    /// solid fill (the same path Reduce Transparency already takes).
    var usesVibrancy: Bool { get }

    // MARK: Geometry strategy

    /// The closed-island agents-grid geometry. Classic delegates to the
    /// `V6RightSlotView` statics pinned by `AgentsGridLayoutTests`, which encode
    /// Classic's shape rather than a universal invariant, so a theme can supply
    /// its own matrix.
    var agentsGridGeometry: IslandAgentsGridGeometry { get }

    // MARK: Slot factories

    /// Closed-pill content, including the agents-grid right slot.
    /// (Scope: closed-pill content, agents-grid style.)
    func closedPill(
        mode: UnifiedBars.Mode,
        label: String?,
        rightSlot: IslandRightSlotContent?,
        layout: V6ClosedLayout,
        height: CGFloat,
        physicalNotchWidth: CGFloat,
        minWidth: CGFloat,
        showsGlyph: Bool
    ) -> AnyView

    /// The opened panel's header row: usage chips plus the mute / settings /
    /// quit controls. (Scope: opened header, usage chip.)
    func openedHeader(
        providers: [UsageProviderPresentation],
        usesNotchAwareLayout: Bool,
        targetScreen: NSScreen?,
        isSoundMuted: Bool,
        lang: LanguageManager,
        onToggleMute: @escaping () -> Void,
        onShowSettings: @escaping () -> Void,
        onQuit: @escaping () -> Void
    ) -> AnyView

    /// One session row, including the approval / question / completion
    /// actionable bodies drawn inside it. (Scope: session row, approval body,
    /// question body, completion body.)
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
    ) -> AnyView

    /// The full grouped session list: overview header, sections, rows, footer.
    /// (Scope: sessions summary, section header, footer.)
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
    ) -> AnyView

    /// The single-session card shown when a notification opened the notch.
    /// (Scope: notification-card chrome.)
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
    ) -> AnyView

    /// Shown in the opened panel when there are no sessions to list.
    /// (Scope: empty state.)
    ///
    /// `workspaceCount` is the number of distinct workspaces across the current
    /// and recent sessions — supplied so a theme can tailor its empty copy
    /// ("no live sessions across N workspaces" vs. a cold "start an agent").
    /// The shipped themes ignore it (zero visual change); it exists as a seam
    /// for the redesign themes (AB-326).
    func emptyState(lang: LanguageManager, hasRecentSessions: Bool, workspaceCount: Int) -> AnyView

    /// Shown while the app is still probing terminals on a cold launch.
    /// (Scope: bootstrap placeholder.)
    func bootstrapPlaceholder(lang: LanguageManager) -> AnyView

    /// The "install hooks" hint shown while no agent hooks are installed.
    /// (Scope: install hint.)
    func installHint(lang: LanguageManager, onTap: @escaping () -> Void) -> AnyView
}

/// The closed-island agents-grid geometry a theme supplies. Expressed as plain
/// functions (rather than a subclass) so Classic can delegate straight to the
/// `V6RightSlotView` statics, which stay the single implementation the layout
/// math and `AgentsGridLayoutTests` share.
struct IslandAgentsGridGeometry {
    /// Per-row cell counts for `n` sessions (the hand-tuned balanced matrix).
    var balancedRows: (Int) -> [Int]

    /// Cell size / gap / corner radius for a matrix with `rowCount` rows.
    var cellGeometry: (Int) -> (cell: CGFloat, gap: CGFloat, radius: CGFloat)
}

// MARK: - Environment

private struct IslandThemeKey: EnvironmentKey {
    static let defaultValue: any IslandTheme = ClassicTheme()
}

extension EnvironmentValues {
    /// The active island theme.
    ///
    /// Defaults to `ClassicTheme` — the look Open Island ships today — so a
    /// view that reads this without an explicit injection renders unchanged,
    /// mirroring `\.islandTokens`. `IslandPanelView` injects the model's active
    /// theme (and its `tokens`) at the overlay root.
    var islandTheme: any IslandTheme {
        get { self[IslandThemeKey.self] }
        set { self[IslandThemeKey.self] = newValue }
    }
}
