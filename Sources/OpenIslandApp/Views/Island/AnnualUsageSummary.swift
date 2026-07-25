import SwiftUI
import OpenIslandCore

/// Annual's usage readout (AB-316): each provider window is rendered as an
/// **oversized light numeral** percentage trailed by a small-caps
/// healthy / elevated / critical **verdict** and underlined by a **2px hairline
/// meter** that fills in proportion to the window's usage — the editorial idiom,
/// where colour is spent only where it must be.
///
/// The verdict bands are the exact `usageColor` cut-offs the rest of the app
/// ships (`IslandUsageSummary`: `>= 90` critical, `70..<90` elevated, else
/// healthy). Accent discipline is strict: **only the critical figure** (its
/// numeral, verdict and meter fill) lights the one Annual accent — every calm
/// (healthy / elevated) window draws in warm paper, so a healthy usage lane
/// carries zero accent pixels. The meter fills with a short sweep on appear,
/// gated off under Reduce Motion where it paints its final width statically.
/// Labels read their opacities through the token contrast floor so they survive
/// Increase Contrast, and — being a flat page — there is no transparency to
/// reduce.
struct AnnualUsageSummary: View {
    let providers: [UsageProviderPresentation]
    let lang: LanguageManager

    var body: some View {
        ViewThatFits(in: .horizontal) {
            summaryRow(usesShortTitles: false)
            summaryRow(usesShortTitles: true)
        }
    }

    private func summaryRow(usesShortTitles: Bool) -> some View {
        HStack(spacing: 14) {
            ForEach(providers) { provider in
                AnnualUsageProviderGroup(
                    provider: provider,
                    usesShortTitle: usesShortTitles,
                    lang: lang
                )
            }
        }
        .lineLimit(1)
        .fixedSize(horizontal: true, vertical: false)
    }
}

/// One provider's editorial usage group: its small-caps title followed by an
/// oversized-numeral readout for each of its rate-limit windows. No box, no
/// pill — the provider is set off by type and whitespace alone.
struct AnnualUsageProviderGroup: View {
    let provider: UsageProviderPresentation
    let usesShortTitle: Bool
    let lang: LanguageManager

    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    private var increasesContrast: Bool { colorSchemeContrast == .increased }

    @Environment(\.islandTokens) private var tokens

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Text(AnnualText.lower(usesShortTitle ? provider.shortTitle : provider.title, lang: lang))
                .font(AnnualTypography.smallCaps)
                .tracking(AnnualText.tracking(0.8, lang: lang))
                .foregroundStyle(tokens.colors.paper.opacity(tokens.colors.text(0.72, increaseContrast: increasesContrast)))

            ForEach(provider.windows) { window in
                AnnualUsageWindowReadout(window: window, lang: lang)
            }
        }
        .help(helpText)
        // One VoiceOver stop per provider — the same per-window summary the app
        // surfaces through `.help()`, matching the other themes (AB-244).
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(usesShortTitle ? provider.shortTitle : provider.title) \(helpText)")
    }

    private var helpText: String {
        provider.windows.map { window in
            var parts = ["\(window.label) \(window.roundedUsedPercentage)%"]
            if let remaining = window.remainingLabel(asOf: Date()) {
                parts.append(remaining)
            }
            return parts.joined(separator: " ")
        }
        .joined(separator: " · ")
    }
}

/// A single window's editorial readout: its lowercase unit label, an oversized
/// light numeral percentage, a small-caps verdict, and a 2px hairline meter. The
/// numeral / verdict / meter light the accent only when the window is critical.
struct AnnualUsageWindowReadout: View {
    let window: UsageWindowPresentation
    let lang: LanguageManager

    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    private var increasesContrast: Bool { colorSchemeContrast == .increased }

    @Environment(\.islandTokens) private var tokens

    private var verdict: AnnualUsageVerdict { AnnualUsageVerdict.verdict(for: window.usedPercentage) }
    private var usesAccent: Bool { verdict.isCritical }

    /// The one place a usage figure spends the accent: the critical numeral.
    /// Every calm window draws in warm paper.
    private var figureColor: Color {
        usesAccent
            ? IslandColorTokens.annualAccent
            : tokens.colors.paper.opacity(tokens.colors.text(0.9, increaseContrast: increasesContrast))
    }

