import Foundation

/// Classifies Codex sessions by where they run, and collapses the several
/// identifiers Codex uses into one session key.
///
/// The originator allow-list below is deliberately explicit. Codex has already
/// renamed the desktop client once — real transcripts contain both
/// `Codex Desktop` and `codex_work_desktop`, and a user's history holds a mix
/// of the two — so prefix matching would quietly misclassify half a corpus the
/// next time a name changes. An unrecognized originator is reported through
/// diagnostics instead of guessed at.
public enum CodexIdentityResolver {
    // MARK: - Surface classification

    /// Originators that identify Codex.app. Both spellings must be honoured:
    /// desktop transcripts written before and after the rename coexist on the
    /// same machine indefinitely.
    public static let desktopOriginators: Set<String> = [
        "Codex Desktop",
        "codex_work_desktop",
    ]

    public static let cliOriginators: Set<String> = [
        "codex-tui",
        "codex_tui",
    ]

    public static let execOriginators: Set<String> = [
        "codex_exec",
        "codex-exec",
    ]

    /// Codex-internal daemons that write rollouts but are not user sessions.
    public static let internalOriginators: Set<String> = [
        "slock-daemon",
    ]

    /// Determine the surface from `session_meta`.
    ///
    /// `source` is checked first because it is the only field that reveals a
    /// spawned subagent thread, and those must never reach the session list
    /// regardless of which client spawned them.
    public static func surface(
        originator: String?,
        source: CodexMetaSource?,
        diagnostics: CodexDiagnostics? = nil
    ) -> CodexSurface {
        if case let .subagent(parentThreadID, kind) = source {
            return .subagent(parentThreadID: parentThreadID, kind: kind)
        }

        guard let originator, !originator.isEmpty else {
            // No originator: fall back to the flat `source` string when present.
            if case let .named(value) = source {
                switch value {
                case "cli": return .cli
                case "vscode": return .vscode
                case "exec": return .exec
                default: break
                }
            }
            return .unknown(originator: nil)
        }

        if internalOriginators.contains(originator) {
            return .internalDaemon
        }
        if desktopOriginators.contains(originator) {
            return .desktopApp
        }
        if cliOriginators.contains(originator) {
            return .cli
        }
        if execOriginators.contains(originator) {
            return .exec
        }

        // A flat `source` can still disambiguate an originator we do not know.
        if case let .named(value) = source, value == "vscode" {
            return .vscode
        }

        diagnostics?.recordUnknownOriginator(originator)
        return .unknown(originator: originator)
    }

    // MARK: - Session key

    /// Collapse a source-specific reference to the stable session key.
    ///
    /// Codex thread IDs and session IDs are the same UUID space in current
    /// releases, so both map directly. Rollout filenames embed the session UUID
    /// and are parsed for it; a file that does not match yields `nil`, and the
    /// caller waits until it has read `session_meta`.
    public static func sessionKey(for ref: CodexIdentityRef) -> String? {
        switch ref {
        case let .threadID(value):
            return value.isEmpty ? nil : value
        case let .sessionID(value):
            return value.isEmpty ? nil : value
        case let .rolloutFile(url):
            return sessionID(fromRolloutFilename: url.lastPathComponent)
        case .processID:
            // A pid alone never identifies a session; the process source must
            // carry a session or thread reference alongside it.
            return nil
        }
    }

    /// Extract the trailing session UUID from `rollout-<timestamp>-<uuid>.jsonl`.
    public static func sessionID(fromRolloutFilename filename: String) -> String? {
        guard filename.hasPrefix("rollout-"), filename.hasSuffix(".jsonl") else {
            return nil
        }
        guard let range = filename.range(
            of: #"[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}\.jsonl$"#,
            options: [.regularExpression]
        ) else {
            return nil
        }
        return String(filename[range]).replacingOccurrences(of: ".jsonl", with: "")
    }
}

/// The `session_meta.source` field, which is polymorphic in practice.
///
/// Real transcripts carry it as a plain string most of the time (`"cli"`,
/// `"vscode"`, `"exec"`) and as a nested object for threads Codex spawned for
/// itself (`{"subagent": {"thread_spawn": {...}}}`,
/// `{"subagent": {"other": "guardian"}}`). Decoding it as `String` — as the
/// previous implementation did — throws on the object form and takes the whole
/// record down with it, which is why spawned threads either vanished or
/// surfaced as bogus user sessions.
public enum CodexMetaSource: Equatable, Sendable {
    case named(String)
    case subagent(parentThreadID: String?, kind: String?)
    case unknown

    public init(json: Any?) {
        switch json {
        case let value as String:
            self = .named(value)
        case let object as [String: Any]:
            if let subagent = object["subagent"] as? [String: Any] {
                if let spawn = subagent["thread_spawn"] as? [String: Any] {
                    let parent = (spawn["parent_thread_id"] as? String)
                        ?? (spawn["parent_turn_id"] as? String)
                    self = .subagent(parentThreadID: parent, kind: "thread_spawn")
                } else if let other = subagent["other"] as? String {
                    self = .subagent(parentThreadID: nil, kind: other)
                } else {
                    self = .subagent(parentThreadID: nil, kind: nil)
                }
            } else {
                self = .unknown
            }
        default:
            self = .unknown
        }
    }
}

extension CodexMetaSource: Decodable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let value = try? container.decode(String.self) {
            self = .named(value)
            return
        }
        if let object = try? container.decode(RawJSONObject.self) {
            self = CodexMetaSource(json: object.value)
            return
        }
        self = .unknown
    }
}

/// Minimal `Decodable` bridge for a JSON object of unknown shape, used where
/// Codex fields are polymorphic and a typed model would reject valid data.
struct RawJSONObject: Decodable {
    let value: [String: Any]

    private struct AnyKey: CodingKey {
        let stringValue: String
        let intValue: Int? = nil
        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { nil }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: AnyKey.self)
        var result: [String: Any] = [:]
        for key in container.allKeys {
            if let value = try? container.decode(String.self, forKey: key) {
                result[key.stringValue] = value
            } else if let value = try? container.decode(Double.self, forKey: key) {
                result[key.stringValue] = value
            } else if let value = try? container.decode(Bool.self, forKey: key) {
                result[key.stringValue] = value
            } else if let value = try? container.decode(RawJSONObject.self, forKey: key) {
                result[key.stringValue] = value.value
            }
        }
        value = result
    }
}
