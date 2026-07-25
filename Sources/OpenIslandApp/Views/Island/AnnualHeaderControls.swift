import AppKit
import SwiftUI
import OpenIslandCore

/// Annual's opened-panel header (AB-316).
///
/// The layout — the notch-split lanes on notched displays, the single flush-left
/// lane on the top-bar / external profile, and the metrics that measure the
/// physical notch out of the way — is shared verbatim with `IslandHeaderControls`
/// (and mirrors `FlightDeckHeaderControls`) so the header keeps its exact
/// geometry across themes. Only the two rendered regions change for the editorial
/// idiom: the usage becomes oversized light numerals with small-caps verdicts and
/// 2px hairline meters (`AnnualUsageSummary`), and the mute / settings / quit
/// controls become quiet glyph buttons (`AnnualHeaderButton`) with ≥24×24pt hit
/// areas and no pill or fill — their behaviors are unchanged, still emitted
/// through the same closures.
struct AnnualHeaderControls: View {
    /// ≥24×24pt hit target for the quiet glyph controls (AB-316 AC #2).
    static let headerControlButtonSize: CGFloat = 24
    static let headerControlSpacing: CGFloat = 8
    private static let headerHorizontalPadding: CGFloat = 18
    private static let headerTopPadding: CGFloat = 2
    private static let notchHeaderHorizontalPadding: CGFloat = 46
    private static let notchLaneSafetyInset: CGFloat = 12
    private static let minimumRightUsageLaneWidth: CGFloat = 58

    let providers: [UsageProviderPresentation]
    let usesNotchAwareLayout: Bool
    let targetScreen: NSScreen?
    let isSoundMuted: Bool
    let lang: LanguageManager
    let onToggleMute: () -> Void
    let onShowSettings: () -> Void
    let onQuit: () -> Void

    @Environment(\.islandTokens) private var tokens

    private var openedHeaderButtonsWidth: CGFloat {
        (Self.headerControlButtonSize * 3) + (Self.headerControlSpacing * 2)
    }

    private var openedHeaderHorizontalPadding: CGFloat {
        usesNotchAwareLayout ? Self.notchHeaderHorizontalPadding : Self.headerHorizontalPadding
    }

    var body: some View {
        if usesNotchAwareLayout {
            GeometryReader { geometry in
                let providerGroups = splitUsageProviders(providers)
                let metrics = openedHeaderMetrics(for: geometry.size.width)

                HStack(spacing: 0) {
                    usageLaneView(providerGroups.left, alignment: .leading)
                        .frame(width: metrics.leftUsageWidth, alignment: .leading)

                    Color.clear
                        .frame(width: metrics.centerGapWidth)

                    HStack(spacing: Self.headerControlSpacing) {
                        if metrics.rightUsageWidth > 0, !providerGroups.right.isEmpty {
                            usageLaneView(providerGroups.right, alignment: .trailing)
                                .frame(width: metrics.rightUsageWidth, alignment: .trailing)
                        }
                        openedHeaderButtons
                    }
                    .frame(width: metrics.rightLaneWidth, alignment: .trailing)
                }
                .padding(.horizontal, openedHeaderHorizontalPadding)
                .padding(.top, Self.headerTopPadding)
            }
        } else {
            HStack(spacing: 12) {
                openedUsageSummary
                    .frame(maxWidth: .infinity, alignment: .leading)

                openedHeaderButtons
            }
            .padding(.leading, openedHeaderHorizontalPadding)
            .padding(.trailing, openedHeaderHorizontalPadding)
            .padding(.top, Self.headerTopPadding)
        }
    }

    private var openedHeaderButtons: some View {
        HStack(spacing: Self.headerControlSpacing) {
            AnnualHeaderButton(
                systemName: isSoundMuted ? "speaker.slash" : "speaker.wave.2",
                emphasised: isSoundMuted,
                accessibilityLabel: lang.t(isSoundMuted ? "a11y.header.unmuteSound" : "a11y.header.muteSound"),
                size: Self.headerControlButtonSize,
                action: onToggleMute
            )

            AnnualHeaderButton(
                systemName: "gearshape",
                emphasised: false,
                accessibilityLabel: lang.t("window.settings"),
                size: Self.headerControlButtonSize,
                action: onShowSettings
            )

            AnnualHeaderButton(
                systemName: "power",
                emphasised: false,
                accessibilityLabel: lang.t("settings.about.quitApp"),
                size: Self.headerControlButtonSize,
                action: onQuit
            )
        }
    }

    @ViewBuilder
    private var openedUsageSummary: some View {
        if providers.isEmpty == false {
            AnnualUsageSummary(providers: providers, lang: lang)
        } else {
            Color.clear
        }
    }

    private func splitUsageProviders(
        _ providers: [UsageProviderPresentation]
    ) -> (left: [UsageProviderPresentation], right: [UsageProviderPresentation]) {
        switch providers.count {
        case 0:
            return ([], [])
        case 1:
            return ([providers[0]], [])
        case 2:
            return ([providers[0]], [providers[1]])
        default:
            let splitIndex = Int(ceil(Double(providers.count) / 2.0))
            return (
                Array(providers.prefix(splitIndex)),
                Array(providers.dropFirst(splitIndex))
            )
        }
    }

