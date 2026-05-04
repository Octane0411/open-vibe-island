import Foundation

public struct CodexHookInstallerManifest: Equatable, Codable, Sendable {
    public static let fileName = "open-island-install.json"
    public static let legacyFileName = "vibe-island-install.json"

    public var hookCommand: String
    public var enabledCodexHooksFeature: Bool
    public var installedAt: Date

    public init(
        hookCommand: String,
        enabledCodexHooksFeature: Bool,
        installedAt: Date = .now
    ) {
        self.hookCommand = hookCommand
        self.enabledCodexHooksFeature = enabledCodexHooksFeature
        self.installedAt = installedAt
    }
}

public struct CodexFeatureMutation: Equatable, Sendable {
    public var contents: String
    public var changed: Bool
    public var featureEnabledByInstaller: Bool

    public init(contents: String, changed: Bool, featureEnabledByInstaller: Bool) {
        self.contents = contents
        self.changed = changed
        self.featureEnabledByInstaller = featureEnabledByInstaller
    }
}

public struct CodexHookFileMutation: Equatable, Sendable {
    public var contents: Data?
    public var changed: Bool
    public var hasRemainingHooks: Bool

    public init(contents: Data?, changed: Bool, hasRemainingHooks: Bool) {
        self.contents = contents
        self.changed = changed
        self.hasRemainingHooks = hasRemainingHooks
    }
}

public enum CodexHookInstallerError: Error, LocalizedError {
    case invalidHooksJSON

    public var errorDescription: String? {
        switch self {
        case .invalidHooksJSON:
            "The existing Codex hooks file is not valid JSON."
        }
    }
}

public enum CodexHookInstaller {
    // Keep matching the legacy status message so uninstall/status still recognize older installs.
    public static let managedStatusMessage = "Managed by Open Island"
    public static let legacyManagedStatusMessage = "Managed by Vibe Island"
    public static let managedTimeout = 45
    // Intentionally above OpenIslandHooksCLI.interactiveCodexHookTimeout (3500) so the CLI can
    // fail open first instead of waiting for the full Codex-managed window.
    public static let managedInteractiveTimeout = 3600

    // Keep the managed Codex install low-noise while still surfacing approval prompts.
    // PermissionRequest hooks are interactive, so they get a long timeout.
    private static let eventSpecs: [(name: String, matcher: String?, timeout: Int)] = [
        ("SessionStart", "startup|resume", managedTimeout),
        ("UserPromptSubmit", nil, managedTimeout),
        ("PermissionRequest", nil, managedInteractiveTimeout),
        ("Stop", nil, managedTimeout),
    ]

    public static func hookCommand(for binaryPath: String) -> String {
        shellQuote(binaryPath)
    }

    public static func installHooksJSON(
        existingData: Data?,
        hookCommand: String
    ) throws -> CodexHookFileMutation {
        var rootObject = try loadRootObject(from: existingData)
        let existingHooksObject = rootObject["hooks"] as? [String: Any] ?? [:]
        var hooksObject: [String: Any] = [:]

        for (eventName, value) in existingHooksObject {
            let existingGroups = value as? [Any] ?? []
            let cleanedGroups = sanitizeForInstall(groups: existingGroups, replacingCommand: hookCommand)

            if !cleanedGroups.isEmpty {
                hooksObject[eventName] = cleanedGroups
            }
        }

        for spec in eventSpecs {
            let existingGroups = hooksObject[spec.name] as? [Any] ?? []
            let cleanedGroups = sanitizeForInstall(groups: existingGroups, replacingCommand: hookCommand)
            hooksObject[spec.name] = cleanedGroups + [managedGroup(
                matcher: spec.matcher,
                hookCommand: hookCommand,
                timeout: spec.timeout
            )]
        }

        rootObject["hooks"] = hooksObject
        let data = try serialize(rootObject)
        let changed = data != existingData
        return CodexHookFileMutation(contents: data, changed: changed, hasRemainingHooks: true)
    }

    public static func uninstallHooksJSON(
        existingData: Data?,
        managedCommand: String?
    ) throws -> CodexHookFileMutation {
        guard let existingData else {
            return CodexHookFileMutation(contents: nil, changed: false, hasRemainingHooks: false)
        }

        var rootObject = try loadRootObject(from: existingData)
        var hooksObject = rootObject["hooks"] as? [String: Any] ?? [:]
        var mutated = false

        for spec in eventSpecs {
            let existingGroups = hooksObject[spec.name] as? [Any] ?? []
            let cleanedGroups = sanitize(groups: existingGroups, managedCommand: managedCommand)

            if cleanedGroups.count != existingGroups.count || containsManagedHook(in: existingGroups, managedCommand: managedCommand) {
                mutated = true
            }

            if cleanedGroups.isEmpty {
                hooksObject.removeValue(forKey: spec.name)
            } else {
                hooksObject[spec.name] = cleanedGroups
            }
        }

        if hooksObject.isEmpty {
            return CodexHookFileMutation(contents: nil, changed: mutated, hasRemainingHooks: false)
        }

        rootObject["hooks"] = hooksObject
        let data = try serialize(rootObject)
        return CodexHookFileMutation(contents: data, changed: mutated || data != existingData, hasRemainingHooks: true)
    }

