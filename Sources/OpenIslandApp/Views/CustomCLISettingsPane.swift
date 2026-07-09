import SwiftUI
import OpenIslandCore

// MARK: - Custom CLI Settings Pane

struct CustomCLISettingsPane: View {
    var model: AppModel

    @State private var profiles: [ClaudeCompatibleCLIProfile] = []
    @State private var showEditSheet = false
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
                    showEditSheet = true
                } label: {
                    Label(lang.t("settings.customCLI.add"), systemImage: "plus")
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle(lang.t("settings.tab.customCLI"))
        .onAppear(perform: loadProfiles)
        .sheet(isPresented: $showEditSheet) {
            if let profile = editingProfile {
                EditCLIProfileSheet(
                    profile: profile,
                    isPresented: $showEditSheet,
                    onSave: { updated in
                        saveProfile(updated)
                        showEditSheet = false
                    },
                    onCancel: { showEditSheet = false }
                )
            }
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
    @State var profile: ClaudeCompatibleCLIProfile
    @Binding var isPresented: Bool
    var onSave: (ClaudeCompatibleCLIProfile) -> Void
    var onCancel: () -> Void

    @State private var displayName: String = ""
    @State private var executablePath: String = ""
    @State private var hookSource: String = ""
    @State private var nameError: String? = nil
    @State private var pathError: String? = nil
    @State private var hookSourceError: String? = nil

    private var isEditing: Bool {
        !profile.displayName.isEmpty
    }

    private var isValid: Bool {
        ClaudeCompatibleCLIProfile(
            displayName: displayName,
            hookSource: hookSource,
            executablePath: executablePath
        ).isValid
    }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    LabeledContent(lang("settings.customCLI.displayName")) {
                        VStack(alignment: .trailing) {
                            TextField("", text: $displayName)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 280)
                                .onChange(of: displayName) { _, _ in
                                    nameError = nil
                                }
                            if let error = nameError {
                                Text(error)
                                    .font(.caption)
                                    .foregroundStyle(.red)
                            }
                        }
                    }

                    LabeledContent(lang("settings.customCLI.executablePath")) {
                        VStack(alignment: .trailing) {
                            HStack(spacing: 6) {
                                TextField("", text: $executablePath)
                                    .textFieldStyle(.roundedBorder)
                                    .frame(width: 220)
                                    .onChange(of: executablePath) { _, newPath in
                                        pathError = nil
                                        autoFillHookSource(from: newPath)
                                    }

                                Button(lang("settings.customCLI.browse")) {
                                    browseFile()
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            }
                            if let error = pathError {
                                Text(error)
                                    .font(.caption)
                                    .foregroundStyle(.red)
                            }
                        }
                    }

                    LabeledContent(lang("settings.customCLI.hookSource")) {
                        VStack(alignment: .trailing) {
                            TextField("", text: $hookSource)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 200)
                                .onChange(of: hookSource) { _, _ in
                                    hookSourceError = nil
                                }
                            if let error = hookSourceError {
                                Text(error)
                                    .font(.caption)
                                    .foregroundStyle(.red)
                            }
                        }
                    }
                } header: {
                    Text(isEditing
                         ? lang("settings.customCLI.edit")
                         : lang("settings.customCLI.addTitle"))
                }
            }
            .formStyle(.grouped)

            Divider()

            HStack {
                Spacer()
                Button(lang("settings.general.cancel")) {
                    onCancel()
                }
                .keyboardShortcut(.cancelAction)

                Button(isEditing
                       ? lang("settings.customCLI.save")
                       : lang("settings.customCLI.add")) {
                    commit()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!isValid)
            }
            .padding()
        }
        .frame(width: 480)
        .onAppear {
            displayName = profile.displayName
            executablePath = profile.executablePath
            hookSource = profile.hookSource
            if hookSource.isEmpty {
                autoFillHookSource(from: executablePath)
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
            autoFillHookSource(from: executablePath)
        }
    }

    private func autoFillHookSource(from path: String) {
        guard !path.isEmpty else { return }
        let basename = URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
        if !basename.isEmpty {
            hookSource = basename
        }
    }

    private func commit() {
        let trimmedName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedPath = executablePath.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedSource = hookSource.trimmingCharacters(in: .whitespacesAndNewlines)

        // Validate
        nameError = trimmedName.isEmpty ? lang("settings.customCLI.errorRequired") : nil
        pathError = trimmedPath.isEmpty ? lang("settings.customCLI.errorRequired") : nil
        if !ClaudeCompatibleCLIProfile.isValidHookSource(trimmedSource) {
            hookSourceError = lang("settings.customCLI.errorHookSource")
        } else {
            hookSourceError = nil
        }

        guard nameError == nil, pathError == nil, hookSourceError == nil else {
            return
        }

        let updated = ClaudeCompatibleCLIProfile(
            id: profile.id,
            displayName: trimmedName,
            hookSource: trimmedSource,
            executablePath: trimmedPath
        )

        onSave(updated)
    }

    private func lang(_ key: String) -> String {
        // Access language via shared instance; model is not available in sheet.
        // Use explicit NSLocalizedString with Bundle lookup via LanguageManager.
        LanguageManager.shared.t(key)
    }
}