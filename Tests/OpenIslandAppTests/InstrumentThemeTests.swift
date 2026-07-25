import Foundation
import SwiftUI
import Testing
@testable import OpenIslandApp
import OpenIslandCore

/// AB-307 (instrument 1/4): the Instrument theme's shell — registration, the
/// near-mono token identity, the flat-panel material, the mono typography floor,
/// and the theme's own squared-tick grid geometry.
///
/// Serialized and defaults-clearing like `ThemeSelectionTests`, since the
/// registry / persistence checks construct real `AppModel`s that read
/// `UserDefaults.standard`.
@MainActor
@Suite(.serialized)
struct InstrumentThemeTests {
    private static let themeKey = "appearance.island.v8.theme"

    init() {
        UserDefaults.standard.removeObject(forKey: Self.themeKey)
    }

    // MARK: - Registration (AC #1)

    @Test
    func instrumentIsRegisteredAndSelectableButNotDefault() {
        #expect(ThemeRegistry.all.contains { $0.id == "instrument" })
        #expect(ThemeRegistry.theme(id: "instrument").id == "instrument")
        // Poured stays the product's face; Instrument is registered, not default.
        #expect(ThemeRegistry.default.id != "instrument")
    }

    @Test
    func selectingInstrumentResolvesTheLiveTheme() {
        let model = AppModel()
        model.islandThemeID = "instrument"
        #expect(model.islandTheme.id == "instrument")
        #expect(model.islandTheme.tokens == .instrument)
    }

    @Test
    func instrumentRoundTripsThroughDefaults() {
        let model = AppModel()
        model.islandThemeID = "instrument"
        let reloaded = AppModel()
        #expect(reloaded.islandThemeID == "instrument")
        #expect(reloaded.islandTheme.id == "instrument")
    }

    // MARK: - Palette (AC #2)

    @Test
    func statusPaletteSpendsColourOnlyOnStatus() {
        let colors = IslandThemeTokens.instrument.colors

        // Run and done share one "live" green.
        #expect(colors.statusRunning == colors.statusCompleted)
        // Approval and failure share one alarm red.
        #expect(colors.statusWaitingForApproval == colors.statusFailed)
        // The softer waiting/interrupted states share the caution amber.
        #expect(colors.statusWaitingForAnswer == colors.statusInterrupted)
        #expect(colors.statusWarning == colors.statusInterrupted)
        // Idle drops to a dim grey derived from the mono ink, distinct from the
        // three status hues.
        #expect(colors.statusIdle != colors.statusRunning)
        #expect(colors.statusIdle != colors.statusWaitingForApproval)
    }

    @Test
    func hairlineIsStrongerThanClassicAndRisesUnderIncreaseContrast() {
        let colors = IslandThemeTokens.instrument.colors
        // Hairline rules are a load-bearing part of the instrument look.
        #expect(colors.hairlineOpacity > IslandThemeTokens.classic.colors.hairlineOpacity)
        // Increase Contrast raises the hairline and the dim-text opacities.
        #expect(colors.hairline(increaseContrast: true) > colors.hairline(increaseContrast: false))
        #expect(colors.secondaryTextOpacityIncreasedContrast > colors.secondaryTextOpacity)
    }

    // MARK: - Flat panel material (AC #3 · #6)

    @Test
    func instrumentIsAFlatPanelWithoutVibrancy() {
        let theme = InstrumentTheme()
        // Flat instrument surface — no vibrancy, so the opened surface takes the
        // opaque `surfaceInk` path and Reduce Transparency is a no-op.
        #expect(theme.usesVibrancy == false)
        // No specular edge, and a fully opaque ink fallback even if vibrancy were
        // ever forced on.
        #expect(theme.tokens.material.specularTopEdge == nil)
        #expect(theme.tokens.material.tintOpacity == 1.0)
    }

    @Test
    func squaredChromeMorphsWithoutAPouredFillet() {
        let metrics = InstrumentTheme().tokens.metrics
        // Squared-off, not soft: smaller opened radii than Classic's 22pt.
        #expect(metrics.openedTopRadius < IslandThemeTokens.classic.metrics.openedTopRadius)
        // No "poured" fillet — the plain concave top corner (the Classic path).
        #expect(metrics.filletRadius == 0)
        // Shadow insets are at least Classic's, so the panel never clips chrome.
        #expect(metrics.openedShadowHorizontalInset >= IslandChromeMetrics.openedShadowHorizontalInset)
        #expect(metrics.openedShadowBottomInset >= IslandChromeMetrics.openedShadowBottomInset)
    }

    // MARK: - Mono typography floor (AC #2)

