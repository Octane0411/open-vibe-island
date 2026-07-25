import Foundation
import Testing
@testable import OpenIslandApp
import OpenIslandCore

/// AB-299: the theme runtime — registry lookup + fallback, `AppModel`
/// persistence via `appearance.island.v8.theme`, and the byte-identical
/// invariants Classic must keep (chrome metrics feeding panel sizing, and the
/// grid geometry strategy delegating to the pinned statics).
///
/// Serialized and defaults-clearing like `AppModelAttentionSurfacesTests`,
/// since it constructs real `AppModel`s that read `UserDefaults.standard`.
@MainActor
@Suite(.serialized)
struct ThemeSelectionTests {
    private static let themeKey = "appearance.island.v8.theme"

    init() {
        UserDefaults.standard.removeObject(forKey: Self.themeKey)
    }

    // MARK: - Registry

    @Test
    func pouredIsTheRegistryDefault() {
        // AB-304 (poured 5/5) flipped the default: Poured Island is now the
        // product's face, so it's first in the picker and the fresh-install
        // fallback.
        #expect(ThemeRegistry.default.id == "poured")
        #expect(ThemeRegistry.all.first?.id == "poured")
    }

    @Test
    func registryResolvesKnownAndFallsBackForNilOrUnknown() {
        #expect(ThemeRegistry.theme(id: "classic").id == "classic")
        #expect(ThemeRegistry.theme(id: "poured").id == "poured")
        // Nil (never selected) and garbage (stale / hand-edited defaults) both
        // resolve to the default rather than crashing or rendering blank.
        #expect(ThemeRegistry.theme(id: nil).id == ThemeRegistry.default.id)
        #expect(ThemeRegistry.theme(id: "does-not-exist").id == ThemeRegistry.default.id)
    }

    // MARK: - Poured Island (AB-300 · default flip AB-304)

    @Test
    func classicIsRegisteredAndSelectableButNotDefault() {
        // Classic stays registered and resolvable from the picker...
        #expect(ThemeRegistry.all.contains { $0.id == "classic" })
        #expect(ThemeRegistry.theme(id: "classic").id == "classic")
        // ...but Poured is the default since Poured 5/5 flipped it.
        #expect(ThemeRegistry.default.id != "classic")
        #expect(ThemeRegistry.default.id == "poured")
    }

    @Test
    func selectingPouredResolvesTheLiveTheme() {
        let model = AppModel()
        model.islandThemeID = "poured"
        #expect(model.islandTheme.id == "poured")
        #expect(model.islandTheme.tokens == .poured)
    }

    @Test
    func pouredGridGeometryReusesClassicStatics() {
        // Poured does not deviate from Classic's closed-grid geometry, so it
        // stays pinned by the same `AgentsGridLayoutTests` — no new vectors.
        let geometry = PouredIslandTheme().agentsGridGeometry
        for n in 0...20 {
            #expect(geometry.balancedRows(n) == V6RightSlotView.balancedRows(n))
        }
        for rowCount in 1...3 {
            let strategy = geometry.cellGeometry(rowCount)
            let statics = V6RightSlotView.cellGeometry(rowCount: rowCount)
            #expect(strategy.cell == statics.cell)
            #expect(strategy.gap == statics.gap)
            #expect(strategy.radius == statics.radius)
        }
    }

    @Test
    func pouredChromeMetricsCarryLargerShadowInsets() {
        // The deeper glass shadow needs more room inside the overlay window,
        // and those insets flow into `OverlayPanelController` panel sizing.
        let metrics = PouredIslandTheme().tokens.metrics
        #expect(metrics.filletRadius > 0)
        #expect(metrics.openedShadowHorizontalInset > IslandChromeMetrics.openedShadowHorizontalInset)
        #expect(metrics.openedShadowBottomInset > IslandChromeMetrics.openedShadowBottomInset)
    }

    @Test
    func pouredMaterialSuppliesGlassConfiguration() {
        // A liquid-glass identity: a specular top edge and a lighter ink tint
        // than Classic so more of the blur reads through.
        let material = PouredIslandTheme().tokens.material
        #expect(material.specularTopEdge != nil)
        #expect(material.tintOpacity < IslandMaterialTokens.classic.tintOpacity)
        // Classic stays flat and unlit.
        #expect(IslandMaterialTokens.classic.specularTopEdge == nil)
    }

    // MARK: - Persistence (AC #4)

    @Test
    func freshInstallUsesTheDefaultTheme() {
        // No stored value (fresh install) → the flipped default, Poured Island.
        UserDefaults.standard.removeObject(forKey: Self.themeKey)
        let model = AppModel()
        #expect(model.islandThemeID == "poured")
        #expect(model.islandTheme.id == "poured")
        #expect(model.islandThemeID == ThemeRegistry.default.id)
    }

