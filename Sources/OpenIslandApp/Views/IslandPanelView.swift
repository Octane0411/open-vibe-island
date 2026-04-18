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
private struct AutoHeightScrollView<Content: View>: View {
    let maxHeight: CGFloat
    @ViewBuilder let content: () -> Content
    @State private var contentHeight: CGFloat = 0

    private var isScrollable: Bool { contentHeight > maxHeight }

    var body: some View {
        // Always use ScrollView so the content gets unconstrained vertical
        // space for measurement.  Without this, a tight parent window can
        // cap the GeometryReader measurement, making long content appear
        // truncated instead of scrollable.
        ScrollView(.vertical) {
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
        .scrollBounceBehavior(.basedOnSize)
        .scrollIndicators(isScrollable ? .automatic : .hidden)
        .frame(height: contentHeight > 0 ? min(contentHeight, maxHeight) : nil)
    }
}

// MARK: - Row Height Estimation

extension AgentSession {
    /// Estimated row height matching `IslandSessionRow` layout for viewport sizing.
    func estimatedIslandRowHeight(at date: Date) -> CGFloat {
        let presence = islandPresence(at: date)
        // Base: vertical padding (28) + headline (~18) + rounding (2)
        var height: CGFloat = 48
        guard presence != .inactive else { return height }
        if spotlightPromptLineText != nil { height += 24 }   // spacing (8) + text (16)
        if spotlightActivityLineText != nil { height += 22 }  // spacing (8) + text (14)
        if let subagents = claudeMetadata?.activeSubagents, !subagents.isEmpty {
            height += 22  // spacing (8) + header (14)
            height += CGFloat(subagents.count) * 18  // each subagent row (spacing 4 + text 14)
        }
        if let tasks = claudeMetadata?.activeTasks, !tasks.isEmpty {
            height += 20  // spacing (8) + summary (12)
            height += CGFloat(tasks.count) * 16  // each task row (spacing 3 + text 13)
        }
        return height
    }
}

// MARK: - Animations

private let openAnimation = Animation.spring(response: 0.42, dampingFraction: 0.8, blendDuration: 0)
private let closeAnimation = Animation.smooth(duration: 0.3)
private let popAnimation = Animation.spring(response: 0.3, dampingFraction: 0.5)

/// Composite equatable key so `hasClosedPresence` and `expansionWidth` share
/// a single `.animation(.smooth, value:)` modifier instead of two separate
/// ones that can conflict when both change simultaneously.
private struct ClosedPresenceKey: Equatable {
    var present: Bool
    var width: CGFloat
}

private struct ConditionalDrawingGroup: ViewModifier {
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
    private static let closedIdleEdgeHeight: CGFloat = 4

    var model: AppModel

    @Namespace private var notchNamespace
    @State private var isHovering = false

    private var isOpened: Bool {
        model.notchStatus == .opened
    }

    private var usesOpenedVisualState: Bool {
        isOpened
    }

    private var isPopping: Bool {
        model.notchStatus == .popping
    }

    /// Single animation selection based on the current notch status.
    private var notchTransitionAnimation: Animation {
        switch model.notchStatus {
        case .opened:  return openAnimation
        case .closed:  return closeAnimation
        case .popping: return popAnimation
        }
    }

    private var closedSpotlightSession: AgentSession? {
        model.surfacedSessions.first(where: { $0.phase.requiresAttention })
            ?? model.surfacedSessions.first(where: { $0.phase == .running })
            ?? model.surfacedSessions.first
    }

    private var hasClosedPresence: Bool {
        model.liveSessionCount > 0
    }

    private var showsIdleEdgeWhenCollapsed: Bool {
        model.showsIdleEdgeWhenCollapsed
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
        if model.isCustomAppearance, let phase = closedSpotlightSession?.phase {
            return model.statusColor(for: phase)
        }
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
        return CGFloat(26 + max(0, digits - 1) * 8)
    }

    private var expansionWidth: CGFloat {
        guard !showsIdleEdgeWhenCollapsed else { return 0 }
        guard hasClosedPresence else { return 0 }
        let hasPending = closedSpotlightSession?.phase.requiresAttention == true
        let leftWidth = sideWidth + 8 + (hasPending ? 18 : 0)
        let rightWidth = max(sideWidth, countBadgeWidth) + (hasPending ? 18 : 0)
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
        .ignoresSafeArea()
        .preferredColorScheme(.dark)
    }

