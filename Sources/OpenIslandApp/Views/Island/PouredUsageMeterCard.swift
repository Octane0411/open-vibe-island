import SwiftUI
import OpenIslandCore

/// Poured Island 2.0's **full** usage meter card (AB-331, `SPEC-poured-island`
/// §4I / mockup §I).
///
/// Where the header lane compresses usage into a 30pt ring, this is the
/// expanded surface: a glass card of **52pt conic dials**, one per provider
/// window, each carrying the `provider · window` label, an oversized tabular
/// percentage, the inline `resets in …` countdown (T06), and a threshold pill
/// that states the band as **word + shape** (`Fine ●` / `Warn ▲` / `Critical ●`)
/// so the state is never colour-alone. Higher percentage = more consumed (the
/// dial fills proportionally). The `>= 90` critical dial keeps Poured's 0.8s
/// danger-glow breathe, held static under Reduce Motion by `PouredUsageRing`.
///
/// Colour is the single `PouredUsageThreshold` rule shared with the header ring:
/// `fine → statusCompleted`, `warn → statusWaitingForAnswer`,
/// `critical → statusFailed`, on the unchanged `>= 90` / `70..<90` / else
/// cut-offs.
struct PouredUsageMeterCard: View {
    let providers: [UsageProviderPresentation]
    let lang: LanguageManager
    /// Injected so the reset countdowns render deterministically; defaults to
    /// the wall clock.
    var now: Date = .now

    @Environment(\.islandTokens) private var tokens
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    private struct Entry: Identifiable {
        let id: String
        let providerTitle: String
        let window: UsageWindowPresentation
    }

    private var entries: [Entry] {
        providers.flatMap { provider in
            provider.windows.map { window in
                Entry(
                    id: "\(provider.id)-\(window.id)",
                    providerTitle: provider.title,
                    window: window
                )
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(lang.t("island.poured.usage.metersTitle").uppercased())
                .font(.system(size: 11, weight: .semibold))
                .tracking(0.9)
                .foregroundStyle(.white.opacity(tokens.colors.tertiaryTextOpacity))

            HStack(alignment: .top, spacing: 22) {
                ForEach(entries) { entry in
                    PouredUsageMeter(
                        providerTitle: entry.providerTitle,
                        window: entry.window,
                        now: now,
                        lang: lang
                    )
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 16)
        .padding(.bottom, 18)
        .background(cardBackground)
    }

    private var cardBackground: some View {
        let shape = RoundedRectangle(cornerRadius: tokens.metrics.openedTopRadius, style: .continuous)
        return ZStack {
            shape.fill(tokens.colors.surfaceInk)

            // The Poured body gradient carries elevation by inner luminance;
            // non-Poured tokens (no `bodyGradient`) keep the flat ink base.
            if let stops = tokens.material.bodyGradient {
                shape.fill(
                    LinearGradient(
                        stops: stops.map { Gradient.Stop(color: $0.resolvedColor, location: $0.location) },
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
            }
        }
        .overlay(
            shape.strokeBorder(.white.opacity(reduceTransparency ? 0.12 : 0.08), lineWidth: 1)
        )
    }
}

/// One provider window's §I meter: a 52pt conic dial beside the label, oversized
/// percentage, inline reset countdown, and the word+shape threshold pill.
struct PouredUsageMeter: View {
    let providerTitle: String
    let window: UsageWindowPresentation
    let now: Date
    let lang: LanguageManager

    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    private var increasesContrast: Bool { colorSchemeContrast == .increased }

    @Environment(\.islandTokens) private var tokens

    private var threshold: PouredUsageThreshold {
        PouredUsageThreshold.threshold(for: window.usedPercentage)
    }

    private var color: Color { threshold.color(tokens.colors) }

    var body: some View {
        HStack(spacing: 12) {
            PouredUsageRing(
                fraction: window.usedPercentage / 100,
                color: color,
                isDanger: threshold.isCritical,
                diameter: PouredUsageMetrics.meterDial,
                lineWidth: PouredUsageMetrics.meterDialLineWidth
            )

            VStack(alignment: .leading, spacing: 2) {
                Text("\(providerTitle) · \(window.label)")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(tokens.colors.text(tokens.colors.secondaryTextOpacity, increaseContrast: increasesContrast)))

                Text("\(window.roundedUsedPercentage)%")
                    .font(PouredType.Role.displayNumeral.font)
                    .tracking(PouredType.Role.displayNumeral.spec.trackingPoints)
                    .foregroundStyle(color)

                if let remaining = window.remainingLabel(asOf: now) {
                    Text(lang.t("island.poured.usage.resetsIn", remaining))
                        .font(PouredType.Role.age.font)
                        .foregroundStyle(.white.opacity(tokens.colors.text(tokens.colors.tertiaryTextOpacity, increaseContrast: increasesContrast)))
                }

                thresholdPill
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }

    /// The band stated as **shape + word** so state survives colour-blindness /
    /// greyscale (`SPEC` §4I "never color alone").
    private var thresholdPill: some View {
        HStack(spacing: 5) {
            Text(threshold.shapeMarker)
                .font(.system(size: 9, weight: .bold))
            Text(lang.t(threshold.localizationKey))
                .font(.system(size: 10, weight: .semibold))
        }
        .foregroundStyle(color)
        .padding(.horizontal, 7)
        .padding(.vertical, 1)
        .background(color.opacity(0.15), in: Capsule())
        .padding(.top, 2)
    }

    private var accessibilityLabel: String {
        var parts = [
            "\(providerTitle) \(window.label)",
            "\(window.roundedUsedPercentage)%",
            lang.t(threshold.localizationKey),
        ]
        if let remaining = window.remainingLabel(asOf: now) {
            parts.append(lang.t("island.poured.usage.resetsIn", remaining))
        }
        return parts.joined(separator: ", ")
    }
}
