import SwiftUI
import OpenIslandCore

/// Flight Deck's usage readout (AB-312 → AB-338): each provider window is a
/// *continuous tape gauge* — a recessed instrument track whose fill sweeps
/// 0–100% with fixed threshold ticks at 70% and 90%, headed by a sans gauge
/// legend + a mono tabular value and trailed by an inline `RESET` countdown, in
/// the avionics-console idiom. AB-338 replaced the shipped 12-tick segmented lane
/// with this tape geometry and surfaced `resetsAt` inline (it was `.help()`-only).
///
/// The colour thresholds are the exact `usageColor` cut-offs the rest of the app
/// ships (`IslandUsageSummary`: `>= 90` red, `70..<90` orange, else green); the
/// placard maps onto the same bands (CRIT / CAUT / NOM) so a red gauge always
/// carries the CRIT semantics and the theme can't drift from the shared meaning.
/// The fill sweeps up on appear and the CRIT band's fill blinks at the 1.2s
/// caution cadence (`FlightDeckMotion.Attention.cautionPeriod`); both are gated
/// off under Reduce Motion, where the gauge paints its final fill statically.
/// Labels read their opacities through the token contrast floor so they survive
/// Increase Contrast, and — being a flat panel — there is no transparency to
/// reduce.
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
        HStack(alignment: .top, spacing: 12) {
            ForEach(providers) { provider in
                FlightDeckUsageProviderChip(
                    provider: provider,
                    usesShortTitle: usesShortTitles,
                    lang: lang
                )
            }
        }
        .fixedSize(horizontal: true, vertical: false)
    }
}

/// One provider's flat avionics chip: a stacked column of tape gauges — one per
/// rate-limit window — boxed by a single hairline bezel rule. Each gauge folds
/// the provider title into its legend (`Claude · 5H`) per the mockup, so the
/// chip no longer carries a separate title line.
struct FlightDeckUsageProviderChip: View {
    let provider: UsageProviderPresentation
    let usesShortTitle: Bool
    let lang: LanguageManager

    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    private var increasesContrast: Bool { colorSchemeContrast == .increased }

