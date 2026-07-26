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

    // MARK: - Two-font split contract (AB-337 · SPEC §2)

    /// The 2.0 board's mono/sans split: narration prose the reader *reads* — the
    /// session name, live narration, assistant rich text, gauge legends — draws
    /// **sans**, and every *value* the reader *scans* — status codes, counts,
    /// the mono body/label/micro-label — draws **mono tabular**. No test pinned
    /// font design before this; a `Font` is opaque, so the contract is pinned on
    /// the `roleFamilies` table the font builders derive their design from.
    @Test
    func monoSansSplitHoldsTheTwoFontContract() {
        // Narration roles are sans — the headline is explicitly NOT monospaced.
        #expect(FlightDeckTypography.family(of: "sessionName") == .sans)
        #expect(FlightDeckTypography.family(of: "narration") == .sans)
        #expect(FlightDeckTypography.family(of: "assistant") == .sans)
        #expect(FlightDeckTypography.family(of: "gaugeLabel") == .sans)

        // Value roles are mono — the status code and every counter/body ARE
        // monospaced (tabular numerals ride the mono design for free).
        #expect(FlightDeckTypography.family(of: "statusCode") == .mono)
        #expect(FlightDeckTypography.family(of: "count") == .mono)
        #expect(FlightDeckTypography.family(of: "microLabel") == .mono)
        #expect(FlightDeckTypography.family(of: "label") == .mono)
        #expect(FlightDeckTypography.family(of: "body") == .mono)

        // The two families map onto the two `Font.Design`s the split intends.
        #expect(FlightDeckTypography.Family.sans.design == .default)
        #expect(FlightDeckTypography.Family.mono.design == .monospaced)

        // Every role in the table declares a family, and an unknown role is nil.
        #expect(FlightDeckTypography.family(of: "does-not-exist") == nil)
        #expect(FlightDeckTypography.roleFamilies.allSatisfy { !$0.name.isEmpty })
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
    func shellRowsAreDrawingGroupUnsafeForPhosphorBleed() {
        // AB-336: the row status lane is now a self-lit phosphor lamp whose halo
        // bleeds *outside* the row silhouette (breathe halo to 11pt, the success
        // settle flash to 18pt). A `.drawingGroup()` off-screen render flattens the
        // row to its own bounds and would clip that out-of-bounds bleed — the same
        // reason Poured is unsafe — so the row opts out of rasterization.
        #expect(FlightDeckTheme().rowIsDrawingGroupSafe == false)
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

    // MARK: - Tape gauge colour + placard bands + threshold geometry (AB-338 AC #1)

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
    func tapeGaugePinsThresholdTicksAtSeventyAndNinety() {
        // AB-338 replaced the fixed 12-segment lane (retired
        // `tickGaugeIsTwelveSegments`) with a continuous tape gauge whose two
        // threshold ticks sit at fixed fractions of the track width regardless of
        // fill: a hairline caution tick at 70% and a red critical tick at 90%.
        #expect(FlightDeckTapeGauge.hairlineTickPosition == 0.70)
        #expect(FlightDeckTapeGauge.criticalTickPosition == 0.90)
        #expect(FlightDeckTapeGauge.thresholdTicks == [0.70, 0.90])
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

    // MARK: - Actionable surface strings localize (AB-314 AC #6 · #8)

    /// The MASTER CAUTION block's own strings (the `MASTER CAUTION` /
    /// `PERMISSION REQUIRED` stencils and the ALLOW / DENY defaults) resolve to a
    /// real translation — not the bare key — in English and both Chinese scripts.
    /// The `FlightDeckText` neutralization (tested above) then guarantees the
    /// stencil casing/tracking is dropped for those CJK strings so the labels stay
    /// legible.
    @Test
    func actionableApprovalStringsLocalizeInEveryLanguage() {
        let originalLanguage = UserDefaults.standard.string(forKey: "appLanguage")
        defer {
            if let originalLanguage {
                UserDefaults.standard.set(originalLanguage, forKey: "appLanguage")
            } else {
                UserDefaults.standard.removeObject(forKey: "appLanguage")
            }
        }

        let keys = [
            "island.flightDeck.approval.masterCaution",
            // AB-334: the red WARNING nomenclature + the amber question annunciator
            // strings + the HELD count-up label all localize alongside the originals.
            "island.flightDeck.approval.masterWarning",
            "island.flightDeck.approval.permissionRequired",
            "island.flightDeck.approval.held",
            "island.flightDeck.approval.allow",
            "island.flightDeck.approval.deny",
            "island.flightDeck.question.kicker",
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

    /// AB-334 AC #1: the new `masterWarning` key resolves to the exact EICAS
    /// nomenclature in every locale, and stays distinct from the amber
    /// `masterCaution` placard it must never be confused with.
    @Test
    func masterWarningResolvesToTheExpectedNomenclatureInEveryLanguage() {
        let originalLanguage = UserDefaults.standard.string(forKey: "appLanguage")
        defer {
            if let originalLanguage {
                UserDefaults.standard.set(originalLanguage, forKey: "appLanguage")
            } else {
                UserDefaults.standard.removeObject(forKey: "appLanguage")
            }
        }

        let expected: [LanguageManager.AppLanguage: String] = [
            .en: "Master Warning",
            .zhHans: "主警告",
            .zhHant: "主警告",
        ]

        for (language, warning) in expected {
            let manager = LanguageManager()
            manager.language = language
            #expect(manager.t("island.flightDeck.approval.masterWarning") == warning)
            // Red WARNING and amber CAUTION are different avionics categories — the
            // placards must never collide.
            #expect(
                manager.t("island.flightDeck.approval.masterWarning")
                    != manager.t("island.flightDeck.approval.masterCaution")
            )
        }
    }

    // MARK: - Layered surface hierarchy (AB-335)

    /// The four opaque surface tones pin to the SPEC hex by exact 8-bit
    /// components, so a drift in any tone fails the build.
    @Test
    func surfaceTonesPinToTheSpecHex() {
        #expect(FlightDeckSurfaces.panel == Color(red: 0x0E / 255.0, green: 0x11 / 255.0, blue: 0x13 / 255.0))
        #expect(FlightDeckSurfaces.tile == Color(red: 0x10 / 255.0, green: 0x15 / 255.0, blue: 0x19 / 255.0))
        #expect(FlightDeckSurfaces.hover == Color(red: 0x16 / 255.0, green: 0x1C / 255.0, blue: 0x22 / 255.0))
        #expect(FlightDeckSurfaces.well == Color(red: 0x06 / 255.0, green: 0x07 / 255.0, blue: 0x08 / 255.0))
    }

    /// The hairline base recolors to the cool blue-grey `#9AB0BC`, and the three
    /// tiers hold their SPEC opacities. Tier-2 is the named replacement for the
    /// shipped inline `hairlineOpacity * 2`.
    @Test
    func hairlineTiersPinBaseColourAndOpacities() {
        #expect(FlightDeckSurfaces.hairlineBase == Color(red: 0x9A / 255.0, green: 0xB0 / 255.0, blue: 0xBC / 255.0))
        #expect(FlightDeckSurfaces.hairlineTier1Opacity == 0.14)
        #expect(FlightDeckSurfaces.hairlineTier2Opacity == 0.26)
        #expect(FlightDeckSurfaces.hairlineTier3Opacity == 0.40)

        // The tier accessors are the base recolored at each tier opacity.
        #expect(FlightDeckSurfaces.hairline1 == FlightDeckSurfaces.hairlineBase.opacity(0.14))
        #expect(FlightDeckSurfaces.hairline2 == FlightDeckSurfaces.hairlineBase.opacity(0.26))
        #expect(FlightDeckSurfaces.hairline3 == FlightDeckSurfaces.hairlineBase.opacity(0.40))
        #expect(FlightDeckSurfaces.hairline(tier: 2) == FlightDeckSurfaces.hairline2)
        // An out-of-range tier clamps to tier 1.
        #expect(FlightDeckSurfaces.hairline(tier: 9) == FlightDeckSurfaces.hairline1)
    }

    /// Increase Contrast brightens every hairline tier, mirroring the shared
    /// token's `0.13 → 0.32` lift (≈ +0.19).
    @Test
    func hairlineTiersBrightenUnderIncreaseContrast() {
        #expect(FlightDeckSurfaces.hairline(tier: 1, increaseContrast: true) == FlightDeckSurfaces.hairlineBase.opacity(0.14 + 0.19))
        #expect(FlightDeckSurfaces.hairline(tier: 2, increaseContrast: true) == FlightDeckSurfaces.hairlineBase.opacity(0.26 + 0.19))
        #expect(FlightDeckSurfaces.hairline(tier: 3, increaseContrast: true) == FlightDeckSurfaces.hairlineBase.opacity(0.40 + 0.19))
    }

    /// The dim / faint legend inks pin to their SPEC hex.
    @Test
    func legendInksPinToTheSpecHex() {
        #expect(FlightDeckSurfaces.dimInk == Color(red: 0x8A / 255.0, green: 0x97 / 255.0, blue: 0xA0 / 255.0))
        #expect(FlightDeckSurfaces.faintInk == Color(red: 0x5B / 255.0, green: 0x65 / 255.0, blue: 0x6C / 255.0))
    }

    /// The surface hierarchy is a genuine stack: the opened panel body is a
    /// distinct tone from the cockpit ground it seats on, and the recessed well
    /// is distinct too. The tones are FD-local paint — they are *not* the shared
    /// `surfaceInk` token.
    @Test
    func surfaceTonesAreDistinctFromTheSharedGround() {
        let ground = IslandThemeTokens.flightDeck.colors.surfaceInk
        #expect(FlightDeckSurfaces.panel != ground)
        #expect(FlightDeckSurfaces.tile != ground)
        #expect(FlightDeckSurfaces.hover != ground)
        #expect(FlightDeckSurfaces.well != ground)
        #expect(FlightDeckSurfaces.panel != FlightDeckSurfaces.tile)
        #expect(FlightDeckSurfaces.tile != FlightDeckSurfaces.hover)
    }

    /// The shared `IslandColorTokens.flightDeck` contract is UNTOUCHED by the
    /// FD-local surface work: the cockpit ground stays `#08090A` and the shared
    /// hairline token stays 0.13 / 0.32. The `#9AB0BC` tiers are FD-local paint,
    /// not a mutation of the token layer.
    @Test
    func sharedFlightDeckColourTokensStayUntouched() {
        let colors = IslandThemeTokens.flightDeck.colors
        #expect(colors.surfaceInk == Color(red: 0x08 / 255.0, green: 0x09 / 255.0, blue: 0x0a / 255.0))
        #expect(colors.hairlineOpacity == 0.13)
        #expect(colors.hairlineOpacityIncreasedContrast == 0.32)
        // The ground and the FD-local hairline base are different colours — the
        // recolor lives only in `FlightDeckSurfaces`.
        #expect(FlightDeckSurfaces.hairlineBase != colors.paper)
    }

    // MARK: - Closed-pill attention segment (AB-338 AC #2 · SPEC §4A A3/A4)

    /// The `.seg` attention segment maps the two phases onto their EICAS placard,
    /// glyph, cadence and tint: permission = red `⚠ ACK` on the faster 1.0s
    /// warning cadence; question = amber `? ANSWER` on the calmer 1.2s caution
    /// cadence. Permission is always the louder alarm.
    @Test
    func attentionSegmentMapsPhaseToPlacardGlyphCadenceAndTint() {
        let colors = IslandThemeTokens.flightDeck.colors

        let permission = FlightDeckAttentionSegmentSpec(kind: .permission)
        #expect(permission.placardKey == "island.flightDeck.pill.ack")
        #expect(permission.glyph == "⚠")
        #expect(permission.period == FlightDeckMotion.Attention.warningPeriod)
        #expect(permission.tint(colors) == colors.statusWaitingForApproval)

        let question = FlightDeckAttentionSegmentSpec(kind: .question)
        #expect(question.placardKey == "island.flightDeck.pill.answer")
        #expect(question.glyph == "?")
        #expect(question.period == FlightDeckMotion.Attention.cautionPeriod)
        #expect(question.tint(colors) == colors.statusWaitingForAnswer)

        // The two are distinct by hue, glyph and cadence — never colour alone.
        #expect(permission.glyph != question.glyph)
        #expect(permission.placardKey != question.placardKey)
        #expect(permission.period < question.period)
        #expect(permission.tint(colors) != question.tint(colors))
    }

    /// The `ACK` / `ANSWER` placards stay **Latin in every locale** — the
    /// EICAS-legend rule the STATUS codes follow (AB-337). The keys exist in all
    /// three `.strings` files but resolve to the same Latin value, and the
    /// tracking neutralizes to `0` under CJK.
    @Test
    func attentionSegmentPlacardsStayLatinInEveryLocale() {
        let originalLanguage = UserDefaults.standard.string(forKey: "appLanguage")
        defer {
            if let originalLanguage {
                UserDefaults.standard.set(originalLanguage, forKey: "appLanguage")
            } else {
                UserDefaults.standard.removeObject(forKey: "appLanguage")
            }
        }

        for language in [LanguageManager.AppLanguage.en, .zhHans, .zhHant] {
            let manager = LanguageManager()
            manager.language = language
            // Values stay Latin (never localized), and are non-empty (the key exists).
            #expect(manager.t("island.flightDeck.pill.ack") == "ACK")
            #expect(manager.t("island.flightDeck.pill.answer") == "ANSWER")
            // CJK neutralizes the placard tracking to 0; Latin keeps it.
            let expectedTracking: CGFloat = manager.usesCJKScript ? 0 : 0.8
            #expect(FlightDeckText.tracking(0.8, lang: manager) == expectedTracking)
        }
    }

    /// The A1 idle `STANDBY` resting caption resolves to a real translation in
    /// every locale (Chinese `待命`), so the bare idle pill never shows a raw key.
    @Test
    func standbyPillCaptionLocalizesInEveryLanguage() {
        let originalLanguage = UserDefaults.standard.string(forKey: "appLanguage")
        defer {
            if let originalLanguage {
                UserDefaults.standard.set(originalLanguage, forKey: "appLanguage")
            } else {
                UserDefaults.standard.removeObject(forKey: "appLanguage")
            }
        }

        for language in [LanguageManager.AppLanguage.en, .zhHans, .zhHant] {
            let manager = LanguageManager()
            manager.language = language
            let resolved = manager.t("island.flightDeck.pill.standby")
            #expect(resolved != "island.flightDeck.pill.standby")
            #expect(!resolved.isEmpty)
        }
    }

    // MARK: - Closed-pill wing label tone (AB-338 AC #3 · SPEC §4A A2/A5)

    /// The wing label tone-splits the resolver's own output: a working narration
    /// into a green verb + bright object, the `N working` aggregate into a strong
    /// count + dim qualifier, and a completion into an advisory `Done ·` prefix +
    /// bright workspace. Non-splittable frames render as one run.
    @Test
    func wingLabelToneSplitsWorkingAndCompletion() {
        typealias Seg = FlightDeckPillLabelTone.Segment

        // A2 working — "Editing AppModel.swift" → verb green, object bright.
        #expect(
            FlightDeckPillLabelTone.segments(for: "Editing AppModel.swift", ambient: .working(manyWorking: false))
                == [Seg(text: "Editing", role: .verb), Seg(text: " AppModel.swift", role: .object)]
        )
        // A2′ aggregate — "3 working" → count strong, qualifier dim.
        #expect(
            FlightDeckPillLabelTone.segments(for: "3 working", ambient: .working(manyWorking: true))
                == [Seg(text: "3", role: .count), Seg(text: " working", role: .plain)]
        )
        // A5 completion — "Done · the-automator" → advisory prefix, bright workspace.
        #expect(
            FlightDeckPillLabelTone.segments(for: "Done · the-automator", ambient: .completed(.success))
                == [Seg(text: "Done ·", role: .donePrefix), Seg(text: " the-automator", role: .object)]
        )
        // Idle / permission / question carry no split — one plain run.
        #expect(
            FlightDeckPillLabelTone.segments(for: "Approve swift build?", ambient: .permission)
                == [Seg(text: "Approve swift build?", role: .plain)]
        )
        // A single-word working label with no object is still one object run.
        #expect(
            FlightDeckPillLabelTone.segments(for: "Working", ambient: .working(manyWorking: false))
                == [Seg(text: "Working", role: .object)]
        )
        // Empty text yields no segments (the pill draws nothing).
        #expect(FlightDeckPillLabelTone.segments(for: "   ", ambient: .idle).isEmpty)
    }
}

// MARK: - Closed-pill width regression (AB-338 · the T12/AB-330 contract)

/// AB-338 renders two *new* right-slot kinds in the Flight Deck idiom (the
/// attention segment and the usage mini-tape) and adds the two-tone wing labels,
/// but the shipped `V6ClosedPill.*OuterWidth` math must stay **byte-identical** —
/// the closed↔opened morph frame (and every theme's pill silhouette) depends on
/// it, and the FD variants must render *inside* the slot the fluid layout already
/// reserved, never widen it. Mirrors `PouredClosedPillWidthRegressionTests` (the
/// T12/AB-330 precedent) so a drift in the width math fails the build regardless
/// of what the FD right-slot / wing views draw.
@MainActor
struct FlightDeckClosedPillWidthRegressionTests {
    private static let height: CGFloat = 38
    private static let tolerance: CGFloat = 0.001

    private func external(_ label: String?, _ rightSlot: IslandRightSlotContent?) -> CGFloat {
        V6ClosedPill.externalOuterWidth(label: label, rightSlot: rightSlot, minWidth: 70, height: Self.height)
    }

    private func macbook(_ label: String?, notch: CGFloat) -> CGFloat {
        V6ClosedPill.macbookOuterWidth(label: label, physicalNotchWidth: notch, height: Self.height)
    }

