import Foundation

public struct ZCodeHookInstallerManifest: Equatable, Codable, Sendable {
    public static let fileName = "open-island-zcode-install.json"

    public var hookCommand: String
    /// Value of `hooks.enabled` in the user's `config.json` before the
    /// installer touched it. `nil` means the key (or the whole `hooks`
    /// object) was absent; uninstall restores this state.
    public var hooksEnabledBeforeInstall: Bool?
    public var installedAt: Date

    public init(
        hookCommand: String,
        hooksEnabledBeforeInstall: Bool?,
        installedAt: Date = .now
    ) {
        self.hookCommand = hookCommand
        self.hooksEnabledBeforeInstall = hooksEnabledBeforeInstall
        self.installedAt = installedAt
    }
}

public struct ZCodeHookFileMutation: Equatable, Sendable {
    public var contents: Data?
    public var changed: Bool
    public var managedHooksPresent: Bool
    /// Prior `hooks.enabled` value observed while installing, so the
    /// manager can persist it in the manifest for a faithful uninstall.
    public var hooksEnabledBefore: Bool?

    public init(
        contents: Data?,
        changed: Bool,
        managedHooksPresent: Bool,
        hooksEnabledBefore: Bool? = nil
    ) {
        self.contents = contents
        self.changed = changed
        self.managedHooksPresent = managedHooksPresent
        self.hooksEnabledBefore = hooksEnabledBefore
    }
}

public enum ZCodeHookInstallerError: Error, LocalizedError {
    case invalidConfigJSON

    public var errorDescription: String? {
        switch self {
        case .invalidConfigJSON:
            "The existing ZCode config.json is not valid JSON."
        }
    }
}

/// Installs/uninstalls Open Island's managed hook entries in
/// `~/.zcode/cli/config.json`.
///
/// ZCode's hook protocol is payload-compatible with Claude Code (the stdin
/// JSON carries snake_case Claude aliases alongside ZCode's own fields), so
/// the runtime side reuses `ClaudeHookPayload` with `--source zcode`. What
/// differs is the configuration file: ZCode reads hooks from the top-level
/// `hooks` object of `config.json` with the event groups nested under
/// `hooks.events`, and requires `hooks.enabled` to be `true` — unlike
/// Claude's `settings.json` where groups sit directly under `hooks`.
///
/// The installer keeps the footprint low-noise: only lifecycle events are
/// installed (SessionStart, UserPromptSubmit, Stop, PermissionRequest);
/// per-tool events are left to the user. ZCode snapshots hook config at
/// session startup, so installed hooks apply to sessions started afterwards.
public enum ZCodeHookInstaller {
    public static let managedTimeoutMs = 45_000
    public static let managedInteractiveTimeoutMs = 60 * 60 * 1000

    private static let eventSpecs: [(name: String, matcher: String?, timeoutMs: Int)] = [
        ("SessionStart", nil, managedTimeoutMs),
        ("UserPromptSubmit", nil, managedTimeoutMs),
        ("Stop", nil, managedTimeoutMs),
        ("PermissionRequest", "*", managedInteractiveTimeoutMs),
    ]

    public static func hookCommand(for binaryPath: String) -> String {
        "\(shellQuote(binaryPath)) --source zcode"
    }

    public static func installConfigJSON(
        existingData: Data?,
        hookCommand: String
    ) throws -> ZCodeHookFileMutation {
        var rootObject = try loadRootObject(from: existingData)
        var hooksObject = rootObject["hooks"] as? [String: Any] ?? [:]
        var eventsObject = hooksObject["events"] as? [String: Any] ?? [:]
        let hooksEnabledBefore = hooksObject["enabled"] as? Bool

        for (eventName, value) in eventsObject {
            let existingGroups = value as? [Any] ?? []
            let cleanedGroups = sanitizeForInstall(groups: existingGroups, replacingCommand: hookCommand)

            if cleanedGroups.isEmpty {
                eventsObject.removeValue(forKey: eventName)
            } else {
                eventsObject[eventName] = cleanedGroups
            }
        }

        for spec in eventSpecs {
            let existingGroups = eventsObject[spec.name] as? [Any] ?? []
            let cleanedGroups = sanitizeForInstall(groups: existingGroups, replacingCommand: hookCommand)
            eventsObject[spec.name] = cleanedGroups + [managedGroup(matcher: spec.matcher, timeoutMs: spec.timeoutMs, hookCommand: hookCommand)]
        }

        hooksObject["events"] = eventsObject
        hooksObject["enabled"] = true
        rootObject["hooks"] = hooksObject

        let data = try serialize(rootObject)
        return ZCodeHookFileMutation(
            contents: data,
            changed: data != existingData,
            managedHooksPresent: true,
            hooksEnabledBefore: hooksEnabledBefore
        )
    }

