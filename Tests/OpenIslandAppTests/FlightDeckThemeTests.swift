import Foundation
import SwiftUI
import Testing
@testable import OpenIslandApp
import OpenIslandCore

/// AB-311 (flightdeck 1/4): the Flight Deck theme's shell — registration, the
/// phosphor annunciator token identity, the flat-panel material, the mono
/// typography floor, and the theme's own square-annunciator-light grid geometry.
///
/// Serialized and defaults-clearing like `ThemeSelectionTests` /
/// `InstrumentThemeTests`, since the registry / persistence checks construct real
/// `AppModel`s that read `UserDefaults.standard`.
@MainActor
@Suite(.serialized)
struct FlightDeckThemeTests {
    private static let themeKey = "appearance.island.v8.theme"

    init() {
        UserDefaults.standard.removeObject(forKey: Self.themeKey)
    }

    // MARK: - Registration (AC #1)

    @Test
    func flightDeckIsRegisteredAndSelectableButNotDefault() {
        #expect(ThemeRegistry.all.contains { $0.id == "flightDeck" })
        #expect(ThemeRegistry.theme(id: "flightDeck").id == "flightDeck")
        // Poured stays the product's face; Flight Deck is registered, not default.
        #expect(ThemeRegistry.default.id != "flightDeck")
    }

    @Test
    func selectingFlightDeckResolvesTheLiveTheme() {
        let model = AppModel()
        model.islandThemeID = "flightDeck"
        #expect(model.islandTheme.id == "flightDeck")
        #expect(model.islandTheme.tokens == .flightDeck)
    }

    @Test
    func flightDeckRoundTripsThroughDefaults() {
        let model = AppModel()
        model.islandThemeID = "flightDeck"
        let reloaded = AppModel()
        #expect(reloaded.islandThemeID == "flightDeck")
        #expect(reloaded.islandTheme.id == "flightDeck")
    }

    // MARK: - Phosphor palette (AC #2)

    @Test
    func statusPaletteIsTheFourPhosphorLightsPlusWarningRed() {
        let colors = IslandThemeTokens.flightDeck.colors

        // Nominal (running) and complete (done) are held apart — the EICAS
        // distinction between a "live" light and a completed advisory. This is a
        // deliberate divergence from Instrument, which collapses them to one green.
        #expect(colors.statusRunning != colors.statusCompleted)
        // The softer waiting / interrupted states share the amber caution.
        #expect(colors.statusWaitingForAnswer == colors.statusInterrupted)
        #expect(colors.statusWarning == colors.statusInterrupted)
        // The loudest states share one warning red: a blocked permission and a
        // failure outcome.
        #expect(colors.statusWaitingForApproval == colors.statusFailed)
        // Caution amber and warning red are distinct lights, and neither is the
        // nominal green.
        #expect(colors.statusWaitingForAnswer != colors.statusWaitingForApproval)
        #expect(colors.statusWaitingForApproval != colors.statusRunning)
        #expect(colors.statusWaitingForAnswer != colors.statusRunning)
        // Idle drops to a dim grey derived from the legend ink, distinct from
        // every status light.
        #expect(colors.statusIdle != colors.statusRunning)
        #expect(colors.statusIdle != colors.statusCompleted)
        #expect(colors.statusIdle != colors.statusWaitingForApproval)
        #expect(colors.statusIdle != colors.statusWaitingForAnswer)
    }

    @Test
    func hairlineIsStrongerThanClassicAndRisesUnderIncreaseContrast() {
        let colors = IslandThemeTokens.flightDeck.colors
        // The panel's bezels and rules are load-bearing hardware.
        #expect(colors.hairlineOpacity > IslandThemeTokens.classic.colors.hairlineOpacity)
        // Increase Contrast raises the hairline and the dim-text opacities.
        #expect(colors.hairline(increaseContrast: true) > colors.hairline(increaseContrast: false))
        #expect(colors.secondaryTextOpacityIncreasedContrast > colors.secondaryTextOpacity)
    }

    // MARK: - Flat panel material (AC #3 · #6)

    @Test
    func flightDeckIsAFlatPanelWithoutVibrancy() {
        let theme = FlightDeckTheme()
        // Flat annunciator surface — no vibrancy, so the opened surface takes the
        // opaque `surfaceInk` path and Reduce Transparency is a no-op.
        #expect(theme.usesVibrancy == false)
        // No specular edge, and a fully opaque ink fallback even if vibrancy were
        // ever forced on.
        #expect(theme.tokens.material.specularTopEdge == nil)
        #expect(theme.tokens.material.tintOpacity == 1.0)
    }

    @Test
    func chamferedChromeMorphsWithoutAPouredFillet() {
        let metrics = FlightDeckTheme().tokens.metrics
        // Tightly-cut chamfer, not soft: smaller opened radii than Classic's 22pt.
        #expect(metrics.openedTopRadius < IslandThemeTokens.classic.metrics.openedTopRadius)
        // No "poured" fillet — the plain concave top corner (the Classic path),
        // so the panel still merges cleanly from the physical notch.
        #expect(metrics.filletRadius == 0)
        // Shadow insets are at least Classic's, so the panel never clips chrome.
        #expect(metrics.openedShadowHorizontalInset >= IslandChromeMetrics.openedShadowHorizontalInset)
        #expect(metrics.openedShadowBottomInset >= IslandChromeMetrics.openedShadowBottomInset)
    }

