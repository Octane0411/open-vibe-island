import SwiftUI
import OpenIslandCore

// MARK: - Animations

private let openAnimation = Animation.spring(response: 0.42, dampingFraction: 0.8, blendDuration: 0)
private let closeAnimation = Animation.spring(response: 0.45, dampingFraction: 1.0, blendDuration: 0)
private let popAnimation = Animation.spring(response: 0.3, dampingFraction: 0.5)

// MARK: - Main island view

struct IslandPanelView: View {
    private static let maxVisibleSessionRows = 6
    private static let headerControlButtonSize: CGFloat = 22
    private static let headerControlSpacing: CGFloat = 8
    private static let headerHorizontalPadding: CGFloat = 18
    private static let headerTopPadding: CGFloat = 2
    private static let notchLaneSafetyInset: CGFloat = 12

    var model: AppModel

    @Namespace private var notchNamespace
    @State private var isHovering = false
    @State private var hoveredSessionID: String?

    private var isOpened: Bool {
        model.notchStatus == .opened
    }

    private var isPopping: Bool {
        model.notchStatus == .popping
    }

    private var closedSpotlightSession: AgentSession? {
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
                    .frame(maxHeight: isOpened ? currentHeight - closedNotchHeight - 12 : 0, alignment: .top)
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
        .animation(.smooth, value: hasClosedPresence)
        .animation(.smooth, value: expansionWidth)
        .animation(popAnimation, value: isPopping)
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
                        OpenIslandIcon(size: 14, isAnimating: hasClosedActivity)
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
                        tint: closedSpotlightSession?.phase.requiresAttention == true ? .orange : (hasClosedActivity ? .mint : .white.opacity(0.7))
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
                systemName: model.isSoundMuted ? "speaker.slash.fill" : "speaker.wave.2.fill",
                tint: model.isSoundMuted ? .orange.opacity(0.92) : .white.opacity(0.62)
            ) {
                model.toggleSoundMuted()
            }

            headerIconButton(systemName: "gearshape.fill", tint: .white.opacity(0.62)) {
                model.showControlCenter()
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
            if let session = model.activeIslandCardSession,
               model.showsNotificationCard {
                notificationCard(session: session)
            } else if model.shouldShowSessionBootstrapPlaceholder {
                sessionBootstrapPlaceholder
            } else if displayedSessions.isEmpty {
                emptyState
            } else {
                sessionList
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
    }

    private var sessionBootstrapPlaceholder: some View {
        VStack(spacing: 12) {
            Spacer()
            ProgressView()
                .progressViewStyle(.circular)
                .tint(.white.opacity(0.7))
                .scaleEffect(0.8)
            Text("Checking open terminal sessions")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.white.opacity(0.58))
            Text("Open Island will show live agents after terminal ownership is confirmed")
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.28))
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()
            Text("No open terminal sessions")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.white.opacity(0.4))
            Text(model.recentSessions.isEmpty
                ? "Start Codex in your terminal"
                : "Recent sessions remain in Control Center until the terminal is open again")
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.25))
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private var sessionList: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 4) {
                    ForEach(displayedSessions) { session in
                        IslandSessionRow(
                            session: session,
                            isHighlighted: session.id == hoveredSessionID,
                            onHoverChange: { isHovering in
                                hoveredSessionID = isHovering ? session.id : (hoveredSessionID == session.id ? nil : hoveredSessionID)
                            },
                            onJump: { model.jumpToSession(session) }
                        )
                    }
                }
            }
            .padding(.vertical, 2)
            .frame(
                maxHeight: sessionListViewportHeight(
                    referenceDate: context.date,
                    sessions: sessionListViewportSessions(at: context.date)
                ),
                alignment: .top
            )
        }
    }

    private func notificationCard(session: AgentSession) -> some View {
        IslandNotificationCard(
            session: session,
            onApprove: { model.approvePermission(for: session.id, approved: $0) },
            onAnswer: { model.answerQuestion(for: session.id, answer: $0) }
        )
    }

    private var displayedSessions: [AgentSession] {
        model.islandListSessions
    }

    private func sessionListViewportSessions(at referenceDate: Date) -> [AgentSession] {
        Array(displayedSessions.prefix(Self.maxVisibleSessionRows))
    }

    private func sessionListViewportHeight(
        referenceDate: Date,
        sessions: [AgentSession]
    ) -> CGFloat {
        let rowHeights = sessions.map { session in
            session.islandPresence(at: referenceDate) == .inactive ? 44.0 : 76.0
        }

        let rowsHeight = rowHeights.reduce(CGFloat.zero, +)
        let spacingHeight = CGFloat(max(0, rowHeights.count - 1)) * 4
        return rowsHeight + spacingHeight + 4
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
                Text("Open Island")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.9))

                Text("Usage waiting")
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

