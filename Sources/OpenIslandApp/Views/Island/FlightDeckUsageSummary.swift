import SwiftUI
import OpenIslandCore

/// Flight Deck's usage readout (AB-312): each provider window is a segmented
/// *12-tick gauge* — a lane of flat square annunciator segments that light up in
/// proportion to the window's usage — trailed by a mono numeric percentage and a
/// NOM / CAUT / CRIT status placard, in the avionics-console idiom.
///
/// The colour thresholds are the exact `usageColor` cut-offs the rest of the app
/// ships (`IslandUsageSummary`: `>= 90` red, `70..<90` orange, else green); the
/// placard maps onto the same bands (CRIT / CAUT / NOM) so a red gauge always
/// carries the CRIT placard and the theme can't drift from the shared semantics.
/// Segments fill with a short sweep on appear and the CRIT band's gauge blinks;
/// both are gated off under Reduce Motion, where the gauge paints its final
/// segment count statically. Labels read their opacities through the token
/// contrast floor so they survive Increase Contrast, and — being a flat panel —
/// there is no transparency to reduce.
struct FlightDeckUsageSummary: View {
    let providers: [UsageProviderPresentation]
    let lang: LanguageManager

    var body: some View {
        ViewThatFits(in: .horizontal) {
            summaryRow(usesShortTitles: false)
            summaryRow(usesShortTitles: true)
        }
    }

    private func summaryRow(usesShortTitles: Bool) -> some View {
        HStack(spacing: 9) {
            ForEach(providers) { provider in
                FlightDeckUsageProviderChip(
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

/// One provider's flat avionics chip: its mono title plus a 12-tick gauge for
/// each of its rate-limit windows, boxed by a single hairline bezel rule.
struct FlightDeckUsageProviderChip: View {
    let provider: UsageProviderPresentation
    let usesShortTitle: Bool
    let lang: LanguageManager

    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    private var increasesContrast: Bool { colorSchemeContrast == .increased }

    @Environment(\.islandTokens) private var tokens

    var body: some View {
        HStack(spacing: 9) {
            Text(usesShortTitle ? provider.shortTitle : provider.title)
                .font(FlightDeckTypography.label)
                .foregroundStyle(tokens.colors.paper.opacity(tokens.colors.text(0.82, increaseContrast: increasesContrast)))

            ForEach(provider.windows) { window in
                FlightDeckUsageWindowGauge(window: window)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(tokens.colors.paper.opacity(increasesContrast ? 0.06 : 0.03))
                .overlay(
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .strokeBorder(
                            tokens.colors.paper.opacity(tokens.colors.hairline(increaseContrast: increasesContrast)),
                            lineWidth: 1
                        )
                )
        )
        .help(helpText)
        // One VoiceOver stop per provider — the same per-window summary the app
        // surfaces through `.help()`, matching Classic / Poured / Instrument
        // (AB-244).
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

/// A single window's 12-tick segmented gauge, its numeric percentage, and its
/// CRIT / CAUT / NOM status placard.
struct FlightDeckUsageWindowGauge: View {
    let window: UsageWindowPresentation

    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    private var increasesContrast: Bool { colorSchemeContrast == .increased }

    @Environment(\.islandTokens) private var tokens

    private var color: Color { Self.usageColor(for: window.usedPercentage) }
    private var placard: FlightDeckUsagePlacard { Self.placard(for: window.usedPercentage) }

    var body: some View {
        HStack(spacing: 5) {
            Text(window.label)
                .font(FlightDeckTypography.microLabel)
                .foregroundStyle(tokens.colors.paper.opacity(tokens.colors.text(tokens.colors.secondaryTextOpacity, increaseContrast: increasesContrast)))

            FlightDeckTickGauge(
                fraction: window.usedPercentage / 100,
                color: color,
                isCritical: window.usedPercentage >= 90
            )

            Text("\(window.roundedUsedPercentage)%")
                .font(.system(size: FlightDeckTypography.countSize, weight: .bold, design: .monospaced))
                .foregroundStyle(color)

            Text(placard.rawValue)
                .font(FlightDeckTypography.microLabel)
                .foregroundStyle(color)
                .accessibilityHidden(true)
        }
    }

    /// The exact `usageColor` cut-offs the app ships (`IslandUsageSummary`):
    /// `>= 90` red, `70..<90` orange, else green — the theme must not drift.
    static func usageColor(for percentage: Double) -> Color {
        switch percentage {
        case 90...:
            .red.opacity(0.95)
        case 70..<90:
            .orange.opacity(0.95)
        default:
            .green.opacity(0.95)
        }
    }

    /// The status placard over the same bands as `usageColor`, so a red gauge
    /// always reads CRIT and a green gauge NOM.
    static func placard(for percentage: Double) -> FlightDeckUsagePlacard {
        switch percentage {
        case 90...:
            .crit
        case 70..<90:
            .caut
        default:
            .nom
        }
    }
}

/// The CRIT / CAUT / NOM status placard banded onto a usage percentage.
/// `rawValue` is the rendered mono glyph — deliberately terse and script-neutral
/// (avionics placards, not prose, so they stay Latin in every locale, the same
/// way EICAS legends do).
enum FlightDeckUsagePlacard: String {
    case crit = "CRIT"
    case caut = "CAUT"
    case nom = "NOM"
}

/// The 12-tick gauge itself: a fixed lane of flat square annunciator segments.
/// Filled segments light the band colour; the rest sit dark in the console
/// ground. The fill sweeps up on appear and a critical gauge blinks — both
/// disabled under Reduce Motion, where the gauge paints its final segment count
/// statically. Empty-segment opacity lifts under Increase Contrast so the gauge
/// stays readable.
struct FlightDeckTickGauge: View {
    let fraction: Double
    let color: Color
    let isCritical: Bool

    /// The ticket pins a **12-tick** gauge.
    var segments: Int = 12
    var tickWidth: CGFloat = 3
    var tickHeight: CGFloat = 9
    var spacing: CGFloat = 2

    @State private var animatedFilled: Int = 0
    @State private var blink = false

    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    private var increasesContrast: Bool { colorSchemeContrast == .increased }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.islandTokens) private var tokens

    private var clampedFraction: Double { min(1, max(0, fraction)) }

    /// Segments lit for the current fraction — at least one whenever there is any
    /// usage, so a non-zero window never reads as fully dark.
    private var filledCount: Int {
        guard clampedFraction > 0 else { return 0 }
        return max(1, Int((clampedFraction * Double(segments)).rounded()))
    }

    private var emptyOpacity: Double {
        increasesContrast ? 0.36 : 0.2
    }

    var body: some View {
        HStack(spacing: spacing) {
            ForEach(0..<segments, id: \.self) { index in
                let isFilled = index < animatedFilled
                RoundedRectangle(cornerRadius: 0.5, style: .continuous)
                    .fill(isFilled
                        ? color.opacity(isCritical && !reduceMotion && !blink ? 0.55 : 1)
                        : tokens.colors.paper.opacity(emptyOpacity))
                    .frame(width: tickWidth, height: tickHeight)
            }
        }
        .onAppear {
            if reduceMotion {
                animatedFilled = filledCount
            } else {
                withAnimation(.easeOut(duration: 0.5)) {
                    animatedFilled = filledCount
                }
                if isCritical {
                    withAnimation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true)) {
                        blink = true
                    }
                }
            }
        }
        .onChange(of: fraction) { _, _ in
            if reduceMotion {
                animatedFilled = filledCount
            } else {
                withAnimation(.easeOut(duration: 0.35)) {
                    animatedFilled = filledCount
                }
            }
        }
        .accessibilityHidden(true)
    }
}
