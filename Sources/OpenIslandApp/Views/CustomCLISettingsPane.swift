import SwiftUI
import OpenIslandCore

// MARK: - Custom CLI Settings Pane

struct CustomCLISettingsPane: View {
    var model: AppModel

    @State private var profiles: [ClaudeCompatibleCLIProfile] = []
    @State private var editingProfile: ClaudeCompatibleCLIProfile?
    @State private var deleteConfirm: ClaudeCompatibleCLIProfile?

    private let store = ClaudeCompatibleCLIProfileStore()
    private var lang: LanguageManager { model.lang }

    var body: some View {
        Form {
            Section {
                Text(lang.t("settings.customCLI.footer"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section(lang.t("settings.customCLI.section")) {
                if profiles.isEmpty {
                    Text(lang.t("settings.customCLI.empty"))
                        .foregroundStyle(.tertiary)
                }

                ForEach(profiles) { profile in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(profile.displayName)
                                .font(.body)
                            Text(profile.executablePath)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }

                        Spacer()

                        Button {
                            deleteConfirm = profile
                        } label: {
                            Image(systemName: "trash")
                                .foregroundStyle(.red)
                        }
                        .buttonStyle(.plain)
                        .help(lang.t("settings.customCLI.delete"))
                    }
                }

                Button {
                    editingProfile = ClaudeCompatibleCLIProfile(
                        displayName: "",
                        hookSource: "",
                        executablePath: ""
                    )
                } label: {
                    Label(lang.t("settings.customCLI.add"), systemImage: "plus")
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle(lang.t("settings.tab.customCLI"))
        .onAppear(perform: loadProfiles)
        .sheet(item: $editingProfile) { profile in
            EditCLIProfileSheet(
                profile: profile,
                onSave: { updated in
                    saveProfile(updated)
                    editingProfile = nil
                },
                onCancel: {
                    editingProfile = nil
                }
            )
        }
        .alert(lang.t("settings.general.uninstallConfirmTitle"),
               isPresented: Binding(
                get: { deleteConfirm != nil },
                set: { if !$0 { deleteConfirm = nil } }
               )) {
            Button(lang.t("settings.customCLI.delete"), role: .destructive) {
                if let profile = deleteConfirm {
                    deleteProfile(profile)
                }
                deleteConfirm = nil
            }
            Button(lang.t("settings.general.cancel"), role: .cancel) {
                deleteConfirm = nil
            }
        } message: {
            if let profile = deleteConfirm {
                Text(String(format: lang.t("settings.customCLI.deleteConfirm"), profile.displayName))
            }
        }
    }

    // MARK: - Helpers

    private func loadProfiles() {
        profiles = store.load()
    }

    private func saveProfile(_ profile: ClaudeCompatibleCLIProfile) {
        var updated = profiles
        if let index = updated.firstIndex(where: { $0.id == profile.id }) {
            updated[index] = profile
        } else {
            updated.append(profile)
        }
        profiles = updated
        try? store.save(updated)
    }

    private func deleteProfile(_ profile: ClaudeCompatibleCLIProfile) {
        profiles.removeAll { $0.id == profile.id }
        try? store.save(profiles)
    }
}

// MARK: - Edit Profile Sheet

private struct EditCLIProfileSheet: View {
    var profile: ClaudeCompatibleCLIProfile
    var onSave: (ClaudeCompatibleCLIProfile) -> Void
    var onCancel: () -> Void

    @State private var displayName: String = ""
    @State private var executablePath: String = ""
    @State private var nameError: String? = nil
    @State private var pathError: String? = nil

    private var isEditing: Bool { !profile.displayName.isEmpty }
    private var fieldsValid: Bool {
        !displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !executablePath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    fieldRow(lang("settings.customCLI.displayName")) {
                        TextField("", text: $displayName)
                            .textFieldStyle(.roundedBorder)
                            .onChange(of: displayName) { _, _ in nameError = nil }
                    } error: {
                        nameError
                    }

                    fieldRow(lang("settings.customCLI.executablePath")) {
                        HStack(spacing: 6) {
                            TextField("", text: $executablePath)
                                .textFieldStyle(.roundedBorder)
                            Button(lang("settings.customCLI.browse")) {
                                browseFile()
                            }
                        }
                    } error: {
                        pathError
                    }

                } header: {
                    Text(isEditing ? lang("settings.customCLI.edit") : lang("settings.customCLI.addTitle"))
                }
            }
            .formStyle(.grouped)

            Divider()

            HStack {
                Spacer()
                Button(lang("settings.general.cancel")) { onCancel() }
                    .keyboardShortcut(.cancelAction)
                Button(isEditing ? lang("settings.customCLI.save") : lang("settings.customCLI.add")) {
                    commit()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!fieldsValid)
            }
            .padding()
        }
        .frame(width: 460)
        .onAppear {
            displayName = profile.displayName
            executablePath = profile.executablePath
        }
    }

    // MARK: - Field row helper

    @ViewBuilder
    private func fieldRow(_ label: String, @ViewBuilder content: () -> some View, error: () -> String?) -> some View {
        HStack(alignment: error() != nil ? .top : .firstTextBaseline) {
            Text(label)
                .frame(width: 100, alignment: .trailing)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 4) {
                content()
                if let err = error() {
                    Text(err)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
        }
    }

    // MARK: - Actions

    private func browseFile() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.canCreateDirectories = false
        panel.showsHiddenFiles = true
        panel.prompt = lang("settings.customCLI.browse")
        if panel.runModal() == .OK, let url = panel.url {
            executablePath = url.path
            pathError = nil
        }
    }

    /// Derive hookSource from the executable path's basename (without extension).
    private static func deriveHookSource(from path: String) -> String {
        URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
    }

    private func commit() {
        let trimmedName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedPath = executablePath.trimmingCharacters(in: .whitespacesAndNewlines)

        nameError = trimmedName.isEmpty ? lang("settings.customCLI.errorRequired") : nil
        pathError = trimmedPath.isEmpty ? lang("settings.customCLI.errorRequired") : nil

        guard nameError == nil, pathError == nil else { return }

        onSave(ClaudeCompatibleCLIProfile(
            id: profile.id,
            displayName: trimmedName,
            hookSource: Self.deriveHookSource(from: trimmedPath),
            executablePath: trimmedPath
        ))
    }

    private func lang(_ key: String) -> String {
        LanguageManager.shared.t(key)
    }
}