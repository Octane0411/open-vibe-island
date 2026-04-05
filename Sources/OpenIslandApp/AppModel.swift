import AppKit
import Foundation
import Observation
import OpenIslandCore
import SwiftUI

enum NotchStatus: Equatable {
    case closed
    case opened
    case popping
}

enum NotchOpenReason: Equatable {
    case click
    case hover
    case notification
    case boot
}

enum TrackedEventIngress {
    case bridge
    case rollout
}

@MainActor
@Observable
final class AppModel {
    private static let overlayDisplayPreferenceDefaultsKey = "overlay.display.preference"
    private static let soundMutedDefaultsKey = "overlay.sound.muted"
    private static let syntheticClaudeSessionPrefix = "claude-process:"
    private static let liveSessionStalenessWindow: TimeInterval = 15 * 60
    private static let notificationSurfaceAutoCollapseDelay: TimeInterval = 10
    private static let jumpOverlayDismissLeadTime: Duration = .milliseconds(20)
    static let hoverOpenDelay: TimeInterval = 0.7
    typealias ActiveProcessSnapshot = ActiveAgentProcessDiscovery.ProcessSnapshot

    struct AcceptanceStep: Identifiable {
        let id: String
        let title: String
        let detail: String
        let isComplete: Bool
    }

    var state = SessionState() {
        didSet { _cachedSessionBuckets = nil }
    }
    @ObservationIgnored private var _cachedSessionBuckets: (primary: [AgentSession], overflow: [AgentSession])?
    var selectedSessionID: String?
    var notchStatus: NotchStatus = .closed
    var notchOpenReason: NotchOpenReason?
    var islandSurface: IslandSurface = .sessionList
    var isOverlayVisible: Bool { notchStatus != .closed }
    var isCodexSetupBusy = false
    var isClaudeHookSetupBusy = false
    var isClaudeUsageSetupBusy = false
    var isBridgeReady = false
    var lastActionMessage = "Waiting for agent hook events..." {
        didSet {
            guard lastActionMessage != oldValue else {
                return
            }

            harnessRuntimeMonitor?.recordLog(lastActionMessage)
        }
    }
    var codexHookStatus: CodexHookInstallationStatus?
    var claudeHookStatus: ClaudeHookInstallationStatus?
    var claudeStatusLineStatus: ClaudeStatusLineInstallationStatus?
    var claudeUsageSnapshot: ClaudeUsageSnapshot?
    var codexUsageSnapshot: CodexUsageSnapshot?
    var hooksBinaryURL: URL?
    var isResolvingInitialLiveSessions = false
    var overlayDisplayOptions: [OverlayDisplayOption] = []
    var overlayPlacementDiagnostics: OverlayPlacementDiagnostics?
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
    var overlayDisplaySelectionID = OverlayDisplayOption.automaticID {
        didSet {
            guard overlayDisplaySelectionID != oldValue else {
                return
            }

            persistOverlayDisplayPreference()
            refreshOverlayPlacement()
        }
    }
    @ObservationIgnored
    var openSettingsWindow: (() -> Void)?

    var ignoresPointerExitDuringHarness = false
    var disablesOverlayEventMonitoringDuringHarness = false

    @ObservationIgnored
    private var overlayTransitionGeneration: UInt64 = 0

    @ObservationIgnored
    private var bridgeTask: Task<Void, Never>?

    @ObservationIgnored
    private var hasStarted = false

    @ObservationIgnored
    private let overlayPanelController = OverlayPanelController()

    @ObservationIgnored
    private let bridgeServer = DemoBridgeServer()

    @ObservationIgnored
    private let bridgeClient = LocalBridgeClient()

    @ObservationIgnored
    private let codexHookInstallationManager = CodexHookInstallationManager()

    @ObservationIgnored
    private let claudeHookInstallationManager = ClaudeHookInstallationManager()

    @ObservationIgnored
    private let claudeStatusLineInstallationManager = ClaudeStatusLineInstallationManager()

    @ObservationIgnored
    private let terminalJumpAction: @Sendable (JumpTarget) throws -> String

    @ObservationIgnored
    private let codexSessionStore = CodexSessionStore()

    @ObservationIgnored
    private let claudeSessionRegistry = ClaudeSessionRegistry()

    @ObservationIgnored
    private let codexRolloutWatcher = CodexRolloutWatcher()

    @ObservationIgnored
    private let codexRolloutDiscovery = CodexRolloutDiscovery()

    @ObservationIgnored
    private let claudeTranscriptDiscovery = ClaudeTranscriptDiscovery()

    @ObservationIgnored
    private let terminalSessionAttachmentProbe = TerminalSessionAttachmentProbe()

    @ObservationIgnored
    private let terminalJumpTargetResolver = TerminalJumpTargetResolver()

    @ObservationIgnored
    var harnessRuntimeMonitor: HarnessRuntimeMonitor?

    @ObservationIgnored
    private let activeAgentProcessDiscovery = ActiveAgentProcessDiscovery()

    @ObservationIgnored
    private var codexSessionPersistenceTask: Task<Void, Never>?

    @ObservationIgnored
    private var claudeSessionPersistenceTask: Task<Void, Never>?

    @ObservationIgnored
    private var sessionAttachmentMonitorTask: Task<Void, Never>?

    @ObservationIgnored
    private var claudeUsageMonitorTask: Task<Void, Never>?

    @ObservationIgnored
    private var notificationAutoCollapseTask: Task<Void, Never>?

    @ObservationIgnored
    private var autoCollapseSurfaceHasBeenEntered = false

    @ObservationIgnored
    private var codexUsageMonitorTask: Task<Void, Never>?

    @ObservationIgnored
    private var jumpTask: Task<Void, Never>?

    init(
        terminalJumpAction: @escaping @Sendable (JumpTarget) throws -> String = { target in
            try TerminalJumpService().jump(to: target)
        }
    ) {
        self.terminalJumpAction = terminalJumpAction
        overlayDisplaySelectionID = UserDefaults.standard.string(
            forKey: Self.overlayDisplayPreferenceDefaultsKey
        ) ?? OverlayDisplayOption.automaticID
        isSoundMuted = UserDefaults.standard.bool(forKey: Self.soundMutedDefaultsKey)
        selectedSoundName = NotificationSoundService.selectedSoundName

        codexRolloutWatcher.eventHandler = { [weak self] event in
            Task { @MainActor [weak self] in
                self?.applyTrackedEvent(
                    event,
                    updateLastActionMessage: false,
                    ingress: .rollout
                )
            }
        }

        refreshOverlayDisplayConfiguration()
    }

