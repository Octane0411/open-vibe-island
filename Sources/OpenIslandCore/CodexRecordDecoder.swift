import Foundation

/// One decoded line of a rollout transcript.
public struct CodexRecord: Equatable, Sendable {
    public var kind: CodexRecordKind
    public var timestamp: Date?
    /// Present on `sessionMeta` records.
    public var meta: CodexSessionMeta?
    /// Message body, for user and assistant messages.
    public var text: String?
    /// Tool name, for tool-call records.
    public var toolName: String?
    /// Short preview of what the tool is doing (a command line, a path).
    public var commandPreview: String?

    public init(
        kind: CodexRecordKind,
        timestamp: Date? = nil,
        meta: CodexSessionMeta? = nil,
        text: String? = nil,
        toolName: String? = nil,
        commandPreview: String? = nil
    ) {
        self.kind = kind
        self.timestamp = timestamp
        self.meta = meta
        self.text = text
        self.toolName = toolName
        self.commandPreview = commandPreview
    }
}

/// The `session_meta` header.
///
/// Current Codex releases write thirteen or more fields here. The previous
/// implementation read three (`id`, `cwd`, `timestamp`) and ignored
/// `originator` and `source` — the two fields that actually determine whether a
/// transcript belongs to Codex.app, the CLI, the VS Code extension, or a thread
/// Codex spawned for itself.
public struct CodexSessionMeta: Equatable, Sendable {
    public var sessionID: String
    public var cwd: String
    public var timestamp: Date?
    public var originator: String?
    public var cliVersion: String?
    public var source: CodexMetaSource
    public var threadSource: String?

    public init(
        sessionID: String,
        cwd: String,
        timestamp: Date? = nil,
        originator: String? = nil,
        cliVersion: String? = nil,
        source: CodexMetaSource = .unknown,
        threadSource: String? = nil
    ) {
        self.sessionID = sessionID
        self.cwd = cwd
        self.timestamp = timestamp
        self.originator = originator
        self.cliVersion = cliVersion
        self.source = source
        self.threadSource = threadSource
    }
}

/// Turns rollout transcript lines into typed records.
///
/// The decoder is tolerant by construction: a line it cannot classify is
/// counted against the Codex version that wrote it and skipped, rather than
/// silently discarded or allowed to fail the whole read. Drift shows up in the
/// diagnostics pane the day it starts, instead of as a mystery weeks later.
public struct CodexRecordDecoder: Sendable {
    private let diagnostics: CodexDiagnostics?

    public init(diagnostics: CodexDiagnostics? = nil) {
        self.diagnostics = diagnostics
    }

    /// Decode one JSONL line. Returns `nil` for blank lines, malformed JSON, or
    /// record types outside the known vocabulary (which are reported first).
    public func decode(line: String, cliVersion: String? = nil) -> CodexRecord? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let data = trimmed.data(using: .utf8) else {
            return nil
        }
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        guard let type = object["type"] as? String else {
            return nil
        }

        let timestamp = Self.parseTimestamp(object["timestamp"] as? String)

        // Records whose meaning lives at the top level.
        if let kind = CodexRecordTable.kind(forTopLevel: type) {
            if kind == .sessionMeta {
                guard let meta = Self.decodeSessionMeta(object) else { return nil }
                return CodexRecord(kind: .sessionMeta, timestamp: timestamp ?? meta.timestamp, meta: meta)
            }
            return CodexRecord(kind: kind, timestamp: timestamp)
        }

        // Records that wrap their meaning in `payload`.
        guard type == "event_msg" || type == "response_item" else {
            diagnostics?.recordUnknownRecordType(type, cliVersion: cliVersion)
            return nil
        }
        guard let payload = object["payload"] as? [String: Any] else {
            return nil
        }

        // `response_item` messages carry `role` instead of a payload `type`.
        let payloadType = (payload["type"] as? String)
            ?? (payload["role"] as? String).map { $0 == "assistant" ? "agent_message" : "user_message" }

        guard let payloadType else {
            return nil
        }

        // Approvals moved to hooks. Recognize the retired literals so they do
        // not register as drift, but produce nothing — actionable state comes
        // from the hook source alone.
        if CodexRecordTable.isRetiredApprovalType(payloadType) {
            return nil
        }

        guard let kind = CodexRecordTable.kind(forPayload: payloadType) else {
            diagnostics?.recordUnknownRecordType(payloadType, cliVersion: cliVersion)
            return nil
        }

        switch kind {
        case .userMessage, .assistantMessage:
            return CodexRecord(
                kind: kind,
                timestamp: timestamp,
                text: Self.extractText(from: payload)
            )
        case .toolCallBegin, .toolCallEnd:
            return CodexRecord(
                kind: kind,
                timestamp: timestamp,
                toolName: Self.extractToolName(from: payload, fallback: payloadType),
                commandPreview: Self.extractCommandPreview(from: payload)
            )
        default:
            return CodexRecord(kind: kind, timestamp: timestamp)
        }
    }

    // MARK: - Field extraction

    static func decodeSessionMeta(_ object: [String: Any]) -> CodexSessionMeta? {
        let payload = object["payload"] as? [String: Any] ?? [:]
        // Recent releases write both `id` and `session_id`; older ones only `id`.
        let sessionID = (payload["id"] as? String)
            ?? (payload["session_id"] as? String)
        guard let sessionID, !sessionID.isEmpty else { return nil }
        guard let cwd = payload["cwd"] as? String, !cwd.isEmpty else { return nil }

        return CodexSessionMeta(
            sessionID: sessionID,
            cwd: cwd,
            timestamp: parseTimestamp(
                (payload["timestamp"] as? String) ?? (object["timestamp"] as? String)
            ),
            originator: payload["originator"] as? String,
            cliVersion: payload["cli_version"] as? String,
            source: CodexMetaSource(json: payload["source"]),
            threadSource: payload["thread_source"] as? String
        )
    }

    static func extractText(from payload: [String: Any]) -> String? {
        if let message = payload["message"] as? String, !message.isEmpty {
            return message
        }
        if let text = payload["text"] as? String, !text.isEmpty {
            return text
        }
        // `response_item` bodies arrive as an array of content parts.
        if let content = payload["content"] as? [[String: Any]] {
            let joined = content
                .compactMap { $0["text"] as? String }
                .joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return joined.isEmpty ? nil : joined
        }
        return nil
    }

    static func extractToolName(from payload: [String: Any], fallback: String) -> String? {
        if let name = payload["name"] as? String, !name.isEmpty {
            return name
        }
        if let tool = payload["tool_name"] as? String, !tool.isEmpty {
            return tool
        }
        if let server = payload["server"] as? String, !server.isEmpty {
            return server
        }
        return fallback
    }

    static func extractCommandPreview(from payload: [String: Any]) -> String? {
        if let command = payload["command"] as? String, !command.isEmpty {
            return command
        }
        if let command = payload["command"] as? [String], !command.isEmpty {
            return command.joined(separator: " ")
        }
        if let arguments = payload["arguments"] as? String, !arguments.isEmpty {
            return String(arguments.prefix(200))
        }
        return nil
    }

    static func parseTimestamp(_ string: String?) -> Date? {
        guard let string else { return nil }
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = withFraction.date(from: string) { return date }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: string)
    }
}
