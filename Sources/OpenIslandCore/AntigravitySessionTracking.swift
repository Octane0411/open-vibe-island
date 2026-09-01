import Foundation
import SQLite3

/// Passive session discovery for the Antigravity CLI (`agy`).
///
/// Google's Antigravity CLI shares the `~/.gemini` root with Gemini CLI but
/// nothing else: its settings live in `~/.gemini/antigravity-cli/settings.json`
/// and its hooks vocabulary is Claude-style (`PreToolUse` / `PostToolUse` /
/// `Stop` in a dedicated `hooks.json`), not Gemini CLI's. Because the hook
/// schema is not yet verified against a logged-in CLI, this discovery is
/// intentionally passive — it never writes to Antigravity's files:
///
/// - `conversations/<uuid>.db` — one sqlite DB per conversation; the file
///   mtime is the authoritative activity signal.
/// - `history.jsonl` — append-only prompt log carrying `conversationId`,
///   `workspace`, and the prompt text.
/// - `conversation_summaries.db` — optional titles and workspace URIs.
/// - `presence/<uuid>.lock` — deliberately NOT used for liveness: stale
///   locks linger after the CLI exits, so a live lock does not imply a live
///   session.
///
/// Session liveness is resolved by the app layer: an `agy` process matched
/// to a session keeps it alive; otherwise the session is only visible while
/// its activity is recent.
public struct AntigravitySessionDiscovery: Sendable {
    public let rootURL: URL

    /// Sessions stop being reported once their last activity is older than
    /// this window.
    public static let defaultMaxAge: TimeInterval = 86_400
    /// Without hooks there is no completion signal: a session whose files
    /// went quiet for this long is treated as completed.
    public static let defaultIdleTimeout: TimeInterval = 600
    static let maxDiscoveredSessions = 20
    static let historyTailByteLimit = 256 * 1024

    public init(rootURL: URL = AntigravitySessionDiscovery.defaultRootURL()) {
        self.rootURL = rootURL
    }

    public static func defaultRootURL() -> URL {
        URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent(".gemini", isDirectory: true)
            .appendingPathComponent("antigravity-cli", isDirectory: true)
    }

    /// Scans Antigravity's on-disk state and builds sessions for recently
    /// active conversations. Failures in any single source degrade to fewer
    /// fields rather than dropping the session.
    public func discover(
        now: Date = .now,
        maxAge: TimeInterval = AntigravitySessionDiscovery.defaultMaxAge
    ) -> [AgentSession] {
        let conversations = recentConversationFiles(now: now, maxAge: maxAge)
        guard !conversations.isEmpty else {
            return []
        }

        let prompts = latestPromptsByConversation()
        let summaries = AntigravitySummariesReader(databasePath: summariesDatabasePath())
            .summaries(for: conversations.map(\.id))

        return conversations.compactMap { conversation in
            makeSession(
                conversation: conversation,
                prompt: prompts[conversation.id],
                summary: summaries[conversation.id],
                now: now
            )
        }
    }

    // MARK: - Conversation files

    private struct ConversationFile {
        var id: String
        var modifiedAt: Date
    }

    private func recentConversationFiles(now: Date, maxAge: TimeInterval) -> [ConversationFile] {
        let conversationsURL = rootURL.appendingPathComponent("conversations", isDirectory: true)
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: conversationsURL,
            includingPropertiesForKeys: [.contentModificationDateKey]
        ) else {
            return []
        }

        let files = entries.compactMap { entry -> ConversationFile? in
            guard entry.pathExtension == "db" else {
                return nil
            }
            let resourceValues = try? entry.resourceValues(forKeys: [.contentModificationDateKey])
            guard let modifiedAt = resourceValues?.contentModificationDate else {
                return nil
            }
            guard now.timeIntervalSince(modifiedAt) <= maxAge else {
                return nil
            }
            return ConversationFile(id: entry.deletingPathExtension().lastPathComponent, modifiedAt: modifiedAt)
        }

        return Array(files.sorted { $0.modifiedAt > $1.modifiedAt }.prefix(Self.maxDiscoveredSessions))
    }

    // MARK: - Prompt history

    private struct HistoryEntry {
        var display: String
        var timestamp: Date
        var workspace: String?
        var conversationID: String?
    }

    /// Reads the tail of `history.jsonl` and keeps the newest prompt per
    /// conversation. The file grows without bound, so only the last
    /// ``historyTailByteLimit`` bytes are parsed; a truncated leading line
    /// is skipped.
    private func latestPromptsByConversation() -> [String: HistoryEntry] {
        let historyURL = rootURL.appendingPathComponent("history.jsonl")
        guard let data = tailData(of: historyURL, byteLimit: Self.historyTailByteLimit) else {
            return [:]
        }

        var latest: [String: HistoryEntry] = [:]
        for line in data.split(separator: UInt8(ascii: "\n")) {
            guard let entry = parseHistoryLine(String(decoding: line, as: UTF8.self)) else {
                continue
            }
            guard let conversationID = entry.conversationID else {
                continue
            }
            if let existing = latest[conversationID], existing.timestamp >= entry.timestamp {
                continue
            }
            latest[conversationID] = entry
        }
        return latest
    }

    private func parseHistoryLine(_ line: String) -> HistoryEntry? {
        guard let data = line.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        let display = object["display"] as? String ?? ""
        // JSONSerialization surfaces JSON numbers as NSNumber, so `Double`
        // always succeeds for the millisecond epoch timestamp.
        let timestampMilliseconds = object["timestamp"] as? Double
        guard let timestampMilliseconds, !display.isEmpty else {
            return nil
        }

        return HistoryEntry(
            display: display,
            timestamp: Date(timeIntervalSince1970: timestampMilliseconds / 1000),
            workspace: object["workspace"] as? String,
            conversationID: object["conversationId"] as? String
        )
    }

    private func tailData(of url: URL, byteLimit: Int) -> Data? {
        guard let handle = try? FileHandle(forReadingFrom: url) else {
            return nil
        }
        defer { try? handle.close() }

        guard let end = try? handle.seekToEnd(), end > 0 else {
            return nil
        }

        let offset = end > UInt64(byteLimit) ? end - UInt64(byteLimit) : 0
        try? handle.seek(toOffset: offset)
        guard var data = try? handle.read(upToCount: Int(end - offset)) else {
            return nil
        }

        if offset > 0, let firstNewline = data.firstIndex(of: UInt8(ascii: "\n")) {
            // Drop the partially-read leading line.
            data = data[data.index(after: firstNewline)...]
        }
        return data
    }

    // MARK: - Session construction

    private func makeSession(
        conversation: ConversationFile,
        prompt: HistoryEntry?,
        summary: AntigravityConversationSummary?,
        now: Date
    ) -> AgentSession? {
        var activityDates = [conversation.modifiedAt]
        if let prompt {
            activityDates.append(prompt.timestamp)
        }
        let updatedAt = activityDates.max() ?? conversation.modifiedAt

        let workspace = prompt?.workspace ?? summary?.workspacePath
        let summaryText = Self.clipped(prompt?.display) ?? Self.clipped(summary?.preview) ?? ""

        return AgentSession(
            id: conversation.id,
            title: title(for: summary, conversationID: conversation.id),
            tool: .antigravity,
            origin: .live,
            phase: now.timeIntervalSince(updatedAt) <= Self.defaultIdleTimeout ? .running : .completed,
            summary: summaryText,
            updatedAt: updatedAt,
            jumpTarget: JumpTarget(
                terminalApp: "Antigravity",
                workspaceName: workspace.map { URL(fileURLWithPath: $0).lastPathComponent } ?? "",
                paneTitle: "",
                workingDirectory: workspace
            )
        )
    }

    private func title(for summary: AntigravityConversationSummary?, conversationID: String) -> String {
        if let title = summary?.title.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty {
            return title
        }
        return "Antigravity \(conversationID.prefix(8))"
    }

    private func summariesDatabasePath() -> String {
        rootURL.appendingPathComponent("conversation_summaries.db").path
    }

    static func clipped(_ value: String?, limit: Int = 110) -> String? {
        guard let value else {
            return nil
        }

        let collapsed = value
            .replacingOccurrences(of: "\n", with: " ")
            .split(separator: " ", omittingEmptySubsequences: true)
            .joined(separator: " ")

        guard !collapsed.isEmpty else {
            return nil
        }

        guard collapsed.count > limit else {
            return collapsed
        }

        let endIndex = collapsed.index(collapsed.startIndex, offsetBy: limit - 1)
        return "\(collapsed[..<endIndex])…"
    }
}

