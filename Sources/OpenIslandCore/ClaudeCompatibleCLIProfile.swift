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
        self.displayName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        self.hookSource = hookSource.trimmingCharacters(in: .whitespacesAndNewlines)
        self.executablePath = executablePath.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Normalized path, always trimmed. Internal consumers should use this
    /// rather than accessing `executablePath` directly.
    public var normalizedExecutablePath: String {
        executablePath.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public var executableBasename: String {
        URL(fileURLWithPath: normalizedExecutablePath).lastPathComponent
    }

    /// Whether the profile has all required fields filled in and valid.
    public var isValid: Bool {
        !displayName.isEmpty
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

        let tokens = command.split(whereSeparator: \.isWhitespace).map(String.init)
        return tokens.contains { token in
            token == path || URL(fileURLWithPath: token).lastPathComponent == executableBasename
        }
    }

    // MARK: - Codable

    /// Trim whitespace on decode, matching the init behaviour so that
    /// profiles persisted via JSON (UserDefaults) are always normalized.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(UUID.self, forKey: .id)
        self.displayName = (try container.decode(String.self, forKey: .displayName))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        self.hookSource = (try container.decode(String.self, forKey: .hookSource))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        self.executablePath = (try container.decode(String.self, forKey: .executablePath))
            .trimmingCharacters(in: .whitespacesAndNewlines)
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