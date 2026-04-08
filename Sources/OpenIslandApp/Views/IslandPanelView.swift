import SwiftUI
@preconcurrency import MarkdownUI
import OpenIslandCore

private struct NotificationContentHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private struct ContentHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

/// Auto-height container: renders content directly (auto-sizing).
/// When content exceeds maxHeight, wraps in ScrollView at fixed maxHeight.
struct AutoHeightScrollView<Content: View>: View {
    let maxHeight: CGFloat
    @ViewBuilder let content: () -> Content
    @State private var contentHeight: CGFloat = 0

    var body: some View {
        if contentHeight > maxHeight {
            // Exceeds max → fixed height, scrollable
            ScrollView(.vertical) {
                measuredContent
            }
            .scrollIndicators(.automatic)
            .frame(height: maxHeight)
        } else {
            // Fits within max → direct render, auto-height
            measuredContent
        }
    }

    private var measuredContent: some View {
        content()
            .background(
                GeometryReader { geo in
                    Color.clear.preference(key: ContentHeightKey.self, value: geo.size.height)
                }
            )
            .onPreferenceChange(ContentHeightKey.self) { height in
                if height > 0 { contentHeight = height }
            }
    }
}

// MARK: - Row Height Estimation

extension TrackedSession {
    /// Estimated row height matching `IslandSessionRow` layout for viewport sizing.
    func estimatedIslandRowHeight(at date: Date) -> CGFloat {
        let presence = islandPresence(at: date)
        // Base: vertical padding (28) + headline (~18) + rounding (2)
        var height: CGFloat = 48
        guard presence != .inactive else { return height }
        if spotlightPromptLineText != nil { height += 24 }   // spacing (8) + text (16)
        if spotlightActivityLineText != nil { height += 22 }  // spacing (8) + text (14)
        if !metadata.activeSubagents.isEmpty {
            height += 22  // spacing (8) + header (14)
            height += CGFloat(metadata.activeSubagents.count) * 18  // each subagent row (spacing 4 + text 14)
        }
        if !metadata.activeTasks.isEmpty {
            height += 20  // spacing (8) + summary (12)
            height += CGFloat(metadata.activeTasks.count) * 16  // each task row (spacing 3 + text 13)
        }
        return height
    }
}

// MARK: - Animations

private let openAnimation = Animation.spring(response: 0.42, dampingFraction: 0.8, blendDuration: 0)
private let closeAnimation = Animation.spring(response: 0.45, dampingFraction: 1.0, blendDuration: 0)
private let popAnimation = Animation.spring(response: 0.3, dampingFraction: 0.5)

/// Composite equatable key so `hasClosedPresence` and `expansionWidth` share
/// a single `.animation(.smooth, value:)` modifier instead of two separate
/// ones that can conflict when both change simultaneously.
private struct ClosedPresenceKey: Equatable {
    var present: Bool
    var width: CGFloat
}

struct ConditionalDrawingGroup: ViewModifier {
    let enabled: Bool

    func body(content: Content) -> some View {
        if enabled {
            content.drawingGroup()
        } else {
            content
        }
    }
}

// MARK: - Main island view

struct IslandPanelView: View {
    private static let headerControlButtonSize: CGFloat = 22
    private static let headerControlSpacing: CGFloat = 8
    private static let headerHorizontalPadding: CGFloat = 18
    private static let headerTopPadding: CGFloat = 2
    private static let notchLaneSafetyInset: CGFloat = 12

    var model: AppModel

    @Namespace private var notchNamespace
    @State private var isHovering = false
    @State private var showDebugIDs = false

    private var isOpened: Bool {
        model.notchStatus == .opened
    }

    private var isPopping: Bool {
        model.notchStatus == .popping
    }

    private var closedSpotlightSession: TrackedSession? {
        model.surfacedSessions.first(where: { $0.phase.requiresAttention })
            ?? model.surfacedSessions.first(where: { $0.phase == .running })
            ?? model.surfacedSessions.first
    }

    private var hasClosedPresence: Bool {
        model.liveSessionCount > 0
    }

    /// Whether any session has activity worth showing in the closed notch
    private var hasClosedActivity: Bool {
        guard let session = closedSpotlightSession else {
            return false
        }
        return session.phase == .running || session.phase.requiresAttention
    }

    /// Scout icon tint: blue if any running, green if any live, else gray.
    private var scoutTint: Color {
        let sessions = model.surfacedSessions
        if sessions.contains(where: { $0.phase == .running }) {
            return Color(red: 0.43, green: 0.62, blue: 1.0) // #6E9FFF working blue
        }
        if !sessions.isEmpty {
            return Color(red: 0.26, green: 0.91, blue: 0.42) // #42E86B idle green
        }
        return Color.white.opacity(0.4) // gray
    }

    private var countBadgeWidth: CGFloat {
        let digits = max(1, "\(model.liveSessionCount)".count)
        return CGFloat(18 + max(0, digits - 1) * 7)
    }

    private var expansionWidth: CGFloat {
        guard hasClosedPresence else { return 0 }
        let leftWidth = sideWidth + 8 + (closedSpotlightSession?.phase.requiresAttention == true ? 18 : 0)
        let rightWidth = max(sideWidth, countBadgeWidth)
        let hasPending = closedSpotlightSession?.phase.requiresAttention == true
        return leftWidth + rightWidth + 16 + (hasPending ? 6 : 0)
    }

    /// Composite key combining `hasClosedPresence` and `expansionWidth` so a
    /// single `.animation(.smooth)` modifier drives both values.  Previously
    /// they had two separate `.animation(.smooth, value:)` modifiers that
    /// could conflict when they changed in the same runloop pass.
    private var closedPresenceAnimationKey: ClosedPresenceKey {
        ClosedPresenceKey(present: hasClosedPresence, width: expansionWidth)
    }

    private var sideWidth: CGFloat {
        max(0, closedNotchHeight - 12) + 10
    }