/// A row of `conversation_summaries.db` restricted to the fields Open Island
/// consumes.
public struct AntigravityConversationSummary: Equatable, Sendable {
    public var title: String
    public var preview: String
    public var workspacePath: String?
}

/// Read-only accessor for `~/.gemini/antigravity-cli/conversation_summaries.db`.
/// All failures degrade to an empty result — the file may not exist yet on
/// machines that only just installed the CLI.
public struct AntigravitySummariesReader: Sendable {
    /// The SQLite3 system module does not re-export `SQLITE_TRANSIENT`.
    private static let transientDestructor = unsafeBitCast(
        OpaquePointer(bitPattern: -1),
        to: sqlite3_destructor_type.self
    )

    public let databasePath: String

    public init(databasePath: String) {
        self.databasePath = databasePath
    }

    public func summaries(for conversationIDs: [String]) -> [String: AntigravityConversationSummary] {
        guard !conversationIDs.isEmpty else {
            return [:]
        }

        var database: OpaquePointer?
        guard sqlite3_open_v2(databasePath, &database, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            sqlite3_close(database)
            return [:]
        }
        defer { sqlite3_close(database) }

        let placeholders = conversationIDs.map { _ in "?" }.joined(separator: ",")
        let query = """
        SELECT conversation_id, title, preview, workspace_uris
        FROM conversation_summaries
        WHERE conversation_id IN (\(placeholders))
        """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, query, -1, &statement, nil) == SQLITE_OK else {
            return [:]
        }
        defer { sqlite3_finalize(statement) }

        for (index, conversationID) in conversationIDs.enumerated() {
            sqlite3_bind_text(statement, Int32(index + 1), conversationID, -1, Self.transientDestructor)
        }

        var result: [String: AntigravityConversationSummary] = [:]
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let conversationID = stringColumn(statement, 0) else {
                continue
            }
            result[conversationID] = AntigravityConversationSummary(
                title: stringColumn(statement, 1) ?? "",
                preview: stringColumn(statement, 2) ?? "",
                workspacePath: firstWorkspacePath(stringColumn(statement, 3))
            )
        }
        return result
    }

    private func stringColumn(_ statement: OpaquePointer?, _ index: Int32) -> String? {
        guard let cString = sqlite3_column_text(statement, index) else {
            return nil
        }
        return String(cString: cString)
    }

    /// `workspace_uris` is a JSON array of `file://` URIs; take the first.
    private func firstWorkspacePath(_ raw: String?) -> String? {
        guard let raw, let data = raw.data(using: .utf8),
              let uris = try? JSONSerialization.jsonObject(with: data) as? [String],
              let uri = uris.first else {
            return nil
        }

        guard uri.hasPrefix("file://") else {
            return uri
        }
        var path = String(uri.dropFirst("file://".count))
        // Percent-decode minimally: paths from Antigravity are plain file URIs.
        path = path.replacingOccurrences(of: "%20", with: " ")
        return path
    }
}