    var sessions: [AgentSession] {
        state.sessions
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

    var codexHooksInstalled: Bool {
        codexHookStatus?.managedHooksPresent == true
    }

    var claudeHooksInstalled: Bool {
        claudeHookStatus?.managedHooksPresent == true
    }

    var claudeUsageInstalled: Bool {
        claudeStatusLineStatus?.managedStatusLineInstalled == true
    }

    var claudeHookStatusTitle: String {
        if claudeHooksInstalled {
            return "Claude hooks installed"
        }

        if hooksBinaryURL == nil {
            return "Hook binary not found"
        }

        return "Claude hooks not installed"
    }

    var claudeHookStatusSummary: String {
        guard let status = claudeHookStatus else {
            return "Reading ~/.claude/settings.json."
        }

        if claudeHooksInstalled {
            if status.hasClaudeIslandHooks {
                return "managed hooks present · claude-island hooks also detected"
            }
            return "managed hooks present"
        }

        if hooksBinaryURL == nil {
            return "Build OpenIslandHooks before installing."
        }

        if status.hasClaudeIslandHooks {
            return "claude-island hooks detected · managed hooks absent"
        }

        return "no managed Claude hooks"
    }

    var claudeUsageStatusTitle: String {
        guard let status = claudeStatusLineStatus else {
            return "Claude usage status unavailable"
        }

        if status.managedStatusLineInstalled {
            return "Claude usage bridge installed"
        }

        if status.managedStatusLineNeedsRepair {
            return "Claude usage bridge needs repair"
        }

        if status.hasConflictingStatusLine {
            return "Custom Claude status line detected"
        }

        return "Claude usage bridge not installed"
    }

    var claudeUsageStatusSummary: String {
        guard let status = claudeStatusLineStatus else {
            return "Reading ~/.claude/settings.json."
        }

        if status.managedStatusLineInstalled {
            if let summary = claudeUsageSummaryText {
                return "Caching rate limits from Claude Code · \(summary)"
            }
            return "Caching rate limits from Claude Code into \(status.cacheURL.path)."
        }

        if status.managedStatusLineNeedsRepair {
            return "Open Island detected a missing managed Claude status line script and will repair it automatically."
        }

        if status.hasConflictingStatusLine {
            return "Open Island will not overwrite an existing Claude status line automatically."
        }

        return "Install a managed Claude status line to cache 5h and 7d usage locally."
    }

    var claudeUsageSummaryText: String? {
        guard let snapshot = claudeUsageSnapshot else {
            return nil
        }

        var components: [String] = []
        if let fiveHour = snapshot.fiveHour {
            components.append("5h \(fiveHour.roundedUsedPercentage)%")
        }
        if let sevenDay = snapshot.sevenDay {
            components.append("7d \(sevenDay.roundedUsedPercentage)%")
        }
        if let cachedAt = snapshot.cachedAt {
            components.append("updated \(relativeTimestampFormatter.localizedString(for: cachedAt, relativeTo: .now))")
        }
        return components.isEmpty ? nil : components.joined(separator: " · ")
    }

    var codexUsageStatusTitle: String {
        if codexUsageSnapshot?.isEmpty == false {
            return "Codex rate limits detected"
        }

        return "Waiting for Codex rate limits"
    }

    var codexUsageStatusSummary: String {
        if let summary = codexUsageSummaryText {
            return "Reading the latest local rollout token_count snapshots · \(summary)"
        }

        return "Passively reading ~/.codex/sessions/**/rollout-*.jsonl and extracting token_count.rate_limits."
    }

    var codexUsageSummaryText: String? {
        guard let snapshot = codexUsageSnapshot else {
            return nil
        }

        var components = snapshot.windows.map { window in
            "\(window.label) \(window.roundedUsedPercentage)%"
        }

        if let planType = snapshot.planType {
            components.append("plan \(planType)")
        }

        if let capturedAt = snapshot.capturedAt {
            components.append("updated \(relativeTimestampFormatter.localizedString(for: capturedAt, relativeTo: .now))")
        }

        return components.isEmpty ? nil : components.joined(separator: " · ")
    }

    var codexHookStatusTitle: String {
        if codexHooksInstalled {
            return "Codex hooks installed"
        }

        if hooksBinaryURL == nil {
            return "Hook binary not found"
        }

        return "Codex hooks not installed"
    }

    var codexHookStatusSummary: String {
        guard let status = codexHookStatus else {
            return "Reading ~/.codex state."
        }

        if codexHooksInstalled {
            let featureText = status.featureFlagEnabled ? "feature on" : "feature off"
            return "\(featureText) · managed hooks present"
        }

        if hooksBinaryURL == nil {
            return "Build OpenIslandHooks before installing."
        }

        return status.featureFlagEnabled ? "feature on · no managed hooks" : "feature off · no managed hooks"
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

    var showsNotificationCard: Bool {
        islandSurface.isNotificationCard
    }

    var shouldAutoCollapseOnMouseLeave: Bool {
        if ignoresPointerExitDuringHarness {
            return false
        }

        guard notchStatus == .opened else {
            return false
        }

        if notchOpenReason == .hover && islandSurface == .sessionList {
            return true
        }

        return notchOpenReason == .notification
            && islandSurface.autoDismissesWhenPresentedAsNotification
    }

    private var autoCollapseOnMouseLeaveRequiresPriorSurfaceEntry: Bool {
        notchOpenReason == .notification
            && islandSurface.autoDismissesWhenPresentedAsNotification
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
                isComplete: codexHooksInstalled
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

    /// Raw I/O results collected off the main thread during startup.
    private struct StartupDiscoveryPayload: Sendable {
        var codexRecords: [CodexTrackedSessionRecord]
        var codexRecordsNeedPrune: Bool
        var claudeRecords: [ClaudeTrackedSessionRecord]
        var claudeRecordsNeedPrune: Bool
        var discoveredCodexRecords: [CodexTrackedSessionRecord]
        var discoveredClaudeSessions: [AgentSession]
        var hooksBinaryURL: URL?
    }

    /// Performs all startup file I/O off the main thread and returns the raw results.
    nonisolated private func loadStartupDiscoveryPayload() -> StartupDiscoveryPayload {
        let cutoff = Date.now.addingTimeInterval(-86_400)

        let allCodex = (try? codexSessionStore.load()) ?? []
        let codexRecords = allCodex.filter { $0.updatedAt >= cutoff && $0.shouldRestoreToLiveState }

        let allClaude = (try? claudeSessionRegistry.load()) ?? []
        let claudeRecords = allClaude.filter { $0.updatedAt >= cutoff && $0.shouldRestoreToLiveState }

        let discoveredCodex = codexRolloutDiscovery.discoverRecentSessions()
        let discoveredClaude = claudeTranscriptDiscovery.discoverRecentSessions()

        return StartupDiscoveryPayload(
            codexRecords: codexRecords,
            codexRecordsNeedPrune: codexRecords != allCodex,
            claudeRecords: claudeRecords,
            claudeRecordsNeedPrune: claudeRecords != allClaude,
            discoveredCodexRecords: discoveredCodex,
            discoveredClaudeSessions: discoveredClaude,
            hooksBinaryURL: HooksBinaryLocator.locate()
        )
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
                let payload = self.loadStartupDiscoveryPayload()
                await MainActor.run {
                    self.applyStartupDiscoveryPayload(payload)
                }
            }

            // These are already async or lightweight — safe to start immediately.
            refreshCodexHookStatus()
            refreshClaudeHookStatus()
            refreshClaudeUsageState()
            startClaudeUsageMonitoringIfNeeded()
            refreshCodexUsageState()
            startCodexUsageMonitoringIfNeeded()
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
            let stream = try bridgeClient.connect()

            Task { [weak self] in
                guard let self else {
                    return
                }

                do {
                    try await self.bridgeClient.send(.registerClient(role: .observer))
                    self.isBridgeReady = true
                    self.lastActionMessage = "Bridge ready. Waiting for Claude and Codex hook events."
                    self.harnessRuntimeMonitor?.recordMilestone("bridgeReady", message: self.lastActionMessage)
                } catch {
                    self.isBridgeReady = false
                    self.lastActionMessage = "Failed to register bridge observer: \(error.localizedDescription)"
                    self.harnessRuntimeMonitor?.recordMilestone(
                        "bridgeRegistrationFailed",
                        message: self.lastActionMessage
                    )
                }
            }

            bridgeTask = Task { [weak self] in
                guard let self else {
                    return
                }

                do {
                    for try await event in stream {
                        self.applyTrackedEvent(event)
                    }
                } catch {
                    self.isBridgeReady = false
                    self.lastActionMessage = "Bridge disconnected: \(error.localizedDescription)"
                    self.harnessRuntimeMonitor?.recordMilestone("bridgeDisconnected", message: self.lastActionMessage)
                }
            }
        } catch {
            isBridgeReady = false
            lastActionMessage = "Failed to start local bridge: \(error.localizedDescription)"
            harnessRuntimeMonitor?.recordMilestone("bridgeStartFailed", message: lastActionMessage)
        }
    }

    func select(sessionID: String) {
        selectedSessionID = sessionID
    }

    func toggleOverlay() {
        if notchStatus == .closed {
            notchOpen(reason: .click)
        } else {
            notchClose()
        }
    }

    func notchOpen(reason: NotchOpenReason, surface: IslandSurface = .sessionList) {
        transitionOverlay(
            to: .opened,
            reason: reason,
            surface: surface,
            interactive: true,
            beforeTransition: nil,
            afterStateChange: { [weak self] in
                guard let self else { return }
                self.autoCollapseSurfaceHasBeenEntered = false
                self.updateNotificationAutoCollapse()
            },
            onPlacementResolved: { [weak self] in
                guard let self, let overlayPlacementDiagnostics else { return }
                self.lastActionMessage = "Overlay showing on \(overlayPlacementDiagnostics.targetScreenName) as \(overlayPlacementDiagnostics.modeDescription.lowercased())."
            }
        )
    }

    func notchClose() {
        transitionOverlay(
            to: .closed,
            reason: nil,
            surface: .sessionList,
            interactive: false,
            beforeTransition: { [weak self] in
                self?.notificationAutoCollapseTask?.cancel()
                self?.notificationAutoCollapseTask = nil
            },
            afterStateChange: { [weak self] in
                self?.autoCollapseSurfaceHasBeenEntered = false
            }
        )
    }

    /// Coordinates overlay transitions so SwiftUI re-renders complete before AppKit
    /// animates the panel frame, preventing main-thread contention.
    ///
    /// Phase 1 (current frame): Mutates @Observable state → SwiftUI re-renders.
    /// Phase 2 (next run-loop iteration): Resizes/repositions the NSPanel via AppKit animation.
    private func transitionOverlay(
        to status: NotchStatus,
        reason: NotchOpenReason?,
        surface: IslandSurface,
        interactive: Bool,
        beforeTransition: (() -> Void)?,
        afterStateChange: (() -> Void)? = nil,
        onPlacementResolved: (() -> Void)? = nil
    ) {
        beforeTransition?()

        // Phase 1: State mutation (drives SwiftUI re-render this frame).
        islandSurface = surface
        notchOpenReason = reason
        notchStatus = status
        overlayPanelController.setInteractive(interactive)
        afterStateChange?()

        // Phase 2: AppKit panel frame animation (deferred to next run-loop iteration).
        overlayTransitionGeneration &+= 1
        let capturedGeneration = overlayTransitionGeneration
        DispatchQueue.main.async { [weak self] in
            guard let self, self.overlayTransitionGeneration == capturedGeneration else { return }
            switch status {
            case .opened:
                self.overlayPlacementDiagnostics = self.overlayPanelController.show(
                    model: self,
                    preferredScreenID: self.preferredOverlayScreenID
                )
            case .closed, .popping:
                self.refreshOverlayPlacement()
            }
            onPlacementResolved?()
        }
    }

    func notchPop() {
        guard notchStatus == .closed else { return }
        islandSurface = .sessionList
        notchStatus = .popping
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            guard self?.notchStatus == .popping else { return }
            self?.notchStatus = .closed
        }
    }

    func performBootAnimation() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self else { return }
            self.notchOpen(reason: .boot, surface: .sessionList)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
                guard self?.notchOpenReason == .boot else { return }
                self?.notchClose()
            }
        }
    }

    func ensureOverlayPanel() {
        overlayPanelController.ensurePanel(model: self, preferredScreenID: preferredOverlayScreenID)
    }

    // Legacy compatibility
    func showOverlay() { notchOpen(reason: .click, surface: .sessionList) }
    func hideOverlay() { notchClose() }

    func refreshOverlayDisplayConfiguration() {
        overlayDisplayOptions = overlayPanelController.availableDisplayOptions()

        let validSelectionIDs = Set(overlayDisplayOptions.map(\.id))
        if !validSelectionIDs.contains(overlayDisplaySelectionID) {
            overlayDisplaySelectionID = OverlayDisplayOption.automaticID
            return
        }

        refreshOverlayPlacement()
    }

    func refreshOverlayPlacement() {
        overlayPlacementDiagnostics = overlayPanelController.reposition(
            preferredScreenID: preferredOverlayScreenID
        )
    }

    private func refreshOverlayPlacementIfVisible() {
        refreshOverlayPlacement()
    }

    func showSettings() {
        openSettingsWindow?()
        if let window = NSApp.windows.first(where: { $0.title == "Open Island Settings" }) {
            window.orderFrontRegardless()
            window.makeKey()
        }
        NSApp.activate(ignoringOtherApps: true)
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

    func loadDebugSnapshot(
        _ snapshot: IslandDebugSnapshot,
        presentOverlay: Bool = false,
        autoCollapseNotificationCards: Bool = false
    ) {
        notificationAutoCollapseTask?.cancel()
        notificationAutoCollapseTask = nil
        autoCollapseSurfaceHasBeenEntered = false

        state = SessionState(sessions: snapshot.sessions)
        selectedSessionID = snapshot.selectedSessionID ?? snapshot.sessions.first?.id
        islandSurface = snapshot.islandSurface
        notchStatus = snapshot.notchStatus
        notchOpenReason = snapshot.notchOpenReason
        lastActionMessage = "Loaded debug scenario: \(snapshot.title)."
        harnessRuntimeMonitor?.recordMilestone("scenarioLoaded", message: snapshot.title)

        if autoCollapseNotificationCards {
            updateNotificationAutoCollapse()
        }

        guard presentOverlay else {
            return
        }

        // Immediate interactivity update.
        let interactive = snapshot.notchStatus == .opened
        overlayPanelController.setInteractive(interactive)

        // Defer AppKit panel animation to the next run-loop iteration.
        overlayTransitionGeneration &+= 1
        let capturedGeneration = overlayTransitionGeneration
        DispatchQueue.main.async { [weak self] in
            guard let self, self.overlayTransitionGeneration == capturedGeneration else { return }
            switch snapshot.notchStatus {
            case .opened:
                self.overlayPlacementDiagnostics = self.overlayPanelController.show(
                    model: self,
                    preferredScreenID: self.preferredOverlayScreenID
                )
            case .closed, .popping:
                self.refreshOverlayPlacement()
            }
            self.harnessRuntimeMonitor?.recordMilestone("overlayPresented", message: snapshot.title)
        }
    }

    func notePointerInsideIslandSurface() {
        guard shouldAutoCollapseOnMouseLeave else {
            return
        }

        autoCollapseSurfaceHasBeenEntered = true
    }

    func handlePointerExitedIslandSurface() {
        guard shouldAutoCollapseOnMouseLeave else {
            return
        }

        guard !autoCollapseOnMouseLeaveRequiresPriorSurfaceEntry
                || autoCollapseSurfaceHasBeenEntered else {
            return
        }

        notchClose()
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

    func refreshCodexHookStatus() {
        Task { [weak self] in
            guard let self else {
                return
            }

            do {
                let status = try self.codexHookInstallationManager.status(hooksBinaryURL: self.hooksBinaryURL)
                self.codexHookStatus = status
            } catch {
                self.lastActionMessage = "Failed to read Codex hook status: \(error.localizedDescription)"
            }
        }
    }

    func refreshClaudeHookStatus() {
        Task { [weak self] in
            guard let self else {
                return
            }

            do {
                let status = try self.claudeHookInstallationManager.status(hooksBinaryURL: self.hooksBinaryURL)
                self.claudeHookStatus = status
            } catch {
                self.lastActionMessage = "Failed to read Claude hook status: \(error.localizedDescription)"
            }
        }
    }

    func refreshClaudeUsageState() {
        let manager = claudeStatusLineInstallationManager
        Task { [weak self] in
            guard let self else {
                return
            }

            do {
                let usageState = try await Task.detached(priority: .utility) {
                    var status = try manager.status()
                    var repairedManagedBridge = false
                    if status.managedStatusLineNeedsRepair {
                        status = try manager.install()
                        repairedManagedBridge = true
                    }
                    let snapshot = try ClaudeUsageLoader.load()
                    return (status: status, snapshot: snapshot, repairedManagedBridge: repairedManagedBridge)
                }.value
                self.claudeStatusLineStatus = usageState.status
                self.claudeUsageSnapshot = usageState.snapshot
                if usageState.repairedManagedBridge {
                    self.lastActionMessage = "Recovered the Claude usage bridge after repairing a missing managed script."
                }
            } catch {
                self.lastActionMessage = "Failed to read Claude usage state: \(error.localizedDescription)"
            }
        }
    }

    func refreshCodexUsageState() {
        Task { [weak self] in
            guard let self else {
                return
            }

            do {
                let snapshot = try await Task.detached(priority: .utility) {
                    try CodexUsageLoader.load()
                }.value
                self.codexUsageSnapshot = snapshot
            } catch {
                self.lastActionMessage = "Failed to read Codex usage state: \(error.localizedDescription)"
            }
        }
    }

    func installCodexHooks() {
        guard let hooksBinaryURL else {
            lastActionMessage = "Could not find a local OpenIslandHooks binary. Build the package first."
            return
        }

        updateCodexHooks(userMessage: "Installing Codex hooks.") { manager in
            try manager.install(hooksBinaryURL: hooksBinaryURL)
        }
    }

    func uninstallCodexHooks() {
        updateCodexHooks(userMessage: "Removing Codex hooks.") { manager in
            try manager.uninstall()
        }
    }

    func installClaudeHooks() {
        guard let hooksBinaryURL else {
            lastActionMessage = "Could not find a local OpenIslandHooks binary. Build the package first."
            return
        }

        updateClaudeHooks(userMessage: "Installing Claude hooks.") { manager in
            try manager.install(hooksBinaryURL: hooksBinaryURL)
        }
    }

    func uninstallClaudeHooks() {
        updateClaudeHooks(userMessage: "Removing Claude hooks.") { manager in
            try manager.uninstall()
        }
    }

    func installClaudeUsageBridge() {
        updateClaudeUsageBridge(userMessage: "Installing Claude usage bridge.") { manager in
            try manager.install()
        }
    }

    func uninstallClaudeUsageBridge() {
        updateClaudeUsageBridge(userMessage: "Removing Claude usage bridge.") { manager in
            try manager.uninstall()
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

    private func updateCodexHooks(
        userMessage: String,
        operation: @escaping (CodexHookInstallationManager) throws -> CodexHookInstallationStatus
    ) {
        isCodexSetupBusy = true
        lastActionMessage = userMessage

        Task { [weak self] in
            guard let self else {
                return
            }

            defer {
                self.isCodexSetupBusy = false
            }

            do {
                let status = try operation(self.codexHookInstallationManager)
                self.codexHookStatus = status
                if status.managedHooksPresent {
                    self.lastActionMessage = "Codex hooks are installed and ready."
                } else {
                    self.lastActionMessage = "Codex hooks are not installed."
                }
            } catch {
                self.lastActionMessage = "Codex hook update failed: \(error.localizedDescription)"
            }
        }
    }

    private func updateClaudeHooks(
        userMessage: String,
        operation: @escaping (ClaudeHookInstallationManager) throws -> ClaudeHookInstallationStatus
    ) {
        isClaudeHookSetupBusy = true
        lastActionMessage = userMessage

        Task { [weak self] in
            guard let self else {
                return
            }

            defer {
                self.isClaudeHookSetupBusy = false
            }

            do {
                let status = try operation(self.claudeHookInstallationManager)
                self.claudeHookStatus = status
                if status.managedHooksPresent {
                    self.lastActionMessage = status.hasClaudeIslandHooks
                        ? "Claude hooks are installed. claude-island hooks are also still present."
                        : "Claude hooks are installed and ready."
                } else {
                    self.lastActionMessage = "Claude hooks are not installed."
                }
            } catch {
                self.lastActionMessage = "Claude hook update failed: \(error.localizedDescription)"
            }
        }
    }

    private func updateClaudeUsageBridge(
        userMessage: String,
        operation: @escaping (ClaudeStatusLineInstallationManager) throws -> ClaudeStatusLineInstallationStatus
    ) {
        isClaudeUsageSetupBusy = true
        lastActionMessage = userMessage

        Task { [weak self] in
            guard let self else {
                return
            }

            defer {
                self.isClaudeUsageSetupBusy = false
            }

            do {
                let status = try operation(self.claudeStatusLineInstallationManager)
                self.claudeStatusLineStatus = status
                self.claudeUsageSnapshot = try ClaudeUsageLoader.load()
                if status.managedStatusLineInstalled {
                    self.lastActionMessage = "Claude usage bridge is installed. Start a Claude Code turn to refresh cached rate limits."
                } else {
                    self.lastActionMessage = "Claude usage bridge is not installed."
                }
            } catch {
                self.lastActionMessage = "Claude usage bridge update failed: \(error.localizedDescription)"
            }
        }
    }

    private func readClaudeUsageState(
        repairManagedBridgeIfNeeded: Bool
    ) throws -> (
        status: ClaudeStatusLineInstallationStatus,
        snapshot: ClaudeUsageSnapshot?,
        repairedManagedBridge: Bool
    ) {
        var status = try claudeStatusLineInstallationManager.status()
        var repairedManagedBridge = false

        if repairManagedBridgeIfNeeded && status.managedStatusLineNeedsRepair {
            status = try claudeStatusLineInstallationManager.install()
            repairedManagedBridge = true
        }

        let snapshot = try ClaudeUsageLoader.load()
        return (status, snapshot, repairedManagedBridge)
    }

    func applyTrackedEvent(
        _ event: AgentEvent,
        updateLastActionMessage: Bool = true,
        ingress: TrackedEventIngress = .bridge
    ) {
        state.apply(event)
        reconcileIslandSurfaceAfterStateChange()
        if ingress == .bridge {
            markSessionAttached(for: event)
            markSessionProcessAlive(for: event)
        }
        synchronizeSelection()
        refreshCodexRolloutTracking()
        refreshOverlayPlacementIfVisible()
        scheduleCodexSessionPersistence()
        scheduleClaudeSessionPersistence()

        if updateLastActionMessage {
            lastActionMessage = describe(event)
        }

        if let surface = IslandSurface.notificationSurface(for: event),
           (ingress == .bridge || !isResolvingInitialLiveSessions),
           notchStatus == .closed || notchOpenReason == .notification {
            presentNotificationSurface(surface)
        }
    }

    private func presentNotificationSurface(_ surface: IslandSurface) {
        guard surface.isNotificationCard else {
            return
        }

        NotificationSoundService.playNotification(isMuted: isSoundMuted)
        notchOpen(reason: .notification, surface: surface)
    }

    private func reconcileIslandSurfaceAfterStateChange() {
        guard islandSurface.isNotificationCard else {
            return
        }

        let session = activeIslandCardSession
        guard islandSurface.matchesCurrentState(of: session) else {
            if notchOpenReason == .notification {
                notchClose()
            } else {
                islandSurface = .sessionList
            }
            return
        }

        updateNotificationAutoCollapse()
    }

    private func dismissNotificationSurfaceIfPresent(for sessionID: String) {
        guard islandSurface.sessionID == sessionID,
              notchOpenReason == .notification else {
            return
        }

        notchClose()
    }

    private func updateNotificationAutoCollapse() {
        notificationAutoCollapseTask?.cancel()
        notificationAutoCollapseTask = nil

        guard notchStatus == .opened,
              notchOpenReason == .notification,
              islandSurface.autoDismissesWhenPresentedAsNotification else {
            return
        }

        notificationAutoCollapseTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(Self.notificationSurfaceAutoCollapseDelay))

            guard let self,
                  self.notchStatus == .opened,
                  self.notchOpenReason == .notification,
                  self.islandSurface.autoDismissesWhenPresentedAsNotification else {
                return
            }

            self.notchClose()
        }
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
    private func applyStartupDiscoveryPayload(_ payload: StartupDiscoveryPayload) {
        // Prune stale records if needed.
        if payload.codexRecordsNeedPrune {
            try? codexSessionStore.save(payload.codexRecords)
        }
        if payload.claudeRecordsNeedPrune {
            try? claudeSessionRegistry.save(payload.claudeRecords)
        }

        // Restore persisted Codex sessions.
        if !payload.codexRecords.isEmpty {
            state = SessionState(sessions: payload.codexRecords.map(\.restorableSession))
            synchronizeSelection()
            refreshOverlayPlacementIfVisible()
            lastActionMessage = "Restored \(payload.codexRecords.count) recent Codex session(s) from local cache."
        }

        // Restore persisted Claude sessions.
        if !payload.claudeRecords.isEmpty {
            let restoredSessions = payload.claudeRecords.map(\.restorableSession)
            state = SessionState(sessions: mergeDiscoveredSessions(restoredSessions))
            synchronizeSelection()
            refreshOverlayPlacementIfVisible()
            lastActionMessage = "Restored \(payload.claudeRecords.count) recent Claude session(s) from local registry."
        }

        // Merge discovered Codex sessions.
        if !payload.discoveredCodexRecords.isEmpty {
            let mergedSessions = mergeDiscoveredSessions(payload.discoveredCodexRecords.map(\.session))
            state = SessionState(sessions: mergedSessions)
            synchronizeSelection()
            refreshOverlayPlacementIfVisible()
            scheduleCodexSessionPersistence()
            lastActionMessage = "Discovered \(payload.discoveredCodexRecords.count) recent Codex session(s) from local rollouts."
        }

        // Merge discovered Claude sessions.
        if !payload.discoveredClaudeSessions.isEmpty {
            let mergedSessions = mergeDiscoveredSessions(payload.discoveredClaudeSessions)
            state = SessionState(sessions: mergedSessions)
            synchronizeSelection()
            refreshOverlayPlacementIfVisible()
            scheduleClaudeSessionPersistence()
            lastActionMessage = "Discovered \(payload.discoveredClaudeSessions.count) recent Claude session(s) from local transcripts."
        }

        // Apply hooks binary URL.
        hooksBinaryURL = payload.hooksBinaryURL

        // Reconcile attachments and start monitoring (requires sessions to be loaded).
        reconcileSessionAttachments()
        startSessionAttachmentMonitoringIfNeeded()
        refreshCodexRolloutTracking()
    }

    private func restorePersistedCodexSessions() {
        do {
            let loadedRecords = try codexSessionStore.load()
            let records = loadedRecords.filter {
                $0.updatedAt >= Date.now.addingTimeInterval(-86_400) && $0.shouldRestoreToLiveState
            }

            if records != loadedRecords {
                try? codexSessionStore.save(records)
            }

            guard !records.isEmpty else {
                return
            }

            state = SessionState(sessions: records.map(\.restorableSession))
            synchronizeSelection()
            refreshOverlayPlacementIfVisible()
            lastActionMessage = "Restored \(records.count) recent Codex session(s) from local cache."
        } catch {
            lastActionMessage = "Failed to restore Codex session cache: \(error.localizedDescription)"
        }
    }

    private func restorePersistedClaudeSessions() {
        do {
            let loadedRecords = try claudeSessionRegistry.load()
            let records = loadedRecords.filter {
                $0.updatedAt >= Date.now.addingTimeInterval(-86_400) && $0.shouldRestoreToLiveState
            }

            if records != loadedRecords {
                try? claudeSessionRegistry.save(records)
            }

            guard !records.isEmpty else {
                return
            }

            let restoredSessions = records.map(\.restorableSession)
            state = SessionState(sessions: mergeDiscoveredSessions(restoredSessions))
            synchronizeSelection()
            refreshOverlayPlacementIfVisible()
            lastActionMessage = "Restored \(records.count) recent Claude session(s) from local registry."
        } catch {
            lastActionMessage = "Failed to restore Claude session registry: \(error.localizedDescription)"
        }
    }

    private func discoverRecentCodexSessions() {
        let records = codexRolloutDiscovery.discoverRecentSessions()
        guard !records.isEmpty else {
            return
        }

        let mergedSessions = mergeDiscoveredSessions(records.map(\.session))
        state = SessionState(sessions: mergedSessions)
        synchronizeSelection()
        refreshOverlayPlacementIfVisible()
        scheduleCodexSessionPersistence()
        lastActionMessage = "Discovered \(records.count) recent Codex session(s) from local rollouts."
    }

    private func discoverRecentClaudeSessions() {
        let sessions = claudeTranscriptDiscovery.discoverRecentSessions()
        guard !sessions.isEmpty else {
            return
        }

        let mergedSessions = mergeDiscoveredSessions(sessions)
        state = SessionState(sessions: mergedSessions)
        synchronizeSelection()
        refreshOverlayPlacementIfVisible()
        scheduleClaudeSessionPersistence()
        lastActionMessage = "Discovered \(sessions.count) recent Claude session(s) from local transcripts."
    }

    private func refreshCodexRolloutTracking() {
        let targets = state.sessions.compactMap { session -> CodexRolloutWatchTarget? in
            guard session.tool == .codex,
                  let transcriptPath = session.codexMetadata?.transcriptPath,
                  !transcriptPath.isEmpty else {
                return nil
            }

            return CodexRolloutWatchTarget(
                sessionID: session.id,
                transcriptPath: transcriptPath
            )
        }

        codexRolloutWatcher.sync(targets: targets)
    }

    func mergeDiscoveredSessions(_ discoveredSessions: [AgentSession]) -> [AgentSession] {
        var mergedByID = Dictionary(uniqueKeysWithValues: state.sessions.map { ($0.id, $0) })

        for discovered in discoveredSessions {
            if let existing = mergedByID[discovered.id] {
                mergedByID[discovered.id] = merge(discovered: discovered, into: existing)
            } else if let existingID = existingSessionID(matchingTranscriptOf: discovered, in: mergedByID) {
                mergedByID[existingID] = merge(discovered: discovered, into: mergedByID[existingID]!)
            } else {
                mergedByID[discovered.id] = discovered
            }
        }

        return Array(mergedByID.values)
    }

    private func existingSessionID(
        matchingTranscriptOf discovered: AgentSession,
        in sessions: [String: AgentSession]
    ) -> String? {
        guard let discoveredPath = discovered.claudeMetadata?.transcriptPath,
              !discoveredPath.isEmpty else {
            return nil
        }

        return sessions.first(where: {
            $0.value.claudeMetadata?.transcriptPath == discoveredPath
        })?.key
    }

    private func merge(discovered: AgentSession, into existing: AgentSession) -> AgentSession {
        var merged = existing
        let discoveredIsNewer = discovered.updatedAt >= existing.updatedAt

        if discoveredIsNewer {
            merged.title = discovered.title
            merged.phase = discovered.phase
            merged.summary = discovered.summary
            merged.updatedAt = discovered.updatedAt
            merged.permissionRequest = discovered.permissionRequest
            merged.questionPrompt = discovered.questionPrompt
        }

        merged.origin = existing.origin ?? discovered.origin
        merged.attachmentState = mergeAttachmentState(existing.attachmentState, discovered.attachmentState)
        merged.jumpTarget = existing.jumpTarget ?? discovered.jumpTarget
        merged.codexMetadata = mergeCodexMetadata(existing.codexMetadata, discovered.codexMetadata)
        merged.claudeMetadata = mergeClaudeMetadata(existing.claudeMetadata, discovered.claudeMetadata)

        return merged
    }

    private func mergeCodexMetadata(
        _ existing: CodexSessionMetadata?,
        _ discovered: CodexSessionMetadata?
    ) -> CodexSessionMetadata? {
        guard let existing else {
            return discovered?.isEmpty == true ? nil : discovered
        }

        guard let discovered else {
            return existing.isEmpty ? nil : existing
        }

        let merged = CodexSessionMetadata(
            transcriptPath: discovered.transcriptPath ?? existing.transcriptPath,
            initialUserPrompt: existing.initialUserPrompt ?? discovered.initialUserPrompt ?? discovered.lastUserPrompt,
            lastUserPrompt: discovered.lastUserPrompt ?? existing.lastUserPrompt,
            lastAssistantMessage: discovered.lastAssistantMessage ?? existing.lastAssistantMessage,
            currentTool: discovered.currentTool ?? existing.currentTool,
            currentCommandPreview: discovered.currentCommandPreview ?? existing.currentCommandPreview
        )
        return merged.isEmpty ? nil : merged
    }

    private func mergeClaudeMetadata(
        _ existing: ClaudeSessionMetadata?,
        _ discovered: ClaudeSessionMetadata?
    ) -> ClaudeSessionMetadata? {
        guard let existing else {
            return discovered?.isEmpty == true ? nil : discovered
        }

        guard let discovered else {
            return existing.isEmpty ? nil : existing
        }

        let merged = ClaudeSessionMetadata(
            transcriptPath: discovered.transcriptPath ?? existing.transcriptPath,
            initialUserPrompt: existing.initialUserPrompt ?? discovered.initialUserPrompt ?? discovered.lastUserPrompt,
            lastUserPrompt: discovered.lastUserPrompt ?? existing.lastUserPrompt,
            lastAssistantMessage: discovered.lastAssistantMessage ?? existing.lastAssistantMessage,
            currentTool: discovered.currentTool ?? existing.currentTool,
            currentToolInputPreview: discovered.currentToolInputPreview ?? existing.currentToolInputPreview,
            model: discovered.model ?? existing.model,
            startupSource: discovered.startupSource ?? existing.startupSource,
            permissionMode: discovered.permissionMode ?? existing.permissionMode,
            agentID: discovered.agentID ?? existing.agentID,
            agentType: discovered.agentType ?? existing.agentType,
            worktreeBranch: discovered.worktreeBranch ?? existing.worktreeBranch,
            activeSubagents: existing.activeSubagents.isEmpty ? discovered.activeSubagents : existing.activeSubagents
        )
        return merged.isEmpty ? nil : merged
    }

    private func dismissOverlayForJump() {
        guard isOverlayVisible else {
            return
        }

        notchClose()
    }

    private var preferredOverlayScreenID: String? {
        overlayDisplaySelectionID == OverlayDisplayOption.automaticID
            ? nil
            : overlayDisplaySelectionID
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

            if let liveAttachmentKey = liveAttachmentKey(for: session) {
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

    private func persistOverlayDisplayPreference() {
        let defaults = UserDefaults.standard

        if overlayDisplaySelectionID == OverlayDisplayOption.automaticID {
            defaults.removeObject(forKey: Self.overlayDisplayPreferenceDefaultsKey)
        } else {
            defaults.set(overlayDisplaySelectionID, forKey: Self.overlayDisplayPreferenceDefaultsKey)
        }
    }

    private func startSessionAttachmentMonitoringIfNeeded() {
        guard sessionAttachmentMonitorTask == nil else {
            return
        }

        sessionAttachmentMonitorTask = Task { @MainActor [weak self] in
            guard let self else {
                return
            }

            while !Task.isCancelled {
                let discovery = self.activeAgentProcessDiscovery
                let probe = self.terminalSessionAttachmentProbe
                let (snapshots, ghosttyAvail, terminalAvail) = await Task.detached(priority: .utility) {
                    let s = discovery.discover()
                    let g = probe.ghosttySnapshotAvailability()
                    let t = probe.terminalSnapshotAvailability()
                    return (s, g, t)
                }.value
                self.reconcileSessionAttachments(
                    activeProcesses: snapshots,
                    ghosttyAvailability: ghosttyAvail,
                    terminalAvailability: terminalAvail
                )
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    private func startClaudeUsageMonitoringIfNeeded() {
        guard claudeUsageMonitorTask == nil else {
            return
        }

        claudeUsageMonitorTask = Task { @MainActor [weak self] in
            guard let self else {
                return
            }

            while !Task.isCancelled {
                self.refreshClaudeUsageState()
                try? await Task.sleep(for: .seconds(5))
            }
        }
    }

    private func startCodexUsageMonitoringIfNeeded() {
        guard codexUsageMonitorTask == nil else {
            return
        }

        codexUsageMonitorTask = Task { @MainActor [weak self] in
            guard let self else {
                return
            }

            while !Task.isCancelled {
                self.refreshCodexUsageState()
                try? await Task.sleep(for: .seconds(120))
            }
        }
    }

    private func reconcileSessionAttachments(
        activeProcesses: [ActiveAgentProcessDiscovery.ProcessSnapshot]? = nil,
        ghosttyAvailability: TerminalSessionAttachmentProbe.SnapshotAvailability<TerminalSessionAttachmentProbe.GhosttyTerminalSnapshot>? = nil,
        terminalAvailability: TerminalSessionAttachmentProbe.SnapshotAvailability<TerminalSessionAttachmentProbe.TerminalTabSnapshot>? = nil
    ) {
        let activeProcesses = activeProcesses ?? activeAgentProcessDiscovery.discover()
        let sanitizedSessions = sanitizeCrossToolGhosttyJumpTargets(in: state.sessions)
        let sanitizedSessionsChanged = sanitizedSessions != state.sessions
        if sanitizedSessionsChanged {
            state = SessionState(sessions: sanitizedSessions)
        }

        let mergedSessions = mergedWithSyntheticClaudeSessions(
            existingSessions: state.sessions,
            activeProcesses: activeProcesses
        )
        let syntheticSessionsChanged = mergedSessions != state.sessions
        if syntheticSessionsChanged {
            state = SessionState(sessions: mergedSessions)
        }

        adoptProcessTTYsForClaudeSessions(activeProcesses: activeProcesses)

        let sessions = state.sessions.filter(\.isTrackedLiveSession)
        guard !sessions.isEmpty else {
            isResolvingInitialLiveSessions = false
            return
        }

        let resolutionReport: TerminalSessionAttachmentProbe.ResolutionReport
        if let ghosttyAvailability, let terminalAvailability {
            resolutionReport = terminalSessionAttachmentProbe.sessionResolutionReport(
                for: sessions,
                ghosttyAvailability: ghosttyAvailability,
                terminalAvailability: terminalAvailability,
                activeProcesses: activeProcesses,
                allowRecentAttachmentGrace: !isResolvingInitialLiveSessions
            )
        } else {
            resolutionReport = terminalSessionAttachmentProbe.sessionResolutionReport(
                for: sessions,
                activeProcesses: activeProcesses,
                allowRecentAttachmentGrace: !isResolvingInitialLiveSessions
            )
        }
        let resolutions = resolutionReport.resolutions
        let attachmentUpdates = resolutions.mapValues { $0.attachmentState }
        let jumpTargetUpdates = resolutions.reduce(into: [String: JumpTarget]()) { partialResult, entry in
            if let correctedJumpTarget = entry.value.correctedJumpTarget {
                partialResult[entry.key] = correctedJumpTarget
            }
        }

        let attachmentsChanged = state.reconcileAttachmentStates(attachmentUpdates)
        let jumpTargetsChanged = state.reconcileJumpTargets(jumpTargetUpdates)

        // Phase 1: populate isProcessAlive in parallel with existing system.
        let aliveIDs = sessionIDsWithAliveProcesses(activeProcesses: activeProcesses)
        let livenessChanges = state.markProcessLiveness(aliveSessionIDs: aliveIDs)

        // Resolve jump targets via the new focused resolver.
        let resolverJumpTargets = terminalJumpTargetResolver.resolveJumpTargets(
            for: state.sessions.filter(\.isTrackedLiveSession),
            activeProcesses: activeProcesses
        )
        if !resolverJumpTargets.isEmpty {
            _ = state.reconcileJumpTargets(resolverJumpTargets)
        }

        // Phase 4: remove sessions that are no longer visible.
        let removedInvisible = state.removeInvisibleSessions()

        guard sanitizedSessionsChanged || syntheticSessionsChanged || attachmentsChanged || jumpTargetsChanged || removedInvisible else {
            if resolutionReport.isAuthoritative {
                isResolvingInitialLiveSessions = false
            }
            return
        }

        if resolutionReport.isAuthoritative {
            isResolvingInitialLiveSessions = false
        }
        synchronizeSelection()
        refreshOverlayPlacementIfVisible()
        scheduleCodexSessionPersistence()
        scheduleClaudeSessionPersistence()
    }

    func sanitizeCrossToolGhosttyJumpTargets(in sessions: [AgentSession]) -> [AgentSession] {
        sessions.map { session in
            guard var jumpTarget = session.jumpTarget,
                  supportedTerminalApp(for: jumpTarget.terminalApp) == "Ghostty",
                  let hintedTool = toolHint(forGhosttyPaneTitle: jumpTarget.paneTitle),
                  hintedTool != session.tool else {
                return session
            }

            jumpTarget.terminalSessionID = nil
            jumpTarget.paneTitle = sanitizedGhosttyPaneTitle(for: session)

            var sanitizedSession = session
            sanitizedSession.jumpTarget = jumpTarget
            return sanitizedSession
        }
    }

    private func markSessionAttached(for event: AgentEvent) {
        guard let sessionID = sessionID(for: event) else {
            return
        }

        _ = state.reconcileAttachmentStates([sessionID: .attached])
    }

    private func markSessionProcessAlive(for event: AgentEvent) {
        guard let sessionID = sessionID(for: event) else {
            return
        }

        state.markSingleSessionAlive(sessionID: sessionID)
    }

    private func sessionID(for event: AgentEvent) -> String? {
        switch event {
        case let .sessionStarted(payload):
            payload.sessionID
        case let .activityUpdated(payload):
            payload.sessionID
        case let .permissionRequested(payload):
            payload.sessionID
        case let .questionAsked(payload):
            payload.sessionID
        case let .sessionCompleted(payload):
            payload.sessionID
        case let .jumpTargetUpdated(payload):
            payload.sessionID
        case let .sessionMetadataUpdated(payload):
            payload.sessionID
        case let .claudeSessionMetadataUpdated(payload):
            payload.sessionID
        }
    }

    /// Determine which session IDs have a corresponding alive process.
    /// This mirrors the matching logic used by `representedClaudeProcessKeys`
    /// but returns matched session IDs instead of process keys.
    private func sessionIDsWithAliveProcesses(
        activeProcesses: [ActiveProcessSnapshot]
    ) -> Set<String> {
        var aliveIDs: Set<String> = []
        let sessions = state.sessions

        // Codex sessions: match by session ID directly.
        let codexProcessIDs = Set(
            activeProcesses
                .filter { $0.tool == .codex }
                .compactMap(\.sessionID)
        )
        for session in sessions where session.tool == .codex && !session.isDemoSession {
            if codexProcessIDs.contains(session.id) {
                aliveIDs.insert(session.id)
            }
        }

        // Claude sessions: reuse the multi-pass matching from representedClaudeProcessKeys.
        let claudeProcesses = activeProcesses.filter { $0.tool == .claudeCode }
        let trackedClaudeSessions = sessions.filter { $0.tool == .claudeCode && !isSyntheticClaudeSession($0) }
        var claimedSessionIDs: Set<String> = []

        // Pass 1: exact session ID match.
        for process in claudeProcesses {
            guard let processSessionID = process.sessionID,
                  let matched = trackedClaudeSessions.first(where: {
                      !claimedSessionIDs.contains($0.id) && $0.id == processSessionID
                  }) else { continue }
            aliveIDs.insert(matched.id)
            claimedSessionIDs.insert(matched.id)
        }

        // Pass 2: transcript path match.
        for process in claudeProcesses {
            guard let transcriptPath = process.transcriptPath,
                  let matched = trackedClaudeSessions.first(where: {
                      !claimedSessionIDs.contains($0.id)
                          && $0.claudeMetadata?.transcriptPath == transcriptPath
                  }) else { continue }
            aliveIDs.insert(matched.id)
            claimedSessionIDs.insert(matched.id)
        }

        // Pass 3: TTY + CWD fallback match.
        for process in claudeProcesses {
            guard let matched = uniqueTrackedClaudeSession(
                for: process,
                sessions: trackedClaudeSessions,
                claimedSessionIDs: claimedSessionIDs
            ) else { continue }
            aliveIDs.insert(matched.id)
            claimedSessionIDs.insert(matched.id)
        }

        // Synthetic sessions: always alive if the process exists.
        let syntheticSessions = sessions.filter { isSyntheticClaudeSession($0) }
        for session in syntheticSessions {
            aliveIDs.insert(session.id)
        }

        return aliveIDs
    }

    private func mergeAttachmentState(
        _ existing: SessionAttachmentState,
        _ discovered: SessionAttachmentState
    ) -> SessionAttachmentState {
        switch (existing, discovered) {
        case (.attached, _), (_, .attached):
            .attached
        case (.stale, _), (_, .stale):
            .stale
        case (.detached, .detached):
            .detached
        }
    }

    private func scheduleCodexSessionPersistence() {
        codexSessionPersistenceTask?.cancel()

        let records = state.sessions
            .filter { $0.isTrackedLiveCodexSession && $0.updatedAt >= Date.now.addingTimeInterval(-86_400) }
            .map(CodexTrackedSessionRecord.init(session:))
        let store = codexSessionStore

        codexSessionPersistenceTask = Task.detached(priority: .utility) {
            try? await Task.sleep(for: .milliseconds(250))
            try? store.save(records)
        }
    }

    private func scheduleClaudeSessionPersistence() {
        claudeSessionPersistenceTask?.cancel()

        let records = state.sessions
            .filter {
                $0.tool == .claudeCode
                    && $0.isTrackedLiveSession
                    && !$0.id.hasPrefix(Self.syntheticClaudeSessionPrefix)
                    && $0.updatedAt >= Date.now.addingTimeInterval(-86_400)
                    && ($0.jumpTarget != nil || $0.claudeMetadata?.transcriptPath != nil)
            }
            .map(ClaudeTrackedSessionRecord.init(session:))
        let registry = claudeSessionRegistry

        claudeSessionPersistenceTask = Task.detached(priority: .utility) {
            try? await Task.sleep(for: .milliseconds(250))
            try? registry.save(records)
        }
    }

    func mergedWithSyntheticClaudeSessions(
        existingSessions: [AgentSession],
        activeProcesses: [ActiveProcessSnapshot],
        now: Date = .now
    ) -> [AgentSession] {
        let baseSessions = existingSessions.filter { !isSyntheticClaudeSession($0) }
        let syntheticSessions = syntheticClaudeSessions(
            existingSessions: baseSessions,
            activeProcesses: activeProcesses,
            now: now
        )

        return baseSessions + syntheticSessions
    }

    private func syntheticClaudeSessions(
        existingSessions: [AgentSession],
        activeProcesses: [ActiveProcessSnapshot],
        now: Date
    ) -> [AgentSession] {
        let activeClaudeProcesses = activeProcesses.filter { process in
            process.tool == .claudeCode
        }
        let trackedClaudeSessions = existingSessions.filter { session in
            session.tool == .claudeCode && !isSyntheticClaudeSession(session)
        }

        let representedProcessKeys = representedClaudeProcessKeys(
            sessions: trackedClaudeSessions,
            activeProcesses: activeClaudeProcesses
        )

        return activeClaudeProcesses
            .filter { !representedProcessKeys.contains(processIdentityKey($0)) }
            .sorted { processIdentityKey($0) < processIdentityKey($1) }
            .map { syntheticClaudeSession(for: $0, now: now) }
    }

    private func syntheticClaudeSession(
        for process: ActiveProcessSnapshot,
        now: Date
    ) -> AgentSession {
        let workingDirectory = process.workingDirectory
        let workspaceName = workingDirectory.map { WorkspaceNameResolver.workspaceName(for: $0) } ?? "Workspace"
        let terminalApp = supportedTerminalApp(for: process.terminalApp) ?? "Unknown"
        let identity = processIdentityKey(process)

        var session = AgentSession(
            id: "\(Self.syntheticClaudeSessionPrefix)\(identity)",
            title: "Claude · \(workspaceName)",
            tool: .claudeCode,
            origin: .live,
            attachmentState: .attached,
            phase: .completed,
            summary: "Claude session detected from \(terminalApp).",
            updatedAt: now,
            jumpTarget: JumpTarget(
                terminalApp: terminalApp,
                workspaceName: workspaceName,
                paneTitle: "Claude \(workspaceName)",
                workingDirectory: workingDirectory,
                terminalTTY: process.terminalTTY
            )
        )
        session.isProcessAlive = true
        return session
    }

    private func isSyntheticClaudeSession(_ session: AgentSession) -> Bool {
        session.tool == .claudeCode && session.id.hasPrefix(Self.syntheticClaudeSessionPrefix)
    }

    private func representedClaudeProcessKeys(
        sessions: [AgentSession],
        activeProcesses: [ActiveProcessSnapshot]
    ) -> Set<String> {
        let trackedClaudeSessions = sessions.filter { session in
            session.tool == .claudeCode && !isSyntheticClaudeSession(session)
        }

        var representedProcessKeys: Set<String> = []
        var claimedSessionIDs: Set<String> = []

        for process in activeProcesses {
            guard let processSessionID = process.sessionID,
                  let matchedSession = trackedClaudeSessions.first(where: {
                      !claimedSessionIDs.contains($0.id) && $0.id == processSessionID
                  }) else {
                continue
            }

            representedProcessKeys.insert(processIdentityKey(process))
            claimedSessionIDs.insert(matchedSession.id)
        }

        for process in activeProcesses {
            let processKey = processIdentityKey(process)
            guard !representedProcessKeys.contains(processKey),
                  let transcriptPath = process.transcriptPath,
                  let matchedSession = trackedClaudeSessions.first(where: {
                      !claimedSessionIDs.contains($0.id)
                          && $0.claudeMetadata?.transcriptPath == transcriptPath
                  }) else {
                continue
            }

            representedProcessKeys.insert(processKey)
            claimedSessionIDs.insert(matchedSession.id)
        }

        for process in activeProcesses {
            let processKey = processIdentityKey(process)
            guard !representedProcessKeys.contains(processKey),
                  let matchedSession = uniqueTrackedClaudeSession(
                      for: process,
                      sessions: trackedClaudeSessions,
                      claimedSessionIDs: claimedSessionIDs
                  ) else {
                continue
            }

            representedProcessKeys.insert(processKey)
            claimedSessionIDs.insert(matchedSession.id)
        }

        return representedProcessKeys
    }

    private func uniqueTrackedClaudeSession(
        for process: ActiveProcessSnapshot,
        sessions: [AgentSession],
        claimedSessionIDs: Set<String>
    ) -> AgentSession? {
        if let terminalTTY = normalizedTTYForMatching(process.terminalTTY),
           let workingDirectory = normalizedPathForMatching(process.workingDirectory) {
            let candidates = claudeTrackedSessions(
                in: sessions,
                claimedSessionIDs: claimedSessionIDs,
                terminalTTY: terminalTTY,
                workingDirectory: workingDirectory
            )
            if candidates.count == 1 {
                return candidates[0]
            }
        }

        if let terminalTTY = normalizedTTYForMatching(process.terminalTTY) {
            let candidates = claudeTrackedSessions(
                in: sessions,
                claimedSessionIDs: claimedSessionIDs,
                terminalTTY: terminalTTY,
                workingDirectory: nil
            )
            if candidates.count == 1 {
                return candidates[0]
            }
        }

        if let workingDirectory = normalizedPathForMatching(process.workingDirectory) {
            let processTTY = normalizedTTYForMatching(process.terminalTTY)
            // When matching by cwd alone, skip sessions whose TTY is known but
            // differs from the process — they belong to a different terminal and
            // should not consume this process's slot.
            let candidates = claudeTrackedSessions(
                in: sessions,
                claimedSessionIDs: claimedSessionIDs,
                terminalTTY: nil,
                workingDirectory: workingDirectory
            ).filter { session in
                guard let sessionTTY = normalizedTTYForMatching(session.jumpTarget?.terminalTTY) else {
                    return true
                }
                return processTTY == nil || sessionTTY == processTTY
            }
            if candidates.count == 1 {
                return candidates[0]
            }

            if candidates.count > 1 {
                return candidates.max(by: { $0.updatedAt < $1.updatedAt })
            }
        }

        return nil
    }

    private func claudeTrackedSessions(
        in sessions: [AgentSession],
        claimedSessionIDs: Set<String>,
        terminalTTY: String?,
        workingDirectory: String?
    ) -> [AgentSession] {
        sessions.filter { session in
            guard session.tool == .claudeCode,
                  !claimedSessionIDs.contains(session.id) else {
                return false
            }

            if let terminalTTY,
               normalizedTTYForMatching(session.jumpTarget?.terminalTTY) != terminalTTY {
                return false
            }

            if let workingDirectory,
               normalizedPathForMatching(session.jumpTarget?.workingDirectory) != workingDirectory {
                return false
            }

            return true
        }
    }

    /// When a Claude session was matched to a process by cwd but has a nil or
    /// mismatched TTY, adopt the process's TTY so that the subsequent terminal
    /// attachment resolution can find and promote the session.
    private func adoptProcessTTYsForClaudeSessions(activeProcesses: [ActiveProcessSnapshot]) {
        let claudeProcesses = activeProcesses.filter { $0.tool == .claudeCode }
        guard !claudeProcesses.isEmpty else { return }

        var sessions = state.sessions
        var changed = false

        for process in claudeProcesses {
            guard let processTTY = process.terminalTTY, !processTTY.isEmpty else { continue }
            let processCWD = normalizedPathForMatching(process.workingDirectory)

            for index in sessions.indices {
                let session = sessions[index]
                guard session.tool == .claudeCode,
                      !isSyntheticClaudeSession(session),
                      let jumpTarget = session.jumpTarget,
                      normalizedPathForMatching(jumpTarget.workingDirectory) == processCWD,
                      normalizedTTYForMatching(jumpTarget.terminalTTY) != normalizedTTYForMatching(processTTY) else {
                    continue
                }

                // Only adopt if no other session already owns this TTY.
                let ttyAlreadyClaimed = sessions.contains { other in
                    other.id != session.id
                        && other.tool == .claudeCode
                        && normalizedTTYForMatching(other.jumpTarget?.terminalTTY) == normalizedTTYForMatching(processTTY)
                }
                guard !ttyAlreadyClaimed else { continue }

                // Only adopt if no other process has the same cwd and already
                // matches this session's TTY (would mean a different process owns it).
                let sessionOwnedByOtherProcess = claudeProcesses.contains { other in
                    normalizedTTYForMatching(other.terminalTTY) == normalizedTTYForMatching(session.jumpTarget?.terminalTTY)
                        && normalizedPathForMatching(other.workingDirectory) == processCWD
                }
                guard !sessionOwnedByOtherProcess else { continue }

                sessions[index].jumpTarget?.terminalTTY = processTTY
                sessions[index].attachmentState = .attached
                sessions[index].updatedAt = .now
                changed = true
                break
            }
        }

        if changed {
            state = SessionState(sessions: sessions)
        }
    }

    private func processIdentityKey(_ process: ActiveProcessSnapshot) -> String {
        [
            process.sessionID,
            normalizedTTYForMatching(process.terminalTTY),
            normalizedPathForMatching(process.workingDirectory),
            supportedTerminalApp(for: process.terminalApp),
        ]
        .compactMap { $0 }
        .joined(separator: "|")
    }

    private func syntheticClaudeGroupKey(for process: ActiveProcessSnapshot) -> String? {
        if let workingDirectory = normalizedPathForMatching(process.workingDirectory) {
            return "cwd:\(workingDirectory)"
        }

        if let terminalTTY = normalizedTTYForMatching(process.terminalTTY) {
            return "tty:\(terminalTTY)"
        }

        return nil
    }

    private func syntheticClaudeGroupKey(for session: AgentSession) -> String? {
        if let workingDirectory = normalizedPathForMatching(session.jumpTarget?.workingDirectory) {
            return "cwd:\(workingDirectory)"
        }

        if let terminalTTY = normalizedTTYForMatching(session.jumpTarget?.terminalTTY) {
            return "tty:\(terminalTTY)"
        }

        return nil
    }

    private func liveAttachmentKey(for session: AgentSession) -> String? {
        guard let jumpTarget = session.jumpTarget else {
            return nil
        }

        let terminalApp = supportedTerminalApp(for: jumpTarget.terminalApp)
            ?? jumpTarget.terminalApp.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !terminalApp.isEmpty else {
            return nil
        }

        if let terminalSessionID = jumpTarget.terminalSessionID?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !terminalSessionID.isEmpty {
            return "\(terminalApp.lowercased()):session:\(terminalSessionID.lowercased())"
        }

        if let terminalTTY = normalizedTTYForMatching(jumpTarget.terminalTTY) {
            return "\(terminalApp.lowercased()):tty:\(terminalTTY.lowercased())"
        }

        let paneTitle = jumpTarget.paneTitle.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if let workingDirectory = normalizedPathForMatching(jumpTarget.workingDirectory),
           !paneTitle.isEmpty {
            return "\(terminalApp.lowercased()):cwd:\(workingDirectory):title:\(paneTitle)"
        }

        if let workingDirectory = normalizedPathForMatching(jumpTarget.workingDirectory) {
            return "\(terminalApp.lowercased()):cwd:\(workingDirectory)"
        }

        return nil
    }

    private func normalizedPathForMatching(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else {
            return nil
        }

        return URL(fileURLWithPath: value).standardizedFileURL.path.lowercased()
    }

    private func normalizedTTYForMatching(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else {
            return nil
        }

        return value.hasPrefix("/dev/") ? value : "/dev/\(value)"
    }

    private func supportedTerminalApp(for value: String?) -> String? {
        guard let normalized = value?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() else {
            return nil
        }

        switch normalized {
        case "ghostty":
            return "Ghostty"
        case "terminal", "apple_terminal":
            return "Terminal"
        case "cmux":
            return "cmux"
        default:
            return nil
        }
    }

    private func toolHint(forGhosttyPaneTitle value: String) -> AgentTool? {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if normalized.contains("codex") {
            return .codex
        }

        if normalized.contains("claude") {
            return .claudeCode
        }

        return nil
    }

    private func sanitizedGhosttyPaneTitle(for session: AgentSession) -> String {
        switch session.tool {
        case .codex:
            return "Codex \(session.id.prefix(8))"
        case .claudeCode:
            return "Claude \(session.id.prefix(8))"
        case .geminiCLI:
            return "Gemini \(session.id.prefix(8))"
        }
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
        }
    }

    private var relativeTimestampFormatter: RelativeDateTimeFormatter {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter
    }
}