    @ViewBuilder
    private func notchContent(availableSize: CGSize) -> some View {
        // Window is always at opened size — use opened insets unconditionally.
        let panelShadowHorizontalInset = IslandChromeMetrics.openedShadowHorizontalInset
        let panelShadowBottomInset = IslandChromeMetrics.openedShadowBottomInset
        let layoutWidth = max(0, availableSize.width - (panelShadowHorizontalInset * 2))
        let layoutHeight = max(0, availableSize.height - panelShadowBottomInset)

        // Opened dimensions: fill the layout area with outer padding.
        let outerHorizontalPadding: CGFloat = 28
        let outerBottomPadding: CGFloat = 14
        let openedWidth = max(0, layoutWidth - outerHorizontalPadding)
        let openedHeight = max(closedNotchHeight, layoutHeight - outerBottomPadding)

        // Closed dimensions: sized to the actual notch + session indicators.
        let closedTotalWidth = closedNotchWidth + expansionWidth + (isPopping ? 18 : 0)
        let closedTotalHeight = closedNotchHeight

        let currentWidth = usesOpenedVisualState ? openedWidth : closedTotalWidth
        let currentHeight = usesOpenedVisualState ? openedHeight : closedTotalHeight
        let horizontalInset = usesOpenedVisualState ? 14.0 : 0.0
        let bottomInset = usesOpenedVisualState ? 14.0 : 0.0
        let surfaceWidth = currentWidth + (horizontalInset * 2)
        let surfaceHeight = currentHeight + bottomInset
        let surfaceShape = NotchShape(
            topCornerRadius: usesOpenedVisualState ? NotchShape.openedTopRadius : NotchShape.closedTopRadius,
            bottomCornerRadius: usesOpenedVisualState ? NotchShape.openedBottomRadius : NotchShape.closedBottomRadius
        )
        let hidesClosedSurfaceChrome = showsIdleEdgeWhenCollapsed && !usesOpenedVisualState
        let idleEdgeWidth = closedNotchWidth + (isPopping ? 18 : 0)

        VStack(spacing: 0) {
            ZStack(alignment: .top) {
                surfaceShape
                    .fill(Color.black.opacity(hidesClosedSurfaceChrome ? 0 : 1))
                    .frame(width: surfaceWidth, height: surfaceHeight)

                VStack(spacing: 0) {
                    headerRow
                        .frame(height: closedNotchHeight)
                        .opacity(hidesClosedSurfaceChrome ? 0 : 1)

                    openedContent
                        .frame(width: openedWidth - 24)
                        .frame(maxHeight: usesOpenedVisualState ? currentHeight - closedNotchHeight - 12 : 0, alignment: .top)
                        .opacity(usesOpenedVisualState ? 1 : 0)
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
                        .padding(.horizontal, usesOpenedVisualState ? NotchShape.openedTopRadius : NotchShape.closedTopRadius)
                        .opacity(hidesClosedSurfaceChrome ? 0 : 1)
                }
                .overlay {
                    surfaceShape
                        .stroke(Color.white.opacity(hidesClosedSurfaceChrome ? 0 : (usesOpenedVisualState ? 0.07 : 0.04)), lineWidth: 1)
                }
                .overlay(alignment: .top) {
                    Capsule()
                        .fill(Color.black)
                        .frame(width: idleEdgeWidth, height: Self.closedIdleEdgeHeight)
                        .overlay {
                            Capsule()
                                .stroke(Color.white.opacity(0.05), lineWidth: 1)
                        }
                        .opacity(showsIdleEdgeWhenCollapsed ? 1 : 0)
                }
            }
            .frame(width: surfaceWidth, height: surfaceHeight, alignment: .top)
        }
        .scaleEffect(usesOpenedVisualState ? 1 : (isHovering ? IslandChromeMetrics.closedHoverScale : 1), anchor: .top)
        .padding(.horizontal, panelShadowHorizontalInset)
        .padding(.bottom, panelShadowBottomInset)
        .animation(notchTransitionAnimation, value: model.notchStatus)
        .animation(.smooth, value: closedPresenceAnimationKey)
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
        if usesOpenedVisualState {
            openedHeaderContent
                .frame(height: closedNotchHeight)
        } else {
            HStack(spacing: 0) {
                if hasClosedPresence {
                    HStack(spacing: 4) {
                        if model.isCustomAppearance {
                            IslandPixelGlyph(
                                tint: scoutTint,
                                style: model.islandPixelShapeStyle,
                                isAnimating: hasClosedActivity,
                                customAvatarImage: model.customAvatarImage
                            )
                            .matchedGeometryEffect(id: "island-icon", in: notchNamespace, isSource: true)
                        } else {
                            OpenIslandIcon(size: 14, isAnimating: hasClosedActivity, tint: scoutTint)
                                .matchedGeometryEffect(id: "island-icon", in: notchNamespace, isSource: true)
                        }

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
                    let attentionBalanceWidth: CGFloat = closedSpotlightSession?.phase.requiresAttention == true ? 18 : 0
                    ClosedCountBadge(
                        liveCount: model.liveSessionCount,
                        tint: closedSpotlightSession?.phase.requiresAttention == true ? .orange : scoutTint
                    )
                    .matchedGeometryEffect(id: "right-indicator", in: notchNamespace, isSource: true)
                    .frame(width: max(sideWidth, countBadgeWidth) + attentionBalanceWidth)
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
        VStack(spacing: 8) {
            if !model.hasAnyInstalledAgent {
                installHooksHint
            }

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

    /// Persistent hint at the top of the expanded island while no agent
    /// hooks are installed. Decoupled from session presence — process
    /// discovery routinely surfaces sessions even on a freshly cleaned
    /// install, so the empty-state branch alone never reaches users who
    /// already run an agent.
    private var installHooksHint: some View {
        Button {
            model.showOnboarding()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                Text(model.lang.t("island.hint.installHooks"))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.85))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.4))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.accentColor.opacity(0.14))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(Color.accentColor.opacity(0.35), lineWidth: 0.5)
                    )
            )
        }
        .buttonStyle(.plain)
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
                // List mode: scroll when content exceeds the panel's available space.
                // The parent frame constraint (currentHeight - closedNotchHeight - 12)
                // determines the viewport; ScrollView handles overflow naturally.
                ScrollView(.vertical) {
                    sessionListContent(context: context)
                }
                .scrollIndicators(.hidden)
                .scrollBounceBehavior(.basedOnSize)
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
                    lang: model.lang,
                    onApprove: { model.approvePermission(for: session.id, action: $0) },
                    onAnswer: { model.answerQuestion(for: session.id, answer: $0) },
                    onReply: TerminalTextSender.canReply(to: session, enabled: model.completionReplyEnabled)
                        ? { model.replyToSession(session, text: $0) } : nil,
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
                        isActionable: session.phase.requiresAttention || session.id == actionableSessionID,
                        useDrawingGroup: model.notchStatus == .opened,
                        isInteractive: model.notchStatus == .opened,
                        lang: model.lang,
                        onApprove: { model.approvePermission(for: session.id, action: $0) },
                        onAnswer: { model.answerQuestion(for: session.id, answer: $0) },
                        onReply: TerminalTextSender.canReply(to: session, enabled: model.completionReplyEnabled)
                            ? { model.replyToSession(session, text: $0) } : nil,
                        onJump: { model.jumpToSession(session) },
                        onDismiss: session.isRemote ? { model.dismissSession(session.id) } : nil
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
        if model.isCustomAppearance {
            return model.statusColor(for: phase)
        }
        return switch phase {
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

        if model.showCodexUsage,
           let snapshot = model.codexUsageSnapshot,
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
    let referenceDate: Date
    var isActionable: Bool = false
    var useDrawingGroup: Bool = true
    var isInteractive: Bool = true
    var lang: LanguageManager = .shared
    var onApprove: ((ApprovalAction) -> Void)?
    var onAnswer: ((QuestionPromptResponse) -> Void)?
    var onReply: ((String) -> Void)?
    let onJump: () -> Void
    var onDismiss: (() -> Void)?

    @State private var isHighlighted = false
    @State private var isManuallyExpanded = false
    @State private var replyText: String = ""

    var body: some View {
        rowBody(referenceDate: referenceDate)
    }

    private func rowBody(referenceDate: Date) -> some View {
        let rawPresence = session.islandPresence(at: referenceDate)
        let presence = (rawPresence == .inactive && isManuallyExpanded) ? .active : rawPresence
        let showsExpandedContent = presence != .inactive
        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 14) {
                statusDot(for: presence)

                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .top, spacing: 12) {
                        Text(session.spotlightHeadlineText)
                            .font(.system(size: isActionable ? 15 : 14, weight: .semibold))
                            .foregroundStyle(headlineColor(for: presence))
                            .lineLimit(1)

                        Spacer(minLength: 8)

                        HStack(spacing: 6) {
                            compactBadge(session.tool.displayName, presence: presence)
                            if session.isRemote {
                                compactBadge("SSH", presence: presence, icon: "network")
                            }
                            if let terminalBadge = session.spotlightTerminalBadge {
                                compactBadge(terminalBadge, presence: presence)
                            }
                            compactBadge(session.spotlightAgeBadge, presence: presence)
                            if let onDismiss {
                                DismissButton(action: onDismiss)
                            }
                        }
                    }

                    if showsExpandedContent || isActionable,
                       let promptLine = session.spotlightPromptLineText ?? expandedPromptLineText {
                        Text(promptLine)
                            .font(.system(size: 11.5, weight: .medium))
                            .foregroundStyle(.white.opacity(0.62))
                            .lineLimit(1)
                    }

                    if showsExpandedContent || isActionable,
                       let activityLine = session.spotlightActivityLineText ?? expandedActivityLineText {
                        Text(activityLine)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(activityColor(for: presence).opacity(0.94))
                            .lineLimit(1)
                    }

                    if showsExpandedContent,
                       let subagents = session.claudeMetadata?.activeSubagents,
                       !subagents.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 5) {
                                Image(systemName: "arrow.triangle.branch")
                                    .font(.system(size: 9, weight: .medium))
                                Text(lang.t("subagents.title", subagents.count))
                                    .font(.system(size: 10.5, weight: .medium))
                            }
                            .foregroundStyle(.cyan.opacity(0.8))

                            ForEach(subagents, id: \.agentID) { sub in
                                HStack(spacing: 6) {
                                    Circle()
                                        .fill(sub.summary != nil
                                            ? Color(red: 0.29, green: 0.86, blue: 0.46)
                                            : Color(red: 0.34, green: 0.61, blue: 0.99))
                                        .frame(width: 6, height: 6)
                                    Text(sub.agentType ?? sub.agentID)
                                        .font(.system(size: 11, weight: .medium))
                                        .foregroundStyle(.white.opacity(0.8))
                                        .lineLimit(1)
                                    if let desc = sub.taskDescription {
                                        Text("(\(desc))")
                                            .font(.system(size: 10.5))
                                            .foregroundStyle(.white.opacity(0.5))
                                            .lineLimit(1)
                                    }
                                    Spacer(minLength: 0)
                                    if sub.summary != nil {
                                        Text(lang.t("subagents.completed"))
                                            .font(.system(size: 10, weight: .medium))
                                            .foregroundStyle(.white.opacity(0.4))
                                    } else if let started = sub.startedAt {
                                        TimelineView(.periodic(from: .now, by: 1)) { timeline in
                                            Text(subagentElapsed(since: started, at: timeline.date))
                                                .font(.system(size: 10, weight: .medium))
                                                .foregroundStyle(.white.opacity(0.4))
                                        }
                                    }
                                }
                            }
                        }
                    }

                    if showsExpandedContent,
                       let tasks = session.claudeMetadata?.activeTasks,
                       !tasks.isEmpty {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(taskSummary(tasks))
                                .font(.system(size: 10.5, weight: .medium))
                                .foregroundStyle(.white.opacity(0.45))
                            ForEach(tasks) { task in
                                HStack(spacing: 5) {
                                    taskStatusIcon(task.status)
                                    Text(task.title)
                                        .font(.system(size: 10.5, weight: .medium))
                                        .foregroundStyle(task.status == .completed
                                            ? .white.opacity(0.4)
                                            : .white.opacity(0.7))
                                        .strikethrough(task.status == .completed)
                                        .lineLimit(1)
                                }
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, isActionable ? 16 : 16)
            .padding(.vertical, isActionable ? 14 : 14)

            if isActionable {
                actionableBody
                    .padding(.horizontal, 16)
                    .padding(.bottom, 14)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: isActionable ? 24 : 22, style: .continuous)
                .fill(isHighlighted ? Color.white.opacity(isActionable ? 0.06 : 0.05) : Color.black)
        )
        .overlay(
            RoundedRectangle(cornerRadius: isActionable ? 24 : 22, style: .continuous)
                .strokeBorder(actionableBorderColor)
        )
        .compositingGroup()
        .shadow(color: .black.opacity(0.24), radius: isHighlighted ? 8 : 0, y: isHighlighted ? 6 : 0)
        .overlay(
            Group {
                if !isActionable {
                    Rectangle()
                        .fill(Color.white.opacity(isHighlighted ? 0 : 0.02))
                        .frame(height: 1)
                }
            },
            alignment: .bottom
        )
        .modifier(ConditionalDrawingGroup(enabled: useDrawingGroup && !isActionable))
        .contentShape(RoundedRectangle(cornerRadius: isActionable ? 24 : 22, style: .continuous))
        .animation(.easeInOut(duration: 0.15), value: isHighlighted)
        .onTapGesture(perform: handlePrimaryTap)
        .onHover { hovering in
            guard isInteractive else { return }
            isHighlighted = hovering
        }
        .onChange(of: isInteractive) { _, interactive in
            if !interactive {
                isManuallyExpanded = false
            }
        }
    }

    private var actionableBorderColor: Color {
        if isActionable {
            return actionableStatusTint.opacity(isHighlighted ? 0.45 : 0.28)
        }
        return isHighlighted ? .white.opacity(0.24) : .white.opacity(0.04)
    }

    private var actionableStatusTint: Color {
        switch session.phase {
        case .waitingForApproval:
            .orange
        case .waitingForAnswer:
            .yellow
        case .running:
            Color(red: 0.34, green: 0.61, blue: 0.99)
        case .completed:
            Color(red: 0.29, green: 0.86, blue: 0.46)
        }
    }

    @ViewBuilder
    private var actionableBody: some View {
        switch session.phase {
        case .waitingForApproval:
            approvalActionBody
        case .waitingForAnswer:
            questionActionBody
        case .completed:
            completionActionBody
        case .running:
            EmptyView()
        }
    }

    // MARK: - Approval action area

    private var approvalActionBody: some View {
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

            HStack(spacing: 8) {
                Button("No") { onApprove?(.deny) }
                    .buttonStyle(IslandWideButtonStyle(kind: .secondary))
                Button("Yes") { onApprove?(.allowOnce) }
                    .buttonStyle(IslandWideButtonStyle(kind: .warning))
                if let toolName = session.permissionRequest?.toolName {
                    Button("Always Allow (\(toolName))") {
                        let rule = ClaudePermissionRuleValue(toolName: toolName)
                        let update = ClaudePermissionUpdate.addRules(
                            destination: .session,
                            rules: [rule],
                            behavior: .allow
                        )
                        onApprove?(.allowWithUpdates([update]))
                    }
                    .buttonStyle(IslandWideButtonStyle(kind: .danger))
                }
            }
        }
    }

    // MARK: - Question action area

    private var questionActionBody: some View {
        StructuredQuestionPromptView(
            prompt: session.questionPrompt,
            lang: lang,
            onAnswer: { onAnswer?($0) }
        )
    }

    // MARK: - Completion action area

    private var completionActionBody: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                Text(completionPromptLabel)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.8))
                    .lineLimit(2)

                Spacer(minLength: 8)

                Text(lang.t("completion.done"))
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Color(red: 0.29, green: 0.86, blue: 0.46).opacity(0.96))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)

            Rectangle()
                .fill(.white.opacity(0.04))
                .frame(height: 1)

            AutoHeightScrollView(maxHeight: 260) {
                Markdown(completionMessageText)
                    .markdownTheme(.completionCard)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
            }

            if onReply != nil {
                Rectangle()
                    .fill(.white.opacity(0.04))
                    .frame(height: 1)

                completionReplyInput
            }
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

    @ViewBuilder
    private var completionReplyInput: some View {
        HStack(spacing: 8) {
            ReplyTextField(
                placeholder: lang.t("completion.replyPlaceholder"),
                text: $replyText,
                onSubmit: { submitReply() }
            )
            .frame(height: 32)

            Button {
                submitReply()
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 24))
                    .foregroundColor(replyText.trimmingCharacters(in: .whitespaces).isEmpty
                        ? .white.opacity(0.2) : .white.opacity(0.9))
            }
            .buttonStyle(.plain)
            .disabled(replyText.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private func submitReply() {
        let text = replyText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        replyText = ""
        onReply?(text)
    }

    // MARK: - Actionable helpers

    private var completionPromptLabel: String {
        if let prompt = session.latestUserPromptText?.trimmedForNotificationCard, !prompt.isEmpty {
            return "You: \(prompt)"
        }
        return "You:"
    }

    private var completionMessageText: String {
        if let text = session.completionAssistantMessageText?.trimmedForNotificationCard, !text.isEmpty {
            return text
        }
        return session.summary
    }

    private var commandLabel: String {
        switch session.currentToolName {
        case "exec_command", "Bash": return "Bash"
        case "AskUserQuestion": return "Question"
        case "ExitPlanMode": return "Plan"
        case "apply_patch": return "Patch"
        case "write_stdin": return "Input"
        case let value?: return value.capitalized
        case nil: return "Command"
        }
    }

    private var commandPreviewText: String {
        let preview = session.currentCommandPreviewText?.trimmedForNotificationCard
        if let preview, !preview.isEmpty {
            return "$ \(preview)"
        }
        return session.permissionRequest?.summary.trimmedForNotificationCard ?? session.summary.trimmedForNotificationCard
    }


    private func subagentElapsed(since start: Date, at now: Date) -> String {
        let seconds = Int(now.timeIntervalSince(start))
        if seconds < 60 { return "\(seconds)s" }
        let minutes = seconds / 60
        let secs = seconds % 60
        return "\(minutes)m \(secs)s"
    }

    private func taskSummary(_ tasks: [ClaudeTaskInfo]) -> String {
        let done = tasks.filter { $0.status == .completed }.count
        let prog = tasks.filter { $0.status == .inProgress }.count
        let pend = tasks.filter { $0.status == .pending }.count
        return lang.t("tasks.summary", done, prog, pend)
    }

    @ViewBuilder
    private func taskStatusIcon(_ status: ClaudeTaskInfo.Status) -> some View {
        switch status {
        case .completed:
            Image(systemName: "checkmark.square.fill")
                .font(.system(size: 9))
                .foregroundStyle(.white.opacity(0.35))
        case .inProgress:
            Circle()
                .fill(Color(red: 0.34, green: 0.61, blue: 0.99))
                .frame(width: 6, height: 6)
        case .pending:
            Circle()
                .strokeBorder(.white.opacity(0.3), lineWidth: 1)
                .frame(width: 6, height: 6)
        }
    }

    private func statusDot(for presence: IslandSessionPresence) -> some View {
        Circle()
            .fill(statusTint(for: presence))
            .frame(width: 9, height: 9)
            .padding(.top, 6)
    }

    /// Prompt line for manually expanded inactive rows (bypasses time-based filter).
    private var expandedPromptLineText: String? {
        guard isManuallyExpanded, let prompt = session.spotlightPromptText else { return nil }
        return "You: \(prompt)"
    }

    /// Activity line for manually expanded inactive rows (bypasses time-based filter).
    private var expandedActivityLineText: String? {
        guard isManuallyExpanded else { return nil }
        let trimmed = session.lastAssistantMessageText?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let assistantMessage = trimmed, !assistantMessage.isEmpty {
            return assistantMessage
        }
        return session.jumpTarget != nil ? "Ready" : "Completed"
    }

    private func handlePrimaryTap() {
        let rawPresence = session.islandPresence(at: referenceDate)
        if rawPresence == .inactive && !isManuallyExpanded {
            withAnimation(.easeInOut(duration: 0.2)) {
                isManuallyExpanded = true
            }
        } else {
            onJump()
        }
    }

    private func compactBadge(
        _ title: String,
        presence: IslandSessionPresence,
        icon: String? = nil
    ) -> some View {
        HStack(spacing: 3) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 7.5, weight: .semibold))
            }
            Text(title)
                .font(.system(size: 9, weight: .semibold))
        }
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

private struct StructuredQuestionPromptView: View {
    let prompt: QuestionPrompt?
    var lang: LanguageManager = .shared
    let onAnswer: (QuestionPromptResponse) -> Void

    @State private var selections: [String: Set<String>] = [:]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if showsPromptTitle {
                Text(promptTitle)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.yellow.opacity(0.96))
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 10) {
                ForEach(structuredQuestions, id: \.question) { question in
                    questionRow(question)
                }

                Button(lang.t("question.submit")) {
                    onAnswer(QuestionPromptResponse(answers: answerMap))
                }
                .buttonStyle(IslandWideButtonStyle(kind: .primary))
                .disabled(!hasCompleteSelection)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
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

    // MARK: - Per-question row

    /// Renders a single question with its header, text, and vertical option list.
    @ViewBuilder
    private func questionRow(_ question: QuestionPromptItem) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if structuredQuestions.count > 1 {
                Text(question.header)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white.opacity(0.5))
            }

            Text(question.question)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(0.88))
                .fixedSize(horizontal: false, vertical: true)

            // Vertical option list
            VStack(alignment: .leading, spacing: 4) {
                ForEach(question.options) { option in
                    optionRow(option, question: question)
                }
            }
        }
    }

    // MARK: - Option row (vertical, CLI-style)

    /// Renders a single option as a selectable row with checkmark indicator, label, and optional description.
    private func optionRow(_ option: QuestionOption, question: QuestionPromptItem) -> some View {
        let isSelected = selectedLabels(for: question).contains(option.label)
        return Button {
            toggle(option: option.label, for: question)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(isSelected ? .yellow : .white.opacity(0.35))

                VStack(alignment: .leading, spacing: 1) {
                    Text(option.label)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white.opacity(isSelected ? 1 : 0.78))

                    if !option.description.isEmpty {
                        Text(option.description)
                            .font(.system(size: 10.5))
                            .foregroundStyle(.white.opacity(0.4))
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 0)
            }
            .padding(.vertical, 5)
            .padding(.horizontal, 10)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isSelected ? Color.yellow.opacity(0.10) : Color.white.opacity(0.04))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(isSelected ? .yellow.opacity(0.25) : .clear)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Helpers

    private var structuredQuestions: [QuestionPromptItem] {
        prompt?.questions ?? []
    }

    private var promptTitle: String {
        prompt?.title.trimmedForNotificationCard ?? lang.t("question.answerNeeded")
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

// MARK: - Reply TextField (NSTextField wrapper for IME-safe Enter handling)

/// NSTextField wrapper that fires `onSubmit` only when the IME composition
/// is finished — pressing Enter during Chinese/Japanese IME composition
/// confirms the candidate instead of submitting.
private struct ReplyTextField: NSViewRepresentable {
    var placeholder: String
    @Binding var text: String
    var onSubmit: () -> Void

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField()
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = .systemFont(ofSize: 13)
        field.textColor = .white
        field.placeholderAttributedString = NSAttributedString(
            string: placeholder,
            attributes: [
                .foregroundColor: NSColor.white.withAlphaComponent(0.35),
                .font: NSFont.systemFont(ofSize: 13),
            ]
        )
        field.delegate = context.coordinator
        field.cell?.lineBreakMode = .byTruncatingTail
        field.cell?.usesSingleLineMode = true
        return field
    }

    func updateNSView(_ nsView: NSTextField, context: Context) {
        if nsView.stringValue != text {
            nsView.stringValue = text
        }
        context.coordinator.onSubmit = onSubmit
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, onSubmit: onSubmit)
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var text: Binding<String>
        var onSubmit: () -> Void

        init(text: Binding<String>, onSubmit: @escaping () -> Void) {
            self.text = text
            self.onSubmit = onSubmit
        }

        func controlTextDidChange(_ obj: Notification) {
            guard let field = obj.object as? NSTextField else { return }
            text.wrappedValue = field.stringValue
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                // Let AppKit handle Enter during IME composition (e.g. confirming
                // a Chinese/Japanese candidate). Only submit when no marked text.
                guard !textView.hasMarkedText() else { return false }
                onSubmit()
                return true
            }
            return false
        }
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
        case warning
        case danger
    }

    let kind: Kind

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11.5, weight: .semibold))
            .foregroundStyle(foregroundColor)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(backgroundColor(configuration.isPressed), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var foregroundColor: Color {
        switch kind {
        case .primary, .warning, .danger:
            return .white
        case .secondary:
            return .white.opacity(0.88)
        }
    }

    private func backgroundColor(_ isPressed: Bool) -> Color {
        let pressedFactor: Double = isPressed ? 0.78 : 1.0
        switch kind {
        case .primary:
            return Color(red: 0.26, green: 0.45, blue: 0.86).opacity(pressedFactor)
        case .secondary:
            return Color.white.opacity(isPressed ? 0.12 : 0.16)
        case .warning:
            return Color(red: 0.85, green: 0.55, blue: 0.15).opacity(pressedFactor)
        case .danger:
            return Color(red: 0.82, green: 0.22, blue: 0.22).opacity(pressedFactor)
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
            Text(model.lang.t("app.name.oss"))
                .font(.headline)
            Text(model.lang.t("menu.status", model.liveSessionCount, model.liveAttentionCount))
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Divider()

            Button(model.lang.t("menu.settings")) {
                model.showSettings()
            }

            #if DEBUG
            Button(model.lang.t("menu.openDebug")) {
                model.showControlCenter()
            }
            #endif

            Text(model.acceptanceStatusTitle)
                .font(.subheadline.weight(.semibold))
            Text(model.acceptanceStatusSummary)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Divider()

            Button(model.isOverlayVisible ? model.lang.t("menu.hideOverlay") : model.lang.t("menu.showOverlay")) {
                model.toggleOverlay()
            }

            Divider()

            Text(model.codexHookStatusTitle)
                .font(.subheadline.weight(.semibold))
            Text(model.codexHookStatusSummary)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Button(model.lang.t("menu.refreshCodexHooks")) {
                model.refreshCodexHookStatus()
            }

            if model.codexHooksInstalled {
                Button(model.lang.t("menu.uninstallCodexHooks")) {
                    model.uninstallCodexHooks()
                }
            } else {
                Button(model.lang.t("menu.installCodexHooks")) {
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

            Button(model.lang.t("menu.refreshClaudeHooks")) {
                model.refreshClaudeHookStatus()
            }

            if model.claudeHooksInstalled {
                Button(model.lang.t("menu.uninstallClaudeHooks")) {
                    model.uninstallClaudeHooks()
                }
            } else {
                Button(model.lang.t("menu.installClaudeHooks")) {
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
                    Text(model.lang.t("menu.liveTool", currentTool))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                if let trackingLabel = session.spotlightTrackingLabel {
                    Text(model.lang.t("menu.tracking", trackingLabel))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(16)
        .frame(width: 280)
    }
}

// MARK: - MarkdownUI Theme

extension MarkdownUI.Theme {
    @MainActor static let completionCard = Theme()
        .text {
            ForegroundColor(.white.opacity(0.88))
            FontSize(13.5)
            FontWeight(.medium)
        }
        .link {
            ForegroundColor(.blue)
        }
        .strong {
            FontWeight(.bold)
        }
        .code {
            FontFamilyVariant(.monospaced)
            FontSize(12.5)
            ForegroundColor(.white.opacity(0.88))
            BackgroundColor(.white.opacity(0.08))
        }
        .codeBlock { configuration in
            configuration.label
                .markdownTextStyle {
                    FontFamilyVariant(.monospaced)
                    FontSize(12.5)
                    ForegroundColor(.white.opacity(0.88))
                }
                .padding(10)
                .background(Color.white.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .heading1 { configuration in
            configuration.label
                .markdownTextStyle {
                    FontSize(16)
                    FontWeight(.bold)
                    ForegroundColor(.white.opacity(0.88))
                }
                .markdownMargin(top: 8, bottom: 4)
        }
        .heading2 { configuration in
            configuration.label
                .markdownTextStyle {
                    FontSize(15)
                    FontWeight(.bold)
                    ForegroundColor(.white.opacity(0.88))
                }
                .markdownMargin(top: 8, bottom: 4)
        }
        .heading3 { configuration in
            configuration.label
                .markdownTextStyle {
                    FontSize(14)
                    FontWeight(.semibold)
                    ForegroundColor(.white.opacity(0.88))
                }
                .markdownMargin(top: 6, bottom: 2)
        }
        .blockquote { configuration in
            configuration.label
                .markdownTextStyle {
                    ForegroundColor(.white.opacity(0.6))
                    FontSize(13.5)
                }
                .padding(.leading, 12)
                .overlay(alignment: .leading) {
                    Rectangle()
                        .fill(Color.white.opacity(0.2))
                        .frame(width: 3)
                }
        }
        .listItem { configuration in
            configuration.label
                .markdownMargin(top: 2, bottom: 2)
        }
        .table { configuration in
            configuration.label
                .fixedSize(horizontal: false, vertical: true)
                .markdownTableBorderStyle(.init(.allBorders, color: .white.opacity(0.15), strokeStyle: .init(lineWidth: 1)))
                .markdownTableBackgroundStyle(
                    .alternatingRows(Color.white.opacity(0.04), Color.white.opacity(0.08))
                )
                .markdownMargin(top: 4, bottom: 8)
        }
        .tableCell { configuration in
            configuration.label
                .markdownTextStyle {
                    if configuration.row == 0 {
                        FontWeight(.semibold)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
                .padding(.vertical, 6)
                .padding(.horizontal, 12)
                .relativeLineSpacing(.em(0.25))
        }
}

private struct DismissButton: View {
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(isHovered ? 0.8 : 0.4))
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}
