import SwiftUI
import OpenIslandCore

// MARK: - Settings tabs

enum SettingsTab: String, CaseIterable, Identifiable {
    case general
    case setup
    case display
    case sound
    case shortcuts
    case lab
    case about

    var id: String { rawValue }

    func label(_ lang: LanguageManager) -> String {
        switch self {
        case .general:   lang.t("settings.tab.general")
        case .setup:     lang.t("settings.tab.setup")
        case .display:   lang.t("settings.tab.display")
        case .sound:     lang.t("settings.tab.sound")
        case .shortcuts: lang.t("settings.tab.shortcuts")
        case .lab:       lang.t("settings.tab.lab")
        case .about:     lang.t("settings.tab.about")
        }
    }

    var icon: String {
        switch self {
        case .general:   "gearshape.fill"
        case .setup:     "arrow.down.circle.fill"
        case .display:   "textformat.size"
        case .sound:     "speaker.wave.2.fill"
        case .shortcuts: "keyboard.fill"
        case .lab:       "flask.fill"
        case .about:     "info.circle.fill"
        }
    }

    var iconColor: Color {
        switch self {
        case .general:   .gray
        case .setup:     .orange
        case .display:   .blue
        case .sound:     .green
        case .shortcuts: .gray
        case .lab:       .pink
        case .about:     .blue
        }
    }

    var section: SettingsSection {
        switch self {
        case .general, .setup, .display, .sound: .system
        case .shortcuts, .lab:                   .advanced
        case .about:                             .app
        }
    }
}

enum SettingsSection: String, CaseIterable {
    case system
    case advanced
    case app

    func header(_ lang: LanguageManager) -> String {
        switch self {
        case .system:   lang.t("settings.section.system")
        case .advanced: lang.t("settings.section.advanced")
        case .app:      "Open Island"
        }
    }

    var tabs: [SettingsTab] {
        SettingsTab.allCases.filter { $0.section == self }
    }
}

// MARK: - Root settings view

struct SettingsView: View {
    var model: AppModel
    @State private var selectedTab: SettingsTab = .general

    private var lang: LanguageManager { model.lang }

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 240)
        } detail: {
            detailView
        }
        .frame(minWidth: 680, minHeight: 480)
        .frame(width: 780, height: 560)
        .preferredColorScheme(.dark)
    }

    // MARK: Sidebar

    @ViewBuilder
    private var sidebar: some View {
        List(selection: $selectedTab) {
            ForEach(SettingsSection.allCases, id: \.self) { section in
                Section(section.header(lang)) {
                    ForEach(section.tabs) { tab in
                        Label {
                            Text(tab.label(lang))
                        } icon: {
                            Image(systemName: tab.icon)
                                .foregroundStyle(tab.iconColor)
                        }
                        .tag(tab)
                    }
                }
            }
        }
        .listStyle(.sidebar)
    }

    // MARK: Detail

    @ViewBuilder
    private var detailView: some View {
        ZStack(alignment: .topTrailing) {
            switch selectedTab {
            case .general:
                GeneralSettingsPane(model: model)
            case .setup:
                SetupSettingsPane(model: model)
            case .display:
                DisplaySettingsPane(model: model)
            case .sound:
                SoundSettingsPane(model: model)
            case .shortcuts:
                PlaceholderSettingsPane(model: model, titleKey: "settings.tab.shortcuts", subtitleKey: "settings.shortcuts.comingSoon")
            case .lab:
                PlaceholderSettingsPane(model: model, titleKey: "settings.tab.lab", subtitleKey: "settings.lab.comingSoon")
            case .about:
                AboutSettingsPane(model: model)
            }

            if model.updateChecker.hasUpdate, let version = model.updateChecker.latestVersion {
                UpdateBanner(version: version, lang: lang) {
                    model.updateChecker.checkForUpdates()
                }
                .padding(.top, 8)
                .padding(.trailing, 16)
            }
        }
    }
}

// MARK: - General

struct GeneralSettingsPane: View {
    var model: AppModel

    @State private var launchAtLogin = false

    private var lang: LanguageManager { model.lang }

    var body: some View {
        Form {
            Section(lang.t("settings.section.system")) {
                Toggle(lang.t("settings.general.launchAtLogin"), isOn: $launchAtLogin)

                Picker(lang.t("settings.general.monitor"), selection: Binding(
                    get: { model.overlayDisplaySelectionID },
                    set: { model.overlayDisplaySelectionID = $0 }
                )) {
                    Text(lang.t("settings.general.automatic")).tag(OverlayDisplayOption.automaticID)
                    ForEach(model.overlayDisplayOptions) { option in
                        Text(option.title).tag(option.id)
                    }
                }
            }

            Section(lang.t("settings.general.language")) {
                Picker(lang.t("settings.general.language"), selection: Binding(
                    get: { lang.language },
                    set: { lang.language = $0 }
                )) {
                    Text(lang.t("settings.general.languageSystem")).tag(LanguageManager.AppLanguage.system)
                    Text(lang.t("settings.general.languageEnglish")).tag(LanguageManager.AppLanguage.en)
                    Text(lang.t("settings.general.languageChinese")).tag(LanguageManager.AppLanguage.zhHans)
                }
            }

            Section(lang.t("settings.general.behavior")) {
                Toggle(lang.t("settings.general.autoCollapse"), isOn: .constant(true))
                Toggle(lang.t("settings.general.showDockIcon"), isOn: Binding(
                    get: { model.showDockIcon },
                    set: { model.showDockIcon = $0 }
                ))
            }

        }
        .formStyle(.grouped)
        .navigationTitle(lang.t("settings.tab.general"))
    }
}

// MARK: - Display

struct DisplaySettingsPane: View {
    var model: AppModel

    private var lang: LanguageManager { model.lang }

    var body: some View {
        Form {
            Section(lang.t("settings.display.monitor")) {
                Picker(lang.t("settings.display.position"), selection: Binding(
                    get: { model.overlayDisplaySelectionID },
                    set: { model.overlayDisplaySelectionID = $0 }
                )) {
                    Text(lang.t("settings.general.automatic")).tag(OverlayDisplayOption.automaticID)
                    ForEach(model.overlayDisplayOptions) { option in
                        Text(option.title).tag(option.id)
                    }
                }
            }

            if let diag = model.overlayPlacementDiagnostics {
                Section(lang.t("settings.display.diagnostics")) {
                    LabeledContent(lang.t("settings.display.currentScreen"), value: diag.targetScreenName)
                    LabeledContent(lang.t("settings.display.layoutMode"), value: diag.modeDescription)
                }
            }

            Section(lang.t("settings.display.avatar")) {
                HStack(spacing: 16) {
                    OpenIslandBrandMark(
                        size: 56,
                        style: .duotone,
                        customAvatarImage: model.customAvatarImage
                    )
                    .frame(width: 56, height: 56)

                    VStack(alignment: .leading, spacing: 6) {
                        Text(lang.t("settings.display.avatarHelp"))
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)

                HStack {
                    Button(lang.t("settings.display.uploadAvatar")) {
                        model.importCustomAvatar()
                    }

                    Button(lang.t("settings.display.removeAvatar")) {
                        model.removeCustomAvatar()
                    }
                    .disabled(model.customAvatarImage == nil)
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle(lang.t("settings.tab.display"))
    }
}

// MARK: - Sound

struct SoundSettingsPane: View {
    var model: AppModel

    private var lang: LanguageManager { model.lang }

    private var availableSounds: [String] {
        NotificationSoundService.availableSounds()
    }

    var body: some View {
        Form {
            Section(lang.t("settings.sound.notifications")) {
                Toggle(lang.t("settings.sound.mute"), isOn: Binding(
                    get: { model.isSoundMuted },
                    set: { _ in model.toggleSoundMuted() }
                ))
            }

            Section(lang.t("settings.sound.selectSound")) {
                List(availableSounds, id: \.self) { name in
                    Button {
                        model.selectedSoundName = name
                        NotificationSoundService.play(name)
                    } label: {
                        HStack {
                            Text(name)
                                .foregroundStyle(.primary)
                            Spacer()
                            if name == model.selectedSoundName {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.blue)
                                    .fontWeight(.semibold)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle(lang.t("settings.tab.sound"))
    }
}

// MARK: - About

struct AboutSettingsPane: View {
    var model: AppModel

    private var lang: LanguageManager { model.lang }

    var body: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "island")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text(lang.t("app.name"))
                .font(.title.bold())
            Text(lang.t("app.description"))
                .foregroundStyle(.secondary)
            if let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String {
                Text(lang.t("settings.about.version", version))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            Button(lang.t("settings.about.checkForUpdates")) {
                model.updateChecker.checkForUpdates()
            }
            .disabled(!model.updateChecker.canCheckForUpdates)
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .navigationTitle(lang.t("settings.tab.about"))
    }
}

// MARK: - Setup

struct SetupSettingsPane: View {
    var model: AppModel

    @State private var confirmingUninstallClaude = false
    @State private var confirmingUninstallCodex = false
    @State private var confirmingUninstallOpenCode = false
    @State private var confirmingUninstallQoder = false
    @State private var confirmingUninstallFactory = false
    @State private var confirmingUninstallCodebuddy = false

    private var lang: LanguageManager { model.lang }

    var body: some View {
        Form {
            Section(lang.t("setup.section.hooks")) {
                hookRow(
                    name: "Claude Code",
                    installed: model.claudeHooksInstalled,
                    busy: model.isClaudeHookSetupBusy,
                    installAction: { model.installClaudeHooks() },
                    uninstallAction: { confirmingUninstallClaude = true }
                )
                .alert(lang.t("settings.general.uninstallConfirmTitle"), isPresented: $confirmingUninstallClaude) {
                    Button(lang.t("settings.general.uninstallConfirmAction"), role: .destructive) {
                        model.uninstallClaudeHooks()
                    }
                    Button(lang.t("settings.general.cancel"), role: .cancel) {}
                } message: {
                    Text(lang.t("settings.general.uninstallConfirmMessage.claude"))
                }

                hookRow(
                    name: "Codex",
                    installed: model.codexHooksInstalled,
                    busy: model.isCodexSetupBusy,
                    installAction: { model.installCodexHooks() },
                    uninstallAction: { confirmingUninstallCodex = true }
                )
                .alert(lang.t("settings.general.uninstallConfirmTitle"), isPresented: $confirmingUninstallCodex) {
                    Button(lang.t("settings.general.uninstallConfirmAction"), role: .destructive) {
                        model.uninstallCodexHooks()
                    }
                    Button(lang.t("settings.general.cancel"), role: .cancel) {}
                } message: {
                    Text(lang.t("settings.general.uninstallConfirmMessage.codex"))
                }

                hookRow(
                    name: "OpenCode",
                    installed: model.openCodePluginInstalled,
                    busy: model.isOpenCodeSetupBusy,
                    requiresBinary: false,
                    installAction: { model.installOpenCodePlugin() },
                    uninstallAction: { confirmingUninstallOpenCode = true }
                )
                .alert(lang.t("settings.general.uninstallConfirmTitle"), isPresented: $confirmingUninstallOpenCode) {
                    Button(lang.t("settings.general.uninstallConfirmAction"), role: .destructive) {
                        model.uninstallOpenCodePlugin()
                    }
                    Button(lang.t("settings.general.cancel"), role: .cancel) {}
                } message: {
                    Text("This will remove the Open Island plugin from ~/.config/opencode/plugins/.")
                }

                hookRow(
                    name: "Qoder",
                    installed: model.qoderHooksInstalled,
                    busy: model.isQoderHookSetupBusy,
                    installAction: { model.installQoderHooks() },
                    uninstallAction: { confirmingUninstallQoder = true }
                )
                .alert(lang.t("settings.general.uninstallConfirmTitle"), isPresented: $confirmingUninstallQoder) {
                    Button(lang.t("settings.general.uninstallConfirmAction"), role: .destructive) {
                        model.uninstallQoderHooks()
                    }
                    Button(lang.t("settings.general.cancel"), role: .cancel) {}
                } message: {
                    Text("This will remove Open Island hooks from ~/.qoder/settings.json.")
                }

                hookRow(
                    name: "Factory",
                    installed: model.factoryHooksInstalled,
                    busy: model.isFactoryHookSetupBusy,
                    installAction: { model.installFactoryHooks() },
                    uninstallAction: { confirmingUninstallFactory = true }
                )
                .alert(lang.t("settings.general.uninstallConfirmTitle"), isPresented: $confirmingUninstallFactory) {
                    Button(lang.t("settings.general.uninstallConfirmAction"), role: .destructive) {
                        model.uninstallFactoryHooks()
                    }
                    Button(lang.t("settings.general.cancel"), role: .cancel) {}
                } message: {
                    Text("This will remove Open Island hooks from ~/.factory/settings.json.")
                }

                hookRow(
                    name: "CodeBuddy",
                    installed: model.codebuddyHooksInstalled,
                    busy: model.isCodebuddyHookSetupBusy,
                    installAction: { model.installCodebuddyHooks() },
                    uninstallAction: { confirmingUninstallCodebuddy = true }
                )
                .alert(lang.t("settings.general.uninstallConfirmTitle"), isPresented: $confirmingUninstallCodebuddy) {
                    Button(lang.t("settings.general.uninstallConfirmAction"), role: .destructive) {
                        model.uninstallCodebuddyHooks()
                    }
                    Button(lang.t("settings.general.cancel"), role: .cancel) {}
                } message: {
                    Text("This will remove Open Island hooks from ~/.codebuddy/settings.json.")
                }
            }

            Section {
                HStack {
                    Label(lang.t("setup.usageBridge"), systemImage: "chart.bar")
                    Spacer()
                    if model.claudeUsageInstalled {
                        HStack(spacing: 4) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                            Text(lang.t("setup.usageBridgeReady"))
                                .foregroundStyle(.secondary)
                        }
                    } else if model.isClaudeUsageSetupBusy {
                        ProgressView().controlSize(.small)
                    } else {
                        Button(lang.t("settings.general.install")) {
                            model.installClaudeUsageBridge()
                        }
                    }
                }
            } header: {
                HStack(spacing: 4) {
                    Text(lang.t("setup.section.usage"))
                    Text(lang.t("setup.optional"))
                        .foregroundStyle(.tertiary)
                }
            }

            Section(lang.t("setup.section.permissions")) {
                HStack(alignment: .top) {
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(lang.t("setup.permissionsTitle"))
                            Text(lang.t("setup.permissionsDesc"))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "lock.shield")
                    }
                    Spacer()
                }
            }

            hookDiagnosticsSection

            RemoteConnectionSection(model: model)

            Section {
                Button(lang.t("setup.installAll")) {
                    if !model.claudeHooksInstalled { model.installClaudeHooks() }
                    if !model.codexHooksInstalled { model.installCodexHooks() }
                    if !model.openCodePluginInstalled { model.installOpenCodePlugin() }
                    if !model.qoderHooksInstalled { model.installQoderHooks() }
                    if !model.factoryHooksInstalled { model.installFactoryHooks() }
                    if !model.codebuddyHooksInstalled { model.installCodebuddyHooks() }
                    if !model.claudeUsageInstalled { model.installClaudeUsageBridge() }
                }
                .disabled(model.hooksBinaryURL == nil || allReady)
                .frame(maxWidth: .infinity, alignment: .center)
            }
        }
        .formStyle(.grouped)
        .navigationTitle(lang.t("settings.tab.setup"))
    }

    private var allReady: Bool {
        model.claudeHooksInstalled && model.codexHooksInstalled && model.openCodePluginInstalled
            && model.qoderHooksInstalled && model.factoryHooksInstalled && model.codebuddyHooksInstalled
            && model.claudeUsageInstalled
    }

    private var hasErrors: Bool {
        let claudeErrors = model.claudeHealthReport?.errors.count ?? 0
        let codexErrors = model.codexHealthReport?.errors.count ?? 0
        return claudeErrors + codexErrors > 0
    }

    private var hasRepairableIssues: Bool {
        let claude = model.claudeHealthReport?.repairableIssues.isEmpty == false
        let codex = model.codexHealthReport?.repairableIssues.isEmpty == false
        return claude || codex
    }

    private var hasNotices: Bool {
        let claude = model.claudeHealthReport?.notices.isEmpty == false
        let codex = model.codexHealthReport?.notices.isEmpty == false
        return claude || codex
    }

    @ViewBuilder
    private var hookDiagnosticsSection: some View {
        Section {
            if let claudeReport = model.claudeHealthReport, !claudeReport.issues.isEmpty {
                issueList(report: claudeReport)
            }
            if let codexReport = model.codexHealthReport, !codexReport.issues.isEmpty {
                issueList(report: codexReport)
            }

            if model.claudeHealthReport == nil && model.codexHealthReport == nil {
                HStack {
                    Text(lang.t("setup.diagnostics.notRun"))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button(lang.t("setup.diagnostics.runCheck")) {
                        model.runHealthChecks()
                    }
                }
            } else if !hasErrors {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text(lang.t("setup.diagnostics.allHealthy"))
                    Spacer()
                    Button(lang.t("setup.diagnostics.recheck")) {
                        model.runHealthChecks()
                    }
                    .font(.caption)
                }
            } else {
                HStack(spacing: 10) {
                    Button(lang.t("setup.diagnostics.recheck")) {
                        model.runHealthChecks()
                    }

                    if hasRepairableIssues {
                        Button(lang.t("setup.diagnostics.repair")) {
                            model.repairHooks()
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
            }
        } header: {
            HStack(spacing: 4) {
                Text(lang.t("setup.section.diagnostics"))
                if hasErrors {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .font(.caption2)
                }
            }
        }
    }

    @ViewBuilder
    private func issueList(report: HookHealthReport) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(report.agent == "claude" ? "Claude Code" : "Codex")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)

            ForEach(Array(report.issues.enumerated()), id: \.offset) { _, issue in
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: issueIcon(for: issue))
                        .font(.caption2)
                        .foregroundStyle(issueColor(for: issue))
                        .frame(width: 14)

                    Text(issue.description)
                        .font(.caption)
                        .foregroundStyle(issue.severity == .info ? .secondary : .primary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if let binaryPath = report.binaryPath {
                Text("Binary: \(binaryPath)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private func issueIcon(for issue: HookHealthReport.Issue) -> String {
        switch issue.severity {
        case .info: "info.circle.fill"
        case .error: issue.isAutoRepairable ? "wrench.fill" : "exclamationmark.triangle.fill"
        }
    }

    private func issueColor(for issue: HookHealthReport.Issue) -> Color {
        switch issue.severity {
        case .info: .blue
        case .error: issue.isAutoRepairable ? .orange : .red
        }
    }

    @ViewBuilder
    private func hookRow(
        name: String,
        installed: Bool,
        busy: Bool,
        requiresBinary: Bool = true,
        installAction: @escaping () -> Void,
        uninstallAction: @escaping () -> Void
    ) -> some View {
        HStack {
            Label(name, systemImage: "terminal")
            Spacer()
            if installed {
                HStack(spacing: 8) {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Text(lang.t("settings.general.activated"))
                            .foregroundStyle(.secondary)
                    }
                    Button(lang.t("settings.general.uninstall")) {
                        uninstallAction()
                    }
                    .foregroundStyle(.red)
                    .font(.caption)
                }
            } else if busy {
                ProgressView().controlSize(.small)
            } else {
                Button(lang.t("settings.general.install")) {
                    installAction()
                }
                .disabled(requiresBinary && model.hooksBinaryURL == nil)
            }
        }
    }
}

// MARK: - Placeholder

struct PlaceholderSettingsPane: View {
    var model: AppModel
    let titleKey: String
    let subtitleKey: String

    private var lang: LanguageManager { model.lang }

    var body: some View {
        VStack(spacing: 12) {
            Spacer()
            Text(lang.t(subtitleKey))
                .foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .navigationTitle(lang.t(titleKey))
    }
}

// MARK: - Remote Connection

struct RemoteConnectionSection: View {
    var model: AppModel

    @State private var copiedCommand: String?

    private var remoteSessionCount: Int {
        model.state.sessions.filter(\.isRemote).count
    }

    private var socketName: String {
        "open-island-\(getuid()).sock"
    }

    private var setupCommand: String {
        "./scripts/remote-setup.sh user@host"
    }

    private var sshCommand: String {
        "ssh -R /tmp/\(socketName):/tmp/\(socketName) user@host"
    }

    private var sshConfigSnippet: String {
        """
        Host myserver
            RemoteForward /tmp/\(socketName) /tmp/\(socketName)
        """
    }

    var body: some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                // Status
                HStack {
                    Label("SSH Remote", systemImage: "network")
                    Spacer()
                    if remoteSessionCount > 0 {
                        HStack(spacing: 4) {
                            Circle()
                                .fill(.green)
                                .frame(width: 7, height: 7)
                            Text("\(remoteSessionCount) active")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        Text("No remote sessions")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }

                Text("Monitor Claude Code running on remote servers via SSH.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                // Step 1
                remoteSetupStep(
                    number: "1",
                    title: "Deploy hooks to remote server",
                    description: "Run from the Open Island repo directory:",
                    command: setupCommand
                )

                // Step 2
                remoteSetupStep(
                    number: "2",
                    title: "Connect with socket forwarding",
                    description: "Add to ~/.ssh/config (recommended):",
                    command: sshConfigSnippet,
                    multiline: true
                )

                // Step 2 alternative
                VStack(alignment: .leading, spacing: 4) {
                    Text("Or connect directly:")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.tertiary)
                    copyableCommand(sshCommand)
                }

                // Tip
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "info.circle")
                        .font(.system(size: 10))
                        .foregroundStyle(.blue.opacity(0.8))
                        .padding(.top, 1)
                    Text("The remote sshd needs `StreamLocalBindUnlink yes` in /etc/ssh/sshd_config for reliable reconnects.")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                }
            }
        } header: {
            HStack(spacing: 4) {
                Text("Remote")
                Text("Beta")
                    .foregroundStyle(.tertiary)
            }
        }
    }

    @ViewBuilder
    private func remoteSetupStep(
        number: String,
        title: String,
        description: String,
        command: String,
        multiline: Bool = false
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(number)
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .frame(width: 16, height: 16)
                    .background(Circle().fill(.blue.opacity(0.7)))
                Text(title)
                    .font(.system(size: 12, weight: .medium))
            }
            Text(description)
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)
            copyableCommand(command, multiline: multiline)
        }
    }

    @ViewBuilder
    private func copyableCommand(_ command: String, multiline: Bool = false) -> some View {
        let isCopied = copiedCommand == command
        GroupBox {
            HStack(alignment: multiline ? .top : .center) {
                Text(command)
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundStyle(.primary)
                    .lineLimit(multiline ? nil : 1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
                Spacer(minLength: 8)
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(command, forType: .string)
                    copiedCommand = command
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        if copiedCommand == command {
                            copiedCommand = nil
                        }
                    }
                } label: {
                    Image(systemName: isCopied ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 10))
                        .foregroundStyle(isCopied ? .green : .secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.vertical, multiline ? 2 : 0)
        }
    }
}

// MARK: - Update Banner

struct UpdateBanner: View {
    let version: String
    let lang: LanguageManager
    var onUpdate: () -> Void

    var body: some View {
        Button(action: onUpdate) {
            HStack(spacing: 6) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 13, weight: .semibold))
                Text(lang.t("settings.update.available", version))
                    .font(.system(size: 12, weight: .medium))
                Image(systemName: "arrow.down.to.line")
                    .font(.system(size: 10, weight: .bold))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(Color.blue)
            )
        }
        .buttonStyle(.plain)
        .shadow(color: .blue.opacity(0.3), radius: 4, y: 2)
    }
}
