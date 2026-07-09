import Foundation

public struct ClaudeCompatibleCLIProfile: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var displayName: String
    public var hookSource: String
    public var executablePath: String

    public init(
        id: UUID = UUID(),
        displayName: String,
        hookSource: String,
        executablePath: String
    ) {
        self.id = id
        self.displayName = displayName
        self.hookSource = hookSource
        self.executablePath = executablePath
    }

    public var normalizedExecutablePath: String {
        executablePath.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public var executableBasename: String {
        URL(fileURLWithPath: normalizedExecutablePath).lastPathComponent
    }

    public var isValid: Bool {
        !displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && Self.isValidHookSource(hookSource)
            && !normalizedExecutablePath.isEmpty
            && !executableBasename.isEmpty
    }

    public static func isValidHookSource(_ source: String) -> Bool {
        guard !source.isEmpty else { return false }
        return source.range(of: #"^[A-Za-z0-9._-]+$"#, options: .regularExpression) != nil
    }

    public func matches(command: String) -> Bool {
        guard isValid else { return false }

        let path = normalizedExecutablePath
        if command.contains(path) {
            return true
        }

        return Self.commandTokens(from: command).contains { token in
            token == path || URL(fileURLWithPath: token).lastPathComponent == executableBasename
        }
    }

    public static func commandTokens(from command: String) -> [String] {
        command.split(whereSeparator: \.isWhitespace).map(String.init)
    }
}

public final class ClaudeCompatibleCLIProfileStore: @unchecked Sendable {
    public static let defaultKey = "customClaudeCompatibleCLIProfiles"

    private let userDefaults: UserDefaults
    private let key: String

    public init(
        userDefaults: UserDefaults = .standard,
        key: String = ClaudeCompatibleCLIProfileStore.defaultKey
    ) {
        self.userDefaults = userDefaults
        self.key = key
    }

    public func load() -> [ClaudeCompatibleCLIProfile] {
        guard let data = userDefaults.data(forKey: key),
              let profiles = try? JSONDecoder().decode([ClaudeCompatibleCLIProfile].self, from: data) else {
            return []
        }
        return profiles.filter(\.isValid)
    }

    public func save(_ profiles: [ClaudeCompatibleCLIProfile]) throws {
        let data = try JSONEncoder().encode(profiles)
        userDefaults.set(data, forKey: key)
    }
}