    /// The four count-shaped kinds (`.count`, `.attentionCount`, `.taskCounter`,
    /// `.usage`) share the badge width math, so the FD attention-segment and
    /// usage-mini-tape renderings never move the external frame.
    @Test
    func externalOuterWidthGoldensAreUnchanged() {
        #expect(abs(external(nil, nil) - 70) < Self.tolerance)
        #expect(abs(external("Editing AppModel.swift", nil) - 238.6) < Self.tolerance)
        #expect(abs(external(nil, .attentionCount(count: 1, kind: .permission)) - 82.4) < Self.tolerance)
        #expect(abs(external(nil, .attentionCount(count: 12, kind: .question)) - 89.6) < Self.tolerance)
        #expect(abs(external(nil, .usage(percent: 92, windowLabel: "7d", providerTitle: "Claude")) - 89.6) < Self.tolerance)
        #expect(abs(external("Done · the-automator", nil) - 224) < Self.tolerance)
    }

    /// A permission and a question segment with the same count reserve the same
    /// width — the two variants differ only in glyph / placard / hue, not geometry.
    @Test
    func attentionSegmentKindDoesNotChangeReservedWidth() {
        #expect(
            external("x", .attentionCount(count: 3, kind: .permission))
                == external("x", .attentionCount(count: 3, kind: .question))
        )
    }

    /// The A1 `STANDBY` caption is fed to the pill as its effective label, so its
    /// reserved width is exactly the shipped label-path width — a new width path
    /// is never introduced (the FD pill reuses the existing math).
    @Test
    func standbyCaptionReservesTheShippedLabelWidth() {
        // "STANDBY" through the label path widens the bare idle pill past minWidth,
        // and does so via the *same* `externalOuterWidth(label:)` every label uses.
        #expect(external("STANDBY", nil) > external(nil, nil))
        #expect(macbook("STANDBY", notch: 180) >= macbook(nil, notch: 180))
    }
}