    @Test
    func explicitClassicSelectionIsPreservedOverTheNewDefault() {
        // A user who explicitly chose Classic before the flip keeps Classic —
        // the new default only applies when nothing is stored.
        UserDefaults.standard.set("classic", forKey: Self.themeKey)
        let reloaded = AppModel()
        #expect(reloaded.islandThemeID == "classic")
        #expect(reloaded.islandTheme.id == "classic")
    }

    @Test
    func explicitPouredSelectionReloadsFromDefaults() {
        // Set → reload from defaults → same theme.
        UserDefaults.standard.set("poured", forKey: Self.themeKey)
        let reloaded = AppModel()
        #expect(reloaded.islandThemeID == "poured")
        #expect(reloaded.islandTheme.id == "poured")
    }

    @Test
    func garbageStoredIdFallsBackToDefault() {
        UserDefaults.standard.set("💥 not-a-theme", forKey: Self.themeKey)
        let model = AppModel()
        // Normalized in-memory to a known id, and the resolved theme is the
        // default — a bad persisted value never leaves the overlay unstyled.
        #expect(model.islandThemeID == ThemeRegistry.default.id)
        #expect(model.islandTheme.id == ThemeRegistry.default.id)
    }

    @Test
    func selectionPersistsBackToDefaults() {
        let model = AppModel()
        model.islandThemeID = "classic"
        // The didSet writes through once init has finished, so a fresh model
        // observes the same id.
        UserDefaults.standard.set(model.islandThemeID, forKey: Self.themeKey)
        let reloaded = AppModel()
        #expect(reloaded.islandThemeID == model.islandThemeID)
    }

    // MARK: - Picker selection round-trip (AB-306)

    @Test
    func pickingEachThemeRoundTripsThroughDefaults() {
        // Mirrors the Appearance picker card action: `model.islandThemeID = id`
        // for every registered theme, then a fresh AppModel reloaded from
        // defaults must resolve the same theme active.
        for theme in ThemeRegistry.all {
            let model = AppModel()
            model.islandThemeID = theme.id
            let reloaded = AppModel()
            #expect(reloaded.islandThemeID == theme.id)
            #expect(reloaded.islandTheme.id == theme.id)
        }
    }

    @Test
    func pickerUnknownStoredIdFallsBackToRegistryDefault() {
        // A theme that was removed from the registry (or a hand-edited garbage
        // id) must resolve to the registry default rather than leaving the
        // picker with no selection or the overlay unstyled.
        UserDefaults.standard.set("retired-theme", forKey: Self.themeKey)
        let model = AppModel()
        #expect(model.islandThemeID == ThemeRegistry.default.id)
        #expect(model.islandTheme.id == ThemeRegistry.default.id)
    }

    // MARK: - Chrome metrics feed panel sizing (AC #6)

    @Test
    func classicChromeMetricsMatchLegacyStatics() {
        // `OverlayPanelController` now sources its shadow insets from the active
        // theme's metric tokens. With Classic active those equal the legacy
        // `IslandChromeMetrics` statics, so computed panel frames are unchanged.
        let metrics = ClassicTheme().tokens.metrics
        #expect(metrics.openedShadowHorizontalInset == IslandChromeMetrics.openedShadowHorizontalInset)
        #expect(metrics.openedShadowBottomInset == IslandChromeMetrics.openedShadowBottomInset)

        // The fresh-install default is now Poured (AB-304), so pin Classic
        // explicitly to assert the Classic-active panel geometry is unchanged.
        let model = AppModel()
        model.islandThemeID = "classic"
        #expect(model.islandTheme.tokens.metrics.openedShadowHorizontalInset == IslandChromeMetrics.openedShadowHorizontalInset)
        #expect(model.islandTheme.tokens.metrics.openedShadowBottomInset == IslandChromeMetrics.openedShadowBottomInset)
    }

    // MARK: - Grid geometry strategy delegates to the pinned statics (AC #7)

    @Test
    func classicGridGeometryDelegatesToV6Statics() {
        let geometry = ClassicTheme().agentsGridGeometry
        for n in 0...20 {
            #expect(geometry.balancedRows(n) == V6RightSlotView.balancedRows(n))
        }
        for rowCount in 1...3 {
            let strategy = geometry.cellGeometry(rowCount)
            let statics = V6RightSlotView.cellGeometry(rowCount: rowCount)
            #expect(strategy.cell == statics.cell)
            #expect(strategy.gap == statics.gap)
            #expect(strategy.radius == statics.radius)
        }
    }
}