// MARK: - Session row (opened state)

private struct IslandSessionRow: View {
    let session: AgentSession
    let isHighlighted: Bool
    let onHoverChange: (Bool) -> Void
    let onJump: () -> Void

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            rowBody(referenceDate: context.date)
        }
    }

    private func rowBody(referenceDate: Date) -> some View {
        let presence = session.islandPresence(at: referenceDate)
        let showsExpandedContent = presence != .inactive
        return Button(action: handlePrimaryTap) {
            HStack(alignment: .top, spacing: 14) {
                statusDot(for: presence)

                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .top, spacing: 12) {
                        Text(session.spotlightHeadlineText)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(headlineColor(for: presence))
                            .lineLimit(1)

                        Spacer(minLength: 8)

                        HStack(spacing: 6) {
                            compactBadge(session.tool.displayName, presence: presence)
                            if let terminalBadge = session.spotlightTerminalBadge {
                                compactBadge(terminalBadge, presence: presence)
                            }
                            compactBadge(session.spotlightAgeBadge, presence: presence)
                        }
                    }

                    if showsExpandedContent,
                       let promptLine = session.spotlightPromptLineText {
                        Text(promptLine)
                            .font(.system(size: 11.5, weight: .medium))
                            .foregroundStyle(.white.opacity(0.62))
                            .lineLimit(1)
                    }

                    if showsExpandedContent,
                       let activityLine = session.spotlightActivityLineText {
                        Text(activityLine)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(activityColor(for: presence).opacity(0.94))
                            .lineLimit(1)
                    }
                }
            }
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(isHighlighted ? Color.white.opacity(0.05) : Color.black)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(isHighlighted ? .white.opacity(0.24) : .white.opacity(0.04))
        )
        .shadow(color: isHighlighted ? .black.opacity(0.24) : .clear, radius: 12, y: 8)
        .overlay(
            Rectangle()
                .fill(Color.white.opacity(isHighlighted ? 0 : 0.02))
                .frame(height: 1),
            alignment: .bottom
        )
        .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .onHover(perform: onHoverChange)
    }

    private func statusDot(for presence: IslandSessionPresence) -> some View {
        Circle()
            .fill(statusTint(for: presence))
            .frame(width: 9, height: 9)
            .padding(.top, 6)
    }

    private func handlePrimaryTap() {
        onJump()
    }

    private func compactBadge(
        _ title: String,
        presence: IslandSessionPresence
    ) -> some View {
        Text(title)
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(badgeTextColor(for: presence))
            .padding(.horizontal, 7)
            .padding(.vertical, 3.5)
            .background(Color(red: 0.14, green: 0.14, blue: 0.15), in: Capsule())
    }

    private func headlineColor(for presence: IslandSessionPresence) -> Color {
        presence == .inactive ? .white.opacity(0.78) : .white
    }

    private func badgeTextColor(for presence: IslandSessionPresence) -> Color {
        presence == .inactive ? .white.opacity(0.42) : .white.opacity(0.56)
    }

    private func statusTint(for presence: IslandSessionPresence) -> Color {
        if session.phase == .waitingForApproval {
            return .orange.opacity(0.94)
        }

        if session.phase == .waitingForAnswer {
            return .yellow.opacity(0.96)
        }

        switch presence {
        case .running:
            return Color(red: 0.34, green: 0.61, blue: 0.99)
        case .active:
            return Color(red: 0.29, green: 0.86, blue: 0.46)
        case .inactive:
            return .white.opacity(0.38)
        }
    }

    private func activityColor(for presence: IslandSessionPresence) -> Color {
        switch session.spotlightActivityTone {
        case .attention:
            .orange.opacity(0.94)
        case .live:
            statusTint(for: presence)
        case .idle:
            .white.opacity(0.46)
        case .ready:
            presence == .inactive ? .white.opacity(0.46) : statusTint(for: presence)
        }
    }
}

