import Foundation

/// A user-defined profile for a Claude Code-compatible CLI wrapper.
///
/// Each profile holds a display name, the identifier passed as ``--source``
/// in the hook invocation, and the path to the CLI executable. Process
/// detection auto-derives matching strategies from the executable path:
///
/// - The full path appears anywhere in the command line.
/// - A token in the command equals the full path.
/// - A token's last path component matches the executable's basename.
///
/// - Note: Whitespace trimming is centralised in ``init(displayName:hookSource:executablePath:)``
///   and the ``Codable`` decoder, so consumers never need to trim manually.
public struct ClaudeCompatibleCLIProfile: Codable, Equatable, Identifiable, Sendable {
    /// Stable identifier used for equality and UI identity.
    public var id: UUID
    /// Human-readable name shown in the settings list (e.g. "Company Claude").
    public var displayName: String
    /// Value passed as ``--source`` when the hook CLI invokes OpenIslandHooks.
    /// Only ``[A-Za-z0-9._-]`` characters are allowed — validated by ``isValidHookSource(_:)``.
    public var hookSource: String
    /// Absolute path to the CLI executable. Auto-derives process matching
    /// strategies; a leading tilde is not expanded, so prefer an absolute path.
    public var executablePath: String

    /// Creates a profile with trimming of all string fields.
    ///
    /// - Parameters:
    ///   - id: Stable identifier. Defaults to a new UUID.
    ///   - displayName: Human-readable name for the settings UI.
    ///   - hookSource: Identifier for the ``--source`` hook argument. Must match
    ///     ``isValidHookSource(_:)`` for the profile to be considered valid.
    ///   - executablePath: Absolute path to the CLI executable.
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

    /// The last path component of ``normalizedExecutablePath``.
    ///
    /// Used internally by ``matches(command:)`` to compare against command
    /// tokens by basename alone.
    public var executableBasename: String {
        URL(fileURLWithPath: normalizedExecutablePath).lastPathComponent
    }

    /// Whether the profile has all required fields filled in and valid.
    ///
    /// A profile is valid when:
    /// - ``displayName`` is non-empty after trimming.
    /// - ``hookSource`` is non-empty and matches ``isValidHookSource(_:)``.
    /// - ``executablePath`` is non-empty after trimming.
    /// - ``executableBasename`` is non-empty.
    ///
    /// Invalid profiles are filtered out on load (see ``ClaudeCompatibleCLIProfileStore.load()``).
    public var isValid: Bool {
        !displayName.isEmpty
            && Self.isValidHookSource(hookSource)
            && !normalizedExecutablePath.isEmpty
            && !executableBasename.isEmpty
    }

    /// Validate a hook-source string.
    ///
    /// Accepted characters: ``[A-Za-z0-9._-]``. This guarantees the source
    /// can safely appear on a command line without quoting issues.
    ///
    /// - Parameter source: The raw source string to validate.
    /// - Returns: ``true`` when the source is non-empty and matches the
    ///   allowed character set.
    public static func isValidHookSource(_ source: String) -> Bool {
        guard !source.isEmpty else { return false }
        return source.range(of: #"^[A-Za-z0-9._-]+$"#, options: .regularExpression) != nil
    }

    /// Check whether a command line matches this profile.
    ///
    /// Matching uses two strategies derived from ``executablePath``:
    /// 1. A whitespace-delimited token equals the full path.
    /// 2. A token's last path component equals the executable's basename.
    ///
    /// - Parameter command: The raw command line (e.g. the ``command`` field
    ///   from a ``ProcessInfo``-style snapshot).
    /// - Returns: ``true`` if the command appears to have been launched via
    ///   this profile's executable.
    ///
    /// - Note: Returns ``false`` immediately when ``isValid`` is false.
    public func matches(command: String) -> Bool {
        guard isValid else { return false }

        let path = normalizedExecutablePath
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

/// Persists an array of ``ClaudeCompatibleCLIProfile`` values via `UserDefaults`.
///
/// Profiles are serialised as JSON. On load, invalid profiles (see
/// ``ClaudeCompatibleCLIProfile/isValid``) are silently filtered out so
/// that a corrupt or manually edited defaults entry degrades gracefully.
///
/// - Note: This class is ``@unchecked Sendable`` because ``UserDefaults``
///   is thread-safe on the platforms we target, even though the compiler
///   cannot prove it.
public final class ClaudeCompatibleCLIProfileStore: @unchecked Sendable {
    /// The default `UserDefaults` key used when no custom key is provided.
    public static let defaultKey = "customClaudeCompatibleCLIProfiles"

    private let userDefaults: UserDefaults
    private let key: String

    /// Create a store backed by a specific `UserDefaults` and key pair.
    ///
    /// - Parameters:
    ///   - userDefaults: The `UserDefaults` instance to use. Defaults to ``.standard``.
    ///   - key: The key under which the encoded profile array is stored.
    ///     Defaults to ``defaultKey``.
    public init(
        userDefaults: UserDefaults = .standard,
        key: String = ClaudeCompatibleCLIProfileStore.defaultKey
    ) {
        self.userDefaults = userDefaults
        self.key = key
    }

    /// Load all stored profiles, filtering out any that are invalid.
    ///
    /// - Returns: An array of valid profiles, or an empty array when no
    ///   data exists or decoding fails.
    public func load() -> [ClaudeCompatibleCLIProfile] {
        guard let data = userDefaults.data(forKey: key),
              let profiles = try? JSONDecoder().decode([ClaudeCompatibleCLIProfile].self, from: data) else {
            return []
        }
        return profiles.filter(\.isValid)
    }

    /// Encode and persist the given profiles.
    ///
    /// - Parameter profiles: The profiles to store. Invalid profiles are
    ///   persisted as-is; filtering to only valid entries is the caller's
    ///   responsibility if desired.
    /// - Throws: ``EncodingError`` if JSON encoding fails.
    public func save(_ profiles: [ClaudeCompatibleCLIProfile]) throws {
        let data = try JSONEncoder().encode(profiles)
        userDefaults.set(data, forKey: key)
    }
}