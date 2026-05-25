import Foundation
import Observation
import OpenIslandCore

@MainActor
@Observable
final class HookInstallationCoordinator {
    @ObservationIgnored
    let intentStore: AgentIntentStore

    var codexHookStatus: CodexHookInstallationStatus?
    var claudeHookStatus: ClaudeHookInstallationStatus?
    var claudeStatusLineStatus: ClaudeStatusLineInstallationStatus?
    var claudeUsageSnapshot: ClaudeUsageSnapshot?
    var codexUsageSnapshot: CodexUsageSnapshot?
    var hooksBinaryURL: URL?

    var qoderHookStatus: ClaudeHookInstallationStatus?
    var qwenCodeHookStatus: ClaudeHookInstallationStatus?
    var factoryHookStatus: ClaudeHookInstallationStatus?
    var codebuddyHookStatus: ClaudeHookInstallationStatus?
    var openCodePluginStatus: OpenCodePluginInstallationStatus?
    var cursorHookStatus: CursorHookInstallationStatus?
    var geminiHookStatus: GeminiHookInstallationStatus?
    var kimiHookStatus: KimiHookInstallationStatus?

    var isCodexSetupBusy = false
    var isClaudeHookSetupBusy = false
    var isClaudeUsageSetupBusy = false
    var isQoderHookSetupBusy = false
    var isQwenCodeHookSetupBusy = false
    var isFactoryHookSetupBusy = false
    var isCodebuddyHookSetupBusy = false
    var isOpenCodeSetupBusy = false
    var isCursorHookSetupBusy = false
    var isGeminiHookSetupBusy = false
    var isKimiHookSetupBusy = false

    var codexHealthReport: HookHealthReport?
    var claudeHealthReport: HookHealthReport?

    @ObservationIgnored
    var onStatusMessage: ((String) -> Void)?

    @ObservationIgnored
    private let codexHookInstallation = CodexHookInstallationManager()

    private var claudeHookInstallation: ClaudeHookInstallationManager {
        ClaudeHookInstallationManager()
    }

    private var claudeStatusLineInstallation: ClaudeStatusLineInstallationManager {
        ClaudeStatusLineInstallationManager()
    }

    @ObservationIgnored
    private var claudeUsageMonitorTask: Task<Void, Never>?

    @ObservationIgnored
    private var codexUsageMonitorTask: Task<Void, Never>?

    @ObservationIgnored
    private var relativeTimestampFormatter: RelativeDateTimeFormatter {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter
    }

    init(intentStore: AgentIntentStore = AgentIntentStore()) {
        self.intentStore = intentStore
    }

    var codexHooksInstalled: Bool { codexHookStatus?.managedHooksPresent == true }
    var claudeHooksInstalled: Bool { claudeHookStatus?.managedHooksPresent == true }
    var claudeUsageInstalled: Bool { claudeStatusLineStatus?.managedStatusLineInstalled == true }

    var qoderHooksInstalled: Bool { false }
    var qwenCodeHooksInstalled: Bool { false }
    var factoryHooksInstalled: Bool { false }
    var codebuddyHooksInstalled: Bool { false }
    var openCodePluginInstalled: Bool { false }
    var cursorHooksInstalled: Bool { false }
    var geminiHooksInstalled: Bool { false }
    var kimiHooksInstalled: Bool { false }

    var codexHookStatusTitle: String {
        codexHooksInstalled ? "Codex hooks installed" : "Codex hooks not installed"
    }

    var codexHookStatusSummary: String {
        guard let status = codexHookStatus else { return "Reading ~/.codex state." }
        if codexHooksInstalled {
            return "\(status.featureFlagEnabled ? "feature on" : "feature off") · managed hooks present"
        }
        if hooksBinaryURL == nil { return "Build OpenIslandHooks before installing." }
        return status.featureFlagEnabled ? "feature on · no managed hooks" : "feature off · no managed hooks"
    }

    var claudeHookStatusTitle: String {
        claudeHooksInstalled ? "Claude hooks installed" : "Claude hooks not installed"
    }

    var claudeHookStatusSummary: String {
        guard let status = claudeHookStatus else {
            return "Reading \(ClaudeConfigDirectory.resolved().appendingPathComponent("settings.json").path)."
        }
        if claudeHooksInstalled {
            return status.hasClaudeIslandHooks
                ? "managed hooks present · claude-island hooks also detected"
                : "managed hooks present"
        }
        if hooksBinaryURL == nil { return "Build OpenIslandHooks before installing." }
        return status.hasClaudeIslandHooks ? "claude-island hooks detected · managed hooks absent" : "no managed Claude hooks"
    }

    var claudeUsageStatusTitle: String {
        guard let status = claudeStatusLineStatus else { return "Claude usage status unavailable" }
        if status.managedStatusLineInstalled { return "Claude usage bridge installed" }
        if status.managedStatusLineNeedsRepair { return "Claude usage bridge needs repair" }
        if status.hasConflictingStatusLine { return "Custom Claude status line detected" }
        return "Claude usage bridge not installed"
    }

    var claudeUsageStatusSummary: String {
        guard let status = claudeStatusLineStatus else {
            return "Reading \(ClaudeConfigDirectory.resolved().appendingPathComponent("settings.json").path)."
        }
        if status.managedStatusLineInstalled {
            if let summary = claudeUsageSummaryText {
                return "Caching rate limits from Claude Code · \(summary)"
            }
            return "Caching rate limits from Claude Code into \(status.cacheURL.path)."
        }
        if status.managedStatusLineNeedsRepair {
            return "The managed Claude status line script is missing and can be reinstalled manually."
        }
        if status.hasConflictingStatusLine {
            return "Open Island will not overwrite an existing Claude status line automatically."
        }
        return "Install a managed Claude status line to cache 5h and 7d usage locally."
    }

    var claudeUsageSummaryText: String? {
        guard let snapshot = claudeUsageSnapshot else { return nil }
        var components: [String] = []
        if let fiveHour = snapshot.fiveHour { components.append("5h \(fiveHour.roundedUsedPercentage)%") }
        if let sevenDay = snapshot.sevenDay { components.append("7d \(sevenDay.roundedUsedPercentage)%") }
        if let cachedAt = snapshot.cachedAt {
            components.append("updated \(relativeTimestampFormatter.localizedString(for: cachedAt, relativeTo: .now))")
        }
        return components.isEmpty ? nil : components.joined(separator: " · ")
    }

    var codexUsageStatusTitle: String {
        codexUsageSnapshot?.isEmpty == false ? "Codex rate limits detected" : "Waiting for Codex rate limits"
    }

    var codexUsageStatusSummary: String {
        if let summary = codexUsageSummaryText {
            return "Reading the latest local rollout token_count snapshots · \(summary)"
        }
        return "Passively reading ~/.codex/sessions/**/rollout-*.jsonl and extracting token_count.rate_limits."
    }

    var codexUsageSummaryText: String? {
        guard let snapshot = codexUsageSnapshot else { return nil }
        var components = snapshot.windows.map { "\($0.label) \($0.roundedUsedPercentage)%" }
        if let planType = snapshot.planType { components.append("plan \(planType)") }
        if let capturedAt = snapshot.capturedAt {
            components.append("updated \(relativeTimestampFormatter.localizedString(for: capturedAt, relativeTo: .now))")
        }
        return components.isEmpty ? nil : components.joined(separator: " · ")
    }

    var openCodePluginStatusTitle: String { "OpenCode disabled in work-safe build" }
    var openCodePluginStatusSummary: String { "Only Codex and Claude integrations are enabled." }
    var cursorHookStatusTitle: String { "Cursor disabled in work-safe build" }
    var cursorHookStatusSummary: String { "Only Codex and Claude integrations are enabled." }
    var geminiHookStatusTitle: String { "Gemini disabled in work-safe build" }
    var geminiHookStatusSummary: String { "Only Codex and Claude integrations are enabled." }
    var kimiHookStatusTitle: String { "Kimi disabled in work-safe build" }
    var kimiHookStatusSummary: String { "Only Codex and Claude integrations are enabled." }

    func updateClaudeConfigDirectory(to newDirectory: URL?) {
        ClaudeConfigDirectory.customDirectory = newDirectory
        refreshClaudeHookStatus()
        refreshClaudeUsageState()
        onStatusMessage?("Claude config directory set to \(ClaudeConfigDirectory.resolved().path).")
    }