    @Test
    func everyReadableTypographyRoleHoldsTheTenPointFloor() {
        #expect(InstrumentTypography.floor == 10)
        #expect(!InstrumentTypography.readableRoleSizes.isEmpty)
        for size in InstrumentTypography.readableRoleSizes {
            #expect(size >= InstrumentTypography.floor)
        }
    }

    // MARK: - Own squared-tick grid geometry (AC #6)

    @Test
    func gridGeometryReusesClassicMatrixButSquaresTheTicks() {
        let geometry = InstrumentTheme().agentsGridGeometry

        // Balanced matrix and cell/gap sizing are Classic's verbatim, so the
        // pill width math and morph frame are unchanged.
        for n in 0...20 {
            #expect(geometry.balancedRows(n) == V6RightSlotView.balancedRows(n))
        }
        for rowCount in 1...3 {
            let strategy = geometry.cellGeometry(rowCount)
            let statics = V6RightSlotView.cellGeometry(rowCount: rowCount)
            #expect(strategy.cell == statics.cell)
            #expect(strategy.gap == statics.gap)
            // ...but the ticks are squared (radius 0), a deliberate deviation
            // from Classic's rounded tiles.
            #expect(strategy.radius == 0)
            #expect(strategy.radius != statics.radius)
        }
    }

    // MARK: - Capability flags

    @Test
    func shellRowsStayDrawingGroupSafe() {
        // The shell reuses Classic's flat rows, which are safe to rasterize.
        #expect(InstrumentTheme().rowIsDrawingGroupSafe == true)
    }

    // MARK: - Tick-meter usage colour + tag bands (AB-308 AC #1)

    @Test
    func tickMeterColoursBandOnTheExactUsageCutoffs() {
        // `>= 90` red, `70..<90` orange, else green — the same cut-offs the app
        // ships in `IslandUsageSummary`; the theme must not drift.
        #expect(InstrumentUsageWindowMeter.usageColor(for: 99) == Color.red.opacity(0.95))
        #expect(InstrumentUsageWindowMeter.usageColor(for: 90) == Color.red.opacity(0.95))
        #expect(InstrumentUsageWindowMeter.usageColor(for: 89.9) == Color.orange.opacity(0.95))
        #expect(InstrumentUsageWindowMeter.usageColor(for: 70) == Color.orange.opacity(0.95))
        #expect(InstrumentUsageWindowMeter.usageColor(for: 69.9) == Color.green.opacity(0.95))
        #expect(InstrumentUsageWindowMeter.usageColor(for: 7) == Color.green.opacity(0.95))
    }

    @Test
    func tickMeterTagsBandOnTheSameCutoffsAsTheColour() {
        // A red meter always reads CRIT, an orange one HIGH, a green one OK.
        #expect(InstrumentUsageWindowMeter.tag(for: 99) == .crit)
        #expect(InstrumentUsageWindowMeter.tag(for: 90) == .crit)
        #expect(InstrumentUsageWindowMeter.tag(for: 89.9) == .high)
        #expect(InstrumentUsageWindowMeter.tag(for: 70) == .high)
        #expect(InstrumentUsageWindowMeter.tag(for: 69.9) == .ok)
        #expect(InstrumentUsageWindowMeter.tag(for: 0) == .ok)
    }

    // MARK: - Uppercase micro-labels neutralize for CJK (AB-308 AC #5)

    @Test
    func uppercaseMicroLabelsNeutralizeForCJK() {
        let originalLanguage = UserDefaults.standard.string(forKey: "appLanguage")
        defer {
            if let originalLanguage {
                UserDefaults.standard.set(originalLanguage, forKey: "appLanguage")
            } else {
                UserDefaults.standard.removeObject(forKey: "appLanguage")
            }
        }

        let en = LanguageManager()
        en.language = .en
        // Latin: uppercased and letterspaced — the precision instrument look.
        #expect(en.usesCJKScript == false)
        #expect(InstrumentText.caps("sessions", lang: en) == "SESSIONS")
        #expect(InstrumentText.tracking(1.4, lang: en) == 1.4)

        // CJK: passed through uncased and untracked so Han glyphs (which have no
        // case) are never pried apart into illegibility.
        let zhHans = LanguageManager()
        zhHans.language = .zhHans
        #expect(zhHans.usesCJKScript == true)
        #expect(InstrumentText.caps("会话", lang: zhHans) == "会话")
        #expect(InstrumentText.tracking(1.4, lang: zhHans) == 0)

        let zhHant = LanguageManager()
        zhHant.language = .zhHant
        #expect(zhHant.usesCJKScript == true)
        #expect(InstrumentText.tracking(0.9, lang: zhHant) == 0)
    }
}
