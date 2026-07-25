import SwiftUI
import OpenIslandCore

/// Poured Island's usage readout (AB-301): one glass chip per provider, and
/// inside each chip a conic-gradient ring with a numeric percentage for *every*
/// configured window (Claude 5h + 7d, each Codex window) — not just the peak
/// window Classic's chip collapses to.
///
/// The colour thresholds are the exact `usageColor` cut-offs Classic ships
/// (`>= 90` red, `70..<90` orange, else green); a ring in the red band carries a
/// red glow. Rings settle with a short sweep and the danger glow breathes, both
/// gated off under Reduce Motion so the rings render static. Ring labels read
/// their opacities through the token contrast floor so they survive Increase
/// Contrast, and the chip's glass fill goes flatter under Reduce Transparency.
struct PouredUsageSummary: View {
    let providers: [UsageProviderPresentation]

    var body: some View {
        ViewThatFits(in: .horizontal) {
            summaryRow(usesShortTitles: false)
            summaryRow(usesShortTitles: true)
        }
    }

    private func summaryRow(usesShortTitles: Bool) -> some View {
        HStack(spacing: 7) {
            ForEach(providers) { provider in
                PouredUsageProviderChip(provider: provider, usesShortTitle: usesShortTitles)
            }
        }
        .lineLimit(1)
        .fixedSize(horizontal: true, vertical: false)
    }
}

/// One provider's glass chip: its title plus a ring-and-readout for each of its
/// rate-limit windows.
struct PouredUsageProviderChip: View {
    let provider: UsageProviderPresentation
    let usesShortTitle: Bool

    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    private var increasesContrast: Bool { colorSchemeContrast == .increased }

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.islandTokens) private var tokens

    var body: some View {
        HStack(spacing: 7) {
            Text(usesShortTitle ? provider.shortTitle : provider.title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.78))

            ForEach(provider.windows) { window in
                PouredUsageWindowRing(window: window)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(.white.opacity(reduceTransparency ? 0.12 : 0.06), in: Capsule())
        .overlay(
            Capsule()
                .strokeBorder(.white.opacity(reduceTransparency ? 0.14 : 0.08), lineWidth: 1)
        )
        .help(helpText)
        // AB-244 / AB-301: the whole chip is one VoiceOver stop — the same
        // per-window summary Classic surfaces through `.help()`.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(usesShortTitle ? provider.shortTitle : provider.title) \(helpText)")
    }

    private var helpText: String {
        provider.windows.map { window in
            var parts = ["\(window.label) \(window.roundedUsedPercentage)%"]
            if let resetsAt = window.resetsAt,
               let remaining = Self.remainingDurationString(until: resetsAt) {
                parts.append(remaining)
            }
            return parts.joined(separator: " ")
        }
        .joined(separator: " · ")
    }

    static func remainingDurationString(until date: Date) -> String? {
        let interval = date.timeIntervalSinceNow
        guard interval > 0 else { return nil }

        let formatter = DateComponentsFormatter()
        formatter.unitsStyle = .abbreviated

        if interval >= 86_400 {
            formatter.allowedUnits = [.day]
            formatter.maximumUnitCount = 1
        } else if interval >= 3_600 {
            formatter.allowedUnits = [.hour, .minute]
            formatter.maximumUnitCount = 2
        } else {
            formatter.allowedUnits = [.minute]
            formatter.maximumUnitCount = 1
        }

        return formatter.string(from: interval)
    }
}

/// A single window's conic-gradient ring plus its label and numeric percentage.
struct PouredUsageWindowRing: View {
    let window: UsageWindowPresentation

    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    private var increasesContrast: Bool { colorSchemeContrast == .increased }

    @Environment(\.islandTokens) private var tokens

    private var color: Color { Self.usageColor(for: window.usedPercentage) }

    var body: some View {
        HStack(spacing: 4) {
            PouredUsageRing(
                fraction: window.usedPercentage / 100,
                color: color,
                isDanger: window.usedPercentage >= 90
            )

            Text(window.label)
                .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                .foregroundStyle(.white.opacity(tokens.colors.text(tokens.colors.secondaryTextOpacity, increaseContrast: increasesContrast)))

            Text("\(window.roundedUsedPercentage)%")
                .font(.system(size: 11.5, weight: .bold, design: .monospaced))
                .foregroundStyle(color)
        }
    }

    /// The exact `usageColor` cut-offs Classic ships (`IslandUsageSummary`):
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
}

/// The ring itself: a faint track under a conic-gradient progress arc. The arc
/// sweeps in on appear and the danger band's red glow breathes — both disabled
/// under Reduce Motion, where the ring paints its final fraction statically. The
/// track opacity lifts under Reduce Transparency so the gauge stays readable.
struct PouredUsageRing: View {
    let fraction: Double
    let color: Color
    let isDanger: Bool
    var diameter: CGFloat = 16
    var lineWidth: CGFloat = 2.6

    @State private var animatedFraction: Double = 0
    @State private var glowPulse = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    private var clampedFraction: Double { min(1, max(0, fraction)) }

    private var glowRadius: CGFloat {
        guard isDanger else { return 0 }
        if reduceMotion { return 2.5 }
        return glowPulse ? 3.5 : 1.5
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(
                    color.opacity(reduceTransparency ? 0.32 : 0.18),
                    lineWidth: lineWidth
                )

            Circle()
                .trim(from: 0, to: max(0.0001, animatedFraction))
                .stroke(
                    AngularGradient(
                        gradient: Gradient(colors: [color.opacity(0.55), color]),
                        center: .center
                    ),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .shadow(color: isDanger ? color.opacity(reduceMotion ? 0.7 : (glowPulse ? 0.85 : 0.4)) : .clear, radius: glowRadius)
        }
        .frame(width: diameter, height: diameter)
        .onAppear {
            if reduceMotion {
                animatedFraction = clampedFraction
            } else {
                withAnimation(.easeOut(duration: 0.6)) {
                    animatedFraction = clampedFraction
                }
                if isDanger {
                    withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                        glowPulse = true
                    }
                }
            }
        }
        .onChange(of: fraction) { _, _ in
            if reduceMotion {
                animatedFraction = clampedFraction
            } else {
                withAnimation(.easeOut(duration: 0.4)) {
                    animatedFraction = clampedFraction
                }
            }
        }
        .accessibilityHidden(true)
    }
}
