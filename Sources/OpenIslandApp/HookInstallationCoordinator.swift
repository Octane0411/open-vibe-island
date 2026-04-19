import Foundation
import Observation
import OpenIslandCore

@MainActor
@Observable
final class HookInstallationCoordinator {
    var codexHookStatus: CodexHookInstallationStatus?
    var claudeHookStatus: ClaudeHookInstallationStatus?
    var qoderHookStatus: ClaudeHookInstallationStatus?
    var qwenCodeHookStatus: ClaudeHookInstallationStatus?
    var factoryHookStatus: ClaudeHookInstallationStatus?
    var codebuddyHookStatus: ClaudeHookInstallationStatus?
    var openCodePluginStatus: OpenCodePluginInstallationStatus?
    var cursorHookStatus: CursorHookInstallationStatus?
    var geminiHookStatus: GeminiHookInstallationStatus?
    var claudeStatusLineStatus: ClaudeStatusLineInstallationStatus?
    var claudeUsageSnapshot: ClaudeUsageSnapshot?
    var codexUsageSnapshot: CodexUsageSnapshot?
    var hooksBinaryURL: URL?
    var isCodexSetupBusy = false
    var isClaudeHookSetupBusy = false
    var isQoderHookSetupBusy = false
    var isQwenCodeHookSetupBusy = false
    var isFactoryHookSetupBusy = false
    var isCodebuddyHookSetupBusy = false
    var isOpenCodeSetupBusy = false
    var isCursorHookSetupBusy = false
    var isGeminiHookSetupBusy = false
    var isClaudeUsageSetupBusy = false

    @ObservationIgnored
    var onStatusMessage: ((String) -> Void)?

    @ObservationIgnored
    private let codexHookInstallationManager = CodexHookInstallationManager()

    /// Computed so it always reflects the latest `ClaudeConfigDirectory` setting.
    private var claudeHookInstallationManager: ClaudeHookInstallationManager {
        ClaudeHookInstallationManager()
    }