    @Environment(\.islandTokens) private var tokens

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            ForEach(provider.windows) { window in
                FlightDeckUsageWindowGauge(label: legend(for: window), window: window)
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
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

    /// The gauge legend — the provider title (full or short) joined to the
    /// window's window-label, uppercased Latin per the EICAS placard idiom
    /// (`Claude · 5H`). The title itself is left in its native casing.
    private func legend(for window: UsageWindowPresentation) -> String {
        let title = usesShortTitle ? provider.shortTitle : provider.title
        return "\(title) · \(window.label.uppercased())"
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

/// A single window's continuous tape gauge: its sans legend + mono tabular
/// percentage on the head row, the recessed tape track (fill + 70/90 threshold
/// ticks) beneath, and — when the window carries a reset time — an inline
/// `RESET <countdown>` readout at the foot. The value colours by the shared
/// usage cut-offs; a critical (≥90) window's fill crosses the 90 tick and blinks.
struct FlightDeckUsageWindowGauge: View {
    /// The gauge legend (`Claude · 5H`), built by the enclosing chip so the tape
    /// gauge stays agnostic of provider identity.
    let label: String
    let window: UsageWindowPresentation

    /// The gauge's fixed drawing width, so the summary keeps an intrinsic size
    /// under `fixedSize(horizontal:)` (a bare `GeometryReader` would collapse to
    /// zero). Wide enough for the longest legend + value on the head row and a
    /// `RESET 4D 06H` foot row.
    static let gaugeWidth: CGFloat = 150

    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    private var increasesContrast: Bool { colorSchemeContrast == .increased }

    @Environment(\.islandTokens) private var tokens

    private var color: Color { Self.usageColor(for: window.usedPercentage) }
    private var placard: FlightDeckUsagePlacard { Self.placard(for: window.usedPercentage) }
    private var isCritical: Bool { window.usedPercentage >= 90 }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            headRow
            FlightDeckTapeGauge(
                fraction: window.usedPercentage / 100,
                color: color,
                isCritical: isCritical
            )
            if let resets = window.remainingLabel(asOf: Date()) {
                resetRow(resets)
            }
        }
        .frame(width: Self.gaugeWidth, alignment: .leading)
    }

    private var headRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(label)
                .font(FlightDeckTypography.gaugeLabel)
                .foregroundStyle(tokens.colors.paper.opacity(tokens.colors.text(0.78, increaseContrast: increasesContrast)))
                .lineLimit(1)

            Spacer(minLength: 4)

            HStack(alignment: .firstTextBaseline, spacing: 1) {
                Text("\(window.roundedUsedPercentage)")
                    .font(.system(size: FlightDeckTypography.countSize, weight: .bold, design: .monospaced))
                Text("%")
                    .font(.system(size: FlightDeckTypography.countSize - 2, weight: .semibold, design: .monospaced))
                    .baselineOffset(0)
            }
            .foregroundStyle(color)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
        }
    }

    /// The inline `RESET <countdown>` readout. `RESET` is a Latin placard (EICAS
    /// legend rule — kept Latin in every locale, like CRIT / CAUT / NOM); the
    /// countdown is the shared AB-324 formatting uppercased to mono tabular
    /// (`RESET 2H 10M`). The tooltip retains the full per-window summary.
    private func resetRow(_ countdown: String) -> some View {
        HStack(spacing: 4) {
            Text("RESET")
                .font(FlightDeckTypography.microLabel)
                .foregroundStyle(tokens.colors.paper.opacity(tokens.colors.text(0.5, increaseContrast: increasesContrast)))
            Spacer(minLength: 4)
            Text(countdown.uppercased())
                .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                .foregroundStyle(tokens.colors.paper.opacity(tokens.colors.text(0.58, increaseContrast: increasesContrast)))
        }
        .lineLimit(1)
        // The reset readout is redundant with the provider chip's VoiceOver
        // summary (built from the same `remainingLabel`), so it stays out of the
        // accessibility tree to avoid double-reading.
        .accessibilityHidden(true)
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
    /// always reads CRIT and a green gauge NOM. Retained for parity tests and the
    /// shared band semantics; the tape gauge conveys the band through fill + value
    /// colour rather than a rendered glyph (per the mockup).
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

/// The continuous tape gauge itself (AB-338): a recessed instrument track sunk
/// into the panel (`FlightDeckSurfaces.well`) whose fill bar sweeps the band
/// colour from 0 to the current fraction, crossed by two fixed threshold ticks —
/// a hairline tier-2 rule at 70% and a red `crit` rule at 90% — drawn at fixed x
/// regardless of the fill. The fill sweeps up on appear; a critical gauge's fill
/// blinks at the 1.2s caution cadence. Both are disabled under Reduce Motion,
/// where the fill paints its final width steadily, fully lit. The blink is a
/// `@State` peak/trough toggle (the `FlightDeckAnnunciatorLamp` precedent), so it
/// never advances under a disabled-animation transaction — a snapshot captures
/// the steady lit frame.
struct FlightDeckTapeGauge: View {
    let fraction: Double
    let color: Color
    let isCritical: Bool

    /// The fixed threshold tick positions (fraction of the track width), drawn
    /// regardless of the fill: the 70% hairline caution tick and the 90% red
    /// critical tick. Pinned by `FlightDeckThemeTests` (replacing the retired
    /// `tickGaugeIsTwelveSegments` segment-count pin).
    static let hairlineTickPosition: Double = 0.70
    static let criticalTickPosition: Double = 0.90
    static let thresholdTicks: [Double] = [hairlineTickPosition, criticalTickPosition]

    var trackHeight: CGFloat = 8
    /// How far each threshold tick overhangs the track top and bottom (mockup
    /// `.tick { top:-2px; bottom:-2px }`).
    private static let tickOverhang: CGFloat = 2

    @State private var blinkPhase = false

    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    private var increasesContrast: Bool { colorSchemeContrast == .increased }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.islandTokens) private var tokens

    private var clampedFraction: Double { min(1, max(0, fraction)) }

    /// The fill's live opacity: fully lit, unless a critical gauge is mid-blink
    /// (and motion is allowed), where it dips to the caution trough. Reduce Motion
    /// and the non-critical bands hold it fully lit.
    private var fillOpacity: Double {
        guard isCritical, !reduceMotion, blinkPhase else { return FlightDeckMotion.Attention.opacityMax }
        return FlightDeckMotion.Attention.opacityMin
    }

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            ZStack(alignment: .leading) {
                // Recessed well track (sunk into the panel) + faint bezel rule.
                RoundedRectangle(cornerRadius: 1, style: .continuous)
                    .fill(FlightDeckSurfaces.well)
                    .overlay(
                        RoundedRectangle(cornerRadius: 1, style: .continuous)
                            .strokeBorder(
                                FlightDeckSurfaces.hairline(tier: 1, increaseContrast: increasesContrast),
                                lineWidth: 1
                            )
                    )
                    .frame(height: trackHeight)

                // Continuous fill 0 → fraction, in the band colour.
                RoundedRectangle(cornerRadius: 1, style: .continuous)
                    .fill(color)
                    .frame(width: max(0, width * clampedFraction), height: trackHeight)
                    .opacity(fillOpacity)

                // Fixed threshold ticks — at 70% (hairline tier-2) and 90% (crit
                // red), at fixed x regardless of fill.
                tick(
                    at: Self.hairlineTickPosition,
                    trackWidth: width,
                    color: FlightDeckSurfaces.hairline(tier: 2, increaseContrast: increasesContrast)
                )
                tick(
                    at: Self.criticalTickPosition,
                    trackWidth: width,
                    color: .red.opacity(0.65)
                )
            }
        }
        .frame(height: trackHeight)
        .onAppear { startBlinkIfNeeded() }
        .onChange(of: isCritical) { _, _ in startBlinkIfNeeded() }
        .accessibilityHidden(true)
    }

    /// A 1pt threshold rule positioned at `position` of the track width,
    /// overhanging the track top and bottom by `tickOverhang`.
    private func tick(at position: Double, trackWidth: CGFloat, color: Color) -> some View {
        Rectangle()
            .fill(color)
            .frame(width: 1, height: trackHeight + Self.tickOverhang * 2)
            .offset(x: trackWidth * position - 0.5)
    }

    /// Starts (or clears) the critical blink — a peak/trough toggle on a
    /// half-cadence ease-in-out that autoreverses forever, so `fillOpacity`
    /// bounces between the caution peak and trough over one `cautionPeriod`. A
    /// non-critical gauge or Reduce Motion pins it lit and never acquires the
    /// animation.
    private func startBlinkIfNeeded() {
        guard isCritical, !reduceMotion else {
            blinkPhase = false
            return
        }
        blinkPhase = false
        withAnimation(
            .easeInOut(duration: FlightDeckMotion.Attention.cautionPeriod / 2).repeatForever(autoreverses: true)
        ) {
            blinkPhase = true
        }
    }
}
