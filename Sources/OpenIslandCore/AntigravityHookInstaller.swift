import Foundation

public struct AntigravityHookInstallerManifest: Equatable, Codable, Sendable {
    public static let fileName = "open-island-antigravity-hooks-install.json"

    public var hookCommand: String
    public var installedAt: Date

    public init(hookCommand: String, installedAt: Date = .now) {
        self.hookCommand = hookCommand
        self.installedAt = installedAt
    }
}

public typealias GeminiHookInstallerManifest = AntigravityHookInstallerManifest

public struct AntigravityHookFileMutation: Equatable, Sendable {
    public var contents: Data?
    public var changed: Bool
    public var managedHooksPresent: Bool

    public init(contents: Data?, changed: Bool, managedHooksPresent: Bool) {
        self.contents = contents
        self.changed = changed
        self.managedHooksPresent = managedHooksPresent
    }
}

public typealias GeminiHookFileMutation = AntigravityHookFileMutation

public enum AntigravityHookInstallerError: Error, LocalizedError {
    case invalidSettingsJSON

    public var errorDescription: String? {
        switch self {
        case .invalidSettingsJSON:
            "The existing Antigravity settings.json is not valid JSON."
        }
    }
}

public typealias GeminiHookInstallerError = AntigravityHookInstallerError

public enum AntigravityHookInstaller {
    private static let eventSpecs: [(name: String, matcher: String?)] = [
        ("SessionStart", "*"),
        ("SessionEnd", "*"),
        ("BeforeAgent", "*"),
        ("AfterAgent", "*"),
        ("Notification", "*"),
    ]

    public static func hookCommand(for binaryPath: String) -> String {
        "\(shellQuote(binaryPath)) --source antigravity"
    }

    public static func installSettingsJSON(
        existingData: Data?,
        hookCommand: String
    ) throws -> AntigravityHookFileMutation {
        var rootObject = try loadRootObject(from: existingData)
        var hooksObject = rootObject["hooks"] as? [String: Any] ?? [:]

        for spec in eventSpecs {
            var groups = hooksObject[spec.name] as? [[String: Any]] ?? []
            groups = groups.filter { !isManagedGroup($0, managedCommand: hookCommand) }
            groups.append(managedGroup(matcher: spec.matcher, hookCommand: hookCommand))
            hooksObject[spec.name] = groups
        }

        rootObject["hooks"] = hooksObject
        let data = try serialize(rootObject)
        return AntigravityHookFileMutation(
            contents: data,
            changed: data != existingData,
            managedHooksPresent: true
        )
    }

    public static func uninstallSettingsJSON(
        existingData: Data?,
        managedCommand: String?
    ) throws -> AntigravityHookFileMutation {
        guard let existingData else {
            return AntigravityHookFileMutation(contents: nil, changed: false, managedHooksPresent: false)
        }

        var rootObject = try loadRootObject(from: existingData)
        var hooksObject = rootObject["hooks"] as? [String: Any] ?? [:]
        var mutated = false

        for spec in eventSpecs {
            let groups = hooksObject[spec.name] as? [[String: Any]] ?? []
            let filtered = groups.filter { !isManagedGroup($0, managedCommand: managedCommand) }
            if filtered.count != groups.count {
                mutated = true
            }

            if filtered.isEmpty {
                hooksObject.removeValue(forKey: spec.name)
            } else {
                hooksObject[spec.name] = filtered
            }
        }

        if hooksObject.isEmpty {
            rootObject.removeValue(forKey: "hooks")
        } else {
            rootObject["hooks"] = hooksObject
        }

        let contents = rootObject.isEmpty ? nil : try serialize(rootObject)
        return AntigravityHookFileMutation(
            contents: contents,
            changed: mutated || contents != existingData,
            managedHooksPresent: mutated
        )
    }

    private static func loadRootObject(from data: Data?) throws -> [String: Any] {
        guard let data else { return [:] }

        let object = try JSONSerialization.jsonObject(with: data)
        guard let rootObject = object as? [String: Any] else {
            throw AntigravityHookInstallerError.invalidSettingsJSON
        }

        return rootObject
    }

    private static func serialize(_ object: [String: Any]) throws -> Data {
        try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
    }

    private static func managedGroup(matcher: String?, hookCommand: String) -> [String: Any] {
        let hook: [String: Any] = [
            "type": "command",
            "command": hookCommand,
            "name": "Open Island"
        ]

        var group: [String: Any] = [
            "hooks": [hook]
        ]

        if let matcher {
            group["matcher"] = matcher
        }

        return group
    }

    private static func isManagedGroup(_ group: [String: Any], managedCommand: String?) -> Bool {
        guard let hooks = group["hooks"] as? [[String: Any]] else {
            return false
        }

        return hooks.contains { hook in
            guard let command = hook["command"] as? String else { return false }
            if let managedCommand, command == managedCommand {
                return true
            }
            return isOpenIslandAntigravityHookCommand(command)
        }
    }

    private static func isOpenIslandAntigravityHookCommand(_ command: String) -> Bool {
        let normalized = command.lowercased()
        return (normalized.contains("openislandhooks") || normalized.contains("vibeislandhooks"))
            && (normalized.contains("antigravity") || normalized.contains("gemini"))
    }

    private static func shellQuote(_ string: String) -> String {
        guard !string.isEmpty else { return "''" }
        return "'\(string.replacingOccurrences(of: "'", with: "'\\''"))'"
    }
}

public typealias GeminiHookInstaller = AntigravityHookInstaller
