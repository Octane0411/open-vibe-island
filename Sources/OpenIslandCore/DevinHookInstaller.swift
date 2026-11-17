import Foundation

public struct DevinHookInstallationManifest: Equatable, Codable, Sendable {
    public static let fileName = "open-island-devin-hooks-install.json"

    public var hookCommand: String
    public var installedAt: Date

    public init(hookCommand: String, installedAt: Date = .now) {
        self.hookCommand = hookCommand
        self.installedAt = installedAt
    }
}

public struct DevinHookFileMutation: Equatable, Sendable {
    public var contents: Data?
    public var changed: Bool
    public var managedHooksPresent: Bool

    public init(contents: Data?, changed: Bool, managedHooksPresent: Bool) {
        self.contents = contents
        self.changed = changed
        self.managedHooksPresent = managedHooksPresent
    }
}

public enum DevinHookInstallerError: Error, Equatable, LocalizedError {
    case invalidConfigJSON

    public var errorDescription: String? {
        switch self {
        case .invalidConfigJSON:
            "The existing Devin config.json is not valid JSON."
        }
    }
}

/// Installs Open Island command hooks into Devin's user config.
///
/// Devin CLI and Desktop read a Claude-shaped `"hooks"` object from
/// `~/.config/devin/config.json`. The matcher is a regex, and an omitted
/// matcher matches every tool, so managed entries do not use Claude's `"*"`.
/// Other top-level keys and user-authored hook entries are preserved.
public enum DevinHookInstaller {
    public static let managedPermissionTimeout = 86_400

    /// Events Devin documents. `PostCompaction` is omitted until the shared
    /// Claude decoder has a case for it.
    private static let eventSpecs: [(name: String, timeout: Int?)] = [
        ("SessionStart", nil),
        ("SessionEnd", nil),
        ("UserPromptSubmit", nil),
        ("Stop", nil),
        ("PreToolUse", nil),
        ("PostToolUse", nil),
        ("PermissionRequest", managedPermissionTimeout),
    ]

    public static func hookCommand(for binaryPath: String) -> String {
        "\(shellQuote(binaryPath)) --source devin"
    }

    public static func installConfigJSON(
        existingData: Data?,
        hookCommand: String
    ) throws -> DevinHookFileMutation {
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
            hooksObject[spec.name] = cleanedGroups + [managedGroup(timeout: spec.timeout, hookCommand: hookCommand)]
        }

        rootObject["hooks"] = hooksObject
        let data = try serialize(rootObject)
        return DevinHookFileMutation(
            contents: data,
            changed: data != existingData,
            managedHooksPresent: true
        )
    }

    public static func uninstallConfigJSON(
        existingData: Data?,
        managedCommand: String?
    ) throws -> DevinHookFileMutation {
        guard let existingData else {
            return DevinHookFileMutation(contents: nil, changed: false, managedHooksPresent: false)
        }

        var rootObject = try loadRootObject(from: existingData)
        var hooksObject = rootObject["hooks"] as? [String: Any] ?? [:]
        var managedHooksPresent = false

        for spec in eventSpecs {
            let existingGroups = hooksObject[spec.name] as? [Any] ?? []
            if containsManagedHook(in: existingGroups, managedCommand: managedCommand) {
                managedHooksPresent = true
            }
            let cleanedGroups = sanitize(groups: existingGroups, managedCommand: managedCommand)
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
        return DevinHookFileMutation(
            contents: contents,
            changed: contents != existingData,
            managedHooksPresent: managedHooksPresent
        )
    }

    private static func loadRootObject(from data: Data?) throws -> [String: Any] {
        guard let data, !data.isEmpty else {
            return [:]
        }

        let object: Any
        do {
            object = try JSONSerialization.jsonObject(with: data)
        } catch {
            throw DevinHookInstallerError.invalidConfigJSON
        }
        guard let rootObject = object as? [String: Any] else {
            throw DevinHookInstallerError.invalidConfigJSON
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

    private static func managedGroup(timeout: Int?, hookCommand: String) -> [String: Any] {
        var hook: [String: Any] = [
            "type": "command",
            "command": hookCommand,
        ]
        if let timeout {
            hook["timeout"] = timeout
        }
        return ["hooks": [hook]]
    }

    private static func isManagedHook(_ hook: [String: Any], managedCommand: String?) -> Bool {
        guard let command = hook["command"] as? String else {
            return false
        }
        if let managedCommand, command == managedCommand {
            return true
        }
        let normalized = command.lowercased()
        return normalized.contains("openislandhooks") && normalized.contains("--source devin")
    }

    private static func shellQuote(_ string: String) -> String {
        guard !string.isEmpty else {
            return "''"
        }
        return "'\(string.replacingOccurrences(of: "'", with: "'\\''"))'"
    }
}

/// Translates a Claude-shaped hook directive into the decision JSON Devin reads.
public enum DevinHookOutputEncoder {
    public static func standardOutput(for response: BridgeResponse) throws -> Data? {
        guard case let .claudeHookDirective(directive) = response else {
            return nil
        }

        let object: [String: Any]
        switch directive {
        case let .permissionRequest(.allow(updatedInput, _)):
            object = approveObject(updatedInput: updatedInput, eventName: "PermissionRequest")
        case let .permissionRequest(.deny(message, _)):
            object = blockObject(reason: message)
        case let .preToolUse(payload):
            switch payload.permissionDecision {
            case .deny:
                object = blockObject(reason: payload.permissionDecisionReason)
            case .allow:
                object = approveObject(updatedInput: payload.updatedInput, eventName: "PreToolUse")
            case .ask, nil:
                return nil
            }
        }

        var data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        data.append(UInt8(ascii: "\n"))
        return data
    }

    private static func approveObject(updatedInput: ClaudeHookJSONValue?, eventName: String) -> [String: Any] {
        var object: [String: Any] = ["decision": "approve"]
        if let updatedInput, let encoded = try? JSONEncoder().encode(updatedInput),
           let value = try? JSONSerialization.jsonObject(with: encoded) {
            object["hookSpecificOutput"] = [
                "hookEventName": eventName,
                "updatedInput": value,
            ]
        }
        return object
    }

    private static func blockObject(reason: String?) -> [String: Any] {
        var object: [String: Any] = ["decision": "block"]
        if let reason, !reason.isEmpty {
            object["reason"] = reason
        }
        return object
    }
}