    public static func enableCodexHooksFeature(in contents: String) -> CodexFeatureMutation {
        var lines = contents.components(separatedBy: "\n")

        if let codexHookIndex = lineIndex(ofKey: "codex_hooks", inSection: "features", lines: lines) {
            let trimmed = lines[codexHookIndex].trimmingCharacters(in: .whitespaces)
            if trimmed == "codex_hooks = true" {
                return CodexFeatureMutation(
                    contents: contents,
                    changed: false,
                    featureEnabledByInstaller: false
                )
            }

            lines[codexHookIndex] = "codex_hooks = true"
            return CodexFeatureMutation(
                contents: lines.joined(separator: "\n"),
                changed: true,
                featureEnabledByInstaller: true
            )
        }

        if let featuresRange = sectionRange(named: "features", lines: lines) {
            let insertIndex = featuresRange.upperBound
            lines.insert("codex_hooks = true", at: insertIndex)
            return CodexFeatureMutation(
                contents: lines.joined(separator: "\n"),
                changed: true,
                featureEnabledByInstaller: true
            )
        }

        if !lines.isEmpty, lines.last?.isEmpty == false {
            lines.append("")
        }
        lines.append("[features]")
        lines.append("codex_hooks = true")

        return CodexFeatureMutation(
            contents: lines.joined(separator: "\n"),
            changed: true,
            featureEnabledByInstaller: true
        )
    }

    public static func disableCodexHooksFeatureIfManaged(in contents: String) -> CodexFeatureMutation {
        var lines = contents.components(separatedBy: "\n")
        guard let featuresRange = sectionRange(named: "features", lines: lines),
              let codexHookIndex = lineIndex(ofKey: "codex_hooks", inSection: "features", lines: lines) else {
            return CodexFeatureMutation(contents: contents, changed: false, featureEnabledByInstaller: false)
        }

        lines.remove(at: codexHookIndex)

        let updatedRange = sectionRange(named: "features", lines: lines) ?? featuresRange
        let remainingFeatureLines = lines[updatedRange.lowerBound + 1..<updatedRange.upperBound]
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("#") }

        if remainingFeatureLines.isEmpty, let featuresHeaderIndex = lines.firstIndex(of: "[features]") {
            lines.remove(at: featuresHeaderIndex)
            if featuresHeaderIndex < lines.count, lines[featuresHeaderIndex].isEmpty {
                lines.remove(at: featuresHeaderIndex)
            }
        }

        return CodexFeatureMutation(
            contents: lines.joined(separator: "\n"),
            changed: true,
            featureEnabledByInstaller: false
        )
    }

    private static func loadRootObject(from data: Data?) throws -> [String: Any] {
        guard let data else {
            return [:]
        }

        let object = try JSONSerialization.jsonObject(with: data)
        guard let rootObject = object as? [String: Any] else {
            throw CodexHookInstallerError.invalidHooksJSON
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
        groups.compactMap { item in
            guard var group = item as? [String: Any] else {
                return nil
            }

            let existingHooks = group["hooks"] as? [Any] ?? []
            let filteredHooks = existingHooks.compactMap { hook -> [String: Any]? in
                guard let hook = hook as? [String: Any] else {
                    return nil
                }

                return isManagedHookForInstall(hook, replacingCommand: replacingCommand) ? nil : hook
            }

            guard !filteredHooks.isEmpty else {
                return nil
            }

            group["hooks"] = filteredHooks
            return group
        }
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

    private static func managedGroup(matcher: String?, hookCommand: String, timeout: Int) -> [String: Any] {
        var group: [String: Any] = [
            "hooks": [[
                "type": "command",
                "command": hookCommand,
                "timeout": timeout,
            ]]
        ]

        if let matcher {
            group["matcher"] = matcher
        }

        return group
    }

    private static func isManagedHook(_ hook: [String: Any], managedCommand: String?) -> Bool {
        if let statusMessage = hook["statusMessage"] as? String,
           statusMessage == managedStatusMessage || statusMessage == legacyManagedStatusMessage {
            return true
        }

        guard let managedCommand else {
            return false
        }

        return hook["command"] as? String == managedCommand
    }

    private static func isManagedHookForInstall(_ hook: [String: Any], replacingCommand: String) -> Bool {
        if isManagedHook(hook, managedCommand: replacingCommand) {
            return true
        }

        guard let command = hook["command"] as? String else {
            return false
        }

        return isLegacyOpenIslandHookCommand(command)
    }

    private static func isLegacyOpenIslandHookCommand(_ command: String) -> Bool {
        let normalized = command.lowercased()
        if normalized.contains("openislandhooks") || normalized.contains("vibeislandhooks") {
            return true
        }

        return normalized.contains("open-island-bridge") || normalized.contains("vibe-island-bridge")
    }

    private static func sectionRange(named section: String, lines: [String]) -> Range<Int>? {
        guard let headerIndex = lines.firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == "[\(section)]" }) else {
            return nil
        }

        var endIndex = lines.count
        for index in (headerIndex + 1)..<lines.count {
            let trimmed = lines[index].trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("[") && trimmed.hasSuffix("]") {
                endIndex = index
                break
            }
        }

        return headerIndex..<endIndex
    }

    private static func lineIndex(ofKey key: String, inSection section: String, lines: [String]) -> Int? {
        guard let range = sectionRange(named: section, lines: lines) else {
            return nil
        }

        for index in (range.lowerBound + 1)..<range.upperBound {
            let trimmed = lines[index].trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("\(key) =") {
                return index
            }
        }

        return nil
    }

    private static func shellQuote(_ string: String) -> String {
        guard !string.isEmpty else {
            return "''"
        }

        return "'\(string.replacingOccurrences(of: "'", with: "'\\''"))'"
    }
}