private struct IslandNotificationCard: View {
    private static let completionReplyMaxHeight: CGFloat = 188

    let session: AgentSession
    let onApprove: (Bool) -> Void
    let onAnswer: (QuestionPromptResponse) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 14) {
                Circle()
                    .fill(statusTint)
                    .frame(width: 10, height: 10)
                    .padding(.top, 6)

                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .top, spacing: 12) {
                        Text(session.spotlightHeadlineText)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.white)
                            .lineLimit(1)

                        Spacer(minLength: 8)

                        HStack(spacing: 6) {
                            compactBadge(session.tool.displayName)
                            if let terminalBadge = session.spotlightTerminalBadge {
                                compactBadge(terminalBadge)
                            }
                            compactBadge(session.spotlightAgeBadge)
                        }
                    }

                    if let promptLine = session.notificationHeaderPromptLineText {
                        Text(promptLine)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.white.opacity(0.66))
                            .lineLimit(2)
                    }
                }
            }

            cardBody
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color.black)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(statusTint.opacity(0.28))
        )
    }

    @ViewBuilder
    private var cardBody: some View {
        switch session.phase {
        case .waitingForApproval:
            approvalBody
        case .waitingForAnswer:
            questionBody
        case .completed:
            completionBody
        case .running:
            defaultBody
        }
    }

    private var approvalBody: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.orange)

                Text(commandLabel)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.orange)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text(commandPreviewText)
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.9))
                    .fixedSize(horizontal: false, vertical: true)

                if let path = session.permissionRequest?.affectedPath.trimmedForNotificationCard,
                   !path.isEmpty {
                    Text(path)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.42))
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color(red: 0.11, green: 0.08, blue: 0.03))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(.orange.opacity(0.18))
            )

            HStack(spacing: 10) {
                Button(denyTitle) { onApprove(false) }
                    .buttonStyle(IslandWideButtonStyle(kind: .secondary))
                Button(allowTitle) { onApprove(true) }
                    .buttonStyle(IslandWideButtonStyle(kind: .primary))
            }
        }
    }

    private var questionBody: some View {
        StructuredQuestionPromptView(
            prompt: session.questionPrompt,
            onAnswer: onAnswer
        )
    }

    private var completionBody: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                Text(session.spotlightPromptLineText ?? "You:")
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.8))
                    .lineLimit(2)

                Spacer(minLength: 8)

                Text("Done")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(completionAccent.opacity(0.96))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)

            Rectangle()
                .fill(.white.opacity(0.04))
                .frame(height: 1)

            ScrollView(.vertical) {
                Text(completionMessageText)
                    .font(.system(size: 13.5, weight: .medium))
                    .foregroundStyle(.white.opacity(0.88))
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 14)
            }
            .scrollIndicators(.visible)
            .frame(minHeight: 0, maxHeight: Self.completionReplyMaxHeight, alignment: .top)
        }
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white.opacity(0.045))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(.white.opacity(0.08))
        )
    }

    private var defaultBody: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(session.spotlightActivityLineText ?? session.summary)
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(statusTint.opacity(0.95))
                .lineLimit(3)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(.white.opacity(0.06))
        )
    }

    private var statusTint: Color {
        switch session.phase {
        case .waitingForApproval:
            .orange
        case .waitingForAnswer:
            .yellow
        case .running:
            Color(red: 0.34, green: 0.61, blue: 0.99)
        case .completed:
            completionAccent
        }
    }

    private var completionAccent: Color {
        Color(red: 0.29, green: 0.86, blue: 0.46)
    }

    private var completionMessageText: String {
        session.lastAssistantMessageText?.trimmedForNotificationCard ?? session.summary
    }

    private var commandLabel: String {
        switch session.currentToolName {
        case "exec_command":
            return "Bash"
        case "Bash":
            return "Bash"
        case "AskUserQuestion":
            return "Question"
        case "ExitPlanMode":
            return "Plan"
        case "apply_patch":
            return "Patch"
        case "write_stdin":
            return "Input"
        case let value?:
            return value.capitalized
        case nil:
            return "Command"
        }
    }

    private var commandPreviewText: String {
        let preview = session.currentCommandPreviewText?.trimmedForNotificationCard
        if let preview, !preview.isEmpty {
            return "$ \(preview)"
        }

        return session.permissionRequest?.summary.trimmedForNotificationCard ?? session.summary.trimmedForNotificationCard
    }

    private var allowTitle: String {
        let title = session.permissionRequest?.primaryActionTitle.trimmedForNotificationCard
        if title == nil || title == "Allow" {
            return "Allow Once"
        }
        return title ?? "Allow Once"
    }

    private var denyTitle: String {
        session.permissionRequest?.secondaryActionTitle.trimmedForNotificationCard ?? "Deny"
    }

    private func compactBadge(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(.white.opacity(0.68))
            .padding(.horizontal, 7)
            .padding(.vertical, 3.5)
            .background(Color(red: 0.14, green: 0.14, blue: 0.15), in: Capsule())
    }
}

