import SwiftUI
import Testing
@testable import OpenIslandApp

/// Stage-1 pins for Poured Island 2.0 (AB-329): the attention palette, the new
/// material gradient / hard-specular / inner-hairline tokens, the grown
/// closed-pill shadow insets, and Classic status-colour parity.
///
/// This is a **starter** suite — stage 2 (typography table + full conformance
/// suite) EXTENDS it. Keep new Poured pins in this struct rather than a parallel
/// file so the theme's contract lives in one place.
struct PouredThemeTests {

    // MARK: - Attention palette (SPEC §0 / §1a)

    /// The two new attention-glow colours, pinned by exact 8-bit components so a
    /// drift in either fails the build.
    @Test
    func attentionPaletteMatchesTheSpecHex() {
        #expect(
            PouredPalette.attention
                == Color(red: 0xFF / 255.0, green: 0xB1 / 255.0, blue: 0x4D / 255.0)
        )
        #expect(
            PouredPalette.attentionHot
                == Color(red: 0xFF / 255.0, green: 0x9D / 255.0, blue: 0x5C / 255.0)
        )
    }

    /// The attention amber is a *brighter* amber than the shipped warning tone
    /// (`statusWarning #d98c26`), which keeps its caution / interrupted role — the
    /// two must never collapse onto one another.
    @Test
    func attentionIsDistinctFromTheWarningTone() {
        let colors = IslandThemeTokens.poured.colors

        #expect(PouredPalette.attention != colors.statusWarning)
        #expect(PouredPalette.attention != colors.statusInterrupted)
        #expect(PouredPalette.attentionHot != colors.statusWarning)
        #expect(PouredPalette.attention != PouredPalette.attentionHot)
    }

    // MARK: - Material tokens (SPEC §1d)

    /// The 3-stop body gradient carries elevation by inner luminance (lighter
    /// top → darker bottom). Pinned stop-by-stop: colour, opacity, location.
    @Test
    func bodyGradientPinsTheThreeStops() throws {
        let stops = try #require(IslandMaterialTokens.poured.bodyGradient)
        #expect(stops.count == 3)

        #expect(
            stops[0] == IslandGradientStop(
                color: Color(red: 26 / 255.0, green: 31 / 255.0, blue: 44 / 255.0),
                opacity: 0.86,
                location: 0.0
            )
        )
        #expect(
            stops[1] == IslandGradientStop(
                color: Color(red: 13 / 255.0, green: 17 / 255.0, blue: 26 / 255.0),
                opacity: 0.94,
                location: 0.62
            )
        )
        #expect(
            stops[2] == IslandGradientStop(
                color: Color(red: 9 / 255.0, green: 12 / 255.0, blue: 20 / 255.0),
                opacity: 0.96,
                location: 1.0
            )
        )
    }

    /// The hard specular is a crisp 1pt white line at 14% — read as a top line
    /// via `IslandSpecularEdge.sheenHeight == 1`.
    @Test
    func hardSpecularEdgeIsAOnePointFourteenPercentWhiteLine() throws {
        let edge = try #require(IslandMaterialTokens.poured.specularHardEdge)

        #expect(edge.color == Color.white)
        #expect(edge.opacity == 0.14)
        #expect(edge.sheenHeight == 1)
    }

    /// The inner hairline is a faint 0.5pt white inset stroke at 5%.
    @Test
    func innerHairlineIsAHalfPointFivePercentStroke() throws {
        let hairline = try #require(IslandMaterialTokens.poured.innerHairline)

        #expect(hairline.opacity == 0.05)
        #expect(hairline.width == 0.5)
    }

    /// The soft 26pt sheen is unchanged — the two hard layers stack *on top* of
    /// it rather than replacing it.
    @Test
    func softSpecularSheenIsUnchanged() throws {
        let sheen = try #require(IslandMaterialTokens.poured.specularTopEdge)

        #expect(sheen.color == Color.white)
        #expect(sheen.opacity == 0.5)
        #expect(sheen.sheenHeight == 26)
    }

    /// The four flat themes opt into none of the three new liquid-glass layers —
    /// `nil` is what guarantees `OpenedSurfaceBackground` renders them exactly as
    /// it does today.
    @Test
    func otherThemesDeclareNoNewMaterialLayers() {
        for material in [
            IslandMaterialTokens.classic,
            IslandMaterialTokens.instrument,
            IslandMaterialTokens.flightDeck,
            IslandMaterialTokens.annual,
        ] {
            #expect(material.bodyGradient == nil)
            #expect(material.specularHardEdge == nil)
            #expect(material.innerHairline == nil)
        }
    }

    /// `IslandMaterialTokens` still declares / synthesises `Equatable` after the
    /// three new fields — a compile-time proof plus a runtime sanity check.
    @Test
    func materialTokensRemainEquatable() {
        #expect(IslandMaterialTokens.poured == IslandMaterialTokens.poured)
        #expect(IslandMaterialTokens.poured != IslandMaterialTokens.classic)
    }

    // MARK: - Closed-inset growth (SPEC §3.1 / AB-329)

    /// Poured's closed-pill shadow insets grew 16/18 → 40/44 so the A3 amber
    /// bloom (radius ≤ 34 + spread) is contained by the always-opened-size
    /// overlay window; the opened insets stay 28/34. Because the closed insets
    /// now exceed the opened ones, `IslandChromeLayout`'s per-axis max grows the
    /// window (asserted in `IslandChromeLayoutTests`).
    @Test
    func closedShadowInsetsGrewToFortyFortyFour() {
        let metrics = IslandMetricsTokens.poured

        #expect(metrics.closedShadowHorizontalInset == 40)
        #expect(metrics.closedShadowBottomInset == 44)
        #expect(metrics.openedShadowHorizontalInset == 28)
        #expect(metrics.openedShadowBottomInset == 34)

        #expect(metrics.closedShadowHorizontalInset > metrics.openedShadowHorizontalInset)
        #expect(metrics.closedShadowBottomInset > metrics.openedShadowBottomInset)
    }

    // MARK: - Classic status-colour parity (SPEC §1a)

    /// Every vivid status tint Poured carries is *byte-identical* to Classic's —
    /// the two themes share status semantics. (Idle / inactive are the honest
    /// exception, pinned separately below.)
    @Test
    func vividStatusColorsAreByteIdenticalToClassic() {
        let poured = IslandThemeTokens.poured.colors
        let classic = IslandThemeTokens.classic.colors

        #expect(poured.statusRunning == classic.statusRunning)
        #expect(poured.statusCompleted == classic.statusCompleted)
        #expect(poured.statusWaitingForApproval == classic.statusWaitingForApproval)
        #expect(poured.statusWaitingForAnswer == classic.statusWaitingForAnswer)
        #expect(poured.statusWaitingAggregate == classic.statusWaitingAggregate)
        #expect(poured.statusWarning == classic.statusWarning)
        #expect(poured.statusInterrupted == classic.statusInterrupted)
        #expect(poured.statusFailed == classic.statusFailed)
    }

    /// The documented divergence from full parity: idle / inactive derive from
    /// each theme's own *paper* tone, not a shared status literal, so Poured's
    /// cool paper (`#f2f5fb`) makes them legitimately differ from Classic's warm
    /// paper (`#f1ead9`). Pinned so the difference stays a decision, not drift.
    @Test
    func idleAndInactiveFollowPouredsOwnPaper() {
        let poured = IslandThemeTokens.poured.colors
        let classic = IslandThemeTokens.classic.colors

        #expect(poured.statusIdle == poured.paper.opacity(0.35))
        #expect(poured.statusInactive == poured.paper.opacity(0.38))
        #expect(poured.statusIdle != classic.statusIdle)
        #expect(poured.statusInactive != classic.statusInactive)
    }

    // MARK: - Text-ramp & hairline opacities (SPEC §1a)

    /// The text ramp and hairline opacities. The mockup's own drift values
    /// (`--t2 .66`, `--hair .09`) are **explicitly NOT adopted**: the mockup's
    /// own comment says `.6`, so the spec's drift-resolution keeps the shipped
    /// `secondaryTextOpacity 0.6` / `hairlineOpacity 0.08`. Pinned so a later
    /// "sync to mockup" pass can't silently reintroduce the drift.
    @Test
    func textAndHairlineOpacitiesKeepShippedValuesNotMockupDrift() {
        let colors = IslandThemeTokens.poured.colors

        #expect(colors.secondaryTextOpacity == 0.6)  // NOT the mockup's 0.66
        #expect(colors.tertiaryTextOpacity == 0.5)
        #expect(colors.hairlineOpacity == 0.08)       // NOT the mockup's 0.09
        // Increase-Contrast hairline lifts to 0.24 (the mockup implies .24 is fine).
        #expect(colors.hairlineOpacityIncreasedContrast == 0.24)
    }

    // MARK: - Chrome metrics (SPEC §1b)

    /// Opened radii, the notch fillet, the hover-lift scale, and the deep soft
    /// surface shadow — pinned so the glass slab's geometry can't drift.
    @Test
    func chromeMetricsMatchTheSpec() {
        let metrics = IslandMetricsTokens.poured

        #expect(metrics.openedTopRadius == 26)
        #expect(metrics.openedBottomRadius == 26)
        #expect(metrics.filletRadius == 12)
        #expect(metrics.closedHoverScale == 1.03)

        #expect(metrics.surfaceShadow.color == .black)
        #expect(metrics.surfaceShadow.opacity == 0.5)
        #expect(metrics.surfaceShadow.radius == 34)
        #expect(metrics.surfaceShadow.yOffset == 18)
    }

    // MARK: - Motion (SPEC §1c)

    /// The "Morph spring · resp .5 · damp .84" the mockup masthead states, plus
    /// the softer close / pop and the grown unmount delay.
    @Test
    func motionTokensMatchTheMorphSpringSpec() {
        let motion = IslandMotionTokens.poured

        #expect(motion.openAnimation == .spring(response: 0.5, dampingFraction: 0.84, blendDuration: 0))
        #expect(motion.closeAnimation == .smooth(duration: 0.34, extraBounce: 0))
        #expect(motion.popAnimation == .spring(response: 0.34, dampingFraction: 0.55, blendDuration: 0))
        #expect(motion.openedSurfaceUnmountDelay == 0.4)
    }

    // MARK: - Material tint (SPEC §1d)

    /// The ink tint drops to 0.5 (from Classic's 0.6) so more of the heavy blur
    /// reads through as glass. The soft 26pt sheen's colour / opacity / height
    /// are pinned by `softSpecularSheenIsUnchanged`; this makes the tint explicit
    /// too, so the whole material family is nailed down.
    @Test
    func inkTintOpacityIsHalf() {
        #expect(IslandMaterialTokens.poured.tintOpacity == 0.5)
    }

    // MARK: - Capability flags (SPEC §5.2)

    /// Poured is a frosted-glass slab whose rows express status as luminous glow:
    /// vibrancy is on, and the row opts out of `.drawingGroup()` rasterization
    /// (which would flatten and clip the glows to the row bounds).
    @MainActor
    @Test
    func pouredIsGlassWithVibrancyAndGlowingRows() {
        let theme = PouredIslandTheme()

        #expect(theme.usesVibrancy == true)
        #expect(theme.rowIsDrawingGroupSafe == false)
    }

    // MARK: - Agents-grid geometry (SPEC §5.2)

    /// Poured's closed grid does not deviate from Classic's, so its geometry
    /// strategy calls straight through to the `V6RightSlotView` statics (pinned
    /// by `AgentsGridLayoutTests`). Unlike Annual / Flight Deck — which reuse the
    /// matrix and cell/gap but square the tile *radius* — Poured delegates
    /// everything verbatim, so `balancedRows`, `cell`, `gap` **and** `radius` all
    /// match the statics.
    @MainActor
    @Test
    func agentsGridGeometryDelegatesToTheSharedStatics() {
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

    // MARK: - Typography table (SPEC §2)

    /// Every role has exactly one `roleTable` entry, so `Role.spec`'s lookup
    /// never traps and the readable-sizes vector covers the whole table.
    @Test
    func everyRoleHasExactlyOneTableEntry() {
        #expect(PouredType.roleTable.count == PouredType.Role.allCases.count)
        for role in PouredType.Role.allCases {
            #expect(PouredType.roleTable[role] != nil)
        }
    }

    /// The floor: every readable Poured role sits at or above 10pt — density
    /// comes from weight, case and tracking, never from sub-10pt micro-type.
    @Test
    func everyReadableRoleHoldsTheFloor() {
        #expect(PouredType.floor == 10)
        #expect(!PouredType.readableRoleSizes.isEmpty)
        for size in PouredType.readableRoleSizes {
            #expect(size >= PouredType.floor)
        }
    }

    /// The load-bearing roles, pinned `(size, weight, mono, tabular)` so a drift
    /// in the §2 table fails the build. Covers the grown headline sizes
    /// (workspace 13.2→14, activity 11→12.5, hero 12.5→14), the mono/sans split
    /// (branch / command / diff stay mono; the rest go SF Pro), the tabular-digit
    /// roles (age / summary number), and the lifted metadata key. Activity is
    /// spec'd 500–550 and set at 550 (matching the live verb).
    @Test
    func loadBearingTypographyRolesMatchTheSpecTable() {
        // (role, size, weight, isMono, isTabular)
        let expected: [(role: PouredType.Role, size: CGFloat, weight: CGFloat, mono: Bool, tabular: Bool)] = [
            (.workspaceTitle, 14, 600, false, false),
            (.activityLine, 12.5, 550, false, false),
            (.branchDisambiguator, 11, 400, true, false),
            (.age, 11, 500, false, true),
            (.sectionHeader, 10.5, 650, false, false),
            (.summaryNumber, 12, 700, false, true),
            (.commandBlock, 12, 600, true, false),
            (.diff, 11.5, 400, true, false),
            (.heroTitle, 14, 640, false, false),
            (.metadataKey, 10, 600, false, false),
        ]

        for entry in expected {
            let spec = entry.role.spec
            #expect(spec.size == entry.size, "\(entry.role) size")
            #expect(spec.weight == entry.weight, "\(entry.role) weight")
            #expect(spec.isMono == entry.mono, "\(entry.role) mono")
            #expect(spec.isTabular == entry.tabular, "\(entry.role) tabular")
        }
        // Activity's spec weight is within the 500–550 band the table allows.
        #expect([500, 550].contains(PouredType.Role.activityLine.spec.weight))
    }

    /// The section header dropped mono (the shipped theme set it `.monospaced`)
    /// and became an uppercase SF Pro micro-label letterspaced 0.09em.
    @Test
    func sectionHeaderIsRetrackedUppercaseSansNotMono() {
        let spec = PouredType.Role.sectionHeader.spec

        #expect(spec.isMono == false)
        #expect(spec.isUppercase == true)
        #expect(spec.trackingEm == 0.09)
    }

    /// Mono is reserved for code-shaped text only — command / diff / branch /
    /// mono-chip / inline `code` / mono metadata value. The roles the shipped
    /// theme drew in mono (section header, summary strip, agent chip, age) are
    /// now proportional SF Pro — Poured 2.0's largest visual change.
    @Test
    func monoIsReservedForCodeShapedRoles() {
        let monoRoles = Set(PouredType.Role.allCases.filter { $0.spec.isMono })
        #expect(monoRoles == Set<PouredType.Role>([
            .branchDisambiguator,
            .monoChip,
            .commandBlock,
            .diff,
            .assistantInlineCode,
            .metadataValueMono,
        ]))

        for role in [PouredType.Role.sectionHeader, .summaryLabel, .summaryNumber, .age, .agentChipLabel, .metaChip] {
            #expect(role.spec.isMono == false, "\(role) must be sans in 2.0")
        }
    }

    /// Metadata keys are 9.5pt in the mockup, but a metadata *key* is readable
    /// chrome (not a fitted micro-indicator), so the table lifts it to the 10pt
    /// floor — the one documented size deviation from the mockup.
    @Test
    func metadataKeyIsLiftedToTheFloor() {
        let size = PouredType.Role.metadataKey.spec.size
        #expect(size == 10)
        #expect(size >= PouredType.floor)
    }

    /// The keycap hint sits exactly at the floor (10pt).
    @Test
    func keycapSitsAtTheFloor() {
        #expect(PouredType.Role.keycap.spec.size == PouredType.floor)
    }

    /// The mockup's CSS-style numeric weights round to the nearest system
    /// `Font.Weight` for rendering, while the numeric spec weight stays the
    /// pinnable design intent. The 600–650 "display semibold" band collapses to
    /// `.semibold`; 550 to `.medium`.
    @Test
    func numericWeightsRoundToNearestSystemWeight() {
        #expect(PouredType.Role.summaryLabel.spec.fontWeight == .regular)     // 400
        #expect(PouredType.Role.metaChip.spec.fontWeight == .medium)         // 500
        #expect(PouredType.Role.activityLine.spec.fontWeight == .medium)     // 550
        #expect(PouredType.Role.workspaceTitle.spec.fontWeight == .semibold) // 600
        #expect(PouredType.Role.sectionHeader.spec.fontWeight == .semibold)  // 650
        #expect(PouredType.Role.summaryNumber.spec.fontWeight == .bold)      // 700
    }
}
