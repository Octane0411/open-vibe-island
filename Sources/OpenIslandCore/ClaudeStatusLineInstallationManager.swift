import Foundation

public struct ClaudeStatusLineInstallationStatus: Equatable, Sendable {
    public var claudeDirectory: URL
    public var settingsURL: URL
    public var scriptDirectoryURL: URL
    public var scriptURL: URL
    public var cacheURL: URL
    public var statusLineCommand: String?
    public var hasStatusLine: Bool
    public var managedStatusLineConfigured: Bool
    public var managedStatusLineInstalled: Bool
    public var managedStatusLineNeedsRepair: Bool
    public var hasConflictingStatusLine: Bool

    public init(
        claudeDirectory: URL,
        settingsURL: URL,
        scriptDirectoryURL: URL,
        scriptURL: URL,
        cacheURL: URL,
        statusLineCommand: String?,
        hasStatusLine: Bool,
        managedStatusLineConfigured: Bool,
        managedStatusLineInstalled: Bool,
        managedStatusLineNeedsRepair: Bool,
        hasConflictingStatusLine: Bool
    ) {
        self.claudeDirectory = claudeDirectory
        self.settingsURL = settingsURL
        self.scriptDirectoryURL = scriptDirectoryURL
        self.scriptURL = scriptURL
        self.cacheURL = cacheURL
        self.statusLineCommand = statusLineCommand
        self.hasStatusLine = hasStatusLine
        self.managedStatusLineConfigured = managedStatusLineConfigured
        self.managedStatusLineInstalled = managedStatusLineInstalled
        self.managedStatusLineNeedsRepair = managedStatusLineNeedsRepair
        self.hasConflictingStatusLine = hasConflictingStatusLine
    }
}

public enum ClaudeStatusLineInstallationError: LocalizedError, Sendable {
    case existingStatusLineConflict(command: String?)
    case invalidSettingsRoot

    public var errorDescription: String? {
        switch self {
        case let .existingStatusLineConflict(command):
            if let command, !command.isEmpty {
                return "Claude Code already has a custom status line: \(command)"
            }
            return "Claude Code already has a custom status line."
        case .invalidSettingsRoot:
            return "Claude Code settings.json must contain a top-level object."
        }
    }
}

public final class ClaudeStatusLineInstallationManager: @unchecked Sendable {
    public static let managedScriptName = "open-island-statusline"
    public static let legacyManagedScriptName = "vibe-island-statusline"
    public static let managedCacheURL = ClaudeUsageLoader.defaultCacheURL

    public let claudeDirectory: URL
    public let scriptDirectoryURL: URL
    public let legacyScriptDirectoryURL: URL
    private let fileManager: FileManager