private struct StructuredQuestionPromptView: View {
    let prompt: QuestionPrompt?
    let onAnswer: (QuestionPromptResponse) -> Void

    @State private var selections: [String: Set<String>] = [:]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if showsPromptTitle {
                Text(promptTitle)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.yellow.opacity(0.96))
                    .fixedSize(horizontal: false, vertical: true)
            }

            if structuredQuestions.isEmpty {
                HStack(spacing: 10) {
                    ForEach(prompt?.options.prefix(3) ?? [], id: \.self) { option in
                        Button(option) {
                            onAnswer(QuestionPromptResponse(answer: option))
                        }
                        .buttonStyle(IslandWideButtonStyle(kind: .secondary))
                    }
                }
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(structuredQuestions, id: \.question) { question in
                            VStack(alignment: .leading, spacing: 8) {
                                Text(question.header)
                                    .font(.system(size: 10.5, weight: .bold))
                                    .foregroundStyle(.white.opacity(0.5))

                                Text(question.question)
                                    .font(.system(size: 12.5, weight: .medium))
                                    .foregroundStyle(.white.opacity(0.88))
                                    .fixedSize(horizontal: false, vertical: true)

                                HStack(spacing: 8) {
                                    ForEach(question.options.prefix(4), id: \.label) { option in
                                        Button(option.label) {
                                            toggle(option: option.label, for: question)
                                        }
                                        .buttonStyle(
                                            IslandWideButtonStyle(
                                                kind: selectedLabels(for: question).contains(option.label) ? .primary : .secondary
                                            )
                                        )
                                    }
                                }
                            }
                        }

                        Button("Submit Answers") {
                            onAnswer(QuestionPromptResponse(answers: answerMap))
                        }
                        .buttonStyle(IslandWideButtonStyle(kind: .primary))
                        .disabled(!hasCompleteSelection)
                    }
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(.white.opacity(0.06))
        )
    }

    private var structuredQuestions: [QuestionPromptItem] {
        prompt?.questions ?? []
    }

    private var promptTitle: String {
        prompt?.title.trimmedForNotificationCard ?? "Answer needed"
    }

    private var showsPromptTitle: Bool {
        guard !promptTitle.isEmpty else {
            return false
        }

        guard structuredQuestions.count == 1,
              let questionTitle = structuredQuestions.first?.question.trimmedForNotificationCard else {
            return true
        }

        return questionTitle.caseInsensitiveCompare(promptTitle) != .orderedSame
    }

    private var answerMap: [String: String] {
        Dictionary(uniqueKeysWithValues: structuredQuestions.compactMap { question in
            let selected = selectedLabels(for: question)
            guard !selected.isEmpty else {
                return nil
            }

            return (question.question, selected.sorted().joined(separator: ", "))
        })
    }

    private var hasCompleteSelection: Bool {
        structuredQuestions.allSatisfy { !selectedLabels(for: $0).isEmpty }
    }

    private func selectedLabels(for question: QuestionPromptItem) -> Set<String> {
        selections[question.question] ?? []
    }

    private func toggle(option: String, for question: QuestionPromptItem) {
        var selected = selections[question.question] ?? []

        if question.multiSelect {
            if selected.contains(option) {
                selected.remove(option)
            } else {
                selected.insert(option)
            }
        } else {
            if selected.contains(option) {
                selected.removeAll()
            } else {
                selected = [option]
            }
        }

        selections[question.question] = selected
    }
}

