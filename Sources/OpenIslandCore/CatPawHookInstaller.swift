import Foundation

// CatPaw uses the same hook format as Claude Code (settings.json with a "hooks" object),
// but stores its configuration under ~/.catpaw/ instead of ~/.claude/.

public struct CatPawHookInstallerManifest: Equatable, Codable, Sendable {
    public static let fileName = "open-island-catpaw-hooks-install.json"

    public var hookCommand: String
    public var installedAt: Date

    public init(hookCommand: String, installedAt: Date = .now) {
        self.hookCommand = hookCommand
        self.installedAt = installedAt
    }
}

public struct CatPawHookFileMutation: Equatable, Sendable {
    public var contents: Data?
    public var changed: Bool
    public var managedHooksPresent: Bool

    public init(contents: Data?, changed: Bool, managedHooksPresent: Bool) {
        self.contents = contents
        self.changed = changed
        self.managedHooksPresent = managedHooksPresent
    }
}

public enum CatPawHookInstallerError: Error, LocalizedError {
    case invalidSettingsJSON

    public var errorDescription: String? {
        switch self {
        case .invalidSettingsJSON:
            "The existing CatPaw settings.json is not valid JSON."
        }
    }
}

/// Installs and uninstalls Open Island hooks into CatPaw's settings.json.
///
/// CatPaw uses the identical hook format as Claude Code (settings.json with a
/// "hooks" key), but stores configuration under ~/.catpaw/ instead of ~/.claude/.
/// The hook binary is invoked with `--source catpaw` so BridgeServer can route
/// the payload to the correct handler.
public enum CatPawHookInstaller {
    public static let managedTimeout = 86_400

    private static let eventSpecs: [(name: String, matcher: String?, timeout: Int?)] = [
        ("UserPromptSubmit", nil, nil),
        ("SessionStart", nil, nil),
        ("SessionEnd", nil, nil),
        ("Stop", nil, nil),
        ("StopFailure", nil, nil),
        ("SubagentStart", nil, nil),
        ("SubagentStop", nil, nil),
        ("Notification", "*", nil),
        ("PreToolUse", "*", nil),
        ("PermissionRequest", "*", managedTimeout),
        ("PostToolUse", "*", nil),
        ("PostToolUseFailure", "*", nil),
        ("PermissionDenied", "*", nil),
        ("PreCompact", nil, nil),
    ]

    public static func hookCommand(for binaryPath: String) -> String {
        "\(shellQuote(binaryPath)) --source catpaw"
    }

    public static func installSettingsJSON(
        existingData: Data?,
        hookCommand: String
    ) throws -> CatPawHookFileMutation {
        var rootObject = try loadRootObject(from: existingData)
        let existingHooksObject = rootObject["hooks"] as? [String: Any] ?? [:]
        var hooksObject: [String: Any] = [:]

        // Preserve non-managed hooks from existing config.
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
            hooksObject[spec.name] = cleanedGroups + [managedGroup(matcher: spec.matcher, timeout: spec.timeout, hookCommand: hookCommand)]
        }

        rootObject["hooks"] = hooksObject
        let data = try serialize(rootObject)

        return CatPawHookFileMutation(
            contents: data,
            changed: data != existingData,
            managedHooksPresent: true
        )
    }

    public static func uninstallSettingsJSON(
        existingData: Data?,
        managedCommand: String?
    ) throws -> CatPawHookFileMutation {
        guard let existingData else {
            return CatPawHookFileMutation(contents: nil, changed: false, managedHooksPresent: false)
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
            rootObject.removeValue(forKey: "hooks")
        } else {
            rootObject["hooks"] = hooksObject
        }

        let contents = rootObject.isEmpty ? nil : try serialize(rootObject)
        return CatPawHookFileMutation(
            contents: contents,
            changed: mutated || contents != existingData,
            managedHooksPresent: mutated
        )
    }

    // MARK: - Private helpers

    private static func loadRootObject(from data: Data?) throws -> [String: Any] {
        guard let data else { return [:] }

        let object = try JSONSerialization.jsonObject(with: data)
        guard let rootObject = object as? [String: Any] else {
            throw CatPawHookInstallerError.invalidSettingsJSON
        }

        return rootObject
    }

    private static func serialize(_ object: [String: Any]) throws -> Data {
        try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
    }

    private static func sanitize(groups: [Any], managedCommand: String?) -> [[String: Any]] {
        groups.compactMap { item in
            guard var group = item as? [String: Any] else { return nil }

            let existingHooks = group["hooks"] as? [Any] ?? []
            let filteredHooks = existingHooks.compactMap { hook -> [String: Any]? in
                guard let hook = hook as? [String: Any] else { return nil }
                return isManagedHook(hook, managedCommand: managedCommand) ? nil : hook
            }

            guard !filteredHooks.isEmpty else { return nil }
            group["hooks"] = filteredHooks
            return group
        }
    }

    private static func sanitizeForInstall(groups: [Any], replacingCommand: String) -> [[String: Any]] {
        groups.compactMap { item in
            guard var group = item as? [String: Any] else { return nil }

            let existingHooks = group["hooks"] as? [Any] ?? []
            let filteredHooks = existingHooks.compactMap { hook -> [String: Any]? in
                guard let hook = hook as? [String: Any] else { return nil }
                return isManagedHookForInstall(hook, replacingCommand: replacingCommand) ? nil : hook
            }

            guard !filteredHooks.isEmpty else { return nil }
            group["hooks"] = filteredHooks
            return group
        }
    }

    private static func containsManagedHook(in groups: [Any], managedCommand: String?) -> Bool {
        groups.contains { item in
            guard let group = item as? [String: Any],
                  let hooks = group["hooks"] as? [Any] else { return false }
            return hooks.contains { hook in
                guard let hook = hook as? [String: Any] else { return false }
                return isManagedHook(hook, managedCommand: managedCommand)
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
        guard let command = hook["command"] as? String else { return false }
        if let managedCommand, command == managedCommand { return true }
        return isOpenIslandCatPawHookCommand(command)
    }

    private static func isManagedHookForInstall(_ hook: [String: Any], replacingCommand: String) -> Bool {
        isManagedHook(hook, managedCommand: replacingCommand)
    }

    private static func isOpenIslandCatPawHookCommand(_ command: String) -> Bool {
        let normalized = command.lowercased()
        return (normalized.contains("openislandhooks") || normalized.contains("vibeislandhooks"))
            && normalized.contains("catpaw")
    }

    private static func shellQuote(_ string: String) -> String {
        guard !string.isEmpty else { return "''" }
        return "'\(string.replacingOccurrences(of: "'", with: "'\\''"))'"
    }
}