    public init(
        claudeDirectory: URL = ClaudeConfigDirectory.resolved(),
        scriptDirectoryURL: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".open-island", isDirectory: true)
            .appendingPathComponent("bin", isDirectory: true),
        legacyScriptDirectoryURL: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".vibe-island", isDirectory: true)
            .appendingPathComponent("bin", isDirectory: true),
        fileManager: FileManager = .default
    ) {
        self.claudeDirectory = claudeDirectory
        self.scriptDirectoryURL = scriptDirectoryURL
        self.legacyScriptDirectoryURL = legacyScriptDirectoryURL
        self.fileManager = fileManager
    }

    public func status() throws -> ClaudeStatusLineInstallationStatus {
        let settingsURL = claudeDirectory.appendingPathComponent("settings.json")
        let scriptURL = scriptDirectoryURL.appendingPathComponent(Self.managedScriptName)
        let legacyScriptURL = legacyScriptDirectoryURL.appendingPathComponent(Self.legacyManagedScriptName)

        let settings = try loadSettings(at: settingsURL)
        let statusLine = settings["statusLine"] as? [String: Any]
        let command = statusLine?["command"] as? String
        let managedCommands = [scriptURL.path, legacyScriptURL.path]
        let managedStatusLineConfigured = managedCommands.contains(command ?? "")
        let managedStatusLineInstalled = managedStatusLineConfigured
            && (command.map { fileManager.fileExists(atPath: $0) } ?? false)
        let managedStatusLineNeedsRepair = managedStatusLineConfigured && !managedStatusLineInstalled
        let hasStatusLine = statusLine != nil
        let hasConflictingStatusLine = hasStatusLine && !managedStatusLineConfigured

        return ClaudeStatusLineInstallationStatus(
            claudeDirectory: claudeDirectory,
            settingsURL: settingsURL,
            scriptDirectoryURL: scriptDirectoryURL,
            scriptURL: scriptURL,
            cacheURL: Self.managedCacheURL,
            statusLineCommand: command,
            hasStatusLine: hasStatusLine,
            managedStatusLineConfigured: managedStatusLineConfigured,
            managedStatusLineInstalled: managedStatusLineInstalled,
            managedStatusLineNeedsRepair: managedStatusLineNeedsRepair,
            hasConflictingStatusLine: hasConflictingStatusLine
        )
    }

    @discardableResult
    public func install(replacingExisting: Bool = false) throws -> ClaudeStatusLineInstallationStatus {
        let currentStatus = try status()
        if currentStatus.hasConflictingStatusLine && !replacingExisting {
            throw ClaudeStatusLineInstallationError.existingStatusLineConflict(
                command: currentStatus.statusLineCommand
            )
        }

        // When replacing an existing status line, wrap it so both work together.
        let wrappedCommand: String? = (replacingExisting && currentStatus.hasConflictingStatusLine)
            ? currentStatus.statusLineCommand
            : existingWrappedCommand()

        try fileManager.createDirectory(at: claudeDirectory, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: scriptDirectoryURL, withIntermediateDirectories: true)

        let settingsURL = currentStatus.settingsURL
        let scriptURL = currentStatus.scriptURL
        let existingSettings = try loadSettings(at: settingsURL)
        var mutatedSettings = existingSettings
        mutatedSettings["statusLine"] = managedStatusLine(for: scriptURL)

        let settingsData = try serializeSettings(mutatedSettings)
        if fileManager.fileExists(atPath: settingsURL.path) {
            try backupFile(at: settingsURL)
        }

        let scriptContents = Self.managedScript(cacheURL: currentStatus.cacheURL, wrappedCommand: wrappedCommand)
        try settingsData.write(to: settingsURL, options: .atomic)
        try scriptContents.write(to: scriptURL, atomically: true, encoding: .utf8)
        try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)
        let legacyScriptURL = legacyScriptDirectoryURL.appendingPathComponent(Self.legacyManagedScriptName)
        if fileManager.fileExists(atPath: legacyScriptURL.path) {
            try fileManager.removeItem(at: legacyScriptURL)
        }

        return try status()
    }

    @discardableResult
    public func uninstall() throws -> ClaudeStatusLineInstallationStatus {
        let currentStatus = try status()
        let settingsURL = currentStatus.settingsURL
        let scriptURL = currentStatus.scriptURL

        // If we wrapped another command, restore it instead of removing statusLine entirely.
        let wrapped = existingWrappedCommand()

        if currentStatus.managedStatusLineConfigured {
            var settings = try loadSettings(at: settingsURL)
            if let wrapped, !wrapped.isEmpty {
                settings["statusLine"] = [
                    "type": "command",
                    "command": wrapped,
                ] as [String: Any]
            } else {
                settings.removeValue(forKey: "statusLine")
            }
            if fileManager.fileExists(atPath: settingsURL.path) {
                try backupFile(at: settingsURL)
            }
            let settingsData = try serializeSettings(settings)
            try settingsData.write(to: settingsURL, options: .atomic)
        }

        if fileManager.fileExists(atPath: scriptURL.path) {
            try fileManager.removeItem(at: scriptURL)
        }
        let legacyScriptURL = legacyScriptDirectoryURL.appendingPathComponent(Self.legacyManagedScriptName)
        if fileManager.fileExists(atPath: legacyScriptURL.path) {
            try fileManager.removeItem(at: legacyScriptURL)
        }

        return try status()
    }

    private func loadSettings(at url: URL) throws -> [String: Any] {
        guard fileManager.fileExists(atPath: url.path) else {
            return [:]
        }

        let data = try Data(contentsOf: url)
        let object = try JSONSerialization.jsonObject(with: data)
        guard let settings = object as? [String: Any] else {
            throw ClaudeStatusLineInstallationError.invalidSettingsRoot
        }
        return settings
    }

    private func serializeSettings(_ settings: [String: Any]) throws -> Data {
        try JSONSerialization.data(withJSONObject: settings, options: [.prettyPrinted, .sortedKeys])
    }

    private func managedStatusLine(for scriptURL: URL) -> [String: Any] {
        [
            "type": "command",
            "command": scriptURL.path,
            "padding": 2,
        ]
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

    /// Marker comment embedded in the generated script to record the original command.
    static let wrappedCommandMarker = "# OPEN_ISLAND_WRAPPED_CMD="

    /// Read the wrapped (original) command from the currently installed managed script, if any.
    private func existingWrappedCommand() -> String? {
        let scriptURL = scriptDirectoryURL.appendingPathComponent(Self.managedScriptName)
        guard let contents = try? String(contentsOf: scriptURL, encoding: .utf8) else { return nil }
        for line in contents.components(separatedBy: "\n") {
            if line.hasPrefix(Self.wrappedCommandMarker) {
                let value = String(line.dropFirst(Self.wrappedCommandMarker.count))
                return value.isEmpty ? nil : value
            }
        }
        return nil
    }

    public static func managedScript(cacheURL: URL = managedCacheURL, wrappedCommand: String? = nil) -> String {
        let markerLine = "\(wrappedCommandMarker)\(wrappedCommand ?? "")"
        let outputSection: String
        if let wrappedCommand, !wrappedCommand.isEmpty {
            // Forward stdin to the original status line command (e.g. claude-hud).
            outputSection = #"echo "$input" | \#(wrappedCommand)"#
        } else {
            // Default: simple one-line status output.
            outputSection = #"echo "$input" | jq -r '"[\(.model.display_name // "Claude")] \(.context_window.used_percentage // 0)% context"' 2>/dev/null"#
        }
        return """
        #!/bin/bash
        \(markerLine)
        # Claude Code StatusLine Script
        # Auto-configured by Open Island
        # FOR AI ASSISTANTS EDITING THIS FILE:
        # This script receives JSON from Claude Code via stdin on
        # every assistant message. The user wants to customize their
        # status line display, so please ADD your code to this file.
        # Do NOT create a separate script or change statusLine.command.
        # IMPORTANT: Keep the rate_limits cache line below intact.
        # It feeds usage data (5h/7d quotas) to the Open Island
        # Notch panel. Removing it will degrade the usage display.
        input=$(cat)
        _rl=$(echo "$input" | jq -c '.rate_limits // empty' 2>/dev/null)
        [ -n "$_rl" ] && printf '%s\\n' "$_rl" > "\(cacheURL.path)"
        \(outputSection)
        """
    }
}
