import SwiftUI

struct IslandShortcutsSettingsPane: View {
    var model: AppModel
    private var lang: LanguageManager { model.lang }

    var body: some View {
        Form {
            Section {
                Toggle(lang.t("settings.shortcuts.enabled"), isOn: Binding(
                    get: { model.keyboardShortcutsEnabled }, set: { model.keyboardShortcutsEnabled = $0 }
                ))
                Picker(lang.t("settings.shortcuts.toggle"), selection: Binding(
                    get: { model.islandToggleShortcut }, set: { model.islandToggleShortcut = $0 }
                )) {
                    ForEach(IslandToggleShortcut.allCases) { shortcut in
                        Text(shortcut.label).tag(shortcut)
                    }
                }
                .disabled(!model.keyboardShortcutsEnabled)
                if model.keyboardShortcutError != nil {
                    Text(lang.t("settings.shortcuts.unavailable"))
                        .font(.caption).foregroundStyle(.orange)
                }
            }
            Section(lang.t("settings.shortcuts.inPanel")) {
                shortcut("settings.shortcuts.next", keys: "⌘↓")
                shortcut("settings.shortcuts.previous", keys: "⌘↑")
                shortcut("settings.shortcuts.jump", keys: "↩")
                shortcut("settings.shortcuts.approve", keys: "⌘Y")
                shortcut("settings.shortcuts.deny", keys: "⌘N")
                shortcut("settings.shortcuts.close", keys: "Esc")
                Text(lang.t("settings.shortcuts.scope"))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .navigationTitle(lang.t("settings.tab.shortcuts"))
    }

    private func shortcut(_ key: String, keys: String) -> some View {
        LabeledContent(lang.t(key)) {
            Text(keys).font(.system(.body, design: .monospaced))
        }
    }
}
