import Foundation
import SwiftUI
import Testing
@testable import OpenIslandApp
import OpenIslandCore

/// AB-315 (annual 1/4): the Annual theme's shell — registration, the warm
/// editorial token identity, the one-accent discipline, the flat-page material,
/// the type scale (including the oversized light numeral), the 1px / 2px hairline
/// weights, and the theme's own square-brand-mark grid geometry.
///
/// Serialized and defaults-clearing like `ThemeSelectionTests` /
/// `FlightDeckThemeTests`, since the registry / persistence checks construct real
/// `AppModel`s that read `UserDefaults.standard`.
@MainActor
@Suite(.serialized)
struct AnnualThemeTests {
    private static let themeKey = "appearance.island.v8.theme"

    init() {
        UserDefaults.standard.removeObject(forKey: Self.themeKey)
    }

    // MARK: - Registration (AC #1)

    @Test
    func annualIsRegisteredAndSelectableButNotDefault() {
        #expect(ThemeRegistry.all.contains { $0.id == "annual" })
        #expect(ThemeRegistry.theme(id: "annual").id == "annual")
        // Poured stays the product's face; Annual is registered, not default.
        #expect(ThemeRegistry.default.id != "annual")
    }

    @Test
    func selectingAnnualResolvesTheLiveTheme() {
        let model = AppModel()
        model.islandThemeID = "annual"
        #expect(model.islandTheme.id == "annual")
        #expect(model.islandTheme.tokens == .annual)
    }

    @Test
    func annualRoundTripsThroughDefaults() {
        let model = AppModel()
        model.islandThemeID = "annual"
        let reloaded = AppModel()
        #expect(reloaded.islandThemeID == "annual")
        #expect(reloaded.islandTheme.id == "annual")
    }

    // MARK: - One-accent discipline (AC #2 · #6)

    /// The core Annual invariant: the theme carries exactly one accent, and it is
    /// spent only on attention (a blocked permission, a pending question, the
    /// collapsed waiting roll-up) and the one critical outcome (failure). Every
    /// calm / non-attention role resolves to a warm grey, never the accent — so a
    /// calm state contains zero accent pixels apart from the agent brand squares.
    /// This pins that discipline at the token level; the pixel screenshot check is
    /// flagged manual in the PR.
    @Test
    func accentIsSpentOnlyOnAttentionAndCriticalStates() {
        let colors = IslandThemeTokens.annual.colors
        let accent = IslandColorTokens.annualAccent

        // The three attention states share the one accent...
        #expect(colors.statusWaitingForApproval == accent)
        #expect(colors.statusWaitingForAnswer == accent)
        #expect(colors.statusWaitingAggregate == accent)
        // ...as does the single critical outcome, failure.
        #expect(colors.statusFailed == accent)

        // Every calm / non-attention role is grey, never the accent — the
        // accent-discipline guarantee for calm-state surfaces.
        #expect(colors.statusRunning != accent)
        #expect(colors.statusCompleted != accent)
        #expect(colors.statusIdle != accent)
        #expect(colors.statusInactive != accent)
        // A persistent bypass badge (statusWarning) and a soft interruption are
        // *not* attention, so they must not light the accent either.
        #expect(colors.statusWarning != accent)
        #expect(colors.statusInterrupted != accent)
    }

    /// The warm grayscale secondary scale keeps the calm states distinct from one
    /// another (running brighter than completed) so hierarchy survives even
    /// though colour is spent only on the accent.
    @Test
    func calmStatesUseADistinctWarmGrayscaleScale() {
        let colors = IslandThemeTokens.annual.colors
        #expect(colors.statusRunning != colors.statusCompleted)
        #expect(colors.statusIdle != colors.statusRunning)
        #expect(colors.statusIdle != colors.statusCompleted)
    }

    @Test
    func hairlineIsStrongerThanClassicAndRisesUnderIncreaseContrast() {
        let colors = IslandThemeTokens.annual.colors
        // Hairline rules are the theme's primary structural device.
        #expect(colors.hairlineOpacity > IslandThemeTokens.classic.colors.hairlineOpacity)
        // Increase Contrast raises the hairline and the dim-text opacities.
        #expect(colors.hairline(increaseContrast: true) > colors.hairline(increaseContrast: false))
        #expect(colors.secondaryTextOpacityIncreasedContrast > colors.secondaryTextOpacity)
    }

