import AppKit
import Foundation
import Observation
import OpenIslandCore
import UserNotifications

/// Drives the first-run onboarding window: tracks the current screen,
/// the user's agent selection, and the status of the three optional
/// permission requests. Agent install side-effects fire only on
/// completion so mid-flow cancellation leaves nothing behind.
@MainActor
@Observable
final class OnboardingCoordinator {
    enum Step: Int, CaseIterable {
        case welcome
        case agents
        case permissions
        case completion
    }

    enum PermissionStatus: Equatable {
        case unknown
        case granted
        case denied
        case pending
    }

    private weak var model: AppModel?

    var step: Step = .welcome
    /// Agents the user has ticked in Screen 2. Default: all managed agents
    /// except the Claude usage bridge (handled silently alongside Claude).
    var selectedAgents: Set<AgentIdentifier>
    var notificationStatus: PermissionStatus = .unknown
    var accessibilityStatus: PermissionStatus = .unknown
    var automationStatus: PermissionStatus = .unknown
    /// Expanded state for the "More agents" fold on Screen 2.
    var moreAgentsExpanded: Bool = false

    init(model: AppModel? = nil) {
        self.model = model
        self.selectedAgents = Set(Self.userFacingAgents)
    }

    // MARK: - Screen 2 model

    /// Agents shown unfolded at the top of Screen 2.
    static let primaryAgents: [AgentIdentifier] = [.claudeCode, .codex, .cursor, .openCode]

    /// Agents hidden behind the "More agents" disclosure on Screen 2.
    static let secondaryAgents: [AgentIdentifier] = [.qoder, .qwenCode, .factory, .codebuddy, .gemini]

    /// The union, in display order — excludes `claudeUsageBridge` because it
    /// is coupled to Claude Code and installed silently alongside it.
    static var userFacingAgents: [AgentIdentifier] {
        primaryAgents + secondaryAgents
    }

    func isSelected(_ agent: AgentIdentifier) -> Bool {
        selectedAgents.contains(agent)
    }

    func toggleSelection(_ agent: AgentIdentifier) {
        if selectedAgents.contains(agent) {
            selectedAgents.remove(agent)
        } else {
            selectedAgents.insert(agent)
        }
    }

    // MARK: - Navigation

    func advance() {
        guard let next = Step(rawValue: step.rawValue + 1) else { return }
        step = next
    }

    func goBack() {
        guard let prev = Step(rawValue: step.rawValue - 1) else { return }
        step = prev
    }

    // MARK: - Permission flow

    func refreshNotificationStatus() {
        Task { [weak self] in
            let settings = await UNUserNotificationCenter.current().notificationSettings()
            await MainActor.run { [weak self] in
                guard let self else { return }
                switch settings.authorizationStatus {
                case .authorized, .provisional, .ephemeral:
                    self.notificationStatus = .granted
                case .denied:
                    self.notificationStatus = .denied
                case .notDetermined:
                    self.notificationStatus = .unknown
                @unknown default:
                    self.notificationStatus = .unknown
                }
            }
        }
    }

    func requestNotificationPermission() {
        notificationStatus = .pending
        Task { [weak self] in
            let granted = (try? await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound, .badge])) ?? false
            await MainActor.run { [weak self] in
                self?.notificationStatus = granted ? .granted : .denied
            }
        }
    }

    func openAccessibilitySettings() {
        accessibilityStatus = .pending
        openSystemSettings(url: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
    }

    func openAutomationSettings() {
        automationStatus = .pending
        openSystemSettings(url: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation")
    }

    private func openSystemSettings(url urlString: String) {
        guard let url = URL(string: urlString) else { return }
        NSWorkspace.shared.open(url)
    }

    // MARK: - Completion

    /// Called by the final screen's primary button. Writes intents for every
    /// agent (selected → `.installed`, unselected → `.uninstalled`), marks
    /// first launch complete, and kicks off the real installs. Does not
    /// block — install is fire-and-forget; failures surface on the
    /// individual agent cards in settings.
    func complete() {
        guard let model else { return }

        for agent in Self.userFacingAgents {
            let intent: AgentHookIntent = selectedAgents.contains(agent) ? .installed : .uninstalled
            model.hooks.intentStore.setIntent(intent, for: agent)
        }

        // Claude usage bridge: install it alongside Claude Code so existing
        // behaviour is preserved. If user deselected Claude Code, keep the
        // bridge uninstalled too.
        let bridgeIntent: AgentHookIntent = selectedAgents.contains(.claudeCode) ? .installed : .uninstalled
        model.hooks.intentStore.setIntent(bridgeIntent, for: .claudeUsageBridge)

        model.firstLaunchCompleted = true

        if selectedAgents.contains(.claudeCode) { model.installClaudeHooks() }
        if selectedAgents.contains(.codex) { model.installCodexHooks() }
        if selectedAgents.contains(.cursor) { model.installCursorHooks() }
        if selectedAgents.contains(.qoder) { model.installQoderHooks() }
        if selectedAgents.contains(.qwenCode) { model.installQwenCodeHooks() }
        if selectedAgents.contains(.factory) { model.installFactoryHooks() }
        if selectedAgents.contains(.codebuddy) { model.installCodebuddyHooks() }
        if selectedAgents.contains(.openCode) { model.installOpenCodePlugin() }
        if selectedAgents.contains(.gemini) { model.installGeminiHooks() }
        if selectedAgents.contains(.claudeCode) { model.installClaudeUsageBridge() }

        model.dismissOnboarding()
    }

    /// Called when the user closes the window mid-flow.
    func skip() {
        // Leave intents as `.untouched`, do not mark first launch complete.
        // Next launch may show onboarding again; the empty-state banner is
        // the backstop.
        model?.dismissOnboarding()
    }
}
