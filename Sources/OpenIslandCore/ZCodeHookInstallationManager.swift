import Foundation

/// Installs managed hooks into the ZCode desktop client's configuration file
/// (`~/.zcode/cli/config.json`).
///
/// ZCode consumes Claude-format hook payloads but stores its hook
/// configuration differently from Claude Code: groups live under the nested
/// `hooks.events.<Event>` key (not a top-level `hooks.<Event>`), the whole
/// `hooks` object must carry `enabled: true` before any configuration-file
/// hook runs, and the client supports exactly seven events —
/// `SessionStart`, `UserPromptSubmit`, `PreToolUse`, `PermissionRequest`,
/// `PostToolUse`, `PostToolUseFailure`, `Stop`. Matchers are case-sensitive
/// regular expressions matched against tool names (`.*` matches all).
public enum ZCodeHookInstaller {
    public static let managedTimeout = ClaudeHookInstaller.managedTimeout

    /// ZCode supports exactly seven hook events; registering any other name
    /// is invalid, so the managed set is fixed to these.
    public static let eventSpecs: [ClaudeHookEventSpec] = [
        ClaudeHookEventSpec(name: "SessionStart"),
        ClaudeHookEventSpec(name: "UserPromptSubmit"),
        ClaudeHookEventSpec(name: "PreToolUse", matcher: ".*"),
        ClaudeHookEventSpec(name: "PermissionRequest", matcher: ".*", timeout: managedTimeout),
        ClaudeHookEventSpec(name: "PostToolUse", matcher: ".*"),
        ClaudeHookEventSpec(name: "PostToolUseFailure", matcher: ".*"),
        ClaudeHookEventSpec(name: "Stop"),
    ]

    public static func hookCommand(for binaryPath: String) -> String {
        ClaudeHookInstaller.hookCommand(for: binaryPath, source: "zcode")
    }

    public static func installConfigJSON(
        existingData: Data?,
        hookCommand: String
    ) throws -> ClaudeHookFileMutation {
        var rootObject = try loadRootObject(from: existingData)
        var hooksObject = rootObject["hooks"] as? [String: Any] ?? [:]
        let existingEvents = hooksObject["events"] as? [String: Any] ?? [:]
        var eventsObject: [String: Any] = [:]

        // Preserve events outside the managed set untouched.
        for (eventName, value) in existingEvents where !eventSpecs.contains(where: { $0.name == eventName }) {
            eventsObject[eventName] = value
        }

        for spec in eventSpecs {
            let existingGroups = existingEvents[spec.name] as? [Any] ?? []
            let cleanedGroups = sanitizeForInstall(groups: existingGroups, replacingCommand: hookCommand)
            eventsObject[spec.name] = cleanedGroups + [managedGroup(matcher: spec.matcher, timeout: spec.timeout, hookCommand: hookCommand)]
        }

        hooksObject["events"] = eventsObject
        // Configuration-file hooks are disabled unless explicitly enabled.
        hooksObject["enabled"] = true
        rootObject["hooks"] = hooksObject
        let data = try serialize(rootObject)

        return ClaudeHookFileMutation(
            contents: data,
            changed: data != existingData,
            managedHooksPresent: true,
            hasClaudeIslandHooks: containsClaudeIslandHook(in: eventsObject)
        )
    }

    public static func uninstallConfigJSON(
        existingData: Data?,
        managedCommand: String?
    ) throws -> ClaudeHookFileMutation {
        guard let existingData else {
            return ClaudeHookFileMutation(
                contents: nil,
                changed: false,
                managedHooksPresent: false,
                hasClaudeIslandHooks: false
            )
        }

        var rootObject = try loadRootObject(from: existingData)
        guard var hooksObject = rootObject["hooks"] as? [String: Any] else {
            return ClaudeHookFileMutation(
                contents: existingData,
                changed: false,
                managedHooksPresent: false,
                hasClaudeIslandHooks: false
            )
        }

        let existingEvents = hooksObject["events"] as? [String: Any] ?? [:]
        var eventsObject = existingEvents
        var mutated = false

        for spec in eventSpecs {
            let existingGroups = eventsObject[spec.name] as? [Any] ?? []
            let cleanedGroups = sanitize(groups: existingGroups, managedCommand: managedCommand)

            if cleanedGroups.count != existingGroups.count || containsManagedHook(in: existingGroups, managedCommand: managedCommand) {
                mutated = true
            }

            if cleanedGroups.isEmpty {
                eventsObject.removeValue(forKey: spec.name)
            } else {
                eventsObject[spec.name] = cleanedGroups
            }
        }

        if eventsObject.isEmpty {
            // No configuration-file hooks remain. Keep the surrounding
            // `hooks` settings (enabled/timeoutMs/maxOutputBytes) as the user
            // configured them and only drop the empty events container.
            hooksObject.removeValue(forKey: "events")
        } else {
            hooksObject["events"] = eventsObject
        }

        if hooksObject.isEmpty {
            rootObject.removeValue(forKey: "hooks")
        } else {
            rootObject["hooks"] = hooksObject
        }

        let contents = rootObject.isEmpty ? nil : try serialize(rootObject)
        return ClaudeHookFileMutation(
            contents: contents,
            changed: mutated || contents != existingData,
            managedHooksPresent: mutated,
            hasClaudeIslandHooks: containsClaudeIslandHook(in: eventsObject)
        )
    }