    // MARK: - Flat page material (AC #3 · #8)

    @Test
    func annualIsAFlatPageWithoutVibrancy() {
        let theme = AnnualTheme()
        // Flat editorial page — no vibrancy, so the opened surface takes the
        // opaque `surfaceInk` path and Reduce Transparency is a no-op.
        #expect(theme.usesVibrancy == false)
        // No specular edge, and a fully opaque ink fallback even if vibrancy were
        // ever forced on.
        #expect(theme.tokens.material.specularTopEdge == nil)
        #expect(theme.tokens.material.tintOpacity == 1.0)
    }

    @Test
    func quietChromeMorphsWithoutAPouredFillet() {
        let metrics = AnnualTheme().tokens.metrics
        // Calmly rounded, not soft-poured: smaller opened radii than Classic's 22pt.
        #expect(metrics.openedTopRadius < IslandThemeTokens.classic.metrics.openedTopRadius)
        // No "poured" fillet — the plain concave top corner (the Classic path),
        // so the panel still merges cleanly from the physical notch.
        #expect(metrics.filletRadius == 0)
        // Shadow insets are at least Classic's, so the panel never clips chrome.
        #expect(metrics.openedShadowHorizontalInset >= IslandChromeMetrics.openedShadowHorizontalInset)
        #expect(metrics.openedShadowBottomInset >= IslandChromeMetrics.openedShadowBottomInset)
    }

    // MARK: - Type scale + oversized numeral (AC #2)

    @Test
    func everyReadableTypographyRoleHoldsTheFloor() {
        #expect(AnnualTypography.floor == 10)
        #expect(!AnnualTypography.readableRoleSizes.isEmpty)
        for size in AnnualTypography.readableRoleSizes {
            #expect(size >= AnnualTypography.floor)
        }
    }

    @Test
    func theOversizedLightNumeralRoleIsDefinedAndLarge() {
        // The editorial hero figure is defined in the shell (spent by the header
        // in AB-316); it is an *oversized* role, well above body copy and the
        // readable floor.
        #expect(AnnualTypography.numeralSize > AnnualTypography.bodySize)
        #expect(AnnualTypography.numeralSize >= 28)
    }

    // MARK: - Hairline weights (AC #2)

    @Test
    func hairlineWeightsAreTheOnePixelAndTwoPixelPair() {
        #expect(AnnualHairline.hairline == 1)
        #expect(AnnualHairline.rule == 2)
        #expect(AnnualHairline.rule == AnnualHairline.hairline * 2)
    }

    // MARK: - Own square-brand-mark grid geometry (AC #7)

