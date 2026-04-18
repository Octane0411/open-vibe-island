import AppKit
import Foundation
import Observation
import OpenIslandCore
import SwiftUI

extension Notification.Name {
    /// Posted by `AppModel.showOnboarding()` to ask `SettingsView` to
    /// switch to the Setup tab. Lets the empty-state CTAs deliver the
    /// user to the right place without `SettingsView`'s `@State` having
    /// to leak into `AppModel`.
    static let openIslandSelectSetupTab = Notification.Name("openIslandSelectSetupTab")
}

@MainActor
@Observable
final class AppModel {
    private static let soundMutedDefaultsKey = "overlay.sound.muted"
    private static let showDockIconDefaultsKey = "app.showDockIcon"
    private static let hapticFeedbackEnabledDefaultsKey = "app.hapticFeedbackEnabled"
    private static let islandAppearanceModeDefaultsKey = "appearance.island.mode"
    private static let islandClosedDisplayStyleDefaultsKey = "appearance.island.closedDisplayStyle"
    private static let islandHideIdleToEdgeDefaultsKey = "appearance.island.hideIdleToEdge"
    private static let islandPixelShapeStyleDefaultsKey = "appearance.island.pixelShapeStyle"
    private static let islandStatusColorsDefaultsKey = "appearance.island.statusColors"
    private static let showCodexUsageDefaultsKey = "app.showCodexUsage"
    private static let completionReplyEnabledDefaultsKey = "feature.completionReply.enabled"
    private static let suppressFrontmostNotificationsDefaultsKey = "app.suppressFrontmostNotifications"

    static let defaultStatusColors: [SessionPhase: String] = [
        .running: "#6E9FFF",
        .waitingForApproval: "#FFB547",
        .waitingForAnswer: "#FFD95A",
        .completed: "#42E86B",
    ]
    private static let syntheticClaudeSessionPrefix = "claude-process:"
    private static let liveSessionStalenessWindow: TimeInterval = 15 * 60
    private static let jumpOverlayDismissLeadTime: Duration = .milliseconds(20)
    static let hoverOpenDelay: TimeInterval = 0.15

    struct AcceptanceStep: Identifiable {
        let id: String
        let title: String
        let detail: String
        let isComplete: Bool
    }

    let lang = LanguageManager.shared

    var state = SessionState() {
        didSet {
            _cachedSessionBuckets = nil
            bridgeServer.updateStateSnapshot(state)
        }
    }
    @ObservationIgnored private var _cachedSessionBuckets: (primary: [AgentSession], overflow: [AgentSession])?
    var selectedSessionID: String?
    let hooks = HookInstallationCoordinator()
    let overlay = OverlayUICoordinator()
    let discovery = SessionDiscoveryCoordinator()
    let monitoring = ProcessMonitoringCoordinator()
    let codexAppServer = CodexAppServerCoordinator()
    let updateChecker = UpdateChecker()

    var notchStatus: NotchStatus {
        get { overlay.notchStatus }
        set { overlay.notchStatus = newValue }
    }
    var notchOpenReason: NotchOpenReason? {
        get { overlay.notchOpenReason }
        set { overlay.notchOpenReason = newValue }
    }
    var islandSurface: IslandSurface {
        get { overlay.islandSurface }
        set { overlay.islandSurface = newValue }
    }
    var isOverlayVisible: Bool { overlay.isOverlayVisible }
    var isOverlayCloseTransitionPending: Bool { overlay.isCloseTransitionPending }
    var overlayCloseTransitionSurfaceOffset: CGSize { overlay.closeTransitionSurfaceOffset }
    var isCodexSetupBusy: Bool { hooks.isCodexSetupBusy }
    var isClaudeHookSetupBusy: Bool { hooks.isClaudeHookSetupBusy }
    var isClaudeUsageSetupBusy: Bool { hooks.isClaudeUsageSetupBusy }
    var codexHookStatus: CodexHookInstallationStatus? { hooks.codexHookStatus }
    var claudeHookStatus: ClaudeHookInstallationStatus? { hooks.claudeHookStatus }
    var claudeStatusLineStatus: ClaudeStatusLineInstallationStatus? { hooks.claudeStatusLineStatus }
    var claudeUsageSnapshot: ClaudeUsageSnapshot? { hooks.claudeUsageSnapshot }
    var codexUsageSnapshot: CodexUsageSnapshot? { hooks.codexUsageSnapshot }
    var hooksBinaryURL: URL? { hooks.hooksBinaryURL }
    var codexHooksInstalled: Bool { hooks.codexHooksInstalled }
    var claudeHooksInstalled: Bool { hooks.claudeHooksInstalled }
    var qoderHooksInstalled: Bool { hooks.qoderHooksInstalled }
    var qwenCodeHooksInstalled: Bool { hooks.qwenCodeHooksInstalled }
    var factoryHooksInstalled: Bool { hooks.factoryHooksInstalled }
    var codebuddyHooksInstalled: Bool { hooks.codebuddyHooksInstalled }
    var qoderHookStatus: ClaudeHookInstallationStatus? { hooks.qoderHookStatus }
    var qwenCodeHookStatus: ClaudeHookInstallationStatus? { hooks.qwenCodeHookStatus }
    var factoryHookStatus: ClaudeHookInstallationStatus? { hooks.factoryHookStatus }
    var codebuddyHookStatus: ClaudeHookInstallationStatus? { hooks.codebuddyHookStatus }
    var isQoderHookSetupBusy: Bool { hooks.isQoderHookSetupBusy }
    var isQwenCodeHookSetupBusy: Bool { hooks.isQwenCodeHookSetupBusy }
    var isFactoryHookSetupBusy: Bool { hooks.isFactoryHookSetupBusy }
    var isCodebuddyHookSetupBusy: Bool { hooks.isCodebuddyHookSetupBusy }
    var openCodePluginInstalled: Bool { hooks.openCodePluginInstalled }
    var claudeUsageInstalled: Bool { hooks.claudeUsageInstalled }
    var claudeHookStatusTitle: String { hooks.claudeHookStatusTitle }
    var claudeHookStatusSummary: String { hooks.claudeHookStatusSummary }
    var claudeUsageStatusTitle: String { hooks.claudeUsageStatusTitle }
    var claudeUsageStatusSummary: String { hooks.claudeUsageStatusSummary }
    var claudeUsageSummaryText: String? { hooks.claudeUsageSummaryText }
    var codexUsageStatusTitle: String { hooks.codexUsageStatusTitle }
    var codexUsageStatusSummary: String { hooks.codexUsageStatusSummary }
    var codexUsageSummaryText: String? { hooks.codexUsageSummaryText }
    var openCodePluginStatus: OpenCodePluginInstallationStatus? { hooks.openCodePluginStatus }
    var isOpenCodeSetupBusy: Bool { hooks.isOpenCodeSetupBusy }
    var openCodePluginStatusTitle: String { hooks.openCodePluginStatusTitle }
    var openCodePluginStatusSummary: String { hooks.openCodePluginStatusSummary }
    var claudeHealthReport: HookHealthReport? { hooks.claudeHealthReport }
    var codexHealthReport: HookHealthReport? { hooks.codexHealthReport }
    var cursorHooksInstalled: Bool { hooks.cursorHooksInstalled }
    var isCursorHookSetupBusy: Bool { hooks.isCursorHookSetupBusy }
    var cursorHookStatus: CursorHookInstallationStatus? { hooks.cursorHookStatus }
    var cursorHookStatusTitle: String { hooks.cursorHookStatusTitle }
    var cursorHookStatusSummary: String { hooks.cursorHookStatusSummary }
    var geminiHooksInstalled: Bool { hooks.geminiHooksInstalled }
    var isGeminiHookSetupBusy: Bool { hooks.isGeminiHookSetupBusy }
    var geminiHookStatus: GeminiHookInstallationStatus? { hooks.geminiHookStatus }
    var geminiHookStatusTitle: String { hooks.geminiHookStatusTitle }
    var geminiHookStatusSummary: String { hooks.geminiHookStatusSummary }
    var kimiHooksInstalled: Bool { hooks.kimiHooksInstalled }
    var isKimiHookSetupBusy: Bool { hooks.isKimiHookSetupBusy }
    var kimiHookStatus: KimiHookInstallationStatus? { hooks.kimiHookStatus }
    var kimiHookStatusTitle: String { hooks.kimiHookStatusTitle }
    var kimiHookStatusSummary: String { hooks.kimiHookStatusSummary }
    var codexHookStatusTitle: String { hooks.codexHookStatusTitle }
    var codexHookStatusSummary: String { hooks.codexHookStatusSummary }

    /// Mirrors `AgentIntentStore.firstLaunchCompleted`. Onboarding sets this
    /// to true after the user completes (or explicitly skips) the flow;
    /// legacy migration also flips it for users upgrading with existing
    /// hooks.
    var firstLaunchCompleted: Bool {
        get { hooks.intentStore.firstLaunchCompleted }
        set { hooks.intentStore.firstLaunchCompleted = newValue }
    }

    /// True if at least one managed hook is currently present on disk.
    /// Drives the "configure agents" empty-state prompts in the island and
    /// the settings window.
    var hasAnyInstalledAgent: Bool {
        hooks.claudeHooksInstalled
            || hooks.codexHooksInstalled
            || hooks.cursorHooksInstalled
            || hooks.qoderHooksInstalled
            || hooks.qwenCodeHooksInstalled
            || hooks.factoryHooksInstalled
            || hooks.codebuddyHooksInstalled
            || hooks.openCodePluginInstalled
            || hooks.geminiHooksInstalled
            || hooks.kimiHooksInstalled
    }
    func refreshCodexHookStatus() { hooks.refreshCodexHookStatus() }
    func refreshClaudeHookStatus() { hooks.refreshClaudeHookStatus() }
    func refreshOpenCodePluginStatus() { hooks.refreshOpenCodePluginStatus() }
    func refreshCursorHookStatus() { hooks.refreshCursorHookStatus() }
    func refreshClaudeUsageState() { hooks.refreshClaudeUsageState() }
    func refreshCodexUsageState() { hooks.refreshCodexUsageState() }
    func installCodexHooks() { hooks.installCodexHooks() }
    func uninstallCodexHooks() { hooks.uninstallCodexHooks() }
    func installClaudeHooks() { hooks.installClaudeHooks() }
    func uninstallClaudeHooks() { hooks.uninstallClaudeHooks() }
    func installQoderHooks() { hooks.installQoderHooks() }
    func uninstallQoderHooks() { hooks.uninstallQoderHooks() }
    func installQwenCodeHooks() { hooks.installQwenCodeHooks() }
    func uninstallQwenCodeHooks() { hooks.uninstallQwenCodeHooks() }
    func installFactoryHooks() { hooks.installFactoryHooks() }
    func uninstallFactoryHooks() { hooks.uninstallFactoryHooks() }
    func installCodebuddyHooks() { hooks.installCodebuddyHooks() }
    func uninstallCodebuddyHooks() { hooks.uninstallCodebuddyHooks() }
    func refreshCCForkHookStatuses() { hooks.refreshCCForkHookStatuses() }
    func installOpenCodePlugin() { hooks.installOpenCodePlugin() }
    func uninstallOpenCodePlugin() { hooks.uninstallOpenCodePlugin() }
    func installCursorHooks() { hooks.installCursorHooks() }
    func uninstallCursorHooks() { hooks.uninstallCursorHooks() }
    func refreshGeminiHookStatus() { hooks.refreshGeminiHookStatus() }
    func installGeminiHooks() { hooks.installGeminiHooks() }
    func uninstallGeminiHooks() { hooks.uninstallGeminiHooks() }
    func refreshKimiHookStatus() { hooks.refreshKimiHookStatus() }
    func installKimiHooks() { hooks.installKimiHooks() }
    func uninstallKimiHooks() { hooks.uninstallKimiHooks() }
    func installClaudeUsageBridge() { hooks.installClaudeUsageBridge() }
    func uninstallClaudeUsageBridge() { hooks.uninstallClaudeUsageBridge() }
    func updateClaudeConfigDirectory(to newDirectory: URL?) { hooks.updateClaudeConfigDirectory(to: newDirectory) }
    func runHealthChecks() { hooks.runHealthChecks() }
    func repairHooks() {
        Task { @MainActor in
            await hooks.repairHooksIfNeeded()
        }
    }
    var isBridgeReady = false
    var lastActionMessage = "Waiting for agent hook events..." {
        didSet {
            guard lastActionMessage != oldValue else {
                return
            }

            harnessRuntimeMonitor?.recordLog(lastActionMessage)
        }
    }
    var isResolvingInitialLiveSessions: Bool {
        get { monitoring.isResolvingInitialLiveSessions }
        set { monitoring.isResolvingInitialLiveSessions = newValue }
    }
    var overlayDisplayOptions: [OverlayDisplayOption] {
        get { overlay.overlayDisplayOptions }
        set { overlay.overlayDisplayOptions = newValue }
    }
    var overlayPlacementDiagnostics: OverlayPlacementDiagnostics? {
        get { overlay.overlayPlacementDiagnostics }
        set { overlay.overlayPlacementDiagnostics = newValue }
    }
    var showDockIcon: Bool = false {
        didSet {
            guard hasFinishedInit, showDockIcon != oldValue else { return }
            UserDefaults.standard.set(showDockIcon, forKey: Self.showDockIconDefaultsKey)
            NSApp.setActivationPolicy(showDockIcon ? .regular : .accessory)
            if !showDockIcon {
                // macOS does not immediately refresh the Dock when switching to
                // .accessory at runtime. Briefly activating another app forces
                // the Dock to drop the icon.
                NSApp.hide(nil)
                DispatchQueue.main.async {
                    NSApp.unhide(nil)
                }
            }
        }
    }
    var hapticFeedbackEnabled: Bool = false {
        didSet {
            guard hasFinishedInit, hapticFeedbackEnabled != oldValue else { return }
            UserDefaults.standard.set(hapticFeedbackEnabled, forKey: Self.hapticFeedbackEnabledDefaultsKey)
        }
    }
    var showCodexUsage: Bool = false {
        didSet {
            guard hasFinishedInit, showCodexUsage != oldValue else { return }
            UserDefaults.standard.set(showCodexUsage, forKey: Self.showCodexUsageDefaultsKey)
        }
    }
    var completionReplyEnabled: Bool = false {
        didSet {
            guard hasFinishedInit, completionReplyEnabled != oldValue else { return }
            UserDefaults.standard.set(completionReplyEnabled, forKey: Self.completionReplyEnabledDefaultsKey)
            refreshOverlayPlacementIfVisible()
        }
    }
    var suppressFrontmostNotifications: Bool = true {
        didSet {
            guard hasFinishedInit, suppressFrontmostNotifications != oldValue else { return }
            UserDefaults.standard.set(suppressFrontmostNotifications, forKey: Self.suppressFrontmostNotificationsDefaultsKey)
        }
    }
    var isSoundMuted = false {
        didSet {
            guard isSoundMuted != oldValue else {
                return
            }

            UserDefaults.standard.set(isSoundMuted, forKey: Self.soundMutedDefaultsKey)
            lastActionMessage = isSoundMuted
                ? "Island sound notifications muted."
                : "Island sound notifications enabled."
        }
    }
    var selectedSoundName: String = NotificationSoundService.defaultSoundName {
        didSet {
            guard selectedSoundName != oldValue else { return }
            NotificationSoundService.selectedSoundName = selectedSoundName
        }
    }
    var overlayDisplaySelectionID: String {
        get { overlay.overlayDisplaySelectionID }
        set { overlay.overlayDisplaySelectionID = newValue }
    }
    var overlayPresentationPolicy: OverlayPresentationPolicy {
        get { overlay.overlayPresentationPolicy }
        set { overlay.overlayPresentationPolicy = newValue }
    }

    // MARK: - Appearance

    var islandAppearanceMode: IslandAppearanceMode = .default {
        didSet {
            guard islandAppearanceMode != oldValue else { return }
            UserDefaults.standard.set(islandAppearanceMode.rawValue, forKey: Self.islandAppearanceModeDefaultsKey)
            refreshOverlayPlacementIfVisible()
        }
    }

    var isCustomAppearance: Bool { islandAppearanceMode == .custom }

    var islandClosedDisplayStyle: IslandClosedDisplayStyle = .detailed {
        didSet {
            guard islandClosedDisplayStyle != oldValue else { return }
            UserDefaults.standard.set(islandClosedDisplayStyle.rawValue, forKey: Self.islandClosedDisplayStyleDefaultsKey)
            refreshOverlayPlacementIfVisible()
        }
    }
    var hideIdleIslandToEdge: Bool = false {
        didSet {
            guard hideIdleIslandToEdge != oldValue else { return }
            UserDefaults.standard.set(hideIdleIslandToEdge, forKey: Self.islandHideIdleToEdgeDefaultsKey)
            refreshOverlayPlacementIfVisible()
        }
    }
    var islandPixelShapeStyle: IslandPixelShapeStyle = .bars {
        didSet {
            guard islandPixelShapeStyle != oldValue else { return }
            UserDefaults.standard.set(islandPixelShapeStyle.rawValue, forKey: Self.islandPixelShapeStyleDefaultsKey)
        }
    }
    var statusColorHexes: [SessionPhase: String] = AppModel.defaultStatusColors {
        didSet {
            guard statusColorHexes != oldValue else { return }
            let encoded = statusColorHexes.reduce(into: [String: String]()) { $0[$1.key.rawValue] = $1.value }
            UserDefaults.standard.set(encoded, forKey: Self.islandStatusColorsDefaultsKey)
            _cachedStatusColors = [:]
        }
    }
    var customAvatarImage: NSImage? = nil
    private var _cachedStatusColors: [SessionPhase: Color] = [:]

    func statusColor(for phase: SessionPhase) -> Color {
        if let cached = _cachedStatusColors[phase] { return cached }
        let hex = statusColorHexes[phase] ?? Self.defaultStatusColors[phase] ?? "#6E9FFF"
        let color = Color(hex: hex) ?? .white
        _cachedStatusColors[phase] = color
        return color
    }

    func setStatusColor(_ color: Color, for phase: SessionPhase) {
        guard let hex = color.opaqueHexString else { return }
        statusColorHexes[phase] = hex
    }

    var showsIdleEdgeWhenCollapsed: Bool {
        hideIdleIslandToEdge && notchStatus == .closed
    }

