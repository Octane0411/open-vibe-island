import Foundation

public struct AntigravityHookInstallerManifest: Equatable, Codable, Sendable {
    public static let fileName = "open-island-antigravity-hooks-install.json"

    public var preInvocationCommand: String
    public var stopCommand: String
    public var installedAt: Date

    public init(
        preInvocationCommand: String,
        stopCommand: String,
        installedAt: Date = .now
    ) {
        self.preInvocationCommand = preInvocationCommand
        self.stopCommand = stopCommand
        self.installedAt = installedAt
    }
}

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

public enum AntigravityHookInstallerError: Error, LocalizedError {
    case invalidHooksJSON
    case managedHookNameConflict

    public var errorDescription: String? {
        switch self {
        case .invalidHooksJSON:
            "The existing Antigravity hooks.json is not valid JSON."
        case .managedHookNameConflict:
            "The Antigravity hook name reserved by Open Island is already used by another hook."
        }
    }
}

public enum AntigravityHookInstaller {
    public static let managedHookName = "open-island-task-monitor"

    public static func hookCommand(
        for binaryPath: String,
        event: AntigravityHookEventName
    ) -> String {
        let eventArgument: String
        switch event {
        case .preInvocation: eventArgument = "pre-invocation"
        case .stop: eventArgument = "stop"
        }
        return "\(shellQuote(binaryPath)) --source antigravity --event \(eventArgument)"
    }

    public static func installHooksJSON(
        existingData: Data?,
        preInvocationCommand: String,
        stopCommand: String
    ) throws -> AntigravityHookFileMutation {
        var rootObject = try loadRootObject(from: existingData)

        if let existingValue = rootObject[managedHookName] {
            guard let existingDefinition = existingValue as? [String: Any],
                  isOwnedDefinition(existingDefinition) else {
                throw AntigravityHookInstallerError.managedHookNameConflict
            }
        }

        rootObject[managedHookName] = managedDefinition(
            preInvocationCommand: preInvocationCommand,
            stopCommand: stopCommand
        )

        let data = try serialize(rootObject)
        return AntigravityHookFileMutation(
            contents: data,
            changed: data != existingData,
            managedHooksPresent: true
        )
    }

    public static func uninstallHooksJSON(existingData: Data?) throws -> AntigravityHookFileMutation {
        guard let existingData else {
            return AntigravityHookFileMutation(contents: nil, changed: false, managedHooksPresent: false)
        }

        var rootObject = try loadRootObject(from: existingData)
        var removedManagedHooks = false
        if let definition = rootObject[managedHookName] as? [String: Any],
           isOwnedDefinition(definition) {
            rootObject.removeValue(forKey: managedHookName)
            removedManagedHooks = true
        }

        let contents = rootObject.isEmpty ? nil : try serialize(rootObject)
        return AntigravityHookFileMutation(
            contents: contents,
            changed: removedManagedHooks,
            managedHooksPresent: false
        )
    }

    public static func containsManagedHooks(in data: Data?) throws -> Bool {
        let rootObject = try loadRootObject(from: data)
        guard let definition = rootObject[managedHookName] as? [String: Any] else {
            return false
        }
        return isManagedDefinition(definition)
    }

    private static func managedDefinition(
        preInvocationCommand: String,
        stopCommand: String
    ) -> [String: Any] {
        [
            "enabled": true,
            "PreInvocation": [[
                "type": "command",
                "command": preInvocationCommand,
                "timeout": 45,
            ]],
            "Stop": [[
                "type": "command",
                "command": stopCommand,
                "timeout": 45,
            ]],
        ]
    }

    private static func isManagedDefinition(_ definition: [String: Any]) -> Bool {
        let preInvocationCommands = commands(in: definition, for: "PreInvocation")
        let stopCommands = commands(in: definition, for: "Stop")
        return preInvocationCommands.count == 1
            && stopCommands.count == 1
            && (preInvocationCommands + stopCommands).allSatisfy(isOpenIslandAntigravityHookCommand)
    }

    private static func isOwnedDefinition(_ definition: [String: Any]) -> Bool {
        let hookCommands = ["PreInvocation", "Stop"].flatMap { eventName in
            commands(in: definition, for: eventName)
        }
        return !hookCommands.isEmpty && hookCommands.allSatisfy(isOpenIslandAntigravityHookCommand)
    }

    private static func commands(in definition: [String: Any], for eventName: String) -> [String] {
        guard let handlers = definition[eventName] as? [[String: Any]] else { return [] }
        return handlers.compactMap { $0["command"] as? String }
    }

    private static func isOpenIslandAntigravityHookCommand(_ command: String) -> Bool {
        let normalized = command.lowercased()
        return (normalized.contains("openislandhooks") || normalized.contains("vibeislandhooks"))
            && normalized.contains("--source antigravity")
    }

    private static func loadRootObject(from data: Data?) throws -> [String: Any] {
        guard let data else { return [:] }
        let object = try JSONSerialization.jsonObject(with: data)
        guard let rootObject = object as? [String: Any] else {
            throw AntigravityHookInstallerError.invalidHooksJSON
        }
        return rootObject
    }

    private static func serialize(_ object: [String: Any]) throws -> Data {
        try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
    }

    private static func shellQuote(_ string: String) -> String {
        guard !string.isEmpty else { return "''" }
        return "'\(string.replacingOccurrences(of: "'", with: "'\\''"))'"
    }
}