    // MARK: - Shared JSON plumbing (mirrors ClaudeHookInstaller, which keeps
    // its equivalents private).

    private static func loadRootObject(from data: Data?) throws -> [String: Any] {
        guard let data else {
            return [:]
        }

        let object = try JSONSerialization.jsonObject(with: data)
        guard let rootObject = object as? [String: Any] else {
            throw ClaudeHookInstallerError.invalidSettingsJSON
        }

        return rootObject
    }

    private static func serialize(_ object: [String: Any]) throws -> Data {
        try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
    }

    private static func sanitize(groups: [Any], managedCommand: String?) -> [[String: Any]] {
        groups.compactMap { item in
            guard var group = item as? [String: Any] else {
                return nil
            }

            let existingHooks = group["hooks"] as? [Any] ?? []
            let filteredHooks = existingHooks.compactMap { hook -> [String: Any]? in
                guard let hook = hook as? [String: Any] else {
                    return nil
                }

                return isManagedHook(hook, managedCommand: managedCommand) ? nil : hook
            }

            guard !filteredHooks.isEmpty else {
                return nil
            }

            group["hooks"] = filteredHooks
            return group
        }
    }

    private static func sanitizeForInstall(groups: [Any], replacingCommand: String) -> [[String: Any]] {
        sanitize(groups: groups, managedCommand: replacingCommand)
    }

    private static func containsManagedHook(in groups: [Any], managedCommand: String?) -> Bool {
        groups.contains { item in
            guard let group = item as? [String: Any],
                  let hooks = group["hooks"] as? [Any] else {
                return false
            }

            return hooks.contains { hook in
                guard let hook = hook as? [String: Any] else {
                    return false
                }

                return isManagedHook(hook, managedCommand: managedCommand)
            }
        }
    }

    private static func containsClaudeIslandHook(in eventsObject: [String: Any]) -> Bool {
        eventsObject.values.contains { value in
            let groups = value as? [Any] ?? []
            return groups.contains { item in
                guard let group = item as? [String: Any],
                      let hooks = group["hooks"] as? [Any] else {
                    return false
                }

                return hooks.contains { hook in
                    guard let hook = hook as? [String: Any],
                          let command = hook["command"] as? String else {
                        return false
                    }

                    return command.contains("claude-island-state.py")
                }
            }
        }
    }

    private static func managedGroup(
        matcher: String?,
        timeout: Int?,
        hookCommand: String
    ) -> [String: Any] {
        var hook: [String: Any] = [
            "type": "command",
            "command": hookCommand,
        ]
        if let timeout {
            hook["timeout"] = timeout
        }

        var group: [String: Any] = [
            "hooks": [hook],
        ]

        if let matcher {
            group["matcher"] = matcher
        }

        return group
    }

    private static func isManagedHook(_ hook: [String: Any], managedCommand: String?) -> Bool {
        guard let command = hook["command"] as? String else {
            return false
        }

        if let managedCommand, command == managedCommand {
            return true
        }

        return isLegacyOpenIslandHookCommand(command)
    }

    /// Matches commands installed by Open Island builds and by the
    /// closed-source Vibe Island (`vibe-island-bridge --source zcode`),
    /// anchored on the exact zcode source token so cleanup never touches
    /// another agent's hooks in the same config.
    private static func isLegacyOpenIslandHookCommand(_ command: String) -> Bool {
        let normalized = command.lowercased()
        if (normalized.contains("openislandhooks") || normalized.contains("vibeislandhooks")) && normalized.contains("--source zcode") {
            return true
        }

        return (normalized.contains("open-island-bridge") || normalized.contains("vibe-island-bridge"))
            && normalized.contains("--source zcode")
    }
}

/// Manages the ZCode hook lifecycle on disk: status reads, installs, and
/// uninstalls against `~/.zcode/cli/config.json`, with the same manifest and
/// managed-binary conventions as `ClaudeHookInstallationManager`.
public final class ZCodeHookInstallationManager: @unchecked Sendable, ClaudeFormatHookInstallationManaging {
    public let configDirectory: URL
    public let managedHooksBinaryURL: URL
    private let fileManager: FileManager

