import Foundation

/// Per-profile install state for the bundled `open-island-dsh` plugin.
public struct DshProfileInstallStatus: Equatable, Sendable {
    public var name: String
    public var directory: URL
    public var patchEntryPresent: Bool
    public var nodeModulesPresent: Bool
    /// Timestamped backups created by the last install that mutated files.
    public var backups: [URL]

    public var installed: Bool {
        patchEntryPresent && nodeModulesPresent
    }

    public init(
        name: String,
        directory: URL,
        patchEntryPresent: Bool,
        nodeModulesPresent: Bool,
        backups: [URL] = []
    ) {
        self.name = name
        self.directory = directory
        self.patchEntryPresent = patchEntryPresent
        self.nodeModulesPresent = nodeModulesPresent
        self.backups = backups
    }
}

/// Aggregated DSH install status across every detected profile.
public struct DshPluginInstallationStatus: Equatable, Sendable {
    public var profiles: [DshProfileInstallStatus]
    public var pluginSourceURL: URL

    /// Healthy only when the plugin is present in every detected profile —
    /// new profiles appear as "not installed" until the user reinstalls.
    public var pluginInstalledInAllDetectedProfiles: Bool {
        !profiles.isEmpty && profiles.allSatisfy(\.installed)
    }

    public init(profiles: [DshProfileInstallStatus], pluginSourceURL: URL) {
        self.profiles = profiles
        self.pluginSourceURL = pluginSourceURL
    }
}

public enum DshPluginInstallationError: Error, LocalizedError {
    case pluginSourceMissing(URL)

    public var errorDescription: String? {
        switch self {
        case let .pluginSourceMissing(url):
            "Open Island DSH plugin source not found at \(url.path)."
        }
    }
}

/// Installs the bundled `open-island-dsh` cordis plugin into every profile
/// under `~/.dsh/profiles/`.
///
/// IRON RULES honored here:
/// - Only user-space files under `~/.dsh/profiles/<name>/` are touched; the
///   DSH app bundle is never modified, so the user can update DSH freely.
/// - Every mutation is preceded by a timestamped backup of the file it
///   rewrites; uninstall restores user-authored bytes exactly.
/// - `package.json` is deliberately left untouched (avoiding pnpm lockfile
///   drift); the loader resolves `open-island-dsh` from node_modules.
public final class DshPluginInstallationManager: @unchecked Sendable {
    public static let pluginPackageName = "open-island-dsh"
    public static let patchFileName = "cordis.patch.yml"
    public static let ownershipManifestFileName = "open-island-plugin-install.json"

    /// Exact block appended to each profile's `cordis.patch.yml`. Uninstall
    /// removes this exact block, never a fuzzy match.
    private static let managedPatchBlock = """
    # Open Island bridge plugin (managed by Open Island)
    - insert:
        - id: open-island
          name: open-island-dsh
          config: {}
    """

    private let dshDirectory: URL
    private let pluginSourceURL: URL
    private let fileManager: FileManager

    public init(
        dshDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".dsh", isDirectory: true),
        pluginSourceURL: URL,
        fileManager: FileManager = .default
    ) {
        self.dshDirectory = dshDirectory
        self.pluginSourceURL = pluginSourceURL.standardizedFileURL
        self.fileManager = fileManager
    }

    // MARK: - Status

    public func status() throws -> DshPluginInstallationStatus {
        var profiles: [DshProfileInstallStatus] = []

        for profileDirectory in try detectProfileDirectories() {
            let patchURL = profileDirectory.appendingPathComponent(Self.patchFileName)
            let patch = try? String(contentsOf: patchURL, encoding: .utf8)
            let patchEntryPresent = patch?.contains("name: \(Self.pluginPackageName)") ?? false

            let pluginDirectory = pluginNodeModulesURL(for: profileDirectory)
            let nodeModulesPresent = fileManager.fileExists(
                atPath: pluginDirectory.appendingPathComponent("index.js").path
            )

            profiles.append(
                DshProfileInstallStatus(
                    name: profileDirectory.lastPathComponent,
                    directory: profileDirectory,
                    patchEntryPresent: patchEntryPresent,
                    nodeModulesPresent: nodeModulesPresent,
                    backups: backupsFor(profileDirectory: profileDirectory)
                )
            )
        }

        return DshPluginInstallationStatus(profiles: profiles, pluginSourceURL: pluginSourceURL)
    }

    // MARK: - Install

    @discardableResult
    public func install() throws -> DshPluginInstallationStatus {
        guard fileManager.fileExists(atPath: pluginSourceURL.appendingPathComponent("index.js").path) else {
            throw DshPluginInstallationError.pluginSourceMissing(pluginSourceURL)
        }

        for profileDirectory in try detectProfileDirectories() {
            // 1. Copy plugin payload into the profile's node_modules.
            let pluginDirectory = pluginNodeModulesURL(for: profileDirectory)
            try fileManager.createDirectory(
                at: pluginDirectory.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            if fileManager.fileExists(atPath: pluginDirectory.path) {
                try fileManager.removeItem(at: pluginDirectory)
            }
            try fileManager.copyItem(at: pluginSourceURL, to: pluginDirectory)

            // 2. Insert the managed patch entry (idempotent).
            // A pristine profile ships `[]` as its whole document — appending
            // list items after a closed flow sequence is invalid YAML, so the
            // bare `[]` line is replaced in place instead.
            let patchURL = profileDirectory.appendingPathComponent(Self.patchFileName)
            let patchExisted = fileManager.fileExists(atPath: patchURL.path)
            let existing = (try? String(contentsOf: patchURL, encoding: .utf8)) ?? ""
            var lastPatchMutation: (separatorAdded: Bool, replacedEmptyArray: Bool, trailingNewlineAdded: Bool)?
            var separatorAdded = false
            var replacedEmptyArray = false
            if !existing.contains("name: \(Self.pluginPackageName)") {
                if patchExisted {
                    try backupFile(at: patchURL)
                }

                var contents: String
                if let range = Self.emptyArrayLineRange(in: existing) {
                    replacedEmptyArray = true
                    contents = existing.replacingCharacters(
                        in: range,
                        with: Self.managedPatchBlock
                    )
                } else {
                    let separator = existing.isEmpty || existing.hasSuffix("\n") ? "" : "\n"
                    separatorAdded = !separator.isEmpty
                    contents = existing + separator + Self.managedPatchBlock
                }
                var trailingNewlineAdded = false
                if !contents.hasSuffix("\n") {
                    contents += "\n"
                    trailingNewlineAdded = true
                }
                try Data(contents.utf8).write(to: patchURL, options: .atomic)

                lastPatchMutation = (
                    separatorAdded: separatorAdded,
                    replacedEmptyArray: replacedEmptyArray,
                    trailingNewlineAdded: trailingNewlineAdded
                )
            }

            // 3. Ownership manifest: records exactly what install changed so
            // uninstall can restore the user's bytes precisely.
            let mutation = lastPatchMutation ?? (
                separatorAdded: false,
                replacedEmptyArray: false,
                trailingNewlineAdded: false
            )
            let manifest: [String: String] = [
                "managedBy": "Open Island",
                "plugin": Self.pluginPackageName,
                "installedAt": ISO8601DateFormatter().string(from: .now),
                "patchExisted": patchExisted ? "true" : "false",
                "separatorAdded": mutation.separatorAdded ? "true" : "false",
                "replacedEmptyArray": mutation.replacedEmptyArray ? "true" : "false",
                "trailingNewlineAdded": mutation.trailingNewlineAdded ? "true" : "false",
            ]
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(manifest).write(
                to: profileDirectory.appendingPathComponent(Self.ownershipManifestFileName),
                options: .atomic
            )
        }

        return try status()
    }

    // MARK: - Uninstall

    @discardableResult
    public func uninstall() throws -> DshPluginInstallationStatus {
        for profileDirectory in try detectProfileDirectories() {
            let patchURL = profileDirectory.appendingPathComponent(Self.patchFileName)
            let manifestURL = profileDirectory.appendingPathComponent(Self.ownershipManifestFileName)
            let manifest = loadManifest(at: manifestURL)

            // 1. Remove the exact managed block from the patch file, restoring
            // the user's bytes precisely (separator byte included).
            if fileManager.fileExists(atPath: patchURL.path) {
                let existing = (try? String(contentsOf: patchURL, encoding: .utf8)) ?? ""
                if existing.contains("name: \(Self.pluginPackageName)") {
                    try backupFile(at: patchURL)

                    if manifest?["patchExisted"] == "false" {
                        // Install created this file: it only ever held our entry.
                        try fileManager.removeItem(at: patchURL)
                    } else if manifest?["replacedEmptyArray"] == "true" {
                        // Install swapped the pristine `[]` line for our block:
                        // put the `[]` back exactly where it was, dropping the
                        // trailing newline install appended if the template
                        // never had one.
                        var restored = existing.replacingOccurrences(
                            of: Self.managedPatchBlock,
                            with: "[]"
                        )
                        if manifest?["trailingNewlineAdded"] == "true", restored.hasSuffix("\n") {
                            restored = String(restored.dropLast())
                        }
                        try Data(restored.utf8).write(to: patchURL, options: .atomic)
                    } else {
                        var restored = existing
                            .replacingOccurrences(of: Self.managedPatchBlock + "\n", with: "")
                            .replacingOccurrences(of: Self.managedPatchBlock, with: "")
                        if manifest?["separatorAdded"] == "true", restored.hasSuffix("\n") {
                            // Strip the single separator byte install inserted.
                            restored = String(restored.dropLast())
                        }
                        try Data(restored.utf8).write(to: patchURL, options: .atomic)
                    }
                }
            }

            // 2. Remove the plugin payload.
            let pluginDirectory = pluginNodeModulesURL(for: profileDirectory)
            if fileManager.fileExists(atPath: pluginDirectory.path) {
                try fileManager.removeItem(at: pluginDirectory)
            }

            // 3. Remove the ownership manifest.
            if fileManager.fileExists(atPath: manifestURL.path) {
                try fileManager.removeItem(at: manifestURL)
            }
        }

        return try status()
    }

    // MARK: - Private

    /// Range of a bare `[]` line ("[]", optionally indented) if the document
    /// still holds the pristine empty-list form.
    private static func emptyArrayLineRange(in contents: String) -> Range<String.Index>? {
        var lineStart = contents.startIndex
        while lineStart < contents.endIndex {
            let lineEnd = contents.lineRange(for: lineStart..<lineStart).upperBound
            let line = contents[lineStart..<lineEnd]
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed == "[]" {
                return lineStart..<lineEnd
            }
            lineStart = lineEnd
        }
        return nil
    }

    private var profilesDirectory: URL {
        dshDirectory.appendingPathComponent("profiles", isDirectory: true)
    }

    private func detectProfileDirectories() throws -> [URL] {
        guard let entries = try? fileManager.contentsOfDirectory(
            at: profilesDirectory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        return entries
            .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
            .filter { fileManager.fileExists(atPath: $0.appendingPathComponent("package.json").path) }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    private func pluginNodeModulesURL(for profileDirectory: URL) -> URL {
        profileDirectory
            .appendingPathComponent("node_modules", isDirectory: true)
            .appendingPathComponent(Self.pluginPackageName, isDirectory: true)
    }

    private func loadManifest(at url: URL) -> [String: String]? {
        guard let data = try? Data(contentsOf: url) else {
            return nil
        }
        return try? JSONDecoder().decode([String: String].self, from: data)
    }

    private func backupsFor(profileDirectory: URL) -> [URL] {
        let prefix = "\(Self.patchFileName).backup."
        guard let entries = try? fileManager.contentsOfDirectory(
            at: profileDirectory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }
        return entries
            .filter { $0.lastPathComponent.hasPrefix(prefix) }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    private func backupFile(at url: URL) throws {
        guard fileManager.fileExists(atPath: url.path) else {
            return
        }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        let timestamp = formatter.string(from: .now).replacingOccurrences(of: ":", with: "-")
        let backupURL = url.appendingPathExtension("backup.\(timestamp)")
        if fileManager.fileExists(atPath: backupURL.path) {
            try fileManager.removeItem(at: backupURL)
        }
        try fileManager.copyItem(at: url, to: backupURL)
    }
}
