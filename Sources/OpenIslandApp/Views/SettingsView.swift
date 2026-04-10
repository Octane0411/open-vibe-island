import SwiftUI
import AppKit
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
    @State private var previewPhase: SessionPhase = .running

    private var lang: LanguageManager { model.lang }
    private let pageBackground = Color(red: 0.16, green: 0.17, blue: 0.18)
    private let cardBackground = Color.white.opacity(0.04)
    private let cardBorder = Color.white.opacity(0.06)
    private let secondaryText = Color.white.opacity(0.48)

    var body: some View {
        Form {
            Section(lang.t("settings.display.notchTitle")) {
                VStack(alignment: .leading, spacing: 16) {
                    notchPreviewCard

                    settingsField(title: lang.t("settings.display.style")) {
                        HStack(alignment: .top, spacing: 14) {
                            styleOptionCard(
                                style: .minimal,
                                title: lang.t("settings.display.style.minimal"),
                                subtitle: lang.t("settings.display.style.minimalSubtitle")
                            )

                            styleOptionCard(
                                style: .detailed,
                                title: lang.t("settings.display.style.detailed"),
                                subtitle: lang.t("settings.display.style.detailedSubtitle")
                            )
                        }
                    }

                    settingsField(title: lang.t("settings.display.pixelShape")) {
                        LazyVGrid(
                            columns: Array(repeating: GridItem(.flexible(), spacing: 14, alignment: .top), count: 3),
                            spacing: 14
                        ) {
                            ForEach(IslandPixelShapeStyle.allCases) { style in
                                pixelShapeCard(style)
                            }
                        }
                    }

                    settingsField(title: lang.t("settings.display.statusColors")) {
                        VStack(alignment: .leading, spacing: 14) {
                            HStack(spacing: 10) {
                                ForEach(statusPhases, id: \.self) { phase in
                                    previewPhaseButton(phase)
                                }
                            }

                            VStack(spacing: 12) {
                                ForEach(statusPhases, id: \.self) { phase in
                                    statusColorRow(phase)
                                }
                            }
                        }
                    }

                }
                .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                .listRowBackground(Color.clear)
            }

            Section(lang.t("settings.display.monitor")) {
                VStack(alignment: .leading, spacing: 16) {
                    settingsInlineField(title: lang.t("settings.display.position")) {
                        Picker(
                            lang.t("settings.display.position"),
                            selection: Binding(
                                get: { model.overlayDisplaySelectionID },
                                set: { model.overlayDisplaySelectionID = $0 }
                            )
                        ) {
                            Text(lang.t("settings.general.automatic")).tag(OverlayDisplayOption.automaticID)
                            ForEach(model.overlayDisplayOptions) { option in
                                Text(option.title).tag(option.id)
                            }
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                        .frame(maxWidth: 220, alignment: .trailing)
                    }

                    if let diag = model.overlayPlacementDiagnostics {
                        VStack(spacing: 12) {
                            diagnosticsRow(
                                title: lang.t("settings.display.currentScreen"),
                                value: diag.targetScreenName
                            )
                            diagnosticsRow(
                                title: lang.t("settings.display.layoutMode"),
                                value: diag.modeDescription
                            )
                        }
                    }
                }
                .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                .listRowBackground(Color.clear)
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .background(pageBackground)
        .navigationTitle(lang.t("settings.tab.display"))
    }

    private func settingsCard<Content: View>(
        description: String? = nil,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            if let description {
                Text(description)
                    .font(.system(size: 13))
                    .foregroundStyle(secondaryText)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .minimumScaleFactor(0.82)
                    .allowsTightening(true)
            }

            content()
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(cardBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .stroke(cardBorder, lineWidth: 1)
        )
    }

    private func settingsField<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white.opacity(0.78))

            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func settingsInlineField<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(alignment: .center, spacing: 16) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white.opacity(0.74))
                .lineLimit(1)
                .truncationMode(.tail)
                .minimumScaleFactor(0.88)
                .allowsTightening(true)

            Spacer(minLength: 12)

            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var notchPreviewCard: some View {
        let previewCount = 2
        let previewLabel = model.islandClosedDisplayStyle == .detailed
            ? lang.t("settings.display.preview.sessions")
            : nil
        let previewStatusText = model.islandClosedDisplayStyle == .detailed
            ? statusTitle(previewPhase)
            : nil
        let previewLeadingWidth = IslandClosedHeaderLayout.leadingContentWidth(
            notchHeight: 24,
            hasAttention: previewPhase.requiresAttention,
            displayStyle: model.islandClosedDisplayStyle,
            detailText: previewStatusText
        )
        let previewTrailingWidth = IslandClosedHeaderLayout.trailingBadgeWidth(
            notchHeight: 24,
            indicatorCount: previewCount,
            displayStyle: model.islandClosedDisplayStyle,
            countLabel: previewLabel
        )
        let previewBarWidth = 224 + IslandClosedHeaderLayout.expansionWidth(
            notchHeight: 24,
            indicatorCount: previewCount,
            hasAttention: previewPhase.requiresAttention,
            displayStyle: model.islandClosedDisplayStyle,
            detailText: previewStatusText,
            countLabel: previewLabel
        )

        return ZStack {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.21, green: 0.11, blue: 0.39),
                            Color(red: 0.16, green: 0.28, blue: 0.62),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            HStack(spacing: 0) {
                HStack(spacing: 5) {
                    HStack(spacing: 4) {
                        IslandPixelGlyph(
                            tint: model.islandStatusColor(for: previewPhase),
                            style: model.islandPixelShapeStyle,
                            isAnimating: previewPhase != .completed
                        )

                        if previewPhase.requiresAttention {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 10.5, weight: .bold))
                                .foregroundStyle(model.islandStatusColor(for: previewPhase))
                        }
                    }

                    if model.islandClosedDisplayStyle == .detailed {
                        Text(statusTitle(previewPhase))
                            .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white.opacity(0.92))
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .minimumScaleFactor(0.7)
                            .allowsTightening(true)
                            .frame(
                                width: IslandClosedHeaderLayout.detailTextWidth(
                                    statusTitle(previewPhase),
                                    displayStyle: model.islandClosedDisplayStyle
                                ),
                                alignment: .leading
                            )
                    }
                }
                .frame(width: previewLeadingWidth, alignment: .leading)

                Spacer(minLength: IslandClosedHeaderLayout.centerSpacing(displayStyle: model.islandClosedDisplayStyle))

                ClosedCountBadge(
                    liveCount: previewCount,
                    tint: model.islandStatusColor(for: previewPhase),
                    label: previewLabel
                )
                .frame(width: previewTrailingWidth, alignment: Alignment.trailing)
            }
            .padding(14)
            .padding(.horizontal, IslandClosedHeaderLayout.horizontalPadding(displayStyle: model.islandClosedDisplayStyle))
            .frame(width: previewBarWidth, height: 62, alignment: .leading)
            .background(Color.black, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .padding(.top, 22)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 128)
    }

    private func styleOptionCard(
        style: IslandClosedDisplayStyle,
        title: String,
        subtitle: String
    ) -> some View {
        return Button {
            model.islandClosedDisplayStyle = style
        } label: {
            VStack(spacing: 6) {
                Text(title)
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.9))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .minimumScaleFactor(0.85)
                    .allowsTightening(true)
                    .frame(height: 24, alignment: .center)

                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.42))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .minimumScaleFactor(0.8)
                    .allowsTightening(true)
                    .multilineTextAlignment(.center)
            }
            .padding(.vertical, 22)
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(Color.white.opacity(style == model.islandClosedDisplayStyle ? 0.06 : 0.02))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(
                        style == model.islandClosedDisplayStyle ? Color.blue.opacity(0.9) : Color.white.opacity(0.08),
                        lineWidth: style == model.islandClosedDisplayStyle ? 2 : 1
                    )
            )
        }
        .buttonStyle(.plain)
    }

    private func diagnosticsRow(title: String, value: String) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(0.5))
            Spacer()
            Text(value)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white.opacity(0.88))
                .lineLimit(1)
                .truncationMode(.tail)
                .minimumScaleFactor(0.84)
                .allowsTightening(true)
        }
        .padding(.vertical, 2)
    }

    private var statusPhases: [SessionPhase] {
        [.running, .waitingForApproval, .waitingForAnswer, .completed]
    }

    private func pixelShapeCard(_ style: IslandPixelShapeStyle) -> some View {
        Button {
            model.islandPixelShapeStyle = style
        } label: {
            VStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.white.opacity(0.05))
                    .frame(height: 62)
                    .overlay {
                        IslandPixelGlyph(
                            tint: model.islandStatusColor(for: previewPhase),
                            style: style,
                            isAnimating: previewPhase != .completed,
                            width: 30,
                            height: 18
                        )
                    }

                Text(pixelShapeTitle(style))
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.84))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .minimumScaleFactor(0.85)
                    .allowsTightening(true)
            }
            .padding(14)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.white.opacity(style == model.islandPixelShapeStyle ? 0.06 : 0.02))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(
                        style == model.islandPixelShapeStyle ? Color.blue.opacity(0.9) : Color.white.opacity(0.08),
                        lineWidth: style == model.islandPixelShapeStyle ? 2 : 1
                    )
            )
        }
        .buttonStyle(.plain)
    }

    private func previewPhaseButton(_ phase: SessionPhase) -> some View {
        Button {
            previewPhase = phase
        } label: {
            Text(statusTitle(phase))
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(previewPhase == phase ? .white : .white.opacity(0.64))
                .lineLimit(1)
                .minimumScaleFactor(0.82)
                .allowsTightening(true)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    Capsule()
                        .fill(previewPhase == phase ? model.islandStatusColor(for: phase).opacity(0.3) : Color.white.opacity(0.06))
                )
                .overlay(
                    Capsule()
                        .stroke(previewPhase == phase ? model.islandStatusColor(for: phase).opacity(0.9) : Color.white.opacity(0.08), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }

    private func statusColorRow(_ phase: SessionPhase) -> some View {
        HStack(spacing: 14) {
            HStack(spacing: 10) {
                Circle()
                    .fill(model.islandStatusColor(for: phase))
                    .frame(width: 12, height: 12)
                Text(statusTitle(phase))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white.opacity(0.82))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .minimumScaleFactor(0.84)
                    .allowsTightening(true)
            }
            .frame(width: 120, alignment: .leading)

            ColorPicker(
                "",
                selection: Binding(
                    get: { model.islandStatusColor(for: phase) },
                    set: { model.setIslandStatusColor($0, for: phase) }
                ),
                supportsOpacity: false
            )
            .labelsHidden()

            Text(model.islandStatusColorHex(for: phase))
                .font(.system(size: 11.5, weight: .semibold, design: .monospaced))
                .foregroundStyle(.white.opacity(0.5))

            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white.opacity(0.03))
        )
    }

    private func pixelShapeTitle(_ style: IslandPixelShapeStyle) -> String {
        switch style {
        case .bars:
            return lang.t("settings.display.pixelShape.bars")
        case .steps:
            return lang.t("settings.display.pixelShape.steps")
        case .blocks:
            return lang.t("settings.display.pixelShape.blocks")
        }
    }

    private func statusTitle(_ phase: SessionPhase) -> String {
        switch phase {
        case .running:
            return lang.t("settings.display.status.running")
        case .waitingForApproval:
            return lang.t("settings.display.status.approval")
        case .waitingForAnswer:
            return lang.t("settings.display.status.answer")
        case .completed:
            return lang.t("settings.display.status.completed")
        }
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
    private let primaryInk = Color.white.opacity(0.94)

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 8) {
                Image(nsImage: NSApplication.shared.applicationIconImage)
                    .resizable()
                    .frame(width: 56, height: 56)

                Text(lang.t("app.name"))
                    .font(.title.bold())

                Text(lang.t("app.description"))
                    .foregroundStyle(.secondary)

                if let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String {
                    Text(lang.t("settings.about.version", version))
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.top, 24)
            .padding(.bottom, 20)

            Divider()

            Form {
                Section {
                    aboutActionRow(
                        title: lang.t("settings.about.checkForUpdates"),
                        systemImage: "arrow.triangle.2.circlepath",
                        tint: primaryInk,
                        action: {
                            model.updateChecker.checkForUpdates()
                        }
                    )
                    .disabled(!model.updateChecker.canCheckForUpdates)
                    .opacity(model.updateChecker.canCheckForUpdates ? 1 : 0.55)
                    .accessibilityIdentifier("settings.about.checkForUpdates")
                }

                Section {
                    aboutActionRow(
                        title: lang.t("settings.about.quitApp"),
                        systemImage: "rectangle.portrait.and.arrow.right",
                        tint: Color(red: 1.0, green: 0.29, blue: 0.29),
                        action: {
                            model.quitApplication()
                        }
                    )
                    .accessibilityIdentifier("settings.about.quitApp")
                }
            }
            .formStyle(.grouped)

            Spacer()
        }
        .frame(maxWidth: .infinity)
        .navigationTitle(lang.t("settings.tab.about"))
    }

    private func aboutActionRow(
        title: String,
        systemImage: String,
        tint: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: systemImage)
                    .font(.system(size: 13, weight: .medium))
                    .frame(width: 18, alignment: .leading)

                Text(title)
                    .font(.system(size: 11.5, weight: .semibold))

                Spacer()
            }
            .foregroundStyle(tint)
            .padding(.vertical, 2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Setup

struct SetupSettingsPane: View {
    var model: AppModel

    @State private var confirmingUninstallClaude = false
    @State private var confirmingUninstallCodex = false
    @State private var confirmingUninstallOpenCode = false
    @State private var confirmingUninstallQoder = false
    @State private var confirmingUninstallQwenCode = false
    @State private var confirmingUninstallFactory = false
    @State private var confirmingUninstallCodebuddy = false
    @State private var confirmingUninstallCursor = false

    private var lang: LanguageManager { model.lang }

    var body: some View {
        Form {
            claudeConfigDirectorySection

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
                    name: "Qwen Code",
                    installed: model.qwenCodeHooksInstalled,
                    busy: model.isQwenCodeHookSetupBusy,
                    installAction: { model.installQwenCodeHooks() },
                    uninstallAction: { confirmingUninstallQwenCode = true }
                )
                .alert(lang.t("settings.general.uninstallConfirmTitle"), isPresented: $confirmingUninstallQwenCode) {
                    Button(lang.t("settings.general.uninstallConfirmAction"), role: .destructive) {
                        model.uninstallQwenCodeHooks()
                    }
                    Button(lang.t("settings.general.cancel"), role: .cancel) {}
                } message: {
                    Text("This will remove Open Island hooks from ~/.qwen/settings.json.")
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

                hookRow(
                    name: "Cursor",
                    installed: model.cursorHooksInstalled,
                    busy: model.isCursorHookSetupBusy,
                    requiresBinary: true,
                    installAction: { model.installCursorHooks() },
                    uninstallAction: { confirmingUninstallCursor = true }
                )
                .alert(lang.t("settings.general.uninstallConfirmTitle"), isPresented: $confirmingUninstallCursor) {
                    Button(lang.t("settings.general.uninstallConfirmAction"), role: .destructive) {
                        model.uninstallCursorHooks()
                    }
                    Button(lang.t("settings.general.cancel"), role: .cancel) {}
                } message: {
                    Text("This will remove the Open Island hooks from ~/.cursor/hooks.json.")
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
                    if !model.qwenCodeHooksInstalled { model.installQwenCodeHooks() }
                    if !model.factoryHooksInstalled { model.installFactoryHooks() }
                    if !model.codebuddyHooksInstalled { model.installCodebuddyHooks() }
                    if !model.cursorHooksInstalled { model.installCursorHooks() }
                    if !model.claudeUsageInstalled { model.installClaudeUsageBridge() }
                }
                .disabled(model.hooksBinaryURL == nil || allReady)
                .frame(maxWidth: .infinity, alignment: .center)
            }
        }
        .formStyle(.grouped)
        .navigationTitle(lang.t("settings.tab.setup"))
    }

    @ViewBuilder
    private var claudeConfigDirectorySection: some View {
        Section {
            HStack {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(lang.t("setup.claudeConfigDir.title"))
                        Text(ClaudeConfigDirectory.resolved().path)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                } icon: {
                    Image(systemName: "folder")
                }
                Spacer()
                if ClaudeConfigDirectory.customDirectory != nil {
                    Button(lang.t("setup.claudeConfigDir.reset")) {
                        model.updateClaudeConfigDirectory(to: nil)
                    }
                    .font(.caption)
                }
                Button(lang.t("setup.claudeConfigDir.choose")) {
                    let panel = NSOpenPanel()
                    panel.canChooseDirectories = true
                    panel.canChooseFiles = false
                    panel.canCreateDirectories = true
                    panel.prompt = lang.t("setup.claudeConfigDir.choose")
                    if panel.runModal() == .OK, let url = panel.url {
                        model.updateClaudeConfigDirectory(to: url)
                    }
                }
            }
        } header: {
            HStack(spacing: 4) {
                Text(lang.t("setup.claudeConfigDir.section"))
                Text(lang.t("setup.optional"))
                    .foregroundStyle(.tertiary)
            }
        } footer: {
            Text(lang.t("setup.claudeConfigDir.footer"))
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    private var allReady: Bool {
        model.claudeHooksInstalled && model.codexHooksInstalled && model.openCodePluginInstalled
            && model.qoderHooksInstalled && model.qwenCodeHooksInstalled && model.factoryHooksInstalled && model.codebuddyHooksInstalled
            && model.cursorHooksInstalled && model.claudeUsageInstalled
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
