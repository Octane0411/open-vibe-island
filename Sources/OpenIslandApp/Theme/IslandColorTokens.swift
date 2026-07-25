import SwiftUI
import OpenIslandCore

/// Colour half of the island theme token layer.
///
/// Values are lifted verbatim from the pre-theme constants they will
/// eventually replace: `V6Palette` for the two surface tones, and
/// `IslandDesignPalette.Status` / `.Contrast` for status tints, body-text
/// opacities and hairline dividers.
///
/// Nothing consumes these yet — later tickets route views through the token
/// layer one region at a time, and the legacy constants stay in place until
/// their last call site is migrated. `IslandThemeTokensTests` pins every
/// `classic` value against the live constant so drift in either direction
/// fails the build.
struct IslandColorTokens: Equatable, Sendable {

    // MARK: - Surface

    /// Near-black island body. Mirrors `V6Palette.ink`.
    var surfaceInk: Color

    /// Warm off-white for text and glyphs drawn on `surfaceInk`.
    /// Mirrors `V6Palette.paper`.
    var paper: Color

    /// Neutral foreground drawn on `surfaceInk`: body copy and the
    /// translucent washes (code backgrounds, table fills, rules) derived from
    /// it by opacity rather than by a separate colour. Distinct from `paper`,
    /// which is the warmer accent tone reserved for badges, primary buttons
    /// and headline chrome.
    var surfaceText: Color

    // MARK: - Status tints

    /// A session that is actively working.
    var statusRunning: Color

    /// A session that finished successfully.
    var statusCompleted: Color

    /// A session blocked on a permission request.
    var statusWaitingForApproval: Color

    /// A session blocked on a question.
    var statusWaitingForAnswer: Color

    /// Single tint for a collapsed "N sessions waiting" roll-up, where the
    /// individual approval/answer tints would be misleading.
    var statusWaitingAggregate: Color

    /// Shared "caution" amber — bypass-permissions chips and the interrupted
    /// completion outcome.
    var statusWarning: Color

    /// A session whose turn was interrupted. Same amber as `statusWarning`.
    var statusInterrupted: Color

    /// A session that finished with a failure outcome.
    var statusFailed: Color

    /// An idle session with no recent activity.
    var statusIdle: Color

    /// A session whose process is no longer running.
    var statusInactive: Color

    // MARK: - Text contrast

    /// Opacity for de-emphasised-but-informative body text.
    var secondaryTextOpacity: Double

    /// Opacity for the dimmest still-legible text tier.
    var tertiaryTextOpacity: Double

    /// Added to a text opacity (clamped at 1) when the user has the system's
    /// Increase Contrast setting enabled.
    var increasedContrastTextBoost: Double

    // MARK: - Hairline

    /// Opacity for row/section dividers at default contrast.
    var hairlineOpacity: Double

    /// Opacity for row/section dividers when Increase Contrast is enabled.
    var hairlineOpacityIncreasedContrast: Double
}

// MARK: - Derived contrast values

extension IslandColorTokens {
    /// Mirrors `IslandDesignPalette.Contrast.text(_:increaseContrast:)`.
    func text(_ base: Double, increaseContrast: Bool) -> Double {
        increaseContrast ? min(1, base + increasedContrastTextBoost) : base
    }

    /// Mirrors `IslandDesignPalette.Contrast.hairline(increaseContrast:)`.
    func hairline(increaseContrast: Bool) -> Double {
        increaseContrast ? hairlineOpacityIncreasedContrast : hairlineOpacity
    }

    /// `secondaryTextOpacity` with the Increase Contrast boost applied.
    var secondaryTextOpacityIncreasedContrast: Double {
        text(secondaryTextOpacity, increaseContrast: true)
    }

    /// `tertiaryTextOpacity` with the Increase Contrast boost applied.
    var tertiaryTextOpacityIncreasedContrast: Double {
        text(tertiaryTextOpacity, increaseContrast: true)
    }
}

// MARK: - Status tint resolution

extension IslandColorTokens {
    /// Mirrors `IslandDesignPalette.Status.tint(for:outcome:)`.
    func statusTint(for phase: SessionPhase, outcome: SessionOutcome = .success) -> Color {
        switch phase {
        case .waitingForApproval:
            statusWaitingForApproval
        case .waitingForAnswer:
            statusWaitingForAnswer
        case .running:
            statusRunning
        case .completed:
            switch outcome {
            case .success:
                statusCompleted
            case .interrupted:
                statusInterrupted
            case .failed:
                statusFailed
            }
        }
    }

    /// Mirrors `IslandDesignPalette.Status.tint(for:presence:outcome:)`.
    func statusTint(
        for phase: SessionPhase,
        presence: IslandSessionPresence,
        outcome: SessionOutcome = .success
    ) -> Color {
        if phase == .waitingForApproval || phase == .waitingForAnswer {
            return statusTint(for: phase)
        }

        switch presence {
        case .running:
            return statusRunning
        case .active:
            // Presence only resolves to `.active` here when the phase is
            // `.completed` (running/attention phases are handled above),
            // so it's safe to fold in the outcome tint.
            return statusTint(for: .completed, outcome: outcome)
        case .inactive:
            return statusInactive
        }
    }
}

// MARK: - Classic

extension IslandColorTokens {
    /// Today's shipping palette, expressed as literals so the token layer is
    /// self-contained once the legacy constants are retired.
    static let classic = IslandColorTokens(
        surfaceInk: classicInk,
        paper: classicPaper,
        surfaceText: .white,
        statusRunning: Color(red: 110.0 / 255.0, green: 167.0 / 255.0, blue: 255.0 / 255.0),
        statusCompleted: Color(red: 111.0 / 255.0, green: 185.0 / 255.0, blue: 130.0 / 255.0),
        statusWaitingForApproval: Color(red: 244.0 / 255.0, green: 164.0 / 255.0, blue: 164.0 / 255.0),
        statusWaitingForAnswer: Color(red: 255.0 / 255.0, green: 213.0 / 255.0, blue: 138.0 / 255.0),
        statusWaitingAggregate: Color(red: 231.0 / 255.0, green: 167.0 / 255.0, blue: 98.0 / 255.0),
        statusWarning: classicWarning,
        statusInterrupted: classicWarning,
        statusFailed: Color(red: 0.86, green: 0.32, blue: 0.32),
        statusIdle: classicPaper.opacity(0.35),
        statusInactive: classicPaper.opacity(0.38),
        secondaryTextOpacity: 0.55,
        tertiaryTextOpacity: 0.48,
        increasedContrastTextBoost: 0.24,
        hairlineOpacity: 0.055,
        hairlineOpacityIncreasedContrast: 0.22
    )

    private static let classicInk = Color(red: 0x0d / 255.0, green: 0x0d / 255.0, blue: 0x0f / 255.0)
    private static let classicPaper = Color(red: 0xf1 / 255.0, green: 0xea / 255.0, blue: 0xd9 / 255.0)
    private static let classicWarning = Color(red: 0.85, green: 0.55, blue: 0.15)
}

// MARK: - Poured Island

extension IslandColorTokens {
    /// Poured Island's cool liquid-glass identity: a blue-black ink under the
    /// frosted slab and a cool near-white for glyphs and labels. The vivid
    /// status tints are shared with Classic — they already read cleanly on a
    /// dark surface and keep the two themes' status semantics identical — while
    /// the neutral surface tones go cool to match the glass. Hairlines are a
    /// touch stronger so dividers survive the added translucency.
    static let poured = IslandColorTokens(
        surfaceInk: pouredInk,
        paper: pouredPaper,
        surfaceText: .white,
        statusRunning: classic.statusRunning,
        statusCompleted: classic.statusCompleted,
        statusWaitingForApproval: classic.statusWaitingForApproval,
        statusWaitingForAnswer: classic.statusWaitingForAnswer,
        statusWaitingAggregate: classic.statusWaitingAggregate,
        statusWarning: classic.statusWarning,
        statusInterrupted: classic.statusInterrupted,
        statusFailed: classic.statusFailed,
        statusIdle: pouredPaper.opacity(0.35),
        statusInactive: pouredPaper.opacity(0.38),
        secondaryTextOpacity: 0.6,
        tertiaryTextOpacity: 0.5,
        increasedContrastTextBoost: 0.24,
        hairlineOpacity: 0.08,
        hairlineOpacityIncreasedContrast: 0.24
    )

    private static let pouredInk = Color(red: 0x0b / 255.0, green: 0x0e / 255.0, blue: 0x16 / 255.0)
    private static let pouredPaper = Color(red: 0xf2 / 255.0, green: 0xf5 / 255.0, blue: 0xfb / 255.0)
}

// MARK: - Instrument

extension IslandColorTokens {
    /// Instrument (precision monospace console): a near-monochrome palette where
    /// colour is spent *only* on status. The surface is a near-black console
    /// ground with a cool light-grey ink; the status tints collapse to the three
    /// the design language allows — one alarm red (approval / failure), one
    /// run/done green (running and completed share the "live" green), and a
    /// caution amber for the softer waiting/interrupted states — while idle and
    /// inactive drop to dim greys. Hairlines are stronger than Classic's because
    /// hairline rules are a load-bearing part of the instrument look, not an
    /// afterthought.
    static let instrument = IslandColorTokens(
        surfaceInk: instrumentInk,
        paper: instrumentPaper,
        surfaceText: .white,
        statusRunning: instrumentGreen,
        statusCompleted: instrumentGreen,
        statusWaitingForApproval: instrumentAlarm,
        statusWaitingForAnswer: instrumentAmber,
        statusWaitingAggregate: instrumentAmber,
        statusWarning: instrumentAmber,
        statusInterrupted: instrumentAmber,
        statusFailed: instrumentAlarm,
        statusIdle: instrumentPaper.opacity(0.32),
        statusInactive: instrumentPaper.opacity(0.28),
        secondaryTextOpacity: 0.6,
        tertiaryTextOpacity: 0.5,
        increasedContrastTextBoost: 0.24,
        hairlineOpacity: 0.12,
        hairlineOpacityIncreasedContrast: 0.3
    )

    private static let instrumentInk = Color(red: 0x0a / 255.0, green: 0x0a / 255.0, blue: 0x0b / 255.0)
    private static let instrumentPaper = Color(red: 0xdf / 255.0, green: 0xe1 / 255.0, blue: 0xde / 255.0)
    private static let instrumentGreen = Color(red: 76.0 / 255.0, green: 201.0 / 255.0, blue: 111.0 / 255.0)
    private static let instrumentAlarm = Color(red: 235.0 / 255.0, green: 77.0 / 255.0, blue: 75.0 / 255.0)
    private static let instrumentAmber = Color(red: 224.0 / 255.0, green: 168.0 / 255.0, blue: 74.0 / 255.0)
}
