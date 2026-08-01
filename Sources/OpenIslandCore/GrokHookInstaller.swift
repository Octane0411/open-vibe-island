import Foundation

public struct GrokHookInstallerManifest: Equatable, Codable, Sendable {
    public static let fileName = "open-island-grok-hooks-install.json"

    public var hookCommand: String
    public var installedAt: Date

    public init(hookCommand: String, installedAt: Date = .now) {
        self.hookCommand = hookCommand
        self.installedAt = installedAt
    }
}

public struct GrokHookFileMutation: Equatable, Sendable {
    public var contents: Data?
    public var changed: Bool
    public var managedHooksPresent: Bool

    public init(contents: Data?, changed: Bool, managedHooksPresent: Bool) {
        self.contents = contents
        self.changed = changed
        self.managedHooksPresent = managedHooksPresent
    }
}

public enum GrokHookInstallerError: Error, LocalizedError, Equatable {
    case managedFileNotOwnedByOpenIsland

    public var errorDescription: String? {
        switch self {
        case .managedFileNotOwnedByOpenIsland:
            "Refusing to uninstall \(GrokHookInstaller.managedHooksFileName): the file is not an Open Island managed Grok hooks file."
        }
    }
}

/// Installs Open Island's managed Grok Build hooks as a dedicated file under
/// `~/.grok/hooks/open-island.json`.
///
/// Grok discovers every `*.json` in `~/.grok/hooks/`, so writing a dedicated
/// managed file (matching the commercial Vibe Island layout) avoids mutating
/// user-authored hooks and makes uninstall a simple delete of *our* file only.
public enum GrokHookInstaller {
    public static let managedHooksFileName = "open-island.json"
    public static let managedTimeout = 45

    /// Full managed event set claimed by the product (must stay in sync with
    /// `GrokHookEventName` / `BridgeServer.handleGrokHook` / docs).
    ///
    /// Lifecycle-focused install. PreToolUse is observation-only (fail-open
    /// without a deny decision on stdout), so a 45s timeout does not block the
    /// agent when the bridge is unhealthy.
    public static let requiredEventSpecs: [(name: String, matcher: String?, timeout: Int?)] = [
        ("SessionStart", nil, managedTimeout),
        ("SessionEnd", nil, managedTimeout),
        ("UserPromptSubmit", nil, managedTimeout),
        ("Stop", nil, managedTimeout),
        ("StopFailure", nil, managedTimeout),
        ("Notification", "*", managedTimeout),
        ("PreToolUse", "*", managedTimeout),
        ("PostToolUse", "*", managedTimeout),
        ("PostToolUseFailure", "*", managedTimeout),
        ("SubagentStart", nil, managedTimeout),
        ("SubagentStop", nil, managedTimeout),
        ("PermissionDenied", nil, managedTimeout),
        ("PreCompact", nil, managedTimeout),
        ("PostCompact", nil, managedTimeout),
    ]

    public static var requiredEventNames: [String] {
        requiredEventSpecs.map(\.name)
    }

    public static func hookCommand(for binaryPath: String) -> String {
        "\(shellQuote(binaryPath)) --source grok"
    }

    public static func installHooksJSON(
        existingData: Data? = nil,
        hookCommand: String
    ) throws -> GrokHookFileMutation {
        var hooksObject: [String: Any] = [:]

        for spec in requiredEventSpecs {
            hooksObject[spec.name] = [
                managedGroup(matcher: spec.matcher, timeout: spec.timeout, hookCommand: hookCommand),
            ]
        }

        let rootObject: [String: Any] = ["hooks": hooksObject]
        let data = try serialize(rootObject)
        let changed = data != existingData

        return GrokHookFileMutation(
            contents: data,
            changed: changed,
            managedHooksPresent: true
        )
    }

    /// Managed integration is present only when **every** required event is
    /// registered with an Open Island Grok command hook.
    ///
    /// Commercial Vibe Island commands (`vibe-island-bridge --source grok`) do
    /// **not** count as Open Island installed.
    public static func managedHooksPresent(in data: Data?, managedCommand: String?) -> Bool {
        guard let data,
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let hooks = object["hooks"] as? [String: Any] else {
            return false
        }

        for eventName in requiredEventNames {
            guard let groups = hooks[eventName] as? [Any],
                  eventHasOpenIslandManagedCommand(
                      in: groups,
                      managedCommand: managedCommand
                  ) else {
                return false
            }
        }

        return true
    }

    /// True when the file contains at least one recognizably Open Island Grok
    /// hook command. Used to refuse silent deletion of user-replaced content.
    public static func isOpenIslandOwnedManagedFile(_ data: Data?) -> Bool {
        guard let data,
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let hooks = object["hooks"] as? [String: Any] else {
            return false
        }

        return hooks.values.contains { value in
            let groups = value as? [Any] ?? []
            return eventHasOpenIslandManagedCommand(in: groups, managedCommand: nil)
        }
    }

    private static func eventHasOpenIslandManagedCommand(
        in groups: [Any],
        managedCommand: String?
    ) -> Bool {
        for item in groups {
            guard let group = item as? [String: Any],
                  let hooks = group["hooks"] as? [Any] else {
                continue
            }

            for hook in hooks {
                guard let hook = hook as? [String: Any],
                      let command = hook["command"] as? String else {
                    continue
                }

                // Prefer type == command when present; older/malformed files may omit it.
                if let type = hook["type"] as? String, type != "command" {
                    continue
                }

                if isOpenIslandManagedGrokCommand(command, managedCommand: managedCommand) {
                    return true
                }
            }
        }
        return false
    }

    /// Open Island only — never treat Vibe Island as our install.
    private static func isOpenIslandManagedGrokCommand(
        _ command: String,
        managedCommand: String?
    ) -> Bool {
        if let managedCommand, command == managedCommand {
            return true
        }

        let normalized = command.lowercased()
        guard normalized.contains("--source grok") else {
            return false
        }

        return normalized.contains("openislandhooks")
            || normalized.contains("open-island-bridge")
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

    private static func serialize(_ object: [String: Any]) throws -> Data {
        try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
    }

    private static func shellQuote(_ string: String) -> String {
        guard !string.isEmpty else { return "''" }
        return "'\(string.replacingOccurrences(of: "'", with: "'\\''"))'"
    }
}
