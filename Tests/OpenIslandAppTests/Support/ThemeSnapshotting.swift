import AppKit
import OpenIslandCore
import SnapshotTesting
import SwiftUI
import XCTest

@testable import OpenIslandApp

/// Deterministic theme-conformance snapshot harness (AB-327 / draft T09).
///
/// The three redesign specs all call for per-scenario golden pins so a theme
/// slice can prove it renders the shared fixtures the way the mockups say it
/// should. This helper turns a `(theme, slot, profile, scenario)` tuple into a
/// pixel image and pins it against a committed golden, using
/// `pointfreeco/swift-snapshot-testing` for the golden store / diff / record
/// machinery (test-target-only dependency).
///
/// ## Determinism contract
///
/// Every knob that could leak run-to-run variance is nailed down:
///
/// - **Frozen fixtures.** Sessions come from ``AppearancePreviewFixtures`` (AB-326),
///   which is fully `now`-injected — a given `now` yields byte-identical model
///   values. `now` is captured once per render (``renderImage(theme:slot:profile:)``).
/// - **Stable age strings.** The live rows still read wall-clock `Date()` for
///   their relative-age badges (`AgentSession.spotlightAgeBadge` → `.now`, and
///   `IslandSessionRow`'s per-row `TimelineView(.periodic(from: .now …))`). We
///   can't inject that clock, so instead `now` is set to *the current wall clock*
///   and the fixtures' offsets are chosen to sit safely inside a coarse age
///   bucket (`<1m`, `1m`, `2m`, `25m` — never within ~30s of a `60s` boundary).
///   The rendered *string* is therefore identical across runs even though the
///   raw `Date` differs. See `docs/quality.md`.
/// - **No motion.** `\.accessibilityReduceMotion` is forced on, and the render
///   captures the model layer (not the presentation layer), so no CoreAnimation
///   phase — the running-bars wave, the waiting-tile pulse — can bleed into the
///   bitmap. No `PulseClock` is supplied, so the animated-dot indicator is static.
/// - **No vibrancy.** `reduceTransparency` is forced, so the opened surface is a
///   flat `surfaceInk` fill instead of an `NSVisualEffectView` (whose window-server
///   blur is neither deterministic nor available off-window).
/// - **Fixed appearance + scale.** The hosting view is pinned to
///   `NSAppearance(named: .darkAqua)` and rasterized at an explicit 2× into a
///   bitmap we own, never the host screen's backing scale.
///
/// ## Environment fingerprint
///
/// Even with all of the above, a golden recorded on one macOS build is not
/// guaranteed to be byte-identical on another (font smoothing, Core Text, GPU).
/// So each golden directory carries an ``environmentFingerprint`` sidecar; when
/// the runtime fingerprint doesn't match the recorded one, the pixel comparison
/// is **skipped** (`XCTSkip`) rather than failed. This keeps CI green on a
/// differently-rendering runner while still enforcing an exact pin on a matching
/// machine. The image is always rendered first, so a slot that crashes or fails
/// to build still fails loudly everywhere.
@MainActor
enum ThemeSnapshotting {

    // MARK: - Profile

    /// The two panel geometries the overlay ships. `width` is the fixed hosting
    /// width the ticket pins (540pt notch / 520pt top-bar); `sideInset` and
    /// `closedLayout` are the matching row inset and closed-pill layout so a
    /// snapshot is faithful to how the real overlay lays that profile out.
    enum Profile: String, Sendable {
        case notch
        case topBar

        var width: CGFloat { self == .notch ? 540 : 520 }
        var sideInset: CGFloat { self == .notch ? 46 : 16 }
        var closedLayout: V6ClosedLayout { self == .notch ? .macbook : .external }
        var displayProfile: IslandAppearanceDisplayProfile { self == .notch ? .notch : .topBar }
    }

    // MARK: - Slot

    /// Which theme slot to render, plus the scenario/fixture that feeds it. New
    /// theme tickets extend this enum (or add profiles) rather than hand-rolling
    /// a parallel render path.
    enum Slot: Sendable {
        /// The closed-island pill in a given activity mode with a given right
        /// slot. Rendered at intrinsic size on a neutral dark backdrop.
        case closedPill(mode: UnifiedBars.Mode, rightSlot: IslandRightSlotContent?)

        /// The full opened session list for an ``AppearancePreviewScenario``,
        /// drawn inside the real opened-surface chrome (flat, reduce-transparency
        /// fill) — the same slot the Settings appearance preview exercises.
        case sessionList(scenario: AppearancePreviewScenario)