    func importCustomAvatar() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.showsHiddenFiles = true
        panel.allowedContentTypes = [.png, .jpeg, .heic, .tiff]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            customAvatarImage = try AvatarImageStore.importImage(from: url)
            islandPixelShapeStyle = .custom
        } catch {
            lastActionMessage = error.localizedDescription
        }
    }

    func removeCustomAvatar() {
        do {
            try AvatarImageStore.removeCurrentImage()
            customAvatarImage = nil
            if islandPixelShapeStyle == .custom {
                islandPixelShapeStyle = .bars
            }
        } catch {
            lastActionMessage = error.localizedDescription
        }
    }
    @ObservationIgnored
    var openSettingsWindow: (() -> Void)?

    @ObservationIgnored
    private var hasFinishedInit = false

    // MARK: - Watch Notification

    private static let watchNotificationEnabledKey = "watch.notification.enabled"

    var watchNotificationEnabled: Bool = false {
        didSet {
            guard watchNotificationEnabled != oldValue else { return }
            UserDefaults.standard.set(watchNotificationEnabled, forKey: Self.watchNotificationEnabledKey)
            if watchNotificationEnabled {
                startWatchRelay()
            } else {
                stopWatchRelay()
            }
        }
    }

    @ObservationIgnored
    private(set) var watchRelay: WatchNotificationRelay?

    /// Current pairing code for display in the settings UI.
    var watchPairingCode: String {
        watchRelay?.endpoint.currentCode() ?? "----"
    }

    /// Number of currently connected iPhone SSE clients.
    var watchConnectedDevices: Int {
        // Placeholder — endpoint doesn't expose count yet
        0
    }

    private func startWatchRelay() {
        guard watchRelay == nil else { return }
        let relay = WatchNotificationRelay()
        setupWatchRelayCallbacks(relay)
        relay.start()
        self.watchRelay = relay
    }

    /// Wire up resolution callbacks so Watch/iPhone actions flow back to the bridge.
    private func setupWatchRelayCallbacks(_ relay: WatchNotificationRelay) {
        relay.onResolvePermission = { [weak self] sessionID, approved in
            Task { @MainActor [weak self] in
                self?.approvePermission(for: sessionID, approved: approved)
            }
        }

        relay.onAnswerQuestion = { [weak self] sessionID, answer in
            Task { @MainActor [weak self] in
                self?.answerQuestion(
                    for: sessionID,
                    answer: QuestionPromptResponse(answer: answer)
                )
            }
        }

        relay.endpoint.activeSessionCountProvider = { [weak self] in
            // Safe to call from any queue — reads a snapshot count.
            guard let self else { return 0 }
            return MainActor.assumeIsolated {
                self.state.sessions.count
            }
        }
    }

    private func stopWatchRelay() {
        watchRelay?.stop()
        watchRelay = nil
    }

    var ignoresPointerExitDuringHarness = false
    var disablesOverlayEventMonitoringDuringHarness = false

    @ObservationIgnored
    private var bridgeTask: Task<Void, Never>?

    @ObservationIgnored
    private var bridgeReconnectTask: Task<Void, Never>?

    @ObservationIgnored
    private var hasStarted = false

    @ObservationIgnored
    private let bridgeServer = BridgeServer()

    @ObservationIgnored
    private var bridgeClient = LocalBridgeClient()

    @ObservationIgnored
    private let terminalJumpAction: @Sendable (JumpTarget) throws -> String

    @ObservationIgnored
    private let isNotificationSessionAlreadyFrontmost: @Sendable (AgentSession) async -> Bool


    @ObservationIgnored
    var harnessRuntimeMonitor: HarnessRuntimeMonitor?


    @ObservationIgnored
    private var jumpTask: Task<Void, Never>?

    @ObservationIgnored
    private var notificationPresentationTask: Task<Void, Never>?

    init(
        terminalJumpAction: @escaping @Sendable (JumpTarget) throws -> String = { target in
            try TerminalJumpService().jump(to: target)
        },
        isNotificationSessionAlreadyFrontmost: @escaping @Sendable (AgentSession) async -> Bool = { session in
            await ForegroundTerminalSessionProbe().matches(session: session)
        }
    ) {
        self.terminalJumpAction = terminalJumpAction
        self.isNotificationSessionAlreadyFrontmost = isNotificationSessionAlreadyFrontmost
        UserDefaults.standard.register(defaults: [
            Self.showDockIconDefaultsKey: true,
            Self.hapticFeedbackEnabledDefaultsKey: false,
            Self.completionReplyEnabledDefaultsKey: false,
            Self.suppressFrontmostNotificationsDefaultsKey: true,
        ])
        isSoundMuted = UserDefaults.standard.bool(forKey: Self.soundMutedDefaultsKey)
        selectedSoundName = NotificationSoundService.selectedSoundName
        showDockIcon = UserDefaults.standard.bool(forKey: Self.showDockIconDefaultsKey)
        hapticFeedbackEnabled = UserDefaults.standard.bool(forKey: Self.hapticFeedbackEnabledDefaultsKey)
        suppressFrontmostNotifications = UserDefaults.standard.bool(forKey: Self.suppressFrontmostNotificationsDefaultsKey)
        if UserDefaults.standard.object(forKey: Self.showCodexUsageDefaultsKey) != nil {
            showCodexUsage = UserDefaults.standard.bool(forKey: Self.showCodexUsageDefaultsKey)
        } else {
            showCodexUsage = FileManager.default.fileExists(
                atPath: CodexRolloutDiscovery.defaultRootURL.path
            )
        }
        completionReplyEnabled = UserDefaults.standard.bool(forKey: Self.completionReplyEnabledDefaultsKey)
        islandAppearanceMode = IslandAppearanceMode(
            rawValue: UserDefaults.standard.string(forKey: Self.islandAppearanceModeDefaultsKey) ?? ""
        ) ?? .default
        islandClosedDisplayStyle = IslandClosedDisplayStyle(
            rawValue: UserDefaults.standard.string(forKey: Self.islandClosedDisplayStyleDefaultsKey) ?? ""
        ) ?? .detailed
        hideIdleIslandToEdge = UserDefaults.standard.bool(forKey: Self.islandHideIdleToEdgeDefaultsKey)
        islandPixelShapeStyle = IslandPixelShapeStyle(
            rawValue: UserDefaults.standard.string(forKey: Self.islandPixelShapeStyleDefaultsKey) ?? ""
        ) ?? .bars
        customAvatarImage = AvatarImageStore.currentImage()
        if let saved = UserDefaults.standard.dictionary(forKey: Self.islandStatusColorsDefaultsKey) as? [String: String] {
            var colors = Self.defaultStatusColors
            for (key, value) in saved {
                if let phase = SessionPhase(rawValue: key) {
                    colors[phase] = value.normalizedHexColorString
                }
            }
            statusColorHexes = colors
        }
        watchNotificationEnabled = UserDefaults.standard.bool(forKey: Self.watchNotificationEnabledKey)
        if watchNotificationEnabled {
            startWatchRelay()
        }

        overlay.appModel = self
        overlay.restoreDisplayPreference()
        overlay.onStatusMessage = { [weak self] message in
            self?.lastActionMessage = message
        }
        overlay.activeIslandCardSessionAccessor = { [weak self] in
            self?.activeIslandCardSession
        }
        overlay.isSoundMutedAccessor = { [weak self] in
            self?.isSoundMuted ?? false
        }
        overlay.ignoresPointerExitAccessor = { [weak self] in
            self?.ignoresPointerExitDuringHarness ?? false
        }

        hooks.onStatusMessage = { [weak self] message in
            self?.lastActionMessage = message
        }

        discovery.syntheticClaudeSessionPrefix = Self.syntheticClaudeSessionPrefix
        discovery.onStatusMessage = { [weak self] message in
            self?.lastActionMessage = message
        }
        discovery.stateAccessor = { [weak self] in self?.state ?? SessionState() }
        discovery.stateUpdater = { [weak self] in self?.state = $0 }
        discovery.onStateChanged = { [weak self] in
            self?.synchronizeSelection()
            self?.refreshOverlayPlacementIfVisible()
        }

        discovery.codexRolloutWatcher.eventHandler = { [weak self] event in
            Task { @MainActor [weak self] in
                self?.applyTrackedEvent(
                    event,
                    updateLastActionMessage: false,
                    ingress: .rollout
                )
            }
        }

        codexAppServer.onEvent = { [weak self] event in
            self?.applyTrackedEvent(event, ingress: .bridge)
        }
        codexAppServer.onStatusMessage = { [weak self] message in
            self?.lastActionMessage = message
        }
        codexAppServer.isSessionTracked = { [weak self] id in
            self?.state.session(id: id) != nil
        }

        monitoring.syntheticClaudeSessionPrefix = Self.syntheticClaudeSessionPrefix
        monitoring.stateAccessor = { [weak self] in self?.state ?? SessionState() }
        monitoring.stateUpdater = { [weak self] in self?.state = $0 }
        monitoring.onSessionsReconciled = { [weak self] in
            self?.synchronizeSelection()
            self?.refreshOverlayPlacementIfVisible()
        }
        monitoring.onPersistenceNeeded = { [weak self] in
            self?.discovery.scheduleCodexSessionPersistence()
            self?.discovery.scheduleClaudeSessionPersistence()
            self?.discovery.scheduleCursorSessionPersistence()
        }
        monitoring.onCodexAppRunningChanged = { [weak self] isRunning in
            guard let self else { return }
            if isRunning {
                self.codexAppServer.ensureConnected()
            } else {
                self.codexAppServer.disconnect()
            }
        }

        refreshOverlayDisplayConfiguration()
        hasFinishedInit = true
    }

    var sessions: [AgentSession] {
        state.sessions
    }

    var allSessions: [AgentSession] {
        state.sessions
    }

    /// Measured by SwiftUI GeometryReader in notification mode. Used by panel controller for sizing.
    /// Uses a tolerance of 2pt to avoid infinite layout loops caused by floating-point jitter
    /// in GeometryReader measurements across consecutive layout passes.
    var measuredNotificationContentHeight: CGFloat = 0 {
        didSet {
            let delta = abs(measuredNotificationContentHeight - oldValue)
            if delta >= 2, measuredNotificationContentHeight > 0 {
                overlay.refreshOverlayPlacementIfVisible()
            }
        }
    }

    var surfacedSessions: [AgentSession] {
        sessionBuckets.primary
    }

    var recentSessions: [AgentSession] {
        sessionBuckets.overflow
    }

    var islandListSessions: [AgentSession] {
        surfacedSessions
    }

    var recentSessionCount: Int {
        recentSessions.count
    }

    var liveSessionCount: Int {
        surfacedSessions.count
    }

    var liveAttentionCount: Int {
        surfacedSessions.filter { $0.phase.requiresAttention }.count
    }

    var liveRunningCount: Int {
        surfacedSessions.filter { $0.phase == .running }.count
    }

    var shouldShowSessionBootstrapPlaceholder: Bool {
        isResolvingInitialLiveSessions
            && liveSessionCount == 0
            && state.sessions.contains(where: \.isTrackedLiveSession)
    }

    var focusedSession: AgentSession? {
        state.session(id: selectedSessionID) ?? surfacedSessions.first ?? state.activeActionableSession ?? state.sessions.first
    }

    var activeIslandCardSession: AgentSession? {
        guard let sessionID = islandSurface.sessionID else {
            return nil
        }

        return state.session(id: sessionID)
    }

    var hasAnySession: Bool {
        !sessions.isEmpty
    }

    var hasCodexSession: Bool {
        sessions.contains(where: { $0.tool == .codex })
    }

    var hasJumpableSession: Bool {
        sessions.contains(where: { $0.jumpTarget != nil })
    }

    var acceptanceSteps: [AcceptanceStep] {
        [
            AcceptanceStep(
                id: "bridge",
                title: "Bridge ready",
                detail: "The app must own the local socket and register as a bridge observer.",
                isComplete: isBridgeReady
            ),
            AcceptanceStep(
                id: "hooks",
                title: "Codex hooks installed",
                detail: "Managed `hooks.json` entries should be present in `~/.codex`.",
                isComplete: hooks.codexHooksInstalled
            ),
            AcceptanceStep(
                id: "overlay",
                title: "Island visible",
                detail: "Show the overlay at least once so the notch/top-bar surface is visible.",
                isComplete: isOverlayVisible
            ),
            AcceptanceStep(
                id: "session",
                title: "A Codex session is observed",
                detail: "Start Codex in Terminal and wait for the first session row to appear.",
                isComplete: hasCodexSession
            ),
            AcceptanceStep(
                id: "jump",
                title: "Jump target captured",
                detail: "At least one session should include terminal jump metadata.",
                isComplete: hasJumpableSession
            ),
        ]
    }

    var acceptanceCompletedCount: Int {
        acceptanceSteps.filter(\.isComplete).count
    }

    var isReadyForFirstAcceptance: Bool {
        acceptanceSteps.prefix(3).allSatisfy(\.isComplete)
    }

    var hasPassedAcceptanceFlow: Bool {
        acceptanceSteps.allSatisfy(\.isComplete)
    }

    var acceptanceStatusTitle: String {
        if hasPassedAcceptanceFlow {
            return "v0.1 acceptance passed"
        }

        if isReadyForFirstAcceptance {
            return "Ready for v0.1 acceptance"
        }

        return "v0.1 acceptance not ready"
    }

    var acceptanceStatusSummary: String {
        if hasPassedAcceptanceFlow {
            return "The current build has completed the first-run checklist end to end."
        }

        if isReadyForFirstAcceptance {
            return "You can start your first acceptance run now. Launch Codex in Terminal and walk the last two steps."
        }

        return "Finish the setup steps in the left column, then start Codex from Terminal."
    }

    func startIfNeeded(
        startBridge: Bool = true,
        shouldPerformBootAnimation: Bool = true,
        loadRuntimeState: Bool = true
    ) {
        guard !hasStarted else {
            return
        }
        hasStarted = true

        if loadRuntimeState {
            isResolvingInitialLiveSessions = true

            Task.detached(priority: .userInitiated) { [weak self] in
                guard let self else { return }
                let payload = self.discovery.loadStartupDiscoveryPayload()
                await MainActor.run {
                    self.applyStartupDiscoveryPayload(payload)
                }
            }

            // These are already async or lightweight — safe to start immediately.
            hooks.refreshCodexHookStatus()
            hooks.refreshClaudeHookStatus()
            hooks.refreshCCForkHookStatuses()
            hooks.refreshOpenCodePluginStatus()
            hooks.refreshCursorHookStatus()
            hooks.refreshClaudeUsageState()
            hooks.startClaudeUsageMonitoringIfNeeded()
            if showCodexUsage {
                hooks.refreshCodexUsageState()
                hooks.startCodexUsageMonitoringIfNeeded()
            }
            updateChecker.startIfNeeded()

        } else {
            isResolvingInitialLiveSessions = false
        }
        refreshOverlayDisplayConfiguration()
        ensureOverlayPanel()
        if shouldPerformBootAnimation {
            performBootAnimation()
        }

        guard startBridge else {
            isBridgeReady = false
            lastActionMessage = loadRuntimeState
                ? "Harness mode active. Bridge startup skipped."
                : "Deterministic harness mode active. Runtime discovery and bridge startup skipped."
            harnessRuntimeMonitor?.recordMilestone("bridgeSkipped", message: lastActionMessage)
            return
        }

        do {
            try bridgeServer.start()
            connectBridgeObserver()
        } catch {
            isBridgeReady = false
            lastActionMessage = "Failed to start local bridge: \(error.localizedDescription)"
            harnessRuntimeMonitor?.recordMilestone("bridgeStartFailed", message: lastActionMessage)
        }
    }

    // MARK: - Bridge observer connection

    private static let bridgeReconnectDelay: Duration = .seconds(2)
    private static let bridgeMaxReconnectDelay: Duration = .seconds(30)

    private func connectBridgeObserver() {
        bridgeTask?.cancel()
        bridgeReconnectTask?.cancel()

        // Explicitly disconnect the old client so its DispatchSource is
        // cancelled deterministically rather than relying on dealloc timing.
        bridgeClient.disconnect()

        // Create a fresh client for each connection attempt so we don't
        // have to worry about stale file-descriptor state.
        let client = LocalBridgeClient()
        bridgeClient = client

        let stream: AsyncThrowingStream<AgentEvent, Error>
        do {
            stream = try client.connect()
        } catch {
            isBridgeReady = false
            lastActionMessage = "Failed to connect bridge observer: \(error.localizedDescription)"
            scheduleBridgeReconnect()
            return
        }

        // A single task handles both registration and event consumption so
        // there is no untracked task that could race with a reconnect.
        bridgeTask = Task { [weak self] in
            guard let self else { return }

            do {
                try await client.send(.registerClient(role: .observer))
                self.isBridgeReady = true
                self.lastActionMessage = "Bridge ready. Waiting for Claude and Codex hook events."
                self.harnessRuntimeMonitor?.recordMilestone("bridgeReady", message: self.lastActionMessage)
            } catch {
                guard !Task.isCancelled else { return }
                self.isBridgeReady = false
                self.lastActionMessage = "Failed to register bridge observer: \(error.localizedDescription)"
                self.harnessRuntimeMonitor?.recordMilestone(
                    "bridgeRegistrationFailed",
                    message: self.lastActionMessage
                )
                self.scheduleBridgeReconnect()
                return
            }

            do {
                for try await event in stream {
                    self.applyTrackedEvent(event)
                }
            } catch {}

            // Stream ended (server closed our connection or transient error).
            // Mark as disconnected and schedule reconnection.
            guard !Task.isCancelled else { return }
            self.isBridgeReady = false
            self.lastActionMessage = "Bridge observer disconnected. Reconnecting…"
            self.harnessRuntimeMonitor?.recordMilestone("bridgeDisconnected", message: self.lastActionMessage)
            self.scheduleBridgeReconnect()
        }
    }

    private func scheduleBridgeReconnect() {
        bridgeReconnectTask?.cancel()
        bridgeReconnectTask = Task { [weak self] in
            var delay = Self.bridgeReconnectDelay
            while !Task.isCancelled {
                try? await Task.sleep(for: delay)
                guard let self, !Task.isCancelled else { return }
                self.connectBridgeObserver()
                // If we're now connected, stop retrying.
                if self.isBridgeReady { return }
                delay = min(delay * 2, Self.bridgeMaxReconnectDelay)
            }
        }
    }

    func select(sessionID: String) {
        selectedSessionID = sessionID
    }

    // MARK: - Overlay forwarding

    func toggleOverlay() { overlay.toggleOverlay() }
    func notchOpen(reason: NotchOpenReason, surface: IslandSurface = .sessionList()) { overlay.notchOpen(reason: reason, surface: surface) }
    func notchClose() { overlay.notchClose() }
    func beginTopBarHoverDrag() { overlay.beginTopBarHoverDrag() }
    func notchPop() { overlay.notchPop() }
    func performBootAnimation() { overlay.performBootAnimation() }
    func ensureOverlayPanel() { overlay.ensureOverlayPanel() }
    func showOverlay() { overlay.showOverlay() }
    func hideOverlay() { overlay.hideOverlay() }
    func expandNotificationToSessionList(clearExpansion: Bool = false) {
        overlay.expandNotificationToSessionList(clearExpansion: clearExpansion)
    }
    func refreshOverlayDisplayConfiguration() { overlay.refreshOverlayDisplayConfiguration() }
    func refreshOverlayPlacement() { overlay.refreshOverlayPlacement() }
    private func refreshOverlayPlacementIfVisible() { overlay.refreshOverlayPlacementIfVisible() }
    func notePointerInsideIslandSurface() { overlay.notePointerInsideIslandSurface() }
    func handlePointerExitedIslandSurface() { overlay.handlePointerExitedIslandSurface() }
    private func presentNotificationSurface(_ surface: IslandSurface) { overlay.presentNotificationSurface(surface) }
    private func reconcileIslandSurfaceAfterStateChange() { overlay.reconcileIslandSurfaceAfterStateChange() }
    private func dismissNotificationSurfaceIfPresent(for sessionID: String) { overlay.dismissNotificationSurfaceIfPresent(for: sessionID) }
    private func dismissOverlayForJump() { overlay.dismissOverlayForJump() }

    var shouldAutoCollapseOnMouseLeave: Bool { overlay.shouldAutoCollapseOnMouseLeave }
    var autoCollapseOnMouseLeaveRequiresPriorSurfaceEntry: Bool { overlay.autoCollapseOnMouseLeaveRequiresPriorSurfaceEntry }
    var showsNotificationCard: Bool { overlay.showsNotificationCard }

    func loadDebugSnapshot(
        _ snapshot: IslandDebugSnapshot,
        presentOverlay: Bool = false,
        autoCollapseNotificationCards: Bool = false
    ) {
        state = SessionState(sessions: snapshot.sessions)
        selectedSessionID = snapshot.selectedSessionID ?? snapshot.sessions.first?.id
        lastActionMessage = "Loaded debug scenario: \(snapshot.title)."
        harnessRuntimeMonitor?.recordMilestone("scenarioLoaded", message: snapshot.title)

        overlay.applyOverlayState(from: snapshot, presentOverlay: presentOverlay, autoCollapseNotificationCards: autoCollapseNotificationCards)
    }

    func showSettings() {
        openSettingsWindow?()
        if let window = NSApp.windows.first(where: { $0.title == "Open Island Settings" }) {
            window.orderFrontRegardless()
            window.makeKey()
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Opens Settings on the Setup tab so the user can install hooks.
    /// Used by every "Set up agents" CTA in the empty-state UI. A
    /// dedicated first-run onboarding window will replace this in a
    /// later PR; until then this is the canonical entry point.
    func showOnboarding() {
        showSettings()
        NotificationCenter.default.post(name: .openIslandSelectSetupTab, object: nil)
    }

    func showControlCenter() {
        guard let window = NSApp.windows.first(where: { $0.title == "Open Island Debug" }) else {
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        window.orderFrontRegardless()
        window.makeKey()
        NSApp.activate(ignoringOtherApps: true)
    }

    func hideControlCenter() {
        guard let window = NSApp.windows.first(where: { $0.title == "Open Island Debug" }) else {
            return
        }

        window.orderOut(nil)
    }

    func toggleSoundMuted() {
        isSoundMuted.toggle()
    }

    func approveFocusedPermission(_ approved: Bool) {
        guard let session = focusedSession else {
            return
        }

        send(
            .resolvePermission(sessionID: session.id, resolution: permissionResolution(for: approved)),
            userMessage: approved
                ? "Approving permission for \(session.title)."
                : "Denying permission for \(session.title)."
        )
    }

    func answerFocusedQuestion(_ answer: String) {
        guard let session = focusedSession else {
            return
        }

        send(
            .answerQuestion(sessionID: session.id, response: QuestionPromptResponse(answer: answer)),
            userMessage: "Sending answer \"\(answer)\" for \(session.title)."
        )
    }

    func jumpToFocusedSession() {
        jump(to: focusedSession?.jumpTarget)
    }

    func jumpToSession(_ session: AgentSession) {
        guard let jumpTarget = session.jumpTarget,
              jumpTarget.terminalApp.lowercased() != "unknown" else {
            lastActionMessage = "Cannot jump: terminal app is unknown."
            return
        }
        jump(to: jumpTarget)
    }

    private func jump(to jumpTarget: JumpTarget?) {
        guard let jumpTarget else {
            lastActionMessage = "No jump target is available yet."
            return
        }

        let shouldDelayForDismissAnimation = isOverlayVisible
        let jumpAction = terminalJumpAction

        dismissOverlayForJump()
        jumpTask?.cancel()
        jumpTask = Task { [weak self] in
            if shouldDelayForDismissAnimation {
                try? await Task.sleep(for: Self.jumpOverlayDismissLeadTime)
            }

            do {
                let result = try await Task.detached(priority: .userInitiated) {
                    try jumpAction(jumpTarget)
                }.value

                guard !Task.isCancelled else {
                    return
                }

                self?.lastActionMessage = result
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled else {
                    return
                }

                self?.lastActionMessage = "Jump failed: \(error.localizedDescription)"
            }
        }
    }

    func approvePermission(for sessionID: String, approved: Bool) {
        guard let session = state.session(id: sessionID) else {
            return
        }

        let resolution = permissionResolution(for: approved)
        dismissNotificationSurfaceIfPresent(for: sessionID)
        state.resolvePermission(sessionID: session.id, resolution: resolution)
        synchronizeSelection()
        refreshOverlayPlacementIfVisible()

        send(
            .resolvePermission(sessionID: session.id, resolution: resolution),
            userMessage: approved
                ? "Approving permission for \(session.title)."
                : "Denying permission for \(session.title)."
        )
    }

    func approvePermission(for sessionID: String, action: ApprovalAction) {
        guard let session = state.session(id: sessionID) else {
            return
        }

        let resolution: PermissionResolution
        let message: String

        switch action {
        case .deny:
            resolution = .deny(message: "Permission denied in Open Island.", interrupt: false)
            message = "Denying permission for \(session.title)."
        case .allowOnce:
            resolution = .allowOnce()
            message = "Approving permission for \(session.title)."
        case let .allowWithUpdates(updates):
            resolution = .allowOnce(updatedPermissions: updates)
            message = "Always allowing for \(session.title)."
        }

        dismissNotificationSurfaceIfPresent(for: sessionID)
        state.resolvePermission(sessionID: session.id, resolution: resolution)
        synchronizeSelection()
        refreshOverlayPlacementIfVisible()

        send(
            .resolvePermission(sessionID: session.id, resolution: resolution),
            userMessage: message
        )
    }

    func dismissSession(_ sessionID: String) {
        state.dismissSession(id: sessionID)
        dismissNotificationSurfaceIfPresent(for: sessionID)
        synchronizeSelection()
    }

    func answerQuestion(for sessionID: String, answer: QuestionPromptResponse) {
        guard let session = state.session(id: sessionID) else {
            return
        }

        dismissNotificationSurfaceIfPresent(for: sessionID)
        state.answerQuestion(sessionID: session.id, response: answer)
        synchronizeSelection()
        refreshOverlayPlacementIfVisible()

        send(
            .answerQuestion(sessionID: session.id, response: answer),
            userMessage: "Sending answer for \(session.title)."
        )
    }

    func replyToSession(_ session: AgentSession, text: String) {
        dismissNotificationSurfaceIfPresent(for: session.id)
        synchronizeSelection()
        refreshOverlayPlacementIfVisible()

        lastActionMessage = "Sending reply to \(session.title)…"

        Task { [weak self] in
            let success = await Task.detached(priority: .userInitiated) {
                TerminalTextSender.send(text, to: session)
            }.value

            self?.lastActionMessage = success
                ? "Sent reply to \(session.title)."
                : "Failed to send reply to \(session.title)."
        }
    }


    private func send(_ command: BridgeCommand, userMessage: String) {
        lastActionMessage = userMessage

        Task { [weak self] in
            guard let self else {
                return
            }

            do {
                try await self.bridgeClient.send(command)
            } catch {
                self.lastActionMessage = "Failed to send bridge command: \(error.localizedDescription)"
            }
        }
    }

    private func permissionResolution(for approved: Bool) -> PermissionResolution {
        if approved {
            return .allowOnce()
        }

        return .deny(message: "Permission denied in Open Island.", interrupt: false)
    }

    func applyTrackedEvent(
        _ event: AgentEvent,
        updateLastActionMessage: Bool = true,
        ingress: TrackedEventIngress = .bridge
    ) {
        // Snapshot whether this session was already completed before applying
        // the event. Used to suppress duplicate/stale completion notifications
        // (e.g. rollout watcher re-discovering an old completion on startup,
        // or producing a duplicate sessionCompleted that races with the bridge).
        let wasAlreadyCompleted: Bool = {
            guard case let .sessionCompleted(payload) = event else { return false }
            return state.session(id: payload.sessionID)?.phase == .completed
        }()

        // Guard: don't let rollout events downgrade a session from completed
        // back to running. The bridge's sessionCompleted is authoritative; the
        // rollout watcher may have read the JSONL before task_complete was
        // flushed, producing a stale activityUpdated(phase: .running).
        if ingress == .rollout,
           case let .activityUpdated(payload) = event,
           payload.phase == .running,
           state.session(id: payload.sessionID)?.phase == .completed {
            return
        }

        state.apply(event)
        reconcileIslandSurfaceAfterStateChange()
        if ingress == .bridge {
            monitoring.markSessionAttached(for: event)
            monitoring.markSessionProcessAlive(for: event)
        }
        synchronizeSelection()
        discovery.refreshCodexRolloutTracking()
        refreshOverlayPlacementIfVisible()
        discovery.scheduleCodexSessionPersistence()
        discovery.scheduleClaudeSessionPersistence()
        discovery.scheduleCursorSessionPersistence()

        // Push relevant events to the Watch/iPhone via the relay
        if let relay = watchRelay {
            let eventSessionID: String? = {
                switch event {
                case let .sessionStarted(p): return p.sessionID
                case let .activityUpdated(p): return p.sessionID
                case let .permissionRequested(p): return p.sessionID
                case let .questionAsked(p): return p.sessionID
                case let .sessionCompleted(p): return p.sessionID
                case let .jumpTargetUpdated(p): return p.sessionID
                case let .sessionMetadataUpdated(p): return p.sessionID
                case let .claudeSessionMetadataUpdated(p): return p.sessionID
                case let .geminiSessionMetadataUpdated(p): return p.sessionID
                case let .openCodeSessionMetadataUpdated(p): return p.sessionID
                case let .cursorSessionMetadataUpdated(p): return p.sessionID
                case let .actionableStateResolved(p): return p.sessionID
                }
            }()
            let session = eventSessionID.flatMap { state.session(id: $0) }
            relay.notifyEvent(event, session: session)
        }

        if updateLastActionMessage {
            lastActionMessage = describe(event)
        }

        if let surface = IslandSurface.notificationSurface(for: event) {
            scheduleNotificationSurfacePresentationIfNeeded(
                surface,
                wasAlreadyCompleted: wasAlreadyCompleted,
                ingress: ingress
            )
        }
    }

    private func scheduleNotificationSurfacePresentationIfNeeded(
        _ surface: IslandSurface,
        wasAlreadyCompleted: Bool,
        ingress: TrackedEventIngress
    ) {
        guard !wasAlreadyCompleted,
              notificationSurfaceIsEligibleForPresentation(surface, ingress: ingress),
              let sessionID = surface.sessionID,
              let session = state.session(id: sessionID) else {
            return
        }

        guard suppressFrontmostNotifications else {
            presentNotificationSurface(surface)
            return
        }

        notificationPresentationTask?.cancel()
        notificationPresentationTask = Task { @MainActor [weak self] in
            guard let self else {
                return
            }

            let shouldSuppress = await self.isNotificationSessionAlreadyFrontmost(session)
            guard !Task.isCancelled,
                  !shouldSuppress,
                  self.notificationSurfaceIsEligibleForPresentation(surface, ingress: ingress) else {
                return
            }

            self.presentNotificationSurface(surface)
        }
    }

    private func notificationSurfaceIsEligibleForPresentation(
        _ surface: IslandSurface,
        ingress: TrackedEventIngress
    ) -> Bool {
        guard let sessionID = surface.sessionID,
              let session = state.session(id: sessionID) else {
            return false
        }

        return (ingress == .bridge || !isResolvingInitialLiveSessions)
            && (notchStatus == .closed || notchOpenReason == .notification)
            && surface.matchesCurrentState(of: session)
    }

    private func synchronizeSelection() {
        let surfacedIDs = Set(surfacedSessions.map(\.id))

        if let activeAction = state.activeActionableSession {
            selectedSessionID = activeAction.id
            return
        }

        guard let selectedSessionID,
              surfacedIDs.contains(selectedSessionID),
              state.session(id: selectedSessionID) != nil else {
            self.selectedSessionID = surfacedSessions.first?.id ?? state.sessions.first?.id
            return
        }
    }

    /// Applies startup discovery results on the main thread after background I/O completes.
    private func applyStartupDiscoveryPayload(_ payload: SessionDiscoveryCoordinator.StartupDiscoveryPayload) {
        discovery.applyStartupDiscoveryPayload(payload)

        // Apply hooks binary URL and update the installed copy if the app ships a newer version.
        hooks.hooksBinaryURL = payload.hooksBinaryURL
        hooks.updateHooksBinaryIfNeeded()

        // Auto-install missing hooks and usage bridge, then run health checks.
        if payload.hooksBinaryURL != nil {
            Task { @MainActor [weak self] in
                guard let self else { return }

                // Wait for all status reads to complete before checking install state.
                await self.hooks.refreshAllHookStatusAndWait()

                // Reconcile persisted intent with what is actually on disk. For
                // legacy users this records existing hooks as `.installed` and
                // marks first-launch as complete so onboarding does not appear
                // on upgrade. Must run after status reads and before any
                // install decision.
                self.hooks.migrateIntentStoreIfNeeded()

                // Install only hooks the user has not explicitly opted out of.
                // `shouldAutoInstall` skips `.uninstalled` agents and agents
                // whose hooks are already present — it is the single checkpoint
                // that fixes #324.
                if self.hooks.shouldAutoInstall(.claudeCode) { self.installClaudeHooks() }
                if self.hooks.shouldAutoInstall(.codex) { self.installCodexHooks() }
                if self.hooks.shouldAutoInstall(.qoder) { self.installQoderHooks() }
                if self.hooks.shouldAutoInstall(.qwenCode) { self.installQwenCodeHooks() }
                if self.hooks.shouldAutoInstall(.factory) { self.installFactoryHooks() }
                if self.hooks.shouldAutoInstall(.codebuddy) { self.installCodebuddyHooks() }
                if self.hooks.shouldAutoInstall(.openCode) { self.installOpenCodePlugin() }
                if self.hooks.shouldAutoInstall(.cursor) { self.installCursorHooks() }
                if self.hooks.shouldAutoInstall(.gemini) { self.installGeminiHooks() }
                if self.hooks.shouldAutoInstall(.kimi) { self.installKimiHooks() }
                if self.hooks.shouldAutoInstall(.claudeUsageBridge) { self.installClaudeUsageBridge() }

                // Run health checks after install to detect stale paths, conflicts, etc.
                try? await Task.sleep(for: .milliseconds(500))
                await self.hooks.repairHooksIfNeeded()
            }
        }

        // Reconcile attachments and start monitoring (requires sessions to be loaded).
        monitoring.reconcileSessionAttachments()
        monitoring.startMonitoringIfNeeded()
    }


    private var sessionBuckets: (primary: [AgentSession], overflow: [AgentSession]) {
        if let cached = _cachedSessionBuckets {
            return cached
        }
        let result = computeSessionBuckets()
        _cachedSessionBuckets = result
        return result
    }

    private func computeSessionBuckets() -> (primary: [AgentSession], overflow: [AgentSession]) {
        let now = Date.now
        let rankedSessions = state.sessions.sorted { lhs, rhs in
            let lhsScore = displayPriority(for: lhs, now: now)
            let rhsScore = displayPriority(for: rhs, now: now)

            if lhsScore == rhsScore {
                if lhs.islandActivityDate == rhs.islandActivityDate {
                    return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
                }

                return lhs.islandActivityDate > rhs.islandActivityDate
            }

            return lhsScore > rhsScore
        }

        var primary: [AgentSession] = []
        var claimedLiveAttachmentKeys: Set<String> = []

        for session in rankedSessions where session.isVisibleInIsland {
            guard !session.isSubagentSession else { continue }

            if let liveAttachmentKey = monitoring.liveAttachmentKey(for: session) {
                guard claimedLiveAttachmentKeys.insert(liveAttachmentKey).inserted else {
                    continue
                }
            }

            primary.append(session)
        }

        let primaryIDs = Set(primary.map(\.id))
        let overflow = rankedSessions.filter { !primaryIDs.contains($0.id) && !$0.isSubagentSession }
        return (primary, overflow)
    }

    private func displayPriority(for session: AgentSession, now: Date) -> Int {
        var score = 0

        let presence = session.islandPresence(at: now)

        if session.isProcessAlive {
            score += presence == .inactive ? 3_000 : 12_000
        } else if session.isDemoSession || session.phase.requiresAttention {
            score += 6_000
        }

        if session.phase.requiresAttention {
            score += 10_000
        }

        if session.currentToolName?.isEmpty == false {
            score += 6_000
        }

        if session.jumpTarget != nil {
            score += 4_000
        }

        switch session.phase {
        case .running:
            score += 2_000
        case .waitingForApproval:
            score += 1_500
        case .waitingForAnswer:
            score += 1_200
        case .completed:
            score += 600
        }

        let age = now.timeIntervalSince(session.islandActivityDate)
        switch age {
        case ..<120:
            score += 500
        case ..<900:
            score += 250
        case ..<3_600:
            score += 120
        case ..<21_600:
            score += 40
        default:
            break
        }

        return score
    }

    private func describe(_ event: AgentEvent) -> String {
        switch event {
        case let .sessionStarted(payload):
            return "Session started: \(payload.title)"
        case let .activityUpdated(payload):
            return payload.summary
        case let .permissionRequested(payload):
            return payload.request.summary
        case let .questionAsked(payload):
            return payload.prompt.title
        case let .sessionCompleted(payload):
            return payload.summary
        case let .jumpTargetUpdated(payload):
            return "Jump target updated to \(payload.jumpTarget.terminalApp)."
        case let .sessionMetadataUpdated(payload):
            if let currentTool = payload.codexMetadata.currentTool {
                return "Codex is running \(currentTool)."
            }

            return payload.codexMetadata.lastAssistantMessage ?? "Codex session metadata updated."
        case let .claudeSessionMetadataUpdated(payload):
            if let currentTool = payload.claudeMetadata.currentTool {
                return "Claude is running \(currentTool)."
            }

            return payload.claudeMetadata.lastAssistantMessage ?? "Claude session metadata updated."
        case let .geminiSessionMetadataUpdated(payload):
            return payload.geminiMetadata.lastAssistantMessage ?? "Gemini session metadata updated."
        case let .openCodeSessionMetadataUpdated(payload):
            if let currentTool = payload.openCodeMetadata.currentTool {
                return "OpenCode is running \(currentTool)."
            }

            return payload.openCodeMetadata.lastAssistantMessage ?? "OpenCode session metadata updated."
        case let .cursorSessionMetadataUpdated(payload):
            if let currentTool = payload.cursorMetadata.currentTool {
                return "Cursor is running \(currentTool)."
            }

            return payload.cursorMetadata.lastAssistantMessage ?? "Cursor session metadata updated."
        case let .actionableStateResolved(payload):
            return "Actionable state resolved for session \(payload.sessionID)."
        }
    }

    func quitApplication() {
        NSApplication.shared.terminate(nil)
    }

}

// MARK: - Hex color helpers

extension String {
    var normalizedHexColorString: String {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        let raw = trimmed.hasPrefix("#") ? String(trimmed.dropFirst()) : trimmed
        guard raw.count == 6, raw.allSatisfy(\.isHexDigit) else { return "#6E9FFF" }
        return "#\(raw.uppercased())"
    }
}

extension Color {
    init?(hex: String) {
        let raw = String(hex.normalizedHexColorString.dropFirst())
        guard let value = Int(raw, radix: 16) else { return nil }
        let red = Double((value >> 16) & 0xFF) / 255
        let green = Double((value >> 8) & 0xFF) / 255
        let blue = Double(value & 0xFF) / 255
        self = Color(red: red, green: green, blue: blue)
    }

    var opaqueHexString: String? {
        guard let nsColor = NSColor(self).usingColorSpace(.deviceRGB) else { return nil }
        let r = Int(round(nsColor.redComponent * 255))
        let g = Int(round(nsColor.greenComponent * 255))
        let b = Int(round(nsColor.blueComponent * 255))
        return String(format: "#%02X%02X%02X", r, g, b)
    }
}
