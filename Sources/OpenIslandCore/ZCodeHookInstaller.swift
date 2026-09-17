import Foundation

public struct ZCodeHookInstallerManifest: Equatable, Codable, Sendable {
    public static let fileName = "open-island-zcode-hooks-install.json"

    public var hookCommand: String
    public var installedAt: Date

    public init(hookCommand: String, installedAt: Date = .now) {
        self.hookCommand = hookCommand
        self.installedAt = installedAt
    }
}

public struct ZCodeHookFileMutation: Equatable, Sendable {
    public var contents: Data?
    public var changed: Bool
    public var managedHooksPresent: Bool

    public init(contents: Data?, changed: Bool, managedHooksPresent: Bool) {
        self.contents = contents
        self.changed = changed
        self.managedHooksPresent = managedHooksPresent
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
/// ZCode's hook payloads are Claude Code compatible on the wire
/// (`hook_event_name`, `session_id`, `cwd`, snake_case tool fields), so the
/// runtime side reuses `ClaudeHookPayload`. What differs is the configuration
/// file: ZCode reads hooks from the top-level `hooks` object of
/// `config.json`, shaped as `{ enabled?, timeoutMs?, events: { <Event>: [group] } }`,
/// and configuration hooks are disabled unless `hooks.enabled` is `true`.
///
/// The managed v1 event set is intentionally minimal (`SessionStart`,
/// `UserPromptSubmit`, `Stop`) — the same low-noise lifecycle coverage as the
/// Codex integration. ZCode supports additional blocking events
/// (`PreToolUse`, `PermissionRequest`), but they are not registered until
/// approval round-trips are designed for this surface.
public enum ZCodeHookInstaller {
    private static let eventNames = ["SessionStart", "UserPromptSubmit", "Stop"]

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

        for eventName in eventNames {
            let existingGroups = eventsObject[eventName] as? [Any] ?? []
            let cleanedGroups = sanitizeGroups(existingGroups, removingCommand: hookCommand)
            eventsObject[eventName] = cleanedGroups + [managedGroup(hookCommand: hookCommand)]
        }

        // Configuration-file hooks are disabled by default; the installer is
        // responsible for turning the runner on. Left untouched on uninstall —
        // an enabled runner with no events is a no-op.
        hooksObject["enabled"] = true
        hooksObject["events"] = eventsObject
        rootObject["hooks"] = hooksObject

        let data = try serialize(rootObject)
        return ZCodeHookFileMutation(
            contents: data,
            changed: data != existingData,
            managedHooksPresent: true
        )
    }

    public static func uninstallConfigJSON(
        existingData: Data?,
        managedCommand: String?
    ) throws -> ZCodeHookFileMutation {
        guard let existingData else {
            return ZCodeHookFileMutation(contents: nil, changed: false, managedHooksPresent: false)
        }

        var rootObject = try loadRootObject(from: existingData)
        guard var hooksObject = rootObject["hooks"] as? [String: Any] else {
            return ZCodeHookFileMutation(contents: existingData, changed: false, managedHooksPresent: false)
        }

        var mutated = false
        if var eventsObject = hooksObject["events"] as? [String: Any] {
            for eventName in eventNames {
                let existingGroups = eventsObject[eventName] as? [Any] ?? []
                let cleanedGroups = sanitizeGroups(existingGroups, removingCommand: managedCommand)

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
        } else {
            hooksObject.removeValue(forKey: "events")
        }

        // `enabled` only matters while managed events exist; drop it when
        // nothing else remains so uninstall restores a hooks-free config.
        if hooksObject.keys.allSatisfy({ $0 == "enabled" }) {
            hooksObject.removeValue(forKey: "enabled")
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

    /// Removes managed hook entries from a group list while preserving
    /// user-authored groups. Groups whose hook list becomes empty are dropped,
    /// matching the Claude installer's behavior.
    private static func sanitizeGroups(_ groups: [Any], removingCommand managedCommand: String?) -> [[String: Any]] {
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

    private static func managedGroup(hookCommand: String) -> [String: Any] {
        [
            "hooks": [
                [
                    "type": "command",
                    "command": hookCommand,
                ]
            ]
        ]
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

    private static func isLegacyOpenIslandHookCommand(_ command: String) -> Bool {
        let normalized = command.lowercased()
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