    public static func uninstallConfigJSON(
        existingData: Data?,
        managedCommand: String?,
        hooksEnabledBeforeInstall: Bool?
    ) throws -> ZCodeHookFileMutation {
        guard let existingData else {
            return ZCodeHookFileMutation(contents: nil, changed: false, managedHooksPresent: false)
        }

        var rootObject = try loadRootObject(from: existingData)
        guard var hooksObject = rootObject["hooks"] as? [String: Any] else {
            return ZCodeHookFileMutation(contents: existingData, changed: false, managedHooksPresent: false)
        }

        var mutated = false
        var eventsObject = hooksObject["events"] as? [String: Any] ?? [:]

        for (eventName, value) in eventsObject {
            let existingGroups = value as? [Any] ?? []
            let cleanedGroups = sanitize(groups: existingGroups, managedCommand: managedCommand)

            if cleanedGroups.count != existingGroups.count {
                mutated = true
            }

            if cleanedGroups.isEmpty {
                eventsObject.removeValue(forKey: eventName)
            } else {
                eventsObject[eventName] = cleanedGroups
            }
        }

        if eventsObject.isEmpty {
            hooksObject.removeValue(forKey: "events")
        } else {
            hooksObject["events"] = eventsObject
        }

        // Restore the user's pre-install `enabled` state once no hooks
        // remain. A user who had hooks configured keeps `enabled: true`.
        if eventsObject.isEmpty {
            switch hooksEnabledBeforeInstall {
            case .some(true):
                hooksObject["enabled"] = true
            case .some(false), .none:
                hooksObject.removeValue(forKey: "enabled")
            }
        }

        if hooksObject.isEmpty {
            rootObject.removeValue(forKey: "hooks")
        } else {
            rootObject["hooks"] = hooksObject
        }

        let contents = rootObject.isEmpty ? nil : try serialize(rootObject)
        return ZCodeHookFileMutation(
            contents: contents,
            changed: mutated || contents != existingData,
            managedHooksPresent: mutated
        )
    }

    private static func loadRootObject(from data: Data?) throws -> [String: Any] {
        guard let data else {
            return [:]
        }

        let object = try JSONSerialization.jsonObject(with: data)
        guard let rootObject = object as? [String: Any] else {
            throw ZCodeHookInstallerError.invalidConfigJSON
        }

        return rootObject
    }

    private static func serialize(_ object: [String: Any]) throws -> Data {
        try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
    }

    private static func managedGroup(matcher: String?, timeoutMs: Int, hookCommand: String) -> [String: Any] {
        let hook: [String: Any] = [
            "type": "command",
            "command": hookCommand,
            "enabled": true,
            "timeoutMs": timeoutMs,
        ]

        var group: [String: Any] = ["hooks": [hook]]
        if let matcher {
            group["matcher"] = matcher
        }
        return group
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

                return isManagedHook(hook, managedCommand: replacingCommand) ? nil : hook
            }

            guard !filteredHooks.isEmpty else {
                return nil
            }

            group["hooks"] = filteredHooks
            return group
        }
    }

    private static func isManagedHook(_ hook: [String: Any], managedCommand: String?) -> Bool {
        let command = hook["command"] as? String ?? ""
        let arguments = (hook["args"] as? [Any])?.compactMap { $0 as? String } ?? []
        let normalized = (command + " " + arguments.joined(separator: " ")).lowercased()

        if let managedCommand, normalized == managedCommand.lowercased() {
            return true
        }

        guard normalized.contains("--source zcode") else {
            return false
        }

        return normalized.contains("openislandhooks")
            || normalized.contains("vibeislandhooks")
            || normalized.contains("open-island-bridge")
            || normalized.contains("vibe-island-bridge")
    }

    private static func shellQuote(_ string: String) -> String {
        guard !string.isEmpty else {
            return "''"
        }
        return "'\(string.replacingOccurrences(of: "'", with: "'\\''"))'"
    }
}
