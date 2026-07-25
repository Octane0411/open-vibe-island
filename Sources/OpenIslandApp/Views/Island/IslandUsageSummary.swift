import SwiftUI
import OpenIslandCore

/// One usage provider (Claude, Codex, …) and its rate-limit windows, in the
/// shape the header's usage chips render. Built at the `IslandPanelView` call
/// site from the model's usage snapshots and handed to `IslandUsageSummary` /
/// `IslandHeaderControls` by value.
struct UsageProviderPresentation: Identifiable {
    let id: String
    let title: String
    let windows: [UsageWindowPresentation]

    var peakWindow: UsageWindowPresentation? {
        windows.max { lhs, rhs in
            lhs.usedPercentage < rhs.usedPercentage
        }
    }

    var peakWindowLabel: String {
        peakWindow?.label ?? ""
    }

    var peakUsedPercentage: Double {
        peakWindow?.usedPercentage ?? 0
    }

    var peakUsagePercentage: Int {
        peakWindow?.roundedUsedPercentage ?? 0
    }

    var shortTitle: String {
        switch id {
        case "claude":
            "Cl"
        case "codex":
            "Cx"
        default:
            String(title.prefix(2))
        }
    }
}

struct UsageWindowPresentation: Identifiable {
    let id: String
    let label: String
    let usedPercentage: Double
    let resetsAt: Date?

    var roundedUsedPercentage: Int {
        Int(usedPercentage.rounded())
    }
}

/// The compact usage chips shown in the opened header — one per provider,
/// each collapsing its title from full ("Claude") to short ("Cl") to fit.
///
/// AB-298: extracted from `IslandPanelView`'s `compactUsageSummaryView` /
/// `compactUsageChip` / `usageColor` / `usageHelpText` / `remainingDurationString`
/// (and the dead `headerPill`) into a standalone slot component. Takes its
/// providers by value and reads its colours from `islandTokens` — no `AppModel`
/// reference.
struct IslandUsageSummary: View {
    let providers: [UsageProviderPresentation]

    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    private var increasesContrast: Bool { colorSchemeContrast == .increased }

    @Environment(\.islandTokens) private var tokens

    var body: some View {
        ViewThatFits(in: .horizontal) {
            compactUsageSummaryView(usesShortTitles: false)
            compactUsageSummaryView(usesShortTitles: true)
        }
    }

    private func compactUsageSummaryView(usesShortTitles: Bool) -> some View {
        HStack(spacing: 7) {
            ForEach(providers) { provider in
                compactUsageChip(provider, usesShortTitle: usesShortTitles)
            }
        }
        .lineLimit(1)
        .fixedSize(horizontal: true, vertical: false)
    }

    private func compactUsageChip(_ provider: UsageProviderPresentation, usesShortTitle: Bool) -> some View {
        HStack(spacing: 5) {
            Text(usesShortTitle ? provider.shortTitle : provider.title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.74))

            Text(provider.peakWindowLabel)
                .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                .foregroundStyle(.white.opacity(tokens.colors.text(tokens.colors.secondaryTextOpacity, increaseContrast: increasesContrast)))

            Text("\(provider.peakUsagePercentage)%")
                .font(.system(size: 11.5, weight: .bold, design: .monospaced))
                .foregroundStyle(usageColor(for: provider.peakUsedPercentage))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(.white.opacity(0.055), in: Capsule())
        .overlay(
            Capsule()
                .strokeBorder(.white.opacity(0.06), lineWidth: 1)
        )
        .help(usageHelpText(for: provider))
        // AB-244: three adjacent `Text`s (title / window / percentage) would
        // otherwise read as three separate VoiceOver stops — combine into
        // one chip-level label reusing the same summary already built for
        // the `.help()` tooltip.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(usesShortTitle ? provider.shortTitle : provider.title) \(usageHelpText(for: provider))")
    }

    private func usageHelpText(for provider: UsageProviderPresentation) -> String {
        provider.windows.map { window in
            var parts = ["\(window.label) \(window.roundedUsedPercentage)%"]
            if let remaining = window.remainingLabel(asOf: Date()) {
                parts.append(remaining)
            }
            return parts.joined(separator: " ")
        }
        .joined(separator: " · ")
    }

    private func headerPill(_ title: String, tint: Color) -> some View {
        Text(title)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.white.opacity(0.08), in: Capsule())
    }

    private func usageColor(for percentage: Double) -> Color {
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
