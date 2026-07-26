import AppKit
import SwiftUI
import OpenIslandCore

/// Poured Island's opened-panel header (AB-301).
///
/// The layout — the notch-split lanes on notched displays, the single flush-left
/// lane on the top-bar / external profile, and the metrics that measure the
/// physical notch out of the way — is shared verbatim with `IslandHeaderControls`
/// so the header keeps its exact geometry across themes. Only the two rendered
/// regions change for glass: the usage chips become conic-gradient rings with a
/// numeric readout per provider window (`PouredUsageSummary`), and the mute /
/// settings / quit buttons become frosted glass buttons with hover states
/// (`PouredHeaderButton`) — their behaviors are unchanged, still emitted through
/// the same closures.
struct PouredHeaderControls: View {
    static let headerControlButtonSize: CGFloat = 22
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

    private var openedHeaderButtonsWidth: CGFloat {
        (Self.headerControlButtonSize * 3) + (Self.headerControlSpacing * 2)
    }

    private var openedHeaderHorizontalPadding: CGFloat {
        usesNotchAwareLayout ? Self.notchHeaderHorizontalPadding : Self.headerHorizontalPadding
    }

    /// The usage ring is fitted to whichever header band this profile draws into:
    /// the ~38pt notch band takes the mockup's 30pt ring, the ~24pt top-bar band
    /// a smaller ring so it can't bleed past the height-capped header (AB-331).
    private var headerRingDiameter: CGFloat {
        usesNotchAwareLayout ? PouredUsageMetrics.headerRingNotch : PouredUsageMetrics.headerRingTopBar
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
            PouredHeaderButton(
                systemName: isSoundMuted ? "speaker.slash.fill" : "speaker.wave.2.fill",
                tint: isSoundMuted ? .orange.opacity(0.92) : .white.opacity(0.7),
                accessibilityLabel: lang.t(isSoundMuted ? "a11y.header.unmuteSound" : "a11y.header.muteSound"),
                size: Self.headerControlButtonSize,
                action: onToggleMute
            )

            PouredHeaderButton(
                systemName: "gearshape.fill",
                tint: .white.opacity(0.7),
                accessibilityLabel: lang.t("window.settings"),
                size: Self.headerControlButtonSize,
                action: onShowSettings
            )

            PouredHeaderButton(
                systemName: "power",
                tint: .white.opacity(0.7),
                accessibilityLabel: lang.t("settings.about.quitApp"),
                size: Self.headerControlButtonSize,
                action: onQuit
            )
        }
    }

    @ViewBuilder
    private var openedUsageSummary: some View {
        if providers.isEmpty == false {
            PouredUsageSummary(providers: providers, lang: lang, ringDiameter: headerRingDiameter)
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
            PouredUsageSummary(providers: providers, lang: lang, ringDiameter: headerRingDiameter)
                .frame(maxWidth: .infinity, alignment: alignment)
        }
    }

    private func openedHeaderMetrics(for totalWidth: CGFloat) -> PouredOpenedHeaderMetrics {
        let horizontalPadding = openedHeaderHorizontalPadding
        let contentWidth = max(0, totalWidth - (horizontalPadding * 2))
        guard usesNotchAwareLayout,
              let screen = targetScreen else {
            let rightLaneWidth = min(contentWidth, openedHeaderButtonsWidth + (contentWidth / 2))
            let leftUsageWidth = max(0, contentWidth - rightLaneWidth)
            return PouredOpenedHeaderMetrics(
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

        return PouredOpenedHeaderMetrics(
            leftUsageWidth: leftUsageWidth,
            centerGapWidth: centerGapWidth,
            rightUsageWidth: rightUsageWidth,
            rightLaneWidth: rightLaneWidth
        )
    }
}

private struct PouredOpenedHeaderMetrics {
    let leftUsageWidth: CGFloat
    let centerGapWidth: CGFloat
    let rightUsageWidth: CGFloat
    let rightLaneWidth: CGFloat
}

// MARK: - Glass header button

/// A frosted circular control for the header's mute / settings / quit actions.
/// The behavior is identical to `IslandHeaderControls.headerIconButton`; the
/// only additions are the glass fill (a touch brighter with a specular ring),
/// and a hover state that lifts the fill and stroke so the control reads as
/// interactive glass. Under Reduce Transparency the fill goes flatter/opaquer so
/// the glyph stays legible.
struct PouredHeaderButton: View {
    let systemName: String
    let tint: Color
    let accessibilityLabel: String
    var size: CGFloat = 22
    let action: () -> Void

    @State private var hovering = false
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var fillOpacity: Double {
        if reduceTransparency {
            return hovering ? 0.22 : 0.14
        }
        return hovering ? 0.17 : 0.09
    }

    private var strokeOpacity: Double {
        hovering ? 0.28 : 0.12
    }

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: size, height: size)
                .background(.white.opacity(fillOpacity), in: Circle())
                .overlay(
                    Circle().strokeBorder(.white.opacity(strokeOpacity), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
        .onHover { hovering = $0 }
        // The hover lift settles instantly under Reduce Motion — the state
        // (and its opacity) still changes, it just doesn't ease (AB-304).
        .animation(reduceMotion ? nil : .easeOut(duration: 0.14), value: hovering)
    }
}