    @ObservationIgnored
    private let qoderHookInstallationManager = ClaudeHookInstallationManager(
        claudeDirectory: FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".qoder", isDirectory: true),
        hookSource: "qoder"
    )

    @ObservationIgnored
    private let qwenCodeHookInstallationManager = ClaudeHookInstallationManager(
        claudeDirectory: FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".qwen", isDirectory: true),
        hookSource: "qwen"
    )

    @ObservationIgnored
    private let factoryHookInstallationManager = ClaudeHookInstallationManager(
        claudeDirectory: FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".factory", isDirectory: true),
        hookSource: "factory"
    )

    @ObservationIgnored
    private let codebuddyHookInstallationManager = ClaudeHookInstallationManager(
        claudeDirectory: FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codebuddy", isDirectory: true),
        hookSource: "codebuddy"
    )

    @ObservationIgnored
    private let openCodePluginInstallationManager = OpenCodePluginInstallationManager()

    @ObservationIgnored
    private let cursorHookInstallationManager = CursorHookInstallationManager()

    @ObservationIgnored
    private let geminiHookInstallationManager = GeminiHookInstallationManager()

    /// Computed so it always reflects the latest `ClaudeConfigDirectory` setting.
    private var claudeStatusLineInstallationManager: ClaudeStatusLineInstallationManager {
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

    // MARK: - Computed display properties

    var codexHooksInstalled: Bool {
        codexHookStatus?.managedHooksPresent == true
    }

    var claudeHooksInstalled: Bool {
        claudeHookStatus?.managedHooksPresent == true
    }

    var qoderHooksInstalled: Bool {
        qoderHookStatus?.managedHooksPresent == true
    }

    var qwenCodeHooksInstalled: Bool {
        qwenCodeHookStatus?.managedHooksPresent == true
    }

    var factoryHooksInstalled: Bool {
        factoryHookStatus?.managedHooksPresent == true
    }

    var codebuddyHooksInstalled: Bool {
        codebuddyHookStatus?.managedHooksPresent == true
    }

    var openCodePluginInstalled: Bool {
        openCodePluginStatus?.isInstalled == true
    }

    var cursorHooksInstalled: Bool {
        cursorHookStatus?.managedHooksPresent == true
    }

    var geminiHooksInstalled: Bool {
        geminiHookStatus?.managedHooksPresent == true
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
            return "Reading \(ClaudeConfigDirectory.resolved().appendingPathComponent("settings.json").path)."
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
            return "Reading \(ClaudeConfigDirectory.resolved().appendingPathComponent("settings.json").path)."
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

    var openCodePluginStatusTitle: String {
        if openCodePluginInstalled {
            return "OpenCode plugin installed"
        }

        return "OpenCode plugin not installed"
    }

    var openCodePluginStatusSummary: String {
        guard let status = openCodePluginStatus else {
            return "Reading ~/.config/opencode state."
        }

        if status.isInstalled {
            return "managed plugin present in \(status.pluginsDirectory.path)"
        }

        if status.pluginFilePresent && !status.pluginRegistered {
            return "plugin file present but not registered in config.json"
        }

        return "no managed OpenCode plugin"
    }

    var cursorHookStatusTitle: String {
        if cursorHooksInstalled {
            return "Cursor hooks installed"
        }

        if hooksBinaryURL == nil {
            return "Hook binary not found"
        }

        return "Cursor hooks not installed"
    }

    var cursorHookStatusSummary: String {
        guard cursorHookStatus != nil else {
            return "Reading ~/.cursor/hooks.json."
        }

        if cursorHooksInstalled {
            return "managed hooks present"
        }

        if hooksBinaryURL == nil {
            return "Build OpenIslandHooks before installing."
        }

        return "no managed Cursor hooks"
    }

    var geminiHookStatusTitle: String {
        guard let status = geminiHookStatus else { return "Gemini hooks loading" }
        return status.managedHooksPresent ? "Gemini hooks installed" : "Gemini hooks not installed"
    }

    var geminiHookStatusSummary: String {
        guard let status = geminiHookStatus else {
            return "Reading ~/.gemini/settings.json."
        }

        if hooksBinaryURL == nil {
            return "Build OpenIslandHooks before installing."
        }

        return status.managedHooksPresent ? "managed hooks present" : "no managed Gemini hooks"
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

    // MARK: - Claude config directory

    /// Updates the custom Claude config directory, cleans up old hooks if present, and refreshes status.
    func updateClaudeConfigDirectory(to newDirectory: URL?) {
        let oldDirectory = ClaudeConfigDirectory.resolved()
        let oldHadHooks = claudeHookStatus?.managedHooksPresent == true

        ClaudeConfigDirectory.customDirectory = newDirectory

        // Refresh status from the new directory
        refreshClaudeHookStatus()
        refreshClaudeUsageState()

        let newPath = ClaudeConfigDirectory.resolved().path
        if oldHadHooks {
            let oldPath = oldDirectory.path
            if oldPath != newPath {
                onStatusMessage?("Claude config directory changed to \(newPath). Hooks in \(oldPath) were not removed — uninstall them manually if no longer needed.")
            }
        } else {
            onStatusMessage?("Claude config directory set to \(newPath).")
        }
    }

    // MARK: - Auto-update hooks binary

    /// Overwrites the installed hooks binary if the app bundle ships a newer version.
    /// Call once at startup after hooksBinaryURL is set.
    func updateHooksBinaryIfNeeded() {
        guard let sourceURL = hooksBinaryURL else { return }

        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let source = sourceURL
                let updated = try await Task.detached(priority: .utility) {
                    try ManagedHooksBinary.updateIfNeeded(from: source)
                }.value
                if updated {
                    self.onStatusMessage?("Hooks binary updated to match the current app version.")
                    self.refreshCodexHookStatus()
                    self.refreshClaudeHookStatus()
                    self.refreshCursorHookStatus()
                }
            } catch {
                self.onStatusMessage?("Failed to update hooks binary: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Health check & auto-repair

    var codexHealthReport: HookHealthReport?
    var claudeHealthReport: HookHealthReport?
    var openCodeHealthReport: HookHealthReport?
    var cursorHealthReport: HookHealthReport?
    var geminiHealthReport: HookHealthReport?


    /// Runs health checks for Claude, Codex and OpenCode hooks.
    func runHealthChecks() {
        Task { @MainActor [weak self] in
            guard let self else { return }

            let binaryURL = self.hooksBinaryURL
            let (claudeReport, codexReport, openCodeReport) = await Task.detached(priority: .utility) {
                let claude = HookHealthCheck.checkClaude(hooksBinaryURL: binaryURL)
                let codex = HookHealthCheck.checkCodex(hooksBinaryURL: binaryURL)
                let openCode = HookHealthCheck.checkOpenCode()
                return (claude, codex, openCode)
            }.value

            self.claudeHealthReport = claudeReport
            self.codexHealthReport = codexReport
            self.openCodeHealthReport = openCodeReport

            if !claudeReport.isHealthy || !codexReport.isHealthy || !openCodeReport.isHealthy {
                let claudeIssueCount = claudeReport.errors.count
                let codexIssueCount = codexReport.errors.count
                let openCodeIssueCount = openCodeReport.errors.count
                self.onStatusMessage?("Hook health check: \(claudeIssueCount) Claude, \(codexIssueCount) Codex, \(openCodeIssueCount) OpenCode issue(s).")
            }
        }
    }

    /// Attempts to auto-repair repairable issues by re-installing hooks.
    /// Returns true if any repairs were attempted.
    @discardableResult
    func repairHooksIfNeeded() async -> Bool {
        var repaired = false

        // Re-run health checks first
        let binaryURL = hooksBinaryURL
        let (claudeReport, codexReport, openCodeReport) = await Task.detached(priority: .utility) {
            let claude = HookHealthCheck.checkClaude(hooksBinaryURL: binaryURL)
            let codex = HookHealthCheck.checkCodex(hooksBinaryURL: binaryURL)
            let openCode = HookHealthCheck.checkOpenCode()
            return (claude, codex, openCode)
        }.value

        claudeHealthReport = claudeReport
        codexHealthReport = codexReport
        openCodeHealthReport = openCodeReport

        // Repair Claude hooks if there are repairable issues
        if !claudeReport.repairableIssues.isEmpty, hooksBinaryURL != nil {
            onStatusMessage?("Repairing Claude hooks: \(claudeReport.repairableIssues.map(\.description).joined(separator: "; "))")
            installClaudeHooks()
            repaired = true
        }

        // Repair Codex hooks if there are repairable issues
        if !codexReport.repairableIssues.isEmpty, hooksBinaryURL != nil {
            onStatusMessage?("Repairing Codex hooks: \(codexReport.repairableIssues.map(\.description).joined(separator: "; "))")
            installCodexHooks()
            repaired = true
        }

        // Repair OpenCode plugin if there are repairable issues
        if !openCodeReport.repairableIssues.isEmpty {
            onStatusMessage?("Repairing OpenCode plugin: \(openCodeReport.repairableIssues.map(\.description).joined(separator: "; "))")
            installOpenCodePlugin()
            repaired = true
        }

        // Refresh health reports after repair
        if repaired {
            try? await Task.sleep(for: .milliseconds(500))
            let (updatedClaude, updatedCodex, updatedOpenCode) = await Task.detached(priority: .utility) {
                let claude = HookHealthCheck.checkClaude(hooksBinaryURL: binaryURL)
                let codex = HookHealthCheck.checkCodex(hooksBinaryURL: binaryURL)
                let openCode = HookHealthCheck.checkOpenCode()
                return (claude, codex, openCode)
            }.value
            claudeHealthReport = updatedClaude
            codexHealthReport = updatedCodex
            openCodeHealthReport = updatedOpenCode

            if updatedClaude.isHealthy && updatedCodex.isHealthy && updatedOpenCode.isHealthy {
                onStatusMessage?("Hook repair completed successfully.")
            } else {
                let remaining = updatedClaude.errors.count + updatedCodex.errors.count + updatedOpenCode.errors.count
                onStatusMessage?("Hook repair finished with \(remaining) remaining issue(s).")
            }
        }

        return repaired
    }

    // MARK: - Refresh

    func refreshCodexHookStatus() {
        Task { [weak self] in
            guard let self else { return }

            do {
                let status = try self.codexHookInstallationManager.status(hooksBinaryURL: self.hooksBinaryURL)
                self.codexHookStatus = status
            } catch {
                self.onStatusMessage?("Failed to read Codex hook status: \(error.localizedDescription)")
            }
        }
    }

    func refreshClaudeHookStatus() {
        Task { [weak self] in
            guard let self else { return }

            do {
                let status = try self.claudeHookInstallationManager.status(hooksBinaryURL: self.hooksBinaryURL)
                self.claudeHookStatus = status
            } catch {
                self.onStatusMessage?("Failed to read Claude hook status: \(error.localizedDescription)")
            }
        }
    }

    func refreshCCForkHookStatuses() {
        refreshCCForkHookStatus(manager: qoderHookInstallationManager, name: "Qoder") { [weak self] in self?.qoderHookStatus = $0 }
        refreshCCForkHookStatus(manager: qwenCodeHookInstallationManager, name: "Qwen Code") { [weak self] in self?.qwenCodeHookStatus = $0 }
        refreshCCForkHookStatus(manager: factoryHookInstallationManager, name: "Factory") { [weak self] in self?.factoryHookStatus = $0 }
        refreshCCForkHookStatus(manager: codebuddyHookInstallationManager, name: "CodeBuddy") { [weak self] in self?.codebuddyHookStatus = $0 }
    }

    private func refreshCCForkHookStatus(
        manager: ClaudeHookInstallationManager,
        name: String,
        apply: @MainActor @escaping (ClaudeHookInstallationStatus) -> Void
    ) {
        Task { [weak self] in
            guard let self else { return }

            do {
                let status = try manager.status(hooksBinaryURL: self.hooksBinaryURL)
                apply(status)
            } catch {
                self.onStatusMessage?("Failed to read \(name) hook status: \(error.localizedDescription)")
            }
        }
    }

    /// Awaitable versions of refresh for use in startup flow to avoid race conditions.
    func refreshAllHookStatusAndWait() async {
        await withTaskGroup(of: Void.self) { group in
            group.addTask { @MainActor [weak self] in
                guard let self else { return }
                do {
                    let status = try self.claudeHookInstallationManager.status(hooksBinaryURL: self.hooksBinaryURL)
                    self.claudeHookStatus = status
                } catch {
                    self.onStatusMessage?("Failed to read Claude hook status: \(error.localizedDescription)")
                }
            }

            group.addTask { @MainActor [weak self] in
                guard let self else { return }
                do {
                    let status = try self.codexHookInstallationManager.status(hooksBinaryURL: self.hooksBinaryURL)
                    self.codexHookStatus = status
                } catch {
                    self.onStatusMessage?("Failed to read Codex hook status: \(error.localizedDescription)")
                }
            }

            group.addTask { @MainActor [weak self] in
                guard let self else { return }
                do {
                    let status = try self.openCodePluginInstallationManager.status()
                    self.openCodePluginStatus = status
                } catch {
                    self.onStatusMessage?("Failed to read OpenCode plugin status: \(error.localizedDescription)")
                }
            }

            group.addTask { @MainActor [weak self] in
                guard let self else { return }
                do {
                    let usageState = try self.readClaudeUsageState(repairManagedBridgeIfNeeded: true)
                    self.claudeStatusLineStatus = usageState.status
                    self.claudeUsageSnapshot = usageState.snapshot
                } catch {
                    self.onStatusMessage?("Failed to read Claude usage state: \(error.localizedDescription)")
                }
            }

            // CC fork agents
            group.addTask { @MainActor [weak self] in
                guard let self else { return }
                for (manager, name, apply) in [
                    (self.qoderHookInstallationManager, "Qoder", { [weak self] (s: ClaudeHookInstallationStatus) in self?.qoderHookStatus = s }),
                    (self.qwenCodeHookInstallationManager, "Qwen Code", { [weak self] (s: ClaudeHookInstallationStatus) in self?.qwenCodeHookStatus = s }),
                    (self.factoryHookInstallationManager, "Factory", { [weak self] (s: ClaudeHookInstallationStatus) in self?.factoryHookStatus = s }),
                    (self.codebuddyHookInstallationManager, "CodeBuddy", { [weak self] (s: ClaudeHookInstallationStatus) in self?.codebuddyHookStatus = s }),
                ] {
                    do {
                        let status = try manager.status(hooksBinaryURL: self.hooksBinaryURL)
                        apply(status)
                    } catch {
                        self.onStatusMessage?("Failed to read \(name) hook status: \(error.localizedDescription)")
                    }
                }
            }

            group.addTask { @MainActor [weak self] in
                guard let self else { return }
                do {
                    let status = try self.geminiHookInstallationManager.status(hooksBinaryURL: self.hooksBinaryURL)
                    self.geminiHookStatus = status
                } catch {
                    self.onStatusMessage?("Failed to read Gemini hook status: \(error.localizedDescription)")
                }
            }
        }
    }

    func refreshOpenCodePluginStatus() {
        Task { [weak self] in
            guard let self else { return }

            do {
                let status = try self.openCodePluginInstallationManager.status()
                self.openCodePluginStatus = status
            } catch {
                self.onStatusMessage?("Failed to read OpenCode plugin status: \(error.localizedDescription)")
            }
        }
    }

    func refreshCursorHookStatus() {
        Task { [weak self] in
            guard let self else { return }

            do {
                let status = try self.cursorHookInstallationManager.status(hooksBinaryURL: self.hooksBinaryURL)
                self.cursorHookStatus = status
            } catch {
                self.onStatusMessage?("Failed to read Cursor hook status: \(error.localizedDescription)")
            }
        }
    }

    func refreshGeminiHookStatus() {
        Task { [weak self] in
            guard let self else { return }

            do {
                let status = try self.geminiHookInstallationManager.status(hooksBinaryURL: self.hooksBinaryURL)
                self.geminiHookStatus = status
            } catch {
                self.onStatusMessage?("Failed to read Gemini hook status: \(error.localizedDescription)")
            }
        }
    }

    func refreshClaudeUsageState() {
        let manager = claudeStatusLineInstallationManager
        Task { [weak self] in
            guard let self else { return }

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
                    self.onStatusMessage?("Recovered the Claude usage bridge after repairing a missing managed script.")
                }
            } catch {
                self.onStatusMessage?("Failed to read Claude usage state: \(error.localizedDescription)")
            }
        }
    }

    func refreshCodexUsageState() {
        Task { [weak self] in
            guard let self else { return }

            do {
                let snapshot = try await Task.detached(priority: .utility) {
                    try CodexUsageLoader.load()
                }.value
                self.codexUsageSnapshot = snapshot
            } catch {
                self.onStatusMessage?("Failed to read Codex usage state: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Install / uninstall

    func installCodexHooks() {
        guard let hooksBinaryURL else {
            onStatusMessage?("Could not find a local OpenIslandHooks binary. Build the package first.")
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
            onStatusMessage?("Could not find a local OpenIslandHooks binary. Build the package first.")
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

    func installQoderHooks() {
        updateCCForkHooks(manager: qoderHookInstallationManager, name: "Qoder", isBusySetter: { [weak self] in self?.isQoderHookSetupBusy = $0 }, statusSetter: { [weak self] in self?.qoderHookStatus = $0 }, install: true)
    }

    func uninstallQoderHooks() {
        updateCCForkHooks(manager: qoderHookInstallationManager, name: "Qoder", isBusySetter: { [weak self] in self?.isQoderHookSetupBusy = $0 }, statusSetter: { [weak self] in self?.qoderHookStatus = $0 }, install: false)
    }

    func installQwenCodeHooks() {
        updateCCForkHooks(manager: qwenCodeHookInstallationManager, name: "Qwen Code", isBusySetter: { [weak self] in self?.isQwenCodeHookSetupBusy = $0 }, statusSetter: { [weak self] in self?.qwenCodeHookStatus = $0 }, install: true)
    }

    func uninstallQwenCodeHooks() {
        updateCCForkHooks(manager: qwenCodeHookInstallationManager, name: "Qwen Code", isBusySetter: { [weak self] in self?.isQwenCodeHookSetupBusy = $0 }, statusSetter: { [weak self] in self?.qwenCodeHookStatus = $0 }, install: false)
    }

    func installFactoryHooks() {
        updateCCForkHooks(manager: factoryHookInstallationManager, name: "Factory", isBusySetter: { [weak self] in self?.isFactoryHookSetupBusy = $0 }, statusSetter: { [weak self] in self?.factoryHookStatus = $0 }, install: true)
    }

    func uninstallFactoryHooks() {
        updateCCForkHooks(manager: factoryHookInstallationManager, name: "Factory", isBusySetter: { [weak self] in self?.isFactoryHookSetupBusy = $0 }, statusSetter: { [weak self] in self?.factoryHookStatus = $0 }, install: false)
    }

    func installCodebuddyHooks() {
        updateCCForkHooks(manager: codebuddyHookInstallationManager, name: "CodeBuddy", isBusySetter: { [weak self] in self?.isCodebuddyHookSetupBusy = $0 }, statusSetter: { [weak self] in self?.codebuddyHookStatus = $0 }, install: true)
    }

    func uninstallCodebuddyHooks() {
        updateCCForkHooks(manager: codebuddyHookInstallationManager, name: "CodeBuddy", isBusySetter: { [weak self] in self?.isCodebuddyHookSetupBusy = $0 }, statusSetter: { [weak self] in self?.codebuddyHookStatus = $0 }, install: false)
    }

    private func updateCCForkHooks(
        manager: ClaudeHookInstallationManager,
        name: String,
        isBusySetter: @MainActor @escaping (Bool) -> Void,
        statusSetter: @MainActor @escaping (ClaudeHookInstallationStatus) -> Void,
        install: Bool
    ) {
        guard let hooksBinaryURL else {
            onStatusMessage?("Could not find a local OpenIslandHooks binary. Build the package first.")
            return
        }

        isBusySetter(true)
        onStatusMessage?(install ? "Installing \(name) hooks." : "Removing \(name) hooks.")

        Task { [weak self] in
            guard let self else { return }

            defer { isBusySetter(false) }

            do {
                let status = install
                    ? try manager.install(hooksBinaryURL: hooksBinaryURL)
                    : try manager.uninstall()
                statusSetter(status)
                if status.managedHooksPresent {
                    self.onStatusMessage?("\(name) hooks are installed and ready.")
                } else {
                    self.onStatusMessage?("\(name) hooks are not installed.")
                }
            } catch {
                self.onStatusMessage?("\(name) hook update failed: \(error.localizedDescription)")
            }
        }
    }

    func installOpenCodePlugin() {
        guard let pluginData = loadBundledOpenCodePlugin() else {
            onStatusMessage?("Could not find the bundled OpenCode plugin resource.")
            return
        }

        isOpenCodeSetupBusy = true
        onStatusMessage?("Installing OpenCode plugin.")

        Task { [weak self] in
            guard let self else { return }

            defer { self.isOpenCodeSetupBusy = false }

            do {
                let status = try self.openCodePluginInstallationManager.install(pluginSourceData: pluginData)
                self.openCodePluginStatus = status
                if status.isInstalled {
                    self.onStatusMessage?("OpenCode plugin is installed. Restart OpenCode to activate.")
                } else {
                    self.onStatusMessage?("OpenCode plugin installation incomplete.")
                }
            } catch {
                self.onStatusMessage?("OpenCode plugin install failed: \(error.localizedDescription)")
            }
        }
    }

    func uninstallOpenCodePlugin() {
        isOpenCodeSetupBusy = true
        onStatusMessage?("Removing OpenCode plugin.")

        Task { [weak self] in
            guard let self else { return }

            defer { self.isOpenCodeSetupBusy = false }

            do {
                let status = try self.openCodePluginInstallationManager.uninstall()
                self.openCodePluginStatus = status
                self.onStatusMessage?("OpenCode plugin removed.")
            } catch {
                self.onStatusMessage?("OpenCode plugin removal failed: \(error.localizedDescription)")
            }
        }
    }

    func installCursorHooks() {
        guard let hooksBinaryURL else {
            onStatusMessage?("Could not find a local OpenIslandHooks binary. Build the package first.")
            return
        }

        updateCursorHooks(userMessage: "Installing Cursor hooks.") { manager in
            try manager.install(hooksBinaryURL: hooksBinaryURL)
        }
    }

    func uninstallCursorHooks() {
        updateCursorHooks(userMessage: "Removing Cursor hooks.") { manager in
            try manager.uninstall()
        }
    }

    func installGeminiHooks() {
        guard let hooksBinaryURL else {
            onStatusMessage?("Could not find a local OpenIslandHooks binary. Build the package first.")
            return
        }

        updateGeminiHooks(userMessage: "Installing Gemini hooks.") { manager in
            try manager.install(hooksBinaryURL: hooksBinaryURL)
        }
    }

    func uninstallGeminiHooks() {
        updateGeminiHooks(userMessage: "Removing Gemini hooks.") { manager in
            try manager.uninstall()
        }
    }

    func installClaudeUsageBridge() {
        updateClaudeUsageBridge(userMessage: "Installing Claude usage bridge.") { manager in
            do {
                return try manager.install()
            } catch ClaudeStatusLineInstallationError.existingStatusLineConflict {
                // User already has a custom statusLine (e.g. claude-hud). Install as a
                // wrapper so their script keeps running and we still get rate_limits.
                return try manager.installAsWrapper()
            }
        }
    }

    func uninstallClaudeUsageBridge() {
        updateClaudeUsageBridge(userMessage: "Removing Claude usage bridge.") { manager in
            try manager.uninstall()
        }
    }

    // MARK: - Monitoring

    func startClaudeUsageMonitoringIfNeeded() {
        guard claudeUsageMonitorTask == nil else { return }

        claudeUsageMonitorTask = Task { @MainActor [weak self] in
            guard let self else { return }

            while !Task.isCancelled {
                self.refreshClaudeUsageState()
                try? await Task.sleep(for: .seconds(5))
            }
        }
    }

    func startCodexUsageMonitoringIfNeeded() {
        guard codexUsageMonitorTask == nil else { return }

        codexUsageMonitorTask = Task { @MainActor [weak self] in
            guard let self else { return }

            while !Task.isCancelled {
                self.refreshCodexUsageState()
                try? await Task.sleep(for: .seconds(120))
            }
        }
    }

    // MARK: - Internal: readClaudeUsageState

    nonisolated func readClaudeUsageState(
        repairManagedBridgeIfNeeded: Bool
    ) throws -> (
        status: ClaudeStatusLineInstallationStatus,
        snapshot: ClaudeUsageSnapshot?,
        repairedManagedBridge: Bool
    ) {
        let manager = ClaudeStatusLineInstallationManager()
        var status = try manager.status()
        var repairedManagedBridge = false

        if repairManagedBridgeIfNeeded && status.managedStatusLineNeedsRepair {
            status = try manager.install()
            repairedManagedBridge = true
        }

        let snapshot = try ClaudeUsageLoader.load()
        return (status, snapshot, repairedManagedBridge)
    }

    // MARK: - Private helpers

    private func updateCodexHooks(
        userMessage: String,
        operation: @escaping (CodexHookInstallationManager) throws -> CodexHookInstallationStatus
    ) {
        isCodexSetupBusy = true
        onStatusMessage?(userMessage)

        Task { [weak self] in
            guard let self else { return }

            defer { self.isCodexSetupBusy = false }

            do {
                let status = try operation(self.codexHookInstallationManager)
                self.codexHookStatus = status
                if status.managedHooksPresent {
                    self.onStatusMessage?("Codex hooks are installed and ready.")
                } else {
                    self.onStatusMessage?("Codex hooks are not installed.")
                }
            } catch {
                self.onStatusMessage?("Codex hook update failed: \(error.localizedDescription)")
            }
        }
    }

    private func updateClaudeHooks(
        userMessage: String,
        operation: @escaping (ClaudeHookInstallationManager) throws -> ClaudeHookInstallationStatus
    ) {
        isClaudeHookSetupBusy = true
        onStatusMessage?(userMessage)

        Task { [weak self] in
            guard let self else { return }

            defer { self.isClaudeHookSetupBusy = false }

            do {
                let status = try operation(self.claudeHookInstallationManager)
                self.claudeHookStatus = status
                if status.managedHooksPresent {
                    self.onStatusMessage?(status.hasClaudeIslandHooks
                        ? "Claude hooks are installed. claude-island hooks are also still present."
                        : "Claude hooks are installed and ready.")
                } else {
                    self.onStatusMessage?("Claude hooks are not installed.")
                }
            } catch {
                self.onStatusMessage?("Claude hook update failed: \(error.localizedDescription)")
            }
        }
    }

    private func updateCursorHooks(
        userMessage: String,
        operation: @escaping (CursorHookInstallationManager) throws -> CursorHookInstallationStatus
    ) {
        isCursorHookSetupBusy = true
        onStatusMessage?(userMessage)

        Task { [weak self] in
            guard let self else { return }

            defer { self.isCursorHookSetupBusy = false }

            do {
                let status = try operation(self.cursorHookInstallationManager)
                self.cursorHookStatus = status
                if status.managedHooksPresent {
                    self.onStatusMessage?("Cursor hooks are installed and ready.")
                } else {
                    self.onStatusMessage?("Cursor hooks are not installed.")
                }
            } catch {
                self.onStatusMessage?("Cursor hook update failed: \(error.localizedDescription)")
            }
        }
    }

    private func updateGeminiHooks(
        userMessage: String,
        operation: @escaping (GeminiHookInstallationManager) throws -> GeminiHookInstallationStatus
    ) {
        isGeminiHookSetupBusy = true
        onStatusMessage?(userMessage)

        Task { [weak self] in
            guard let self else { return }

            defer { self.isGeminiHookSetupBusy = false }

            do {
                let status = try operation(self.geminiHookInstallationManager)
                self.geminiHookStatus = status
                if status.managedHooksPresent {
                    self.onStatusMessage?("Gemini hooks are installed and ready.")
                } else {
                    self.onStatusMessage?("Gemini hooks are not installed.")
                }
            } catch {
                self.onStatusMessage?("Gemini hook update failed: \(error.localizedDescription)")
            }
        }
    }

    private func updateClaudeUsageBridge(
        userMessage: String,
        operation: @escaping (ClaudeStatusLineInstallationManager) throws -> ClaudeStatusLineInstallationStatus
    ) {
        isClaudeUsageSetupBusy = true
        onStatusMessage?(userMessage)

        Task { [weak self] in
            guard let self else { return }

            defer { self.isClaudeUsageSetupBusy = false }

            do {
                let status = try operation(self.claudeStatusLineInstallationManager)
                self.claudeStatusLineStatus = status
                self.claudeUsageSnapshot = try ClaudeUsageLoader.load()
                if status.managedStatusLineInstalled {
                    if status.managedStatusLineIsWrapper {
                        self.onStatusMessage?("Claude usage bridge installed in wrapper mode — your existing statusLine is preserved. Start a Claude Code turn to refresh cached rate limits.")
                    } else {
                        self.onStatusMessage?("Claude usage bridge is installed. Start a Claude Code turn to refresh cached rate limits.")
                    }
                } else {
                    self.onStatusMessage?("Claude usage bridge is not installed.")
                }
            } catch {
                self.onStatusMessage?("Claude usage bridge update failed: \(error.localizedDescription)")
            }
        }
    }

    private func loadBundledOpenCodePlugin() -> Data? {
        // Use appResources which searches both Contents/Resources/ and .app root
        if let url = Bundle.appResources.url(forResource: "open-island-opencode", withExtension: "js") {
            return try? Data(contentsOf: url)
        }

        // Fallback: Bundle.main for Xcode builds
        if let url = Bundle.main.url(forResource: "open-island-opencode", withExtension: "js") {
            return try? Data(contentsOf: url)
        }

        return nil
    }
}