    public init(
        configDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".zcode", isDirectory: true)
            .appendingPathComponent("cli", isDirectory: true),
        managedHooksBinaryURL: URL = ManagedHooksBinary.defaultURL(),
        fileManager: FileManager = .default
    ) {
        self.configDirectory = configDirectory
        self.managedHooksBinaryURL = managedHooksBinaryURL.standardizedFileURL
        self.fileManager = fileManager
    }

    public func status(hooksBinaryURL: URL? = nil) throws -> ClaudeHookInstallationStatus {
        let configURL = configDirectory.appendingPathComponent("config.json")
        let manifestURL = resolvedManifestURL()
        let resolvedHooksBinaryURL = resolvedHooksBinaryURL(explicitURL: hooksBinaryURL)

        let configData = try? Data(contentsOf: configURL)
        let manifest = try loadManifest(at: manifestURL)
        let managedCommand = manifest?.hookCommand ?? resolvedHooksBinaryURL.map { ZCodeHookInstaller.hookCommand(for: $0.path) }
        let uninstallMutation = try ZCodeHookInstaller.uninstallConfigJSON(
            existingData: configData,
            managedCommand: managedCommand
        )

        return ClaudeHookInstallationStatus(
            claudeDirectory: configDirectory,
            settingsURL: configURL,
            manifestURL: manifestURL,
            hooksBinaryURL: resolvedHooksBinaryURL,
            managedHooksPresent: uninstallMutation.managedHooksPresent,
            hasClaudeIslandHooks: uninstallMutation.hasClaudeIslandHooks,
            manifest: manifest
        )
    }

    @discardableResult
    public func install(hooksBinaryURL: URL) throws -> ClaudeHookInstallationStatus {
        try fileManager.createDirectory(at: configDirectory, withIntermediateDirectories: true)

        let configURL = configDirectory.appendingPathComponent("config.json")
        let manifestURL = configDirectory.appendingPathComponent(ClaudeHookInstallerManifest.fileName)
        let legacyManifestURL = configDirectory.appendingPathComponent(ClaudeHookInstallerManifest.legacyFileName)
        let existingConfig = try? Data(contentsOf: configURL)
        let installedHooksBinaryURL = try ManagedHooksBinary.install(
            from: hooksBinaryURL,
            to: managedHooksBinaryURL,
            fileManager: fileManager
        )
        let command = ZCodeHookInstaller.hookCommand(for: installedHooksBinaryURL.path)
        let mutation = try ZCodeHookInstaller.installConfigJSON(
            existingData: existingConfig,
            hookCommand: command
        )

        if mutation.changed, fileManager.fileExists(atPath: configURL.path) {
            try backupFile(at: configURL)
        }

        if let contents = mutation.contents {
            try contents.write(to: configURL, options: .atomic)
        }

        let manifest = ClaudeHookInstallerManifest(hookCommand: command)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(manifest).write(to: manifestURL, options: .atomic)
        if fileManager.fileExists(atPath: legacyManifestURL.path) {
            try fileManager.removeItem(at: legacyManifestURL)
        }

        return try status(hooksBinaryURL: installedHooksBinaryURL)
    }

    @discardableResult
    public func uninstall() throws -> ClaudeHookInstallationStatus {
        let configURL = configDirectory.appendingPathComponent("config.json")
        let manifestURL = resolvedManifestURL()
        let primaryManifestURL = configDirectory.appendingPathComponent(ClaudeHookInstallerManifest.fileName)
        let legacyManifestURL = configDirectory.appendingPathComponent(ClaudeHookInstallerManifest.legacyFileName)
        let manifest = try loadManifest(at: manifestURL)
        let existingConfig = try? Data(contentsOf: configURL)
        let mutation = try ZCodeHookInstaller.uninstallConfigJSON(
            existingData: existingConfig,
            managedCommand: manifest?.hookCommand
        )

        if mutation.changed, fileManager.fileExists(atPath: configURL.path) {
            try backupFile(at: configURL)
        }

        if let contents = mutation.contents {
            try contents.write(to: configURL, options: .atomic)
        } else if fileManager.fileExists(atPath: configURL.path) {
            try fileManager.removeItem(at: configURL)
        }

        for candidate in [primaryManifestURL, legacyManifestURL] where fileManager.fileExists(atPath: candidate.path) {
            try fileManager.removeItem(at: candidate)
        }

        return try status()
    }

    private func loadManifest(at url: URL) throws -> ClaudeHookInstallerManifest? {
        guard fileManager.fileExists(atPath: url.path) else {
            return nil
        }

        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(ClaudeHookInstallerManifest.self, from: data)
    }

    private func resolvedManifestURL() -> URL {
        let primaryURL = configDirectory.appendingPathComponent(ClaudeHookInstallerManifest.fileName)
        if fileManager.fileExists(atPath: primaryURL.path) {
            return primaryURL
        }

        let legacyURL = configDirectory.appendingPathComponent(ClaudeHookInstallerManifest.legacyFileName)
        return fileManager.fileExists(atPath: legacyURL.path) ? legacyURL : primaryURL
    }

    private func resolvedHooksBinaryURL(explicitURL: URL?) -> URL? {
        if let explicitURL {
            return explicitURL.standardizedFileURL
        }

        guard fileManager.isExecutableFile(atPath: managedHooksBinaryURL.path) else {
            return nil
        }

        return managedHooksBinaryURL
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