    private var verdictColor: Color {
        usesAccent
            ? IslandColorTokens.annualAccent
            : tokens.colors.paper.opacity(tokens.colors.text(tokens.colors.secondaryTextOpacity, increaseContrast: increasesContrast))
    }

    var body: some View {
        HStack(alignment: .center, spacing: 6) {
            Text(AnnualText.lower(window.label, lang: lang))
                .font(AnnualTypography.microLabel)
                .tracking(AnnualText.tracking(0.4, lang: lang))
                .foregroundStyle(tokens.colors.paper.opacity(tokens.colors.text(tokens.colors.tertiaryTextOpacity, increaseContrast: increasesContrast)))

            HStack(alignment: .firstTextBaseline, spacing: 1) {
                Text("\(window.roundedUsedPercentage)")
                    .font(AnnualTypography.headerNumeral)
                    .foregroundStyle(figureColor)
                Text("%")
                    .font(.system(size: 11, weight: .regular, design: .default))
                    .foregroundStyle(figureColor.opacity(0.7))
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(AnnualText.lower(lang.t(verdict.localizationKey), lang: lang))
                    .font(AnnualTypography.smallCaps)
                    .tracking(AnnualText.tracking(0.6, lang: lang))
                    .foregroundStyle(verdictColor)
                    .accessibilityHidden(true)

                AnnualUsageMeter(fraction: window.usedPercentage / 100, usesAccent: usesAccent)
                    .frame(width: 34)
            }
        }
    }
}

/// The verdict banded onto a usage percentage, on the exact `usageColor` cut-offs
/// the app ships so Annual can't drift from the shared usage semantics. Only
/// `critical` is loud — it is the sole verdict that spends the Annual accent.
enum AnnualUsageVerdict: String {
    case healthy
    case elevated
    case critical

    /// The bands mirror `IslandUsageSummary.usageColor`: `>= 90` critical (its
    /// red band), `70..<90` elevated (its orange band), else healthy (its green
    /// band).
    static func verdict(for percentage: Double) -> AnnualUsageVerdict {
        switch percentage {
        case 90...:
            .critical
        case 70..<90:
            .elevated
        default:
            .healthy
        }
    }

    /// Only the critical verdict is allowed to spend the accent, on the figure,
    /// the verdict word and the meter fill — the accent-discipline guarantee for
    /// calm usage surfaces, pinned by `AnnualThemeTests`.
    var isCritical: Bool { self == .critical }

    var localizationKey: String { "island.annual.usage.\(rawValue)" }
}

/// A window's 2px hairline meter: a full-width track hairline with a filled bar
/// sized to the window's usage. The fill sweeps in on appear and settles
/// statically under Reduce Motion; it lights the accent only when the window is
/// critical, and the empty track lifts under Increase Contrast so it stays
/// visible.
struct AnnualUsageMeter: View {
    let fraction: Double
    let usesAccent: Bool

    @State private var animatedFraction: Double = 0

    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    private var increasesContrast: Bool { colorSchemeContrast == .increased }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.islandTokens) private var tokens

    private var clampedFraction: Double { min(1, max(0, fraction)) }

    private var fillColor: Color {
        usesAccent
            ? IslandColorTokens.annualAccent
            : tokens.colors.paper.opacity(tokens.colors.text(0.6, increaseContrast: increasesContrast))
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Rectangle()
                    .fill(tokens.colors.paper.opacity(tokens.colors.hairline(increaseContrast: increasesContrast)))
                    .frame(height: AnnualHairline.rule)

                Rectangle()
                    .fill(fillColor)
                    .frame(width: max(0, geometry.size.width * animatedFraction), height: AnnualHairline.rule)
            }
            .frame(maxHeight: .infinity, alignment: .center)
        }
        .frame(height: AnnualHairline.rule)
        .onAppear {
            if reduceMotion {
                animatedFraction = clampedFraction
            } else {
                withAnimation(.easeOut(duration: 0.5)) {
                    animatedFraction = clampedFraction
                }
            }
        }
        .onChange(of: fraction) { _, _ in
            if reduceMotion {
                animatedFraction = clampedFraction
            } else {
                withAnimation(.easeOut(duration: 0.35)) {
                    animatedFraction = clampedFraction
                }
            }
        }
        .accessibilityHidden(true)
    }
}