    // MARK: - Mono typography floor (AC #2)

    @Test
    func everyReadableTypographyRoleHoldsTheTenPointFloor() {
        #expect(FlightDeckTypography.floor == 10)
        #expect(!FlightDeckTypography.readableRoleSizes.isEmpty)
        for size in FlightDeckTypography.readableRoleSizes {
            #expect(size >= FlightDeckTypography.floor)
        }
    }

    // MARK: - Own square-annunciator-light grid geometry (AC #6)

    @Test
    func gridGeometryReusesClassicMatrixButSquaresTheLights() {
        let geometry = FlightDeckTheme().agentsGridGeometry

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
            // ...but the lamps are squared (radius 0), a deliberate deviation from
            // Classic's rounded tiles.
            #expect(strategy.radius == 0)
            #expect(strategy.radius != statics.radius)
        }
    }

    // MARK: - Capability flags

    @Test
    func shellRowsStayDrawingGroupSafe() {
        // The shell reuses Classic's flat rows, which are safe to rasterize.
        #expect(FlightDeckTheme().rowIsDrawingGroupSafe == true)
    }

    // MARK: - Uppercase micro-labels neutralize for CJK

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
        // Latin: uppercased and letterspaced — the precision annunciator look.
        #expect(en.usesCJKScript == false)
        #expect(FlightDeckText.caps("sessions", lang: en) == "SESSIONS")
        #expect(FlightDeckText.tracking(1.4, lang: en) == 1.4)

        // CJK: passed through uncased and untracked so Han glyphs (which have no
        // case) are never pried apart into illegibility.
        let zhHans = LanguageManager()
        zhHans.language = .zhHans
        #expect(zhHans.usesCJKScript == true)
        #expect(FlightDeckText.caps("会话", lang: zhHans) == "会话")
        #expect(FlightDeckText.tracking(1.4, lang: zhHans) == 0)

        let zhHant = LanguageManager()
        zhHant.language = .zhHant
        #expect(zhHant.usesCJKScript == true)
        #expect(FlightDeckText.tracking(0.9, lang: zhHant) == 0)
    }

    // MARK: - 12-tick gauge colour + placard bands (AB-312 AC #1)

    @Test
    func tickGaugeColoursBandOnTheExactUsageCutoffs() {
        // `>= 90` red, `70..<90` orange, else green — the same cut-offs the app
        // ships in `IslandUsageSummary`; the theme must not drift. Screenshot
        // points 99% (CRIT/red) and 7% (NOM/green) are covered by the endpoints.
        #expect(FlightDeckUsageWindowGauge.usageColor(for: 99) == Color.red.opacity(0.95))
        #expect(FlightDeckUsageWindowGauge.usageColor(for: 90) == Color.red.opacity(0.95))
        #expect(FlightDeckUsageWindowGauge.usageColor(for: 89.9) == Color.orange.opacity(0.95))
        #expect(FlightDeckUsageWindowGauge.usageColor(for: 70) == Color.orange.opacity(0.95))
        #expect(FlightDeckUsageWindowGauge.usageColor(for: 69.9) == Color.green.opacity(0.95))
        #expect(FlightDeckUsageWindowGauge.usageColor(for: 7) == Color.green.opacity(0.95))
    }

    @Test
    func tickGaugePlacardsBandOnTheSameCutoffsAsTheColour() {
        // A red gauge always reads CRIT, an orange one CAUT, a green one NOM.
        #expect(FlightDeckUsageWindowGauge.placard(for: 99) == .crit)
        #expect(FlightDeckUsageWindowGauge.placard(for: 90) == .crit)
        #expect(FlightDeckUsageWindowGauge.placard(for: 89.9) == .caut)
        #expect(FlightDeckUsageWindowGauge.placard(for: 70) == .caut)
        #expect(FlightDeckUsageWindowGauge.placard(for: 69.9) == .nom)
        #expect(FlightDeckUsageWindowGauge.placard(for: 0) == .nom)
    }

    @Test
    func tickGaugeIsTwelveSegments() {
        // The ticket pins a 12-tick segmented gauge.
        #expect(FlightDeckTickGauge(fraction: 0.5, color: .green, isCritical: false).segments == 12)
    }

    // MARK: - Theme name / descriptor localize (AC #1)

    @Test
    func themeNameAndDescriptorLocalizeInEveryLanguage() {
        let originalLanguage = UserDefaults.standard.string(forKey: "appLanguage")
        defer {
            if let originalLanguage {
                UserDefaults.standard.set(originalLanguage, forKey: "appLanguage")
            } else {
                UserDefaults.standard.removeObject(forKey: "appLanguage")
            }
        }

        let theme = FlightDeckTheme()
        for language in [LanguageManager.AppLanguage.en, .zhHans, .zhHant] {
            let manager = LanguageManager()
            manager.language = language
            let name = theme.name(manager)
            let descriptor = theme.descriptor(manager)
            #expect(!name.isEmpty)
            #expect(name != "theme.flightDeck.name", "name is unlocalized in \(language)")
            #expect(!descriptor.isEmpty)
            #expect(descriptor != "theme.flightDeck.descriptor", "descriptor is unlocalized in \(language)")
        }
    }
}