    @ViewBuilder
    private func usageLaneView(
        _ providers: [UsageProviderPresentation],
        alignment: Alignment
    ) -> some View {
        if providers.isEmpty {
            Color.clear
                .frame(maxWidth: .infinity)
        } else {
            AnnualUsageSummary(providers: providers, lang: lang)
                .frame(maxWidth: .infinity, alignment: alignment)
        }
    }

    private func openedHeaderMetrics(for totalWidth: CGFloat) -> AnnualOpenedHeaderMetrics {
        let horizontalPadding = openedHeaderHorizontalPadding
        let contentWidth = max(0, totalWidth - (horizontalPadding * 2))
        guard usesNotchAwareLayout,
              let screen = targetScreen else {
            let rightLaneWidth = min(contentWidth, openedHeaderButtonsWidth + (contentWidth / 2))
            let leftUsageWidth = max(0, contentWidth - rightLaneWidth)
            return AnnualOpenedHeaderMetrics(
                leftUsageWidth: leftUsageWidth,
                centerGapWidth: 0,
                rightUsageWidth: max(0, rightLaneWidth - openedHeaderButtonsWidth - Self.headerControlSpacing),
                rightLaneWidth: rightLaneWidth
            )
        }

        let panelMinX = screen.frame.midX - (totalWidth / 2)
        let panelMaxX = panelMinX + totalWidth
        let contentMinX = panelMinX + horizontalPadding
        let contentMaxX = panelMaxX - horizontalPadding

        let fallbackNotchHalfWidth = screen.notchSize.width / 2
        let notchLeftEdge = screen.frame.midX - fallbackNotchHalfWidth
        let notchRightEdge = screen.frame.midX + fallbackNotchHalfWidth
        let leftVisibleMaxX = screen.auxiliaryTopLeftArea?.maxX ?? notchLeftEdge
        let rightVisibleMinX = screen.auxiliaryTopRightArea?.minX ?? notchRightEdge

        let rawLeftWidth = max(0, min(contentMaxX, leftVisibleMaxX) - contentMinX)
        let rawRightWidth = max(0, contentMaxX - max(contentMinX, rightVisibleMinX))

        let leftUsageWidth = max(0, rawLeftWidth - Self.notchLaneSafetyInset)
        let rightAvailableWidth = max(0, rawRightWidth - Self.notchLaneSafetyInset)
        let proposedRightUsageWidth = max(
            0,
            rightAvailableWidth - openedHeaderButtonsWidth - Self.headerControlSpacing
        )
        let rightUsageWidth = proposedRightUsageWidth >= Self.minimumRightUsageLaneWidth
            ? proposedRightUsageWidth
            : 0
        let rightLaneWidth = min(
            contentWidth,
            openedHeaderButtonsWidth
                + (rightUsageWidth > 0 ? Self.headerControlSpacing + rightUsageWidth : 0)
        )
        let centerGapWidth = max(0, contentWidth - leftUsageWidth - rightLaneWidth)

        return AnnualOpenedHeaderMetrics(
            leftUsageWidth: leftUsageWidth,
            centerGapWidth: centerGapWidth,
            rightUsageWidth: rightUsageWidth,
            rightLaneWidth: rightLaneWidth
        )
    }
}

private struct AnnualOpenedHeaderMetrics {
    let leftUsageWidth: CGFloat
    let centerGapWidth: CGFloat
    let rightUsageWidth: CGFloat
    let rightLaneWidth: CGFloat
}

// MARK: - Annual header button (quiet glyph)

/// A quiet glyph button for the header's mute / settings / quit actions. The
/// behavior is identical to `IslandHeaderControls.headerIconButton` — same
/// closures, same accessibility labels — the only change is the editorial
/// styling: no pill, no fill, no chip. Just the SF glyph drawn in warm paper on
/// a ≥24×24pt hit target, lifting its opacity on hover; the muted state is
/// carried by the slashed glyph itself rather than by colour, keeping the accent
/// unspent on this calm chrome. There is no transparency to reduce on this flat
/// page; the hover lift settles without easing under Reduce Motion.
struct AnnualHeaderButton: View {
    let systemName: String
    /// The muted state — drawn a touch brighter so the slashed glyph reads as an
    /// active toggle, without spending colour.
    let emphasised: Bool
    let accessibilityLabel: String
    var size: CGFloat = 24
    let action: () -> Void

    @State private var hovering = false
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    private var increasesContrast: Bool { colorSchemeContrast == .increased }
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.islandTokens) private var tokens

    private var glyphOpacity: Double {
        let base = emphasised ? 0.82 : 0.62
        let resolved = hovering ? min(1, base + 0.22) : base
        return tokens.colors.text(resolved, increaseContrast: increasesContrast)
    }

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 12, weight: .regular))
                .foregroundStyle(tokens.colors.paper.opacity(glyphOpacity))
                .frame(width: size, height: size)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
        .onHover { hovering = $0 }
        // The hover lift settles instantly under Reduce Motion — the state (and
        // its opacity) still changes, it just doesn't ease (AB-316).
        .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: hovering)
    }
}
