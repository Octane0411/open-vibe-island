import Testing
@testable import OpenIslandApp

struct OrbitSurfaceStyleTests {
    @Test
    func polarQuietKeepsDecorationOffByDefault() {
        #expect(OrbitSurfaceStyle.defaultStarfieldEnabled == false)
    }

    @Test
    func starDensityIsOrderedAndBounded() {
        #expect(OrbitStarDensity.sparse.starCount < OrbitStarDensity.balanced.starCount)
        #expect(OrbitStarDensity.balanced.starCount < OrbitStarDensity.vivid.starCount)
        #expect(OrbitStarDensity.vivid.starCount <= 54)
    }

    @Test
    func starDensityHasStableSettingsKeys() {
        #expect(OrbitStarDensity.sparse.titleKey == "settings.appearance.starfield.sparse")
        #expect(OrbitStarDensity.balanced.titleKey == "settings.appearance.starfield.balanced")
        #expect(OrbitStarDensity.vivid.titleKey == "settings.appearance.starfield.vivid")
    }
}