        var descriptor: String {
            switch self {
            case .closedPill: return "closedPill"
            case .sessionList(let scenario): return "sessionList.\(scenario.rawValue)"
            }
        }
    }

    // MARK: - Public API

    /// Renders `slot` through `theme` at `profile` and pins the pixels against a
    /// committed golden named `name`.
    ///
    /// The golden lives under `<testFile>/__Snapshots__/<TestFile>/` per
    /// swift-snapshot-testing convention (pass `file` / `testName` from the call
    /// site so the path lands next to the test). The comparison is gated on the
    /// environment fingerprint: on a non-matching macOS build it is skipped, not
    /// failed. Set `record` (or `OPEN_ISLAND_RECORD_SNAPSHOTS=1`) to (re)record.
    ///
    /// - Parameters:
    ///   - theme: the `IslandTheme` under test (e.g. `ClassicTheme()`).
    ///   - slot: which slot + scenario to draw (see ``Slot``).
    ///   - profile: panel geometry — `.notch` (540pt) or `.topBar` (520pt).
    ///   - name: golden identifier, stable across runs.
    ///   - record: force re-record. Defaults to the `OPEN_ISLAND_RECORD_SNAPSHOTS` env flag.
    static func assertSnapshot(
        theme: any IslandTheme,
        slot: Slot,
        profile: Profile,
        named name: String,
        record: Bool = ThemeSnapshotting.isRecording,
        file: StaticString = #filePath,
        testName: String = #function,
        line: UInt = #line
    ) throws {
        // 1. Always render — this exercises the slot's view code on every runner,
        //    so a crash or build regression fails loudly even where the pixel
        //    comparison would be skipped.
        let image = renderImage(theme: theme, slot: slot, profile: profile)
        XCTAssertGreaterThan(
            image.size.width, 0,
            "Rendered a zero-width image for \(name)",
            file: file, line: line
        )

        // 2. Gate the pixel comparison on the environment fingerprint.
        let runtime = environmentFingerprint()
        let fingerprintURL = fingerprintSidecarURL(file: file)

        if record {
            try? writeFingerprint(runtime, to: fingerprintURL)
        } else if let recorded = readFingerprint(from: fingerprintURL), recorded != runtime {
            throw XCTSkip(
                """
                Snapshot pixel comparison skipped for "\(name)": environment fingerprint mismatch.
                  recorded: \(recorded)
                  runtime:  \(runtime)
                Goldens are byte-exact pins; a different macOS build / arch / scale renders
                differently. Re-record on this environment (OPEN_ISLAND_RECORD_SNAPSHOTS=1) only
                if you intend to move the pin. See docs/quality.md.
                """
            )
        }

        // 3. Delegate the diff / record / attachment machinery to the library.
        SnapshotTesting.assertSnapshot(
            of: image,
            as: .image(precision: 1, perceptualPrecision: 1),
            named: name,
            record: record ? .all : .never,
            file: file,
            testName: testName,
            line: line
        )
    }

    /// Whether recording is on for this run (`OPEN_ISLAND_RECORD_SNAPSHOTS=1`).
    static var isRecording: Bool {
        ProcessInfo.processInfo.environment["OPEN_ISLAND_RECORD_SNAPSHOTS"] == "1"
    }

    // MARK: - Rendering

    /// Deterministically rasterizes a slot to a 2× dark-appearance `NSImage`.
    /// Exposed (not just used by ``assertSnapshot(theme:slot:profile:named:record:file:testName:line:)``)
    /// so later tickets can pull the raw image for a bespoke assertion.
    static func renderImage(
        theme: any IslandTheme,
        slot: Slot,
        profile: Profile
    ) -> NSImage {
        // Wall-clock `now`: keeps the fixtures' relative-age strings inside their
        // stable buckets (see the type doc). Everything downstream of this is a
        // pure function of `now`.
        let now = Date()
        let lang = Self.englishLanguageManager()

        switch slot {
        case .closedPill(let mode, let rightSlot):
            let pill = V6ClosedPill(
                mode: mode,
                label: nil,
                rightSlot: rightSlot,
                layout: profile.closedLayout,
                physicalNotchWidth: profile.closedLayout == .macbook ? 180 : 0
            )
            .padding(20)
            .background(Color(white: 0.055))
            .themedSnapshotEnvironment(theme: theme)

            return rasterize(pill, width: nil)

        case .sessionList(let scenario):
            let content = AppearancePreviewFixtures.scenarioContent(scenario, now: now, lang: lang)
            let prefs = IslandAppearancePreferences()
            let sections = IslandSessionSectioning.sections(
                for: content.sessions,
                group: prefs.sessionGroup,
                sort: prefs.sessionSort,
                completedStaleThreshold: prefs.completedStaleThreshold.seconds,
                now: now
            )

            let panel = SnapshotSessionListPanel(
                profile: profile,
                sessions: content.sessions,
                sections: sections,
                group: prefs.sessionGroup,
                stateIndicator: prefs.sessionStateIndicator,
                completedStaleThreshold: prefs.completedStaleThreshold.seconds,
                actionableSessionID: content.actionableSessionID,
                usageProviders: content.usageProviders,
                // Deterministic installed-agents set so Poured's empty-state
                // reassurance pill renders identically every run (AB-331).
                installedAgentNames: ["Claude", "Codex", "Gemini"],
                lang: lang
            )
            .themedSnapshotEnvironment(theme: theme)

            return rasterize(panel, width: profile.width)
        }
    }

