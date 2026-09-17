import Foundation

/// A single named Claude Code configuration directory ("account").
///
/// Users who run multiple Claude accounts (e.g. personal, work, client) each
/// have their own `~/.claude`-style directory (commonly pointed at via
/// `CLAUDE_CONFIG_DIR`). This lets Open Island track more than one at once.
public struct ClaudeAccountDirectory: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var label: String
    public var directoryPath: String

    public var directoryURL: URL {
        URL(fileURLWithPath: directoryPath, isDirectory: true)
    }

    public init(id: UUID = UUID(), label: String, directoryURL: URL) {
        self.id = id
        self.label = label
        self.directoryPath = directoryURL.path
    }
}

/// Persists and resolves the set of Claude config directories ("accounts")
/// the user wants Open Island to monitor.
public enum ClaudeAccountsStore {
    public static let defaultsKey = "claude.accountDirectories"

    /// The user-configured list of accounts. Empty when the user has not
    /// opted into multi-account tracking, in which case `effectiveDirectories`
    /// falls back to the single `ClaudeConfigDirectory` setting.
    public static var accounts: [ClaudeAccountDirectory] {
        get {
            guard let data = UserDefaults.standard.data(forKey: defaultsKey) else {
                return []
            }
            return (try? JSONDecoder().decode([ClaudeAccountDirectory].self, from: data)) ?? []
        }
        set {
            if newValue.isEmpty {
                UserDefaults.standard.removeObject(forKey: defaultsKey)
            } else if let data = try? JSONEncoder().encode(newValue) {
                UserDefaults.standard.set(data, forKey: defaultsKey)
            }
        }
    }

    /// The directories Open Island should discover sessions in / install
    /// hooks into: every account the user has explicitly added, plus the
    /// existing (legacy) `ClaudeConfigDirectory` if it isn't already covered
    /// by one of them. This is additive — configuring extra accounts never
    /// stops monitoring the directory that already worked before this
    /// feature existed. A user-added account whose directory happens to
    /// match the default takes precedence, so the default account can be
    /// labeled too (e.g. when `CLAUDE_CONFIG_DIR` already points at it).
    public static func effectiveDirectories(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> [ClaudeAccountDirectory] {
        let defaultURL = ClaudeConfigDirectory.resolved(environment: environment)
        let defaultPath = defaultURL.standardizedFileURL.path
        var seenPaths: Set<String> = []
        var result: [ClaudeAccountDirectory] = []

        for account in accounts {
            let path = account.directoryURL.standardizedFileURL.path
            guard !seenPaths.contains(path) else { continue }
            seenPaths.insert(path)
            result.append(account)
        }

        if !seenPaths.contains(defaultPath) {
            result.append(ClaudeAccountDirectory(label: "", directoryURL: defaultURL))
        }
        return result
    }

    /// Account labels are only surfaced in the UI once the user has actually
    /// added at least one extra account — this avoids cluttering the notch
    /// for the common single-account case.
    public static var shouldShowAccountLabels: Bool {
        !accounts.isEmpty
    }

    @discardableResult
    public static func add(label: String, directoryURL: URL) -> ClaudeAccountDirectory {
        let account = ClaudeAccountDirectory(label: label, directoryURL: directoryURL)
        accounts.append(account)
        return account
    }

    public static func remove(id: UUID) {
        var current = accounts
        current.removeAll { $0.id == id }
        accounts = current
    }

    public static func update(_ account: ClaudeAccountDirectory) {
        var current = accounts
        guard let index = current.firstIndex(where: { $0.id == account.id }) else {
            return
        }
        current[index] = account
        accounts = current
    }

    /// Resolves the configured account label for an arbitrary file path (e.g.
    /// a transcript or hook manifest path) by matching it against the
    /// configured account directories. Returns `nil` when zero or one
    /// account is configured, since there's nothing to disambiguate.
    public static func label(forPath path: String) -> String? {
        guard shouldShowAccountLabels else {
            return nil
        }
        let standardizedPath = (path as NSString).standardizingPath
        for account in accounts {
            let prefix = account.directoryURL.standardizedFileURL.path
            if standardizedPath.hasPrefix(prefix) {
                return account.label
            }
        }
        return nil
    }
}