    private var targetOverlayScreen: NSScreen? {
        if let targetScreenID = model.overlayPlacementDiagnostics?.targetScreenID,
           let screen = NSScreen.screens.first(where: { screenID(for: $0) == targetScreenID }) {
            return screen
        }

        return NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 }) ?? NSScreen.main
    }

    private var usesNotchAwareOpenedHeader: Bool {
        model.overlayPlacementDiagnostics?.mode == .notch
            || targetOverlayScreen?.safeAreaInsets.top ?? 0 > 0
    }

    private var openedHeaderButtonsWidth: CGFloat {
        (Self.headerControlButtonSize * 2) + Self.headerControlSpacing
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .top) {
                Color.clear

                notchContent(availableSize: geometry.size)
                    .frame(maxWidth: .infinity, alignment: .top)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .preferredColorScheme(.dark)
    }

    @ViewBuilder
    private func notchContent(availableSize: CGSize) -> some View {
        let panelShadowHorizontalInset = isOpened
            ? IslandChromeMetrics.openedShadowHorizontalInset
            : IslandChromeMetrics.closedShadowHorizontalInset
        let panelShadowBottomInset = isOpened
            ? IslandChromeMetrics.openedShadowBottomInset
            : IslandChromeMetrics.closedShadowBottomInset
        let layoutWidth = max(0, availableSize.width - (panelShadowHorizontalInset * 2))
        let layoutHeight = max(0, availableSize.height - panelShadowBottomInset)
        let outerHorizontalPadding: CGFloat = isOpened ? 28 : 0
        let outerBottomPadding: CGFloat = isOpened ? 14 : 0
        let openedWidth = max(0, layoutWidth - outerHorizontalPadding)
        let closedWidth = layoutWidth
        let currentWidth = isOpened ? openedWidth : closedWidth
        let currentHeight = isOpened ? max(closedNotchHeight, layoutHeight - outerBottomPadding) : layoutHeight
        let horizontalInset = isOpened ? 14.0 : 0.0
        let bottomInset = isOpened ? 14.0 : 0.0
        let surfaceWidth = currentWidth + (horizontalInset * 2)
        let surfaceHeight = currentHeight + bottomInset
        let surfaceShape = NotchShape(
            topCornerRadius: isOpened ? NotchShape.openedTopRadius : NotchShape.closedTopRadius,
            bottomCornerRadius: isOpened ? NotchShape.openedBottomRadius : NotchShape.closedBottomRadius
        )

        ZStack(alignment: .top) {
            surfaceShape
                .fill(Color.black)
                .frame(width: surfaceWidth, height: surfaceHeight)

            VStack(spacing: 0) {
                headerRow
                    .frame(height: closedNotchHeight)

                openedContent
                    .frame(width: openedWidth - 24)
                    .frame(maxHeight: isOpened ? max(0, currentHeight - closedNotchHeight - 12) : 0, alignment: .top)
                    .opacity(isOpened ? 1 : 0)
                    .clipped()
            }
            .frame(width: currentWidth, height: currentHeight, alignment: .top)
            .padding(.horizontal, horizontalInset)
            .padding(.bottom, bottomInset)
            .clipShape(surfaceShape)
            .overlay(alignment: .top) {
                // Black strip to blend with physical notch at the very top
                Rectangle()
                    .fill(Color.black)
                    .frame(height: 1)
                    .padding(.horizontal, isOpened ? NotchShape.openedTopRadius : NotchShape.closedTopRadius)
            }
            .overlay {
                surfaceShape
                    .stroke(Color.white.opacity(isOpened ? 0.07 : 0.04), lineWidth: 1)
            }
        }
        .frame(width: surfaceWidth, height: surfaceHeight, alignment: .top)
        .scaleEffect(isOpened ? 1 : (isHovering ? IslandChromeMetrics.closedHoverScale : 1), anchor: .top)
        .padding(.horizontal, panelShadowHorizontalInset)
        .padding(.bottom, panelShadowBottomInset)
        .animation(isOpened ? openAnimation : closeAnimation, value: model.notchStatus)
        .animation(isOpened ? nil : .smooth, value: closedPresenceAnimationKey)
        .animation(isOpened ? nil : popAnimation, value: isPopping)
        .contentShape(Rectangle())
        .onHover { hovering in
            withAnimation(.spring(response: 0.38, dampingFraction: 0.8)) {
                isHovering = hovering
            }
        }
        .onTapGesture {
            if !isOpened {
                model.notchOpen(reason: .click)
            }
        }
    }

    // MARK: - Closed state

    private var closedNotchWidth: CGFloat {
        (targetOverlayScreen ?? NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 }))?.notchSize.width ?? 224
    }

    private var closedNotchHeight: CGFloat {
        (targetOverlayScreen ?? NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 }))?.islandClosedHeight ?? 24
    }

    // MARK: - Header row (shared between closed and opened)

    @ViewBuilder
    private var headerRow: some View {
        if isOpened {
            openedHeaderContent
                .frame(height: closedNotchHeight)
        } else {
            HStack(spacing: 0) {
                if hasClosedPresence {
                    HStack(spacing: 4) {
                        OpenIslandIcon(size: 14, isAnimating: hasClosedActivity, tint: scoutTint)
                            .matchedGeometryEffect(id: "island-icon", in: notchNamespace, isSource: true)

                        if closedSpotlightSession?.phase.requiresAttention == true {
                            AttentionIndicator(
                                size: 14,
                                color: phaseColor(closedSpotlightSession?.phase ?? .running)
                            )
                        }
                    }
                    .frame(width: sideWidth + 8 + (closedSpotlightSession?.phase.requiresAttention == true ? 18 : 0))
                }

                if !hasClosedPresence {
                    Rectangle()
                        .fill(Color.clear)
                        .frame(width: closedNotchWidth - 20)
                } else {
                    Rectangle()
                        .fill(Color.black)
                        .frame(width: closedNotchWidth - NotchShape.closedTopRadius + (isPopping ? 18 : 0))
                }

                if hasClosedPresence {
                    ClosedCountBadge(
                        liveCount: model.liveSessionCount,
                        tint: closedSpotlightSession?.phase.requiresAttention == true ? .orange : scoutTint
                    )
                    .matchedGeometryEffect(id: "right-indicator", in: notchNamespace, isSource: true)
                    .frame(width: max(sideWidth, countBadgeWidth))
                }
            }
            .frame(height: closedNotchHeight)
        }
    }

    @ViewBuilder
    private var openedHeaderContent: some View {
        if usesNotchAwareOpenedHeader {
            GeometryReader { geometry in
                let providers = openedUsageProviders
                let providerGroups = splitUsageProviders(providers)
                let metrics = openedHeaderMetrics(for: geometry.size.width)

                HStack(spacing: 0) {
                    usageLaneView(providerGroups.left, alignment: .leading)
                        .frame(width: metrics.leftUsageWidth, alignment: .leading)

                    Color.clear
                        .frame(width: metrics.centerGapWidth)

                    HStack(spacing: Self.headerControlSpacing) {
                        usageLaneView(providerGroups.right, alignment: .trailing)
                        openedHeaderButtons
                    }
                    .frame(width: metrics.rightLaneWidth, alignment: .trailing)
                }
                .padding(.horizontal, Self.headerHorizontalPadding)
                .padding(.top, Self.headerTopPadding)
            }
        } else {
            HStack(spacing: 12) {
                openedUsageSummary
                    .frame(maxWidth: .infinity, alignment: .leading)

                openedHeaderButtons
            }
            .padding(.leading, Self.headerHorizontalPadding)
            .padding(.trailing, Self.headerHorizontalPadding)
            .padding(.top, Self.headerTopPadding)
        }
    }

    private var openedHeaderButtons: some View {
        HStack(spacing: Self.headerControlSpacing) {
            headerIconButton(
                systemName: showDebugIDs ? "ladybug.fill" : "ladybug",
                tint: showDebugIDs ? .green.opacity(0.82) : .white.opacity(0.42)
            ) {
                showDebugIDs.toggle()
            }

            headerIconButton(
                systemName: model.isSoundMuted ? "speaker.slash.fill" : "speaker.wave.2.fill",
                tint: model.isSoundMuted ? .orange.opacity(0.92) : .white.opacity(0.62)
            ) {
                model.toggleSoundMuted()
            }

            headerIconButton(systemName: "gearshape.fill", tint: .white.opacity(0.62)) {
                model.showSettings()
            }
        }
    }

    private func headerIconButton(
        systemName: String,
        tint: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: Self.headerControlButtonSize, height: Self.headerControlButtonSize)
                .background(.white.opacity(0.08), in: Circle())
        }
        .buttonStyle(.plain)
    }

    private var openedContent: some View {
        VStack(spacing: 0) {
            if model.shouldShowSessionBootstrapPlaceholder {
                sessionBootstrapPlaceholder
            } else if model.islandListSessions.isEmpty {
                emptyState
            } else {
                sessionList
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 8)
        .padding(.bottom, 0)
    }

    private var sessionBootstrapPlaceholder: some View {
        VStack(spacing: 12) {
            Spacer()
            ProgressView()
                .progressViewStyle(.circular)
                .tint(.white.opacity(0.7))
                .scaleEffect(0.8)
            Text(model.lang.t("island.checkingTerminals"))
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.white.opacity(0.58))
            Text(model.lang.t("island.terminalOwnership"))
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.28))
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()
            Text(model.lang.t("island.noTerminals"))
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.white.opacity(0.4))
            Text(model.recentSessions.isEmpty
                ? model.lang.t("island.startAgent")
                : model.lang.t("island.recentSessions"))
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.25))
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private var actionableSessionID: String? {
        model.islandSurface.sessionID
    }

    /// Whether the panel was opened by a notification (show only actionable session + footer).
    private var isNotificationMode: Bool {
        model.notchOpenReason == .notification && actionableSessionID != nil
    }

    private static let maxSessionListHeight: CGFloat = 560

    private var sessionList: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            if isNotificationMode {
                // Notification mode: NO ScrollView — content sizes naturally
                sessionListContent(context: context)
                    .padding(.vertical, 2)
                    .background(
                        GeometryReader { geo in
                            Color.clear.preference(
                                key: NotificationContentHeightKey.self,
                                value: geo.size.height
                            )
                        }
                    )
                    .onPreferenceChange(NotificationContentHeightKey.self) { height in
                        if height > 0 {
                            model.measuredNotificationContentHeight = height
                        }
                    }
            } else {
                // List mode: scrollable
                ScrollView(.vertical) {
                    sessionListContent(context: context)
                }
                .scrollIndicators(.automatic, axes: .vertical)
                .scrollContentBackground(.hidden)
                .frame(maxHeight: Self.maxSessionListHeight)
                .padding(.vertical, 2)
            }
        }
    }

    @ViewBuilder
    private func sessionListContent(context: TimelineViewDefaultContext) -> some View {
        VStack(spacing: 6) {
            if isNotificationMode, let session = model.activeIslandCardSession {
                IslandSessionRow(
                    session: session,
                    referenceDate: context.date,
                    isActionable: true,
                    useDrawingGroup: model.notchStatus == .opened,
                    isInteractive: model.notchStatus == .opened,
                    showDebugIDs: showDebugIDs,
                    lang: model.lang,
                    onApprove: { model.approvePermission(for: session.id, mode: $0) },
                    onAnswer: { model.answerQuestion(for: session.id, answer: $0) },
                    onJump: { model.jumpToSession(session) }
                )

                if model.allSessions.count > 1 {
                    Button {
                        let isCompletion = session.phase == .completed
                        model.expandNotificationToSessionList(clearExpansion: isCompletion)
                    } label: {
                        Text(model.lang.t("island.showAll", model.allSessions.count))
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.white.opacity(0.45))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                    }
                    .buttonStyle(.plain)
                }
            } else {
                ForEach(model.islandListSessions) { session in
                    IslandSessionRow(
                        session: session,
                        referenceDate: context.date,
                        isActionable: session.id == actionableSessionID,
                        useDrawingGroup: model.notchStatus == .opened,
                        isInteractive: model.notchStatus == .opened,
                        showDebugIDs: showDebugIDs,
                        lang: model.lang,
                        onApprove: { model.approvePermission(for: session.id, mode: $0) },
                        onAnswer: { model.answerQuestion(for: session.id, answer: $0) },
                        onJump: { model.jumpToSession(session) }
                    )
                }
            }
        }
    }

    // MARK: - Helpers

    private var surfaceFill: some ShapeStyle {
        Color.black
    }

    private func phaseColor(_ phase: SessionPhase) -> Color {
        switch phase {
        case .running: .mint
        case .waitingForApproval: .orange
        case .waitingForAnswer: .yellow
        case .completed: .blue
        }
    }

    @ViewBuilder
    private var openedUsageSummary: some View {
        let providers = openedUsageProviders

        if providers.isEmpty == false {
            ViewThatFits(in: .horizontal) {
                usageSummaryView(providers, layout: .full)
                usageSummaryView(providers, layout: .compact)
                usageSummaryView(providers, layout: .condensed)
                usageSummaryView(providers, layout: .minimal)
            }
        } else {
            HStack(spacing: 8) {
                Text(model.lang.t("app.name"))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.9))

                Text(model.lang.t("island.usageWaiting"))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.4))
            }
            .lineLimit(1)
        }
    }

    private var openedUsageProviders: [UsageProviderPresentation] {
        var providers: [UsageProviderPresentation] = []

        if let snapshot = model.claudeUsageSnapshot,
           snapshot.isEmpty == false {
            var windows: [UsageWindowPresentation] = []

            if let fiveHour = snapshot.fiveHour {
                windows.append(
                    UsageWindowPresentation(
                        id: "claude-5h",
                        label: "5h",
                        usedPercentage: fiveHour.usedPercentage,
                        resetsAt: fiveHour.resetsAt
                    )
                )
            }

            if let sevenDay = snapshot.sevenDay {
                windows.append(
                    UsageWindowPresentation(
                        id: "claude-7d",
                        label: "7d",
                        usedPercentage: sevenDay.usedPercentage,
                        resetsAt: sevenDay.resetsAt
                    )
                )
            }

            if windows.isEmpty == false {
                providers.append(
                    UsageProviderPresentation(
                        id: "claude",
                        title: "Claude",
                        windows: windows
                    )
                )
            }
        }

        if let snapshot = model.codexUsageSnapshot,
           snapshot.isEmpty == false {
            let windows = snapshot.windows.map { window in
                UsageWindowPresentation(
                    id: "codex-\(window.key)",
                    label: window.label,
                    usedPercentage: window.usedPercentage,
                    resetsAt: window.resetsAt
                )
            }

            if windows.isEmpty == false {
                providers.append(
                    UsageProviderPresentation(
                        id: "codex",
                        title: "Codex",
                        windows: windows
                    )
                )
            }
        }

        return providers
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
            ViewThatFits(in: .horizontal) {
                usageSummaryView(providers, layout: .full)
                usageSummaryView(providers, layout: .compact)
                usageSummaryView(providers, layout: .condensed)
                usageSummaryView(providers, layout: .minimal)
            }
            .frame(maxWidth: .infinity, alignment: alignment)
        }
    }

    private func openedHeaderMetrics(for totalWidth: CGFloat) -> OpenedHeaderMetrics {
        let contentWidth = max(0, totalWidth - (Self.headerHorizontalPadding * 2))
        guard usesNotchAwareOpenedHeader,
              let screen = targetOverlayScreen else {
            let rightLaneWidth = min(contentWidth, openedHeaderButtonsWidth + (contentWidth / 2))
            let leftUsageWidth = max(0, contentWidth - rightLaneWidth)
            return OpenedHeaderMetrics(
                leftUsageWidth: leftUsageWidth,
                centerGapWidth: 0,
                rightLaneWidth: rightLaneWidth
            )
        }

        let panelMinX = screen.frame.midX - (totalWidth / 2)
        let panelMaxX = panelMinX + totalWidth
        let contentMinX = panelMinX + Self.headerHorizontalPadding
        let contentMaxX = panelMaxX - Self.headerHorizontalPadding

        let fallbackNotchHalfWidth = screen.notchSize.width / 2
        let notchLeftEdge = screen.frame.midX - fallbackNotchHalfWidth
        let notchRightEdge = screen.frame.midX + fallbackNotchHalfWidth
        let leftVisibleMaxX = screen.auxiliaryTopLeftArea?.maxX ?? notchLeftEdge
        let rightVisibleMinX = screen.auxiliaryTopRightArea?.minX ?? notchRightEdge

        let rawLeftWidth = max(0, min(contentMaxX, leftVisibleMaxX) - contentMinX)
        let rawRightWidth = max(0, contentMaxX - max(contentMinX, rightVisibleMinX))

        let leftUsageWidth = max(0, rawLeftWidth - Self.notchLaneSafetyInset)
        let rightLaneWidth = max(0, rawRightWidth - Self.notchLaneSafetyInset)
        let centerGapWidth = max(0, contentWidth - leftUsageWidth - rightLaneWidth)

        return OpenedHeaderMetrics(
            leftUsageWidth: leftUsageWidth,
            centerGapWidth: centerGapWidth,
            rightLaneWidth: rightLaneWidth
        )
    }

    private func usageSummaryView(
        _ providers: [UsageProviderPresentation],
        layout: UsageSummaryLayout
    ) -> some View {
        HStack(spacing: layout.providerSpacing) {
            ForEach(Array(providers.enumerated()), id: \.element.id) { index, provider in
                if index > 0 {
                    usageSeparator(layout.providerSeparator, opacity: layout.providerSeparatorOpacity)
                }

                usageProviderView(provider, layout: layout)
            }
        }
        .lineLimit(1)
        .fixedSize(horizontal: true, vertical: false)
    }

    private func usageProviderView(
        _ provider: UsageProviderPresentation,
        layout: UsageSummaryLayout
    ) -> some View {
        HStack(spacing: 8) {
            Text(layout.usesShortProviderTitle ? provider.shortTitle : provider.title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white.opacity(0.9))

            ForEach(Array(provider.windows.enumerated()), id: \.element.id) { index, window in
                if index > 0 {
                    usageSeparator(layout.windowSeparator, opacity: layout.windowSeparatorOpacity)
                }

                usageWindowView(window: window, layout: layout)
            }
        }
    }

    private func screenID(for screen: NSScreen) -> String {
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        if let number = screen.deviceDescription[key] as? NSNumber {
            return "display-\(number.uint32Value)"
        }

        return screen.localizedName
    }

    private func usageWindowView(
        window: UsageWindowPresentation,
        layout: UsageSummaryLayout
    ) -> some View {
        HStack(spacing: 4) {
            if layout.showsWindowLabel {
                Text(window.label)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.55))
            }

            Text("\(window.roundedUsedPercentage)%")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(usageColor(for: window.usedPercentage))

            if layout.showsResetTime,
               let resetsAt = window.resetsAt,
               let remaining = remainingDurationString(until: resetsAt) {
                Text(remaining)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.35))
            }
        }
    }

    private func usageSeparator(_ title: String, opacity: Double) -> some View {
        Text(title)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(.white.opacity(opacity))
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

    private func remainingDurationString(until date: Date) -> String? {
        let interval = date.timeIntervalSinceNow
        guard interval > 0 else {
            return nil
        }

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

private struct UsageProviderPresentation: Identifiable {
    let id: String
    let title: String
    let windows: [UsageWindowPresentation]

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

private struct UsageWindowPresentation: Identifiable {
    let id: String
    let label: String
    let usedPercentage: Double
    let resetsAt: Date?

    var roundedUsedPercentage: Int {
        Int(usedPercentage.rounded())
    }
}

private enum UsageSummaryLayout {
    case full
    case compact
    case condensed
    case minimal

    var showsResetTime: Bool {
        switch self {
        case .full:
            true
        case .compact, .condensed, .minimal:
            false
        }
    }

    var showsWindowLabel: Bool {
        switch self {
        case .full, .compact:
            true
        case .condensed, .minimal:
            false
        }
    }

    var usesShortProviderTitle: Bool {
        self == .minimal
    }

    var providerSpacing: CGFloat {
        switch self {
        case .full, .compact:
            8
        case .condensed, .minimal:
            6
        }
    }

    var providerSeparator: String {
        "|"
    }

    var providerSeparatorOpacity: Double {
        switch self {
        case .full, .compact:
            0.2
        case .condensed, .minimal:
            0.12
        }
    }

    var windowSeparator: String {
        switch self {
        case .full, .compact:
            "|"
        case .condensed, .minimal:
            "/"
        }
    }

    var windowSeparatorOpacity: Double {
        switch self {
        case .full, .compact:
            0.16
        case .condensed, .minimal:
            0.28
        }
    }
}

private struct OpenedHeaderMetrics {
    let leftUsageWidth: CGFloat
    let centerGapWidth: CGFloat
    let rightLaneWidth: CGFloat
}