    @Test
    func gridGeometryReusesClassicMatrixButSquaresTheMarks() {
        let geometry = AnnualTheme().agentsGridGeometry

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
            // ...but the marks are squared (radius 0), a deliberate deviation from
            // Classic's rounded tiles — the design's 6px brand squares.
            #expect(strategy.radius == 0)
            #expect(strategy.radius != statics.radius)
        }
    }

    // MARK: - Capability flags

    @Test
    func shellRowsStayDrawingGroupSafe() {
        // The shell reuses Classic's flat rows, which are safe to rasterize.
        #expect(AnnualTheme().rowIsDrawingGroupSafe == true)
    }

    // MARK: - Lowercase labels neutralize for CJK (AC #4)

    @Test
    func lowercaseLabelsNeutralizeForCJK() {
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
        // Latin: lowercased and letterspaced — the quiet editorial look.
        #expect(en.usesCJKScript == false)
        #expect(AnnualText.lower("Sessions", lang: en) == "sessions")
        #expect(AnnualText.tracking(0.6, lang: en) == 0.6)

        // CJK: passed through uncased and untracked so Han glyphs (which have no
        // case) are never touched or pried apart.
        let zhHans = LanguageManager()
        zhHans.language = .zhHans
        #expect(zhHans.usesCJKScript == true)
        #expect(AnnualText.lower("会话", lang: zhHans) == "会话")
        #expect(AnnualText.tracking(0.6, lang: zhHans) == 0)

        let zhHant = LanguageManager()
        zhHant.language = .zhHant
        #expect(zhHant.usesCJKScript == true)
        #expect(AnnualText.tracking(0.9, lang: zhHant) == 0)
    }

    // MARK: - Usage verdict bands + accent discipline (AB-316 AC #1 · #6 · #7)

    /// The verdict bands mirror the exact `usageColor` cut-offs the app ships
    /// (`>= 90` critical, `70..<90` elevated, else healthy) — pinned at both
    /// boundaries so Annual can't drift from the shared usage semantics. The
    /// screenshot points 99% (critical) and 7% (healthy) are covered by the
    /// endpoints.
    @Test
    func usageVerdictBandsMatchTheUsageColorCutoffs() {
        #expect(AnnualUsageVerdict.verdict(for: 99) == .critical)
        #expect(AnnualUsageVerdict.verdict(for: 90) == .critical)
        #expect(AnnualUsageVerdict.verdict(for: 89.9) == .elevated)
        #expect(AnnualUsageVerdict.verdict(for: 70) == .elevated)
        #expect(AnnualUsageVerdict.verdict(for: 69.9) == .healthy)
        #expect(AnnualUsageVerdict.verdict(for: 7) == .healthy)
        #expect(AnnualUsageVerdict.verdict(for: 0) == .healthy)
    }

    /// Accent discipline on the usage surface: **only** the critical verdict is
    /// allowed to spend the accent (on its figure, its verdict word and its meter
    /// fill). Elevated and healthy are calm, so with healthy usage the usage lane
    /// carries zero accent — the code-level half of AC #7 (the pixel screenshot is
    /// flagged manual in the PR).
    @Test
    func onlyTheCriticalUsageVerdictSpendsTheAccent() {
        #expect(AnnualUsageVerdict.critical.isCritical == true)
        #expect(AnnualUsageVerdict.elevated.isCritical == false)
        #expect(AnnualUsageVerdict.healthy.isCritical == false)
        // The three bands as they resolve from a percentage: only the 90+ band is
        // loud, so 7% (healthy) and 75% (elevated) stay accent-free.
        #expect(AnnualUsageVerdict.verdict(for: 7).isCritical == false)
        #expect(AnnualUsageVerdict.verdict(for: 75).isCritical == false)
        #expect(AnnualUsageVerdict.verdict(for: 95).isCritical == true)
    }

    // MARK: - Header controls (AB-316 AC #2)

    @Test
    func headerControlHitTargetsAreAtLeastTwentyFourPoints() {
        // The quiet glyph controls carry ≥24×24pt hit areas.
        #expect(AnnualHeaderControls.headerControlButtonSize >= 24)
    }

    // MARK: - AB-316 strings localize (AC #1 · #4)

    /// Every new AB-316 string (usage verdicts, the pre-list eyebrows, the setup
    /// tag) resolves to a real translation — not the bare key — in English and
    /// both Chinese scripts, so the `AnnualText` neutralization has real localized
    /// copy to render naturally for CJK.
    @Test
    func annualOpenedChromeStringsLocalizeInEveryLanguage() {
        let originalLanguage = UserDefaults.standard.string(forKey: "appLanguage")
        defer {
            if let originalLanguage {
                UserDefaults.standard.set(originalLanguage, forKey: "appLanguage")
            } else {
                UserDefaults.standard.removeObject(forKey: "appLanguage")
            }
        }

        let keys = [
            "island.annual.usage.healthy",
            "island.annual.usage.elevated",
            "island.annual.usage.critical",
            "island.annual.state.empty",
            "island.annual.state.loading",
            "island.annual.hint.setup",
        ]

        for language in [LanguageManager.AppLanguage.en, .zhHans, .zhHant] {
            let manager = LanguageManager()
            manager.language = language
            for key in keys {
                let resolved = manager.t(key)
                #expect(resolved != key, "\(key) is unlocalized in \(language)")
                #expect(!resolved.isEmpty)
            }
        }
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

        let theme = AnnualTheme()
        for language in [LanguageManager.AppLanguage.en, .zhHans, .zhHant] {
            let manager = LanguageManager()
            manager.language = language
            let name = theme.name(manager)
            let descriptor = theme.descriptor(manager)
            #expect(!name.isEmpty)
            #expect(name != "theme.annual.name", "name is unlocalized in \(language)")
            #expect(!descriptor.isEmpty)
            #expect(descriptor != "theme.annual.descriptor", "descriptor is unlocalized in \(language)")
        }
    }
}