    func updateHooksBinaryIfNeeded() {
        guard let sourceURL = hooksBinaryURL else { return }
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let updated = try await Task.detached(priority: .utility) {
                    try ManagedHooksBinary.updateIfNeeded(from: sourceURL)
                }.value
                if updated {
                    self.onStatusMessage?("Hooks binary updated to match the current app version.")
                    self.refreshCodexHookStatus()
                    self.refreshClaudeHookStatus()
                }
            } catch {
                self.onStatusMessage?("Failed to update hooks binary: \(error.localizedDescription)")
            }
        }
    }

    func runHealthChecks() {
        Task { @MainActor [weak self] in
            guard let self else { return }
            let binaryURL = self.hooksBinaryURL
            let reports = await Task.detached(priority: .utility) {
                (
                    HookHealthCheck.checkClaude(hooksBinaryURL: binaryURL),
                    HookHealthCheck.checkCodex(hooksBinaryURL: binaryURL)
                )
            }.value
            self.claudeHealthReport = reports.0
            self.codexHealthReport = reports.1
        }
    }

    @discardableResult
    func repairHooksIfNeeded() async -> Bool {
        false
    }

    func refreshCodexHookStatus() {
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                self.codexHookStatus = try self.codexHookInstallation.status(hooksBinaryURL: self.hooksBinaryURL)
            } catch {
                self.onStatusMessage?("Failed to read Codex hook status: \(error.localizedDescription)")
            }
        }
    }

    func refreshClaudeHookStatus() {
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                self.claudeHookStatus = try self.claudeHookInstallation.status(hooksBinaryURL: self.hooksBinaryURL)
            } catch {
                self.onStatusMessage?("Failed to read Claude hook status: \(error.localizedDescription)")
            }
        }
    }

    func refreshAllHookStatusAndWait() async {
        do {
            codexHookStatus = try codexHookInstallation.status(hooksBinaryURL: hooksBinaryURL)
        } catch {
            onStatusMessage?("Failed to read Codex hook status: \(error.localizedDescription)")
        }
        do {
            claudeHookStatus = try claudeHookInstallation.status(hooksBinaryURL: hooksBinaryURL)
        } catch {
            onStatusMessage?("Failed to read Claude hook status: \(error.localizedDescription)")
        }
        refreshClaudeUsageState()
        refreshCodexUsageState()
    }

    func migrateIntentStoreIfNeeded() {
        let present: Set<AgentIdentifier> = [
            codexHooksInstalled ? .codex : nil,
            claudeHooksInstalled ? .claudeCode : nil,
            claudeUsageInstalled ? .claudeUsageBridge : nil,
        ].compactMap { $0 }.reduce(into: Set<AgentIdentifier>()) { $0.insert($1) }
        intentStore.migrateFromLegacyStateIfNeeded(detectInstalled: { present.contains($0) })
    }

    func shouldAutoInstall(_ agent: AgentIdentifier) -> Bool {
        switch agent {
        case .claudeCode:
            intentStore.intent(for: agent) != .uninstalled && !claudeHooksInstalled
        case .codex:
            intentStore.intent(for: agent) != .uninstalled && !codexHooksInstalled
        case .claudeUsageBridge:
            intentStore.intent(for: agent) == .installed && !claudeUsageInstalled
        case .cursor, .qoder, .qwenCode, .factory, .codebuddy, .openCode, .gemini, .kimi:
            false
        }
    }

    func refreshCCForkHookStatuses() {}
    func refreshOpenCodePluginStatus() {}
    func refreshCursorHookStatus() {}
    func refreshGeminiHookStatus() {}
    func refreshKimiHookStatus() {}

    func installCodexHooks() {
        guard let hooksBinaryURL else {
            onStatusMessage?("Build OpenIslandHooks before installing Codex hooks.")
            return
        }
        updateCodexHooks(hooksBinaryURL: hooksBinaryURL, install: true)
    }

    func uninstallCodexHooks() {
        updateCodexHooks(hooksBinaryURL: hooksBinaryURL, install: false)
    }

    private func updateCodexHooks(hooksBinaryURL: URL?, install: Bool) {
        isCodexSetupBusy = true
        Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.isCodexSetupBusy = false }
            do {
                let status: CodexHookInstallationStatus
                if install, let hooksBinaryURL {
                    status = try self.codexHookInstallation.install(hooksBinaryURL: hooksBinaryURL)
                    self.intentStore.setIntent(.installed, for: .codex)
                    self.onStatusMessage?("Installed Open Island Codex hooks.")
                } else {
                    status = try self.codexHookInstallation.uninstall()
                    self.intentStore.setIntent(.uninstalled, for: .codex)
                    self.onStatusMessage?("Removed Open Island Codex hooks.")
                }
                self.codexHookStatus = status
            } catch {
                self.onStatusMessage?("Failed to \(install ? "install" : "remove") Codex hooks: \(error.localizedDescription)")
            }
        }
    }

    func installClaudeHooks() {
        guard let hooksBinaryURL else {
            onStatusMessage?("Build OpenIslandHooks before installing Claude hooks.")
            return
        }
        updateClaudeHooks(hooksBinaryURL: hooksBinaryURL, install: true)
    }

    func uninstallClaudeHooks() {
        updateClaudeHooks(hooksBinaryURL: hooksBinaryURL, install: false)
    }

    private func updateClaudeHooks(hooksBinaryURL: URL?, install: Bool) {
        isClaudeHookSetupBusy = true
        Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.isClaudeHookSetupBusy = false }
            do {
                let status: ClaudeHookInstallationStatus
                if install, let hooksBinaryURL {
                    status = try self.claudeHookInstallation.install(hooksBinaryURL: hooksBinaryURL)
                    self.intentStore.setIntent(.installed, for: .claudeCode)
                    self.onStatusMessage?("Installed Open Island Claude hooks.")
                } else {
                    status = try self.claudeHookInstallation.uninstall()
                    self.intentStore.setIntent(.uninstalled, for: .claudeCode)
                    self.onStatusMessage?("Removed Open Island Claude hooks.")
                }
                self.claudeHookStatus = status
            } catch {
                self.onStatusMessage?("Failed to \(install ? "install" : "remove") Claude hooks: \(error.localizedDescription)")
            }
        }
    }

    func installClaudeUsageBridge() {
        isClaudeUsageSetupBusy = true
        Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.isClaudeUsageSetupBusy = false }
            do {
                self.claudeStatusLineStatus = try self.claudeStatusLineInstallation.install()
                self.intentStore.setIntent(.installed, for: .claudeUsageBridge)
                self.refreshClaudeUsageState()
                self.onStatusMessage?("Installed Claude usage bridge.")
            } catch {
                self.onStatusMessage?("Failed to install Claude usage bridge: \(error.localizedDescription)")
            }
        }
    }

    func uninstallClaudeUsageBridge() {
        isClaudeUsageSetupBusy = true
        Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.isClaudeUsageSetupBusy = false }
            do {
                self.claudeStatusLineStatus = try self.claudeStatusLineInstallation.uninstall()
                self.intentStore.setIntent(.uninstalled, for: .claudeUsageBridge)
                self.refreshClaudeUsageState()
                self.onStatusMessage?("Removed Claude usage bridge.")
            } catch {
                self.onStatusMessage?("Failed to remove Claude usage bridge: \(error.localizedDescription)")
            }
        }
    }

    func refreshClaudeUsageState() {
        do {
            claudeStatusLineStatus = try claudeStatusLineInstallation.status()
            claudeUsageSnapshot = try ClaudeUsageLoader.load()
        } catch {
            onStatusMessage?("Failed to read Claude usage status: \(error.localizedDescription)")
        }
    }

    func refreshCodexUsageState() {
        codexUsageSnapshot = try? CodexUsageLoader.load()
    }

    func startClaudeUsageMonitoringIfNeeded() {
        guard claudeUsageMonitorTask == nil else { return }
        claudeUsageMonitorTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                self?.refreshClaudeUsageState()
                try? await Task.sleep(for: .seconds(30))
            }
        }
    }

    func startCodexUsageMonitoringIfNeeded() {
        guard codexUsageMonitorTask == nil else { return }
        codexUsageMonitorTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                self?.refreshCodexUsageState()
                try? await Task.sleep(for: .seconds(30))
            }
        }
    }

    func installQoderHooks() { markUnsupported(.qoder) }
    func uninstallQoderHooks() { markUnsupported(.qoder) }
    func installQwenCodeHooks() { markUnsupported(.qwenCode) }
    func uninstallQwenCodeHooks() { markUnsupported(.qwenCode) }
    func installFactoryHooks() { markUnsupported(.factory) }
    func uninstallFactoryHooks() { markUnsupported(.factory) }
    func installCodebuddyHooks() { markUnsupported(.codebuddy) }
    func uninstallCodebuddyHooks() { markUnsupported(.codebuddy) }
    func installOpenCodePlugin() { markUnsupported(.openCode) }
    func uninstallOpenCodePlugin() { markUnsupported(.openCode) }
    func installCursorHooks() { markUnsupported(.cursor) }
    func uninstallCursorHooks() { markUnsupported(.cursor) }
    func installGeminiHooks() { markUnsupported(.gemini) }
    func uninstallGeminiHooks() { markUnsupported(.gemini) }
    func installKimiHooks() { markUnsupported(.kimi) }
    func uninstallKimiHooks() { markUnsupported(.kimi) }

    private func markUnsupported(_ agent: AgentIdentifier) {
        intentStore.setIntent(.uninstalled, for: agent)
        onStatusMessage?("This work-safe build only supports Codex and Claude.")
    }
}
