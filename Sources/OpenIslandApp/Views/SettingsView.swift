import SwiftUI
import OpenIslandCore

// MARK: - Settings tabs

enum SettingsTab: String, CaseIterable, Identifiable {
    case general
    case display
    case sound
    case shortcuts
    case lab
    case about

    var id: String { rawValue }

    var label: String {
        switch self {
        case .general:   "通用"
        case .display:   "显示"
        case .sound:     "声音"
        case .shortcuts: "快捷键"
        case .lab:       "实验室"
        case .about:     "关于"
        }
    }

    var icon: String {
        switch self {
        case .general:   "gearshape.fill"
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
        case .display:   .blue
        case .sound:     .green
        case .shortcuts: .gray
        case .lab:       .pink
        case .about:     .blue
        }
    }

    var section: SettingsSection {
        switch self {
        case .general, .display, .sound: .system
        case .shortcuts, .lab:           .advanced
        case .about:                     .app
        }
    }
}

enum SettingsSection: String, CaseIterable {
    case system
    case advanced
    case app

    var header: String {
        switch self {
        case .system:   "系统"
        case .advanced: "高级"
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
                Section(section.header) {
                    ForEach(section.tabs) { tab in
                        Label {
                            Text(tab.label)
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
        switch selectedTab {
        case .general:
            GeneralSettingsPane(model: model)
        case .display:
            DisplaySettingsPane(model: model)
        case .sound:
            SoundSettingsPane(model: model)
        case .shortcuts:
            PlaceholderSettingsPane(title: "快捷键", subtitle: "快捷键设置即将推出。")
        case .lab:
            PlaceholderSettingsPane(title: "实验室", subtitle: "实验性功能即将推出。")
        case .about:
            AboutSettingsPane()
        }
    }
}

// MARK: - General

struct GeneralSettingsPane: View {
    var model: AppModel

    @State private var launchAtLogin = false

    var body: some View {
        Form {
            Section("系统") {
                Toggle("登录时打开", isOn: $launchAtLogin)

                Picker("显示器", selection: Binding(
                    get: { model.overlayDisplaySelectionID },
                    set: { model.overlayDisplaySelectionID = $0 }
                )) {
                    ForEach(model.overlayDisplayOptions) { option in
                        Text(option.title).tag(option.id)
                    }
                }
            }

            Section("行为") {
                Toggle("全屏时隐藏", isOn: .constant(false))
                Toggle("无活跃会话时自动隐藏", isOn: .constant(false))
                Toggle("鼠标离开时自动收起", isOn: .constant(true))
            }

            Section("CLI Hooks") {
                HStack {
                    Text("Claude Code")
                    Spacer()
                    if model.claudeHooksInstalled {
                        HStack(spacing: 4) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                            Text("已激活")
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        Button("安装") {
                            model.installClaudeHooks()
                        }
                        .disabled(model.hooksBinaryURL == nil)
                    }
                }

                HStack {
                    Text("Codex")
                    Spacer()
                    if model.codexHooksInstalled {
                        HStack(spacing: 4) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                            Text("已激活")
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        Button("安装") {
                            model.installCodexHooks()
                        }
                        .disabled(model.hooksBinaryURL == nil)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("通用")
    }
}

// MARK: - Display

struct DisplaySettingsPane: View {
    var model: AppModel

    var body: some View {
        Form {
            Section("显示器") {
                Picker("显示位置", selection: Binding(
                    get: { model.overlayDisplaySelectionID },
                    set: { model.overlayDisplaySelectionID = $0 }
                )) {
                    ForEach(model.overlayDisplayOptions) { option in
                        Text(option.title).tag(option.id)
                    }
                }
            }

            if let diag = model.overlayPlacementDiagnostics {
                Section("诊断") {
                    LabeledContent("当前屏幕", value: diag.targetScreenName)
                    LabeledContent("布局模式", value: diag.modeDescription)
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("显示")
    }
}

// MARK: - Sound

struct SoundSettingsPane: View {
    var model: AppModel

    private var availableSounds: [String] {
        NotificationSoundService.availableSounds()
    }

    var body: some View {
        Form {
            Section("通知音效") {
                Toggle("静音", isOn: Binding(
                    get: { model.isSoundMuted },
                    set: { _ in model.toggleSoundMuted() }
                ))
            }

            Section("选择音效") {
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
        .navigationTitle("声音")
    }
}

// MARK: - About

struct AboutSettingsPane: View {
    var body: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "island")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("Open Island")
                .font(.title.bold())
            Text("macOS companion for AI coding agents")
                .foregroundStyle(.secondary)
            if let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String {
                Text("Version \(version)")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .navigationTitle("关于")
    }
}

// MARK: - Placeholder

struct PlaceholderSettingsPane: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(spacing: 12) {
            Spacer()
            Text(subtitle)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .navigationTitle(title)
    }
}
