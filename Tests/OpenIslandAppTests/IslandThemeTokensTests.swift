import Foundation
import SwiftUI
import Testing
@testable import OpenIslandApp
import OpenIslandCore

/// Drift pins for `IslandThemeTokens.classic`.
///
/// The guarantee is that `.classic` reproduces today's look exactly. Tokens
/// whose legacy constant still has un-migrated call sites are compared against
/// that live constant — `V6Palette`, `IslandDesignPalette`, `NotchShape`,
/// `IslandChromeMetrics` — so a change to either side fails here.
///
/// The opened-surface shadow and the open/close/pop animations no longer have
/// a second definition to compare against: AB-295 routed `IslandPanelView`
/// through the tokens and deleted the file-private constants they were lifted
/// from, making the token the single source. Those stay pinned against
/// literals, which is now a pin on the shipping values themselves.
struct IslandThemeTokensTests {

    // MARK: - Colors

    @Test
    func classicSurfaceColorsMatchV6Palette() {
        let colors = IslandThemeTokens.classic.colors

        #expect(colors.surfaceInk == V6Palette.ink)
        #expect(colors.paper == V6Palette.paper)
    }

    /// Literal pin: `surfaceText` has no legacy constant to compare against.
    /// The MarkdownUI `completionCard` theme spelled this out as `.white` at
    /// every foreground and wash until AB-296 pointed it at the tokens, so
    /// this literal is now the only definition.
    @Test
    func classicSurfaceTextIsPlainWhite() {
        #expect(IslandThemeTokens.classic.colors.surfaceText == Color.white)
    }

    @Test
    func classicStatusColorsMatchIslandDesignPalette() {
        let colors = IslandThemeTokens.classic.colors

        #expect(colors.statusRunning == IslandDesignPalette.Status.running)
        #expect(colors.statusCompleted == IslandDesignPalette.Status.completed)
        #expect(colors.statusWaitingForApproval == IslandDesignPalette.Status.waitingForApproval)
        #expect(colors.statusWaitingForAnswer == IslandDesignPalette.Status.waitingForAnswer)
        #expect(colors.statusWaitingAggregate == IslandDesignPalette.Status.waitingAggregate)
        #expect(colors.statusWarning == IslandDesignPalette.Status.warning)
        #expect(colors.statusInterrupted == IslandDesignPalette.Status.interrupted)
        #expect(colors.statusFailed == IslandDesignPalette.Status.failed)
        #expect(colors.statusIdle == IslandDesignPalette.Status.idle)
        #expect(colors.statusInactive == IslandDesignPalette.Status.inactive)
    }

    @Test
    func interruptedReusesTheWarningTone() {
        let colors = IslandThemeTokens.classic.colors

        #expect(colors.statusInterrupted == colors.statusWarning)
    }

    @Test
    func classicContrastValuesMatchIslandDesignPalette() {
        let colors = IslandThemeTokens.classic.colors

        #expect(colors.secondaryTextOpacity == IslandDesignPalette.Contrast.secondaryText)
        #expect(colors.tertiaryTextOpacity == IslandDesignPalette.Contrast.tertiaryText)
        #expect(colors.hairlineOpacity == IslandDesignPalette.Contrast.hairline(increaseContrast: false))
        #expect(
            colors.hairlineOpacityIncreasedContrast
                == IslandDesignPalette.Contrast.hairline(increaseContrast: true)
        )
    }

    @Test
    func contrastHelpersMatchIslandDesignPalette() {
        let colors = IslandThemeTokens.classic.colors

        for base in [0.0, 0.25, 0.48, 0.55, 0.9, 1.0] {
            for increaseContrast in [false, true] {
                #expect(
                    colors.text(base, increaseContrast: increaseContrast)
                        == IslandDesignPalette.Contrast.text(base, increaseContrast: increaseContrast)
                )
            }
        }

        for increaseContrast in [false, true] {
            #expect(
                colors.hairline(increaseContrast: increaseContrast)
                    == IslandDesignPalette.Contrast.hairline(increaseContrast: increaseContrast)
            )
        }
    }

    @Test
    func increasedContrastTextVariantsApplyTheBoost() {
        let colors = IslandThemeTokens.classic.colors

        #expect(colors.increasedContrastTextBoost == 0.24)
        #expect(colors.secondaryTextOpacityIncreasedContrast == 0.55 + 0.24)
        #expect(colors.tertiaryTextOpacityIncreasedContrast == 0.48 + 0.24)
        // The boost clamps rather than overshooting.
        #expect(colors.text(0.9, increaseContrast: true) == 1)
    }

    @Test
    func statusTintMatchesIslandDesignPaletteForEveryPhase() {
        let colors = IslandThemeTokens.classic.colors

        for phase in SessionPhase.allCases {
            for outcome in SessionOutcome.allCases {
                #expect(
                    colors.statusTint(for: phase, outcome: outcome)
                        == IslandDesignPalette.Status.tint(for: phase, outcome: outcome)
                )
            }
        }
    }

    @Test
    func presenceAwareStatusTintMatchesIslandDesignPalette() {
        let colors = IslandThemeTokens.classic.colors
        let presences: [IslandSessionPresence] = [.running, .active, .inactive]

        for phase in SessionPhase.allCases {
            for presence in presences {
                for outcome in SessionOutcome.allCases {
                    #expect(
                        colors.statusTint(for: phase, presence: presence, outcome: outcome)
                            == IslandDesignPalette.Status.tint(
                                for: phase,
                                presence: presence,
                                outcome: outcome
                            )
                    )
                }
            }
        }
    }

    // MARK: - Metrics

    @Test
    func classicRadiiMatchNotchShape() {
        let metrics = IslandThemeTokens.classic.metrics

        #expect(metrics.openedTopRadius == NotchShape.openedTopRadius)
        #expect(metrics.openedBottomRadius == NotchShape.openedBottomRadius)
        #expect(metrics.openedTopRadius == 22)
        #expect(metrics.openedBottomRadius == 22)
    }

    @Test
    func classicChromeInsetsMatchIslandChromeMetrics() {
        let metrics = IslandThemeTokens.classic.metrics

        #expect(metrics.openedShadowHorizontalInset == IslandChromeMetrics.openedShadowHorizontalInset)
        #expect(metrics.openedShadowBottomInset == IslandChromeMetrics.openedShadowBottomInset)
        #expect(metrics.closedShadowHorizontalInset == IslandChromeMetrics.closedShadowHorizontalInset)
        #expect(metrics.closedShadowBottomInset == IslandChromeMetrics.closedShadowBottomInset)
        #expect(metrics.closedHoverScale == IslandChromeMetrics.closedHoverScale)
    }

    /// Literal pin: `IslandPanelView` used to apply this inline as
    /// `.shadow(color: .black.opacity(0.36), radius: 22, y: 12)` in both the
    /// morph and the Reduce Motion path. Since AB-295 both sites read
    /// `surfaceShadow`, so this token is the only definition left and the
    /// literals here are what keep it from drifting.
    @Test
    func classicSurfaceShadowMatchesTheShippingOpenedSurface() {
        let shadow = IslandThemeTokens.classic.metrics.surfaceShadow

        #expect(shadow.color == Color.black)
        #expect(shadow.opacity == 0.36)
        #expect(shadow.radius == 22)
        #expect(shadow.yOffset == 12)
        #expect(shadow.resolvedColor == Color.black.opacity(0.36))
    }

    /// AB-320 shape pin: `closedSurfaceShadow` is opt-in. Every shipped theme
    /// leaves it `nil`, which is what makes the morph's new
    /// theme-driven closed shadow a no-op for all of them — the previous code
    /// hard-zeroed the closed end of the interpolation.
    @MainActor
    @Test
    func shippedThemesDeclareNoClosedSurfaceShadow() {
        for theme in ThemeRegistry.all {
            #expect(theme.tokens.metrics.closedSurfaceShadow == nil)
        }
    }

    /// The fallback the morph interpolates towards when a theme declares no
    /// closed shadow: same hue as the opened shadow, everything else zeroed —
    /// exactly the `opacity/radius/y == 0` the morph used to hard-code.
    @Test
    func resolvedClosedSurfaceShadowIsInertWithoutOptIn() {
        let metrics = IslandThemeTokens.classic.metrics
        let closed = metrics.resolvedClosedSurfaceShadow

        #expect(closed.color == metrics.surfaceShadow.color)
        #expect(closed.opacity == 0)
        #expect(closed.radius == 0)
        #expect(closed.yOffset == 0)
    }

    // MARK: - Motion

    /// Literal pin: `openAnimation` / `closeAnimation` / `popAnimation` /
    /// `openedSurfaceUnmountDelay` used to be file-private constants in
    /// `IslandPanelView.swift`. AB-295 pointed that view at these tokens and
    /// deleted the constants, so the parameters pinned here — plus the
    /// resolved `Animation` values below, which SwiftUI compares structurally
    /// — are the only definition of the island's transition motion.
    @Test
    func classicMotionMatchesTheShippingNotchTransitions() {
        let motion = IslandThemeTokens.classic.motion

        #expect(motion.openAnimation == .spring(response: 0.42, dampingFraction: 0.8, blendDuration: 0))
        #expect(motion.closeAnimation == .smooth(duration: 0.3, extraBounce: 0))
        #expect(motion.popAnimation == .spring(response: 0.3, dampingFraction: 0.5, blendDuration: 0))
        #expect(motion.openedSurfaceUnmountDelay == 0.36)
    }

    @Test
    func animationTokensResolveToTheExpectedSwiftUIAnimations() {
        let motion = IslandThemeTokens.classic.motion

        #expect(
            motion.openAnimation.animation
                == Animation.spring(response: 0.42, dampingFraction: 0.8, blendDuration: 0)
        )
        #expect(motion.closeAnimation.animation == Animation.smooth(duration: 0.3))
        #expect(motion.popAnimation.animation == Animation.spring(response: 0.3, dampingFraction: 0.5))
        #expect(IslandAnimationToken.easeInOut(duration: 0.18).animation == Animation.easeInOut(duration: 0.18))
    }

    // MARK: - Environment

    @Test
    func islandTokensEnvironmentDefaultsToClassic() {
        #expect(EnvironmentValues().islandTokens == IslandThemeTokens.classic)
    }

    @Test
    func islandTokensEnvironmentCanBeOverridden() {
        var values = EnvironmentValues()
        var custom = IslandThemeTokens.classic
        custom.metrics.openedTopRadius = 4
        values.islandTokens = custom

        #expect(values.islandTokens.metrics.openedTopRadius == 4)
        #expect(values.islandTokens != IslandThemeTokens.classic)
    }

    /// Compile-time proof that a view can read the tokens with
    /// `@Environment(\.islandTokens)`.
    private struct TokenReadingProbe: View {
        @Environment(\.islandTokens) private var tokens

        var body: some View {
            tokens.colors.surfaceInk
        }
    }

    @Test
    func aViewCanDeclareAnIslandTokensEnvironmentRead() {
        _ = TokenReadingProbe()
    }
}