private extension String {
    var trimmedForNotificationCard: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - Compact button style

private struct IslandCompactButtonStyle: ButtonStyle {
    var tint: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(tint == .secondary ? .white.opacity(0.7) : tint)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                (tint == .secondary ? Color.white.opacity(0.08) : tint.opacity(0.15)),
                in: Capsule()
            )
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

private struct IslandWideButtonStyle: ButtonStyle {
    enum Kind {
        case primary
        case secondary
    }

    let kind: Kind

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11.5, weight: .semibold))
            .foregroundStyle(kind == .primary ? Color.white : Color.white.opacity(0.88))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(backgroundColor(configuration.isPressed), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func backgroundColor(_ isPressed: Bool) -> Color {
        switch kind {
        case .primary:
            return Color(red: 0.26, green: 0.45, blue: 0.86).opacity(isPressed ? 0.78 : 1.0)
        case .secondary:
            return Color.white.opacity(isPressed ? 0.12 : 0.16)
        }
    }
}

// MARK: - Open Island icon (left side of closed notch)

private struct OpenIslandIcon: View {
    let size: CGFloat
    var isAnimating: Bool = false
    var tint: Color = .mint

    var body: some View {
        OpenIslandBrandMark(
            size: size,
            tint: tint,
            isAnimating: isAnimating,
            style: .duotone
        )
    }
}

// MARK: - Attention indicator (permission/question dot)

private struct AttentionIndicator: View {
    let size: CGFloat
    let color: Color

    var body: some View {
        Image(systemName: "exclamationmark.triangle.fill")
            .font(.system(size: size * 0.75, weight: .bold))
            .foregroundStyle(color)
    }
}

// MARK: - Closed count badge (right side of closed notch)

private struct ClosedCountBadge: View {
    let liveCount: Int
    let tint: Color

    var body: some View {
        Text("\(liveCount)")
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(Color(red: 0.14, green: 0.14, blue: 0.15), in: Capsule())
    }
}

// MARK: - Menu bar content (unchanged)

struct MenuBarContentView: View {
    var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Open Island OSS")
                .font(.headline)
            Text("\(model.liveSessionCount) live · \(model.liveAttentionCount) attention")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Divider()

            Button("Open Control Center") {
                model.showControlCenter()
            }

            Text(model.acceptanceStatusTitle)
                .font(.subheadline.weight(.semibold))
            Text(model.acceptanceStatusSummary)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Divider()

            Button(model.isOverlayVisible ? "Hide Island Overlay" : "Show Island Overlay") {
                model.toggleOverlay()
            }

            Divider()

            Text(model.codexHookStatusTitle)
                .font(.subheadline.weight(.semibold))
            Text(model.codexHookStatusSummary)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Button("Refresh Codex Hook Status") {
                model.refreshCodexHookStatus()
            }

            if model.codexHooksInstalled {
                Button("Uninstall Codex Hooks") {
                    model.uninstallCodexHooks()
                }
            } else {
                Button("Install Codex Hooks") {
                    model.installCodexHooks()
                }
                .disabled(model.hooksBinaryURL == nil)
            }

            Divider()

            Text(model.claudeHookStatusTitle)
                .font(.subheadline.weight(.semibold))
            Text(model.claudeHookStatusSummary)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Button("Refresh Claude Hook Status") {
                model.refreshClaudeHookStatus()
            }

            if model.claudeHooksInstalled {
                Button("Uninstall Claude Hooks") {
                    model.uninstallClaudeHooks()
                }
            } else {
                Button("Install Claude Hooks") {
                    model.installClaudeHooks()
                }
                .disabled(model.hooksBinaryURL == nil)
            }

            if let session = model.focusedSession {
                Divider()
                Text(session.title)
                    .font(.subheadline.weight(.semibold))
                Text(session.spotlightPrimaryText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if let currentTool = session.spotlightCurrentToolLabel {
                    Text("Live tool: \(currentTool)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                if let trackingLabel = session.spotlightTrackingLabel {
                    Text("Tracking: \(trackingLabel)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(16)
        .frame(width: 280)
    }
}