    /// Renders a SwiftUI view into a bitmap we fully control: forced dark
    /// appearance, explicit 2× scale, no dependency on the host screen. When
    /// `width` is `nil` the view is sized to its intrinsic fit (used for the
    /// closed pill); otherwise the width is pinned and the height is intrinsic.
    private static func rasterize(_ view: some View, width: CGFloat?) -> NSImage {
        let scale: CGFloat = 2

        let host = NSHostingView(rootView: AnyView(view))
        host.appearance = NSAppearance(named: .darkAqua)

        // Size the host: fixed width + intrinsic height, or fully intrinsic.
        if let width {
            host.frame = NSRect(x: 0, y: 0, width: width, height: 5_000)
            host.layoutSubtreeIfNeeded()
            let fitting = host.fittingSize
            host.frame = NSRect(x: 0, y: 0, width: width, height: max(1, ceil(fitting.height)))
        } else {
            host.layoutSubtreeIfNeeded()
            let fitting = host.fittingSize
            host.frame = NSRect(
                x: 0, y: 0,
                width: max(1, ceil(fitting.width)),
                height: max(1, ceil(fitting.height))
            )
        }

        // Realize the view tree in an offscreen window so SwiftUI instantiates
        // every representable (e.g. the pill's `UnifiedBars` glyph) before capture.
        let window = NSWindow(
            contentRect: host.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = host
        window.appearance = NSAppearance(named: .darkAqua)
        host.layoutSubtreeIfNeeded()

        let bounds = host.bounds
        let pixelsWide = Int((bounds.width * scale).rounded())
        let pixelsHigh = Int((bounds.height * scale).rounded())

        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: pixelsWide,
            pixelsHigh: pixelsHigh,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else {
            return NSImage(size: bounds.size)
        }
        // Point size < pixel size ⇒ the caching draw renders at 2×.
        rep.size = bounds.size

        host.cacheDisplay(in: bounds, to: rep)

        let image = NSImage(size: bounds.size)
        image.addRepresentation(rep)
        return image
    }

    // MARK: - Environment fingerprint

    /// A coarse identity of the render environment. Two machines that share this
    /// string are expected to rasterize the same view to the same bytes; two that
    /// don't are not, so the comparison is skipped across the boundary.
    static func environmentFingerprint() -> String {
        let os = ProcessInfo.processInfo.operatingSystemVersionString // "Version X (Build …)"
        let arch: String
        #if arch(arm64)
        arch = "arm64"
        #elseif arch(x86_64)
        arch = "x86_64"
        #else
        arch = "unknown"
        #endif
        return "macos=\(os) arch=\(arch) scale=2x"
    }

    private static func fingerprintSidecarURL(file: StaticString) -> URL {
        let fileURL = URL(fileURLWithPath: "\(file)", isDirectory: false)
        let fileName = fileURL.deletingPathExtension().lastPathComponent
        return fileURL
            .deletingLastPathComponent()
            .appendingPathComponent("__Snapshots__", isDirectory: true)
            .appendingPathComponent(fileName, isDirectory: true)
            .appendingPathComponent("environment-fingerprint.txt", isDirectory: false)
    }

    private static func readFingerprint(from url: URL) -> String? {
        guard let raw = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func writeFingerprint(_ value: String, to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try (value + "\n").write(to: url, atomically: true, encoding: .utf8)
    }

    // MARK: - Localization

    /// A LanguageManager pinned to English so golden text never drifts with the
    /// runner's locale.
    private static func englishLanguageManager() -> LanguageManager {
        let lang = LanguageManager()
        if lang.language != .en {
            lang.language = .en
        }
        return lang
    }
}

// MARK: - Themed environment

private extension View {
    /// Injects the theme, its tokens, a forced dark scheme, and disables the
    /// initial transaction's animations — the environment a slot reads at the
    /// overlay root.
    ///
    /// Reduce Motion is deliberately *not* injected here: the two shipped
    /// motion sources are CoreAnimation layers (the pill's `UnifiedBars` wave,
    /// the agents-grid waiting-tile pulse), and the capture reads the *model*
    /// layer, never the animating presentation layer — so no animation phase can
    /// reach the bitmap regardless of the Reduce Motion flag. `disablesAnimations`
    /// covers the SwiftUI-level implicit animations for good measure.
    func themedSnapshotEnvironment(theme: any IslandTheme) -> some View {
        self
            .environment(\.islandTheme, theme)
            .environment(\.islandTokens, theme.tokens)
            .environment(\.colorScheme, .dark)
            .transaction { $0.disablesAnimations = true }
    }
}

// MARK: - Session-list panel

/// The opened session-list surface, rebuilt for the harness from the same parts
/// `AppearanceSessionListPreview` composes (that one is `private` to the app
/// target). `reduceTransparency` is hard-forced so the surface is a flat
/// `surfaceInk` fill — the deterministic, window-server-independent path.
@MainActor
private struct SnapshotSessionListPanel: View {
    let profile: ThemeSnapshotting.Profile
    let sessions: [AgentSession]
    let sections: [IslandSessionSection]
    let group: IslandSessionGroup
    let stateIndicator: IslandSessionStateIndicator
    let completedStaleThreshold: TimeInterval
    let actionableSessionID: String?
    let usageProviders: [UsageProviderPresentation]?
    let installedAgentNames: [String]
    let lang: LanguageManager

    @Environment(\.islandTheme) private var theme
    @Environment(\.islandTokens) private var tokens

    var body: some View {
        let shape = OpenedIslandSurfaceShape(
            topProfile: profile == .notch ? .notch : .topBar,
            topCornerRadius: tokens.metrics.openedTopRadius,
            bottomCornerRadius: tokens.metrics.openedBottomRadius,
            filletRadius: tokens.metrics.filletRadius
        )

        return ZStack(alignment: .top) {
            // Forced reduce-transparency ⇒ flat opaque fill, no NSVisualEffectView.
            OpenedSurfaceBackground(reduceTransparency: true)
                .clipShape(shape)

            VStack(spacing: 0) {
                if let usageProviders {
                    theme.openedHeader(
                        providers: usageProviders,
                        usesNotchAwareLayout: false,
                        targetScreen: nil,
                        isSoundMuted: false,
                        lang: lang,
                        onToggleMute: {},
                        onShowSettings: {},
                        onQuit: {}
                    )
                    .padding(.top, profile == .notch ? 34 : 10)
                    .padding(.bottom, 4)

                    // AB-331: exercise the theme's §I full-meter surface in the
                    // `meters` snapshot (Poured returns the card; others `nil`).
                    if let meterCard = theme.usageMeterCard(providers: usageProviders, lang: lang) {
                        meterCard
                            .padding(.horizontal, profile.sideInset)
                            .padding(.bottom, 8)
                    }
                }

                if sessions.isEmpty {
                    theme.emptyState(
                        lang: lang,
                        hasRecentSessions: false,
                        workspaceCount: 0,
                        installedAgentNames: installedAgentNames
                    )
                        .frame(minHeight: 120)
                        .padding(.vertical, 12)
                } else {
                    theme.sessionList(
                        sessions: sessions,
                        sections: sections,
                        group: group,
                        stateIndicator: stateIndicator,
                        completedStaleThreshold: completedStaleThreshold,
                        sideInset: profile.sideInset,
                        isInteractive: true,
                        actionableSessionID: actionableSessionID,
                        lang: lang,
                        keyboardCoordinator: nil,
                        pulseClock: nil,
                        makeActions: { _ in RowActions(jump: {}) }
                    )
                }
            }
            .clipShape(shape)
            .overlay { shape.stroke(Color.white.opacity(0.07), lineWidth: 1) }
        }
        .frame(width: profile.width)
        .fixedSize(horizontal: false, vertical: true)
    }
}
