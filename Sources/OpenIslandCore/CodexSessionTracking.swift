import Dispatch
import Foundation

public struct CodexSessionMetadata: Equatable, Codable, Sendable {
    public var transcriptPath: String?
    public var initialUserPrompt: String?
    public var lastUserPrompt: String?
    public var lastAssistantMessage: String?
    public var currentTool: String?
    public var currentCommandPreview: String?

    public init(
        transcriptPath: String? = nil,
        initialUserPrompt: String? = nil,
        lastUserPrompt: String? = nil,
        lastAssistantMessage: String? = nil,
        currentTool: String? = nil,
        currentCommandPreview: String? = nil
    ) {
        self.transcriptPath = transcriptPath
        self.initialUserPrompt = initialUserPrompt
        self.lastUserPrompt = lastUserPrompt
        self.lastAssistantMessage = lastAssistantMessage
        self.currentTool = currentTool
        self.currentCommandPreview = currentCommandPreview
    }

    public var isEmpty: Bool {
        transcriptPath == nil
            && initialUserPrompt == nil
            && lastUserPrompt == nil
            && lastAssistantMessage == nil
            && currentTool == nil
            && currentCommandPreview == nil
    }
}

public struct CodexTrackedSessionRecord: Equatable, Codable, Sendable {
    public var sessionID: String
    public var title: String
    public var origin: SessionOrigin?
    public var attachmentState: SessionAttachmentState
    public var summary: String
    public var phase: SessionPhase
    public var updatedAt: Date
    public var jumpTarget: JumpTarget?
    public var codexMetadata: CodexSessionMetadata?

    public init(
        sessionID: String,
        title: String,
        origin: SessionOrigin? = nil,
        attachmentState: SessionAttachmentState = .stale,
        summary: String,
        phase: SessionPhase,
        updatedAt: Date,
        jumpTarget: JumpTarget? = nil,
        codexMetadata: CodexSessionMetadata? = nil
    ) {
        self.sessionID = sessionID
        self.title = title
        self.origin = origin
        self.attachmentState = attachmentState
        self.summary = summary
        self.phase = phase
        self.updatedAt = updatedAt
        self.jumpTarget = jumpTarget
        self.codexMetadata = codexMetadata
    }

    public init(session: AgentSession) {
        self.init(
            sessionID: session.id,
            title: session.title,
            origin: session.origin,
            attachmentState: session.attachmentState,
            summary: session.summary,
            phase: session.phase,
            updatedAt: session.updatedAt,
            jumpTarget: session.jumpTarget,
            codexMetadata: session.codexMetadata
        )
    }

    public var session: AgentSession {
        AgentSession(
            id: sessionID,
            title: title,
            tool: .codex,
            origin: origin,
            attachmentState: attachmentState,
            phase: phase,
            summary: summary,
            updatedAt: updatedAt,
            jumpTarget: jumpTarget,
            codexMetadata: codexMetadata
        )
    }

    private enum CodingKeys: String, CodingKey {
        case sessionID
        case title
        case origin
        case attachmentState
        case summary
        case phase
        case updatedAt
        case jumpTarget
        case codexMetadata
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        sessionID = try container.decode(String.self, forKey: .sessionID)
        title = try container.decode(String.self, forKey: .title)
        origin = try container.decodeIfPresent(SessionOrigin.self, forKey: .origin)
        attachmentState = try container.decodeIfPresent(SessionAttachmentState.self, forKey: .attachmentState) ?? .stale
        summary = try container.decode(String.self, forKey: .summary)
        phase = try container.decode(SessionPhase.self, forKey: .phase)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        jumpTarget = try container.decodeIfPresent(JumpTarget.self, forKey: .jumpTarget)
        codexMetadata = try container.decodeIfPresent(CodexSessionMetadata.self, forKey: .codexMetadata)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(sessionID, forKey: .sessionID)
        try container.encode(title, forKey: .title)
        try container.encodeIfPresent(origin, forKey: .origin)
        try container.encode(attachmentState, forKey: .attachmentState)
        try container.encode(summary, forKey: .summary)
        try container.encode(phase, forKey: .phase)
        try container.encode(updatedAt, forKey: .updatedAt)
        try container.encodeIfPresent(jumpTarget, forKey: .jumpTarget)
        try container.encodeIfPresent(codexMetadata, forKey: .codexMetadata)
    }
}

public extension CodexTrackedSessionRecord {
    var restorableSession: AgentSession {
        var session = session
        session.attachmentState = .stale
        return session
    }

    var shouldRestoreToLiveState: Bool {
        origin != .demo && !LegacyMockSessionIDs.all.contains(sessionID)
    }
}

private enum LegacyMockSessionIDs {
    static let all: Set<String> = [
        "claude-fix-auth-bug",
        "codex-backend-server",
        "gemini-optimize-queries",
        "session-running",
        "session-recent",
        "session-claude-research",
        "session-personal",
        "session-open-agent-sdk",
        "session-voice-input",
        "session-agents",
        "session-claude",
        "session-hooks",
        "session-approval",
        "session-question",
        "session-completion",
        "session-completion-long",
    ]
}

public final class CodexSessionStore: @unchecked Sendable {
    public let fileURL: URL
    private let fileManager: FileManager

    public static var defaultDirectoryURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/open-island", isDirectory: true)
    }

    public static var defaultFileURL: URL {
        defaultDirectoryURL.appendingPathComponent("session-terminals.json")
    }

    public init(
        fileURL: URL = CodexSessionStore.defaultFileURL,
        fileManager: FileManager = .default
    ) {
        self.fileURL = fileURL
        self.fileManager = fileManager
    }

    public func load() throws -> [CodexTrackedSessionRecord] {
        guard fileManager.fileExists(atPath: fileURL.path) else {
            return []
        }

        let data = try Data(contentsOf: fileURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode([CodexTrackedSessionRecord].self, from: data)
    }

    public func save(_ records: [CodexTrackedSessionRecord]) throws {
        let directoryURL = fileURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        let data = try encoder.encode(records)
        try data.write(to: fileURL, options: .atomic)
    }
}

public final class CodexRolloutDiscovery: @unchecked Sendable {
    private struct Candidate {
        var fileURL: URL
        var modifiedAt: Date
    }

    private struct SessionMeta {
        var sessionID: String
        var cwd: String
        var timestamp: Date?

        var workspaceName: String {
            let workspace = URL(fileURLWithPath: cwd).lastPathComponent
            return workspace.isEmpty ? "Workspace" : workspace
        }

        var sessionTitle: String {
            "Codex · \(workspaceName)"
        }

        var defaultSummary: String {
            "Started Codex session in \(workspaceName)."
        }
    }

    public static var defaultRootURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex/sessions", isDirectory: true)
    }

    private let rootURL: URL
    private let fileManager: FileManager
    private let maxAge: TimeInterval
    private let maxFiles: Int

    public init(
        rootURL: URL = CodexRolloutDiscovery.defaultRootURL,
        fileManager: FileManager = .default,
        maxAge: TimeInterval = 86_400,
        maxFiles: Int = 40
    ) {
        self.rootURL = rootURL
        self.fileManager = fileManager
        self.maxAge = maxAge
        self.maxFiles = maxFiles
    }

    public func discoverRecentSessions(now: Date = .now) -> [CodexTrackedSessionRecord] {
        guard fileManager.fileExists(atPath: rootURL.path),
              let enumerator = fileManager.enumerator(
                at: rootURL,
                includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
                options: [.skipsHiddenFiles]
              ) else {
            return []
        }

        let cutoff = now.addingTimeInterval(-maxAge)
        var candidates: [Candidate] = []

        for case let fileURL as URL in enumerator {
            guard fileURL.lastPathComponent.hasPrefix("rollout-"),
                  fileURL.pathExtension == "jsonl" else {
                continue
            }

            guard let resourceValues = try? fileURL.resourceValues(
                forKeys: [.contentModificationDateKey, .isRegularFileKey]
            ),
            resourceValues.isRegularFile == true else {
                continue
            }

            let modifiedAt = resourceValues.contentModificationDate ?? .distantPast
            guard modifiedAt >= cutoff else {
                continue
            }

            candidates.append(Candidate(fileURL: fileURL, modifiedAt: modifiedAt))
        }

        let recentCandidates = candidates
            .sorted { lhs, rhs in
                if lhs.modifiedAt == rhs.modifiedAt {
                    return lhs.fileURL.lastPathComponent.localizedStandardCompare(rhs.fileURL.lastPathComponent) == .orderedDescending
                }

                return lhs.modifiedAt > rhs.modifiedAt
            }
            .prefix(maxFiles)

        var recordsByID: [String: CodexTrackedSessionRecord] = [:]
        for candidate in recentCandidates {
            guard let record = discoverRecord(fileURL: candidate.fileURL, modifiedAt: candidate.modifiedAt) else {
                continue
            }

            if let existing = recordsByID[record.sessionID], existing.updatedAt >= record.updatedAt {
                continue
            }

            recordsByID[record.sessionID] = record
        }

        return recordsByID.values.sorted { lhs, rhs in
            if lhs.updatedAt == rhs.updatedAt {
                return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
            }

            return lhs.updatedAt > rhs.updatedAt
        }
    }

    private func discoverRecord(fileURL: URL, modifiedAt: Date) -> CodexTrackedSessionRecord? {
        guard let contents = try? String(contentsOf: fileURL, encoding: .utf8) else {
            return nil
        }

        let lines = contents
            .split(whereSeparator: \.isNewline)
            .map(String.init)
        guard !lines.isEmpty,
              let sessionMeta = sessionMeta(from: lines) else {
            return nil
        }

        let snapshot = CodexRolloutReducer.snapshot(for: lines)
        let summary = snapshot.summary ?? sessionMeta.defaultSummary
        let updatedAt = snapshot.updatedAt ?? sessionMeta.timestamp ?? modifiedAt
        let metadata = CodexSessionMetadata(
            transcriptPath: fileURL.path,
            initialUserPrompt: snapshot.initialUserPrompt,
            lastUserPrompt: snapshot.lastUserPrompt,
            lastAssistantMessage: snapshot.lastAssistantMessage,
            currentTool: snapshot.currentTool,
            currentCommandPreview: snapshot.currentCommandPreview
        )

        return CodexTrackedSessionRecord(
            sessionID: sessionMeta.sessionID,
            title: sessionMeta.sessionTitle,
            origin: .live,
            attachmentState: .stale,
            summary: summary,
            phase: snapshot.phase,
            updatedAt: updatedAt,
            codexMetadata: metadata
        )
    }

    private func sessionMeta(from lines: [String]) -> SessionMeta? {
        for line in lines {
            guard let object = codexRolloutJSONObject(for: line),
                  object["type"] as? String == "session_meta" else {
                continue
            }

            let payload = object["payload"] as? [String: Any] ?? [:]
            guard let sessionID = payload["id"] as? String,
                  !sessionID.isEmpty,
                  let cwd = payload["cwd"] as? String,
                  !cwd.isEmpty else {
                continue
            }

            return SessionMeta(
                sessionID: sessionID,
                cwd: cwd,
                timestamp: codexRolloutParseTimestamp(
                    (payload["timestamp"] as? String) ?? (object["timestamp"] as? String)
                )
            )
        }

        return nil
    }
}

public struct CodexRolloutWatchTarget: Equatable, Sendable {
    public var sessionID: String
    public var transcriptPath: String

    public init(sessionID: String, transcriptPath: String) {
        self.sessionID = sessionID
        self.transcriptPath = transcriptPath
    }
}

struct CodexRolloutPermissionRequest: Equatable, Sendable {
    var callID: String?
    var title: String
    var summary: String
    var affectedPath: String
}

public struct CodexRolloutSnapshot: Equatable, Sendable {
    public var summary: String?
    public var phase: SessionPhase
    public var updatedAt: Date?
    public var initialUserPrompt: String?
    public var lastUserPrompt: String?
    public var lastAssistantMessage: String?
    public var currentTool: String?
    public var currentCommandPreview: String?
    public var isCompleted: Bool
    public var isInterrupted: Bool
    var pendingPermissionRequest: CodexRolloutPermissionRequest?

    public init(
        summary: String? = nil,
        phase: SessionPhase = .running,
        updatedAt: Date? = nil,
        initialUserPrompt: String? = nil,
        lastUserPrompt: String? = nil,
        lastAssistantMessage: String? = nil,
        currentTool: String? = nil,
        currentCommandPreview: String? = nil,
        isCompleted: Bool = false,
        isInterrupted: Bool = false
    ) {
        self.summary = summary
        self.phase = phase
        self.updatedAt = updatedAt
        self.initialUserPrompt = initialUserPrompt
        self.lastUserPrompt = lastUserPrompt
        self.lastAssistantMessage = lastAssistantMessage
        self.currentTool = currentTool
        self.currentCommandPreview = currentCommandPreview
        self.isCompleted = isCompleted
        self.isInterrupted = isInterrupted
        pendingPermissionRequest = nil
    }

    public var metadata: CodexSessionMetadata {
        CodexSessionMetadata(
            initialUserPrompt: initialUserPrompt,
            lastUserPrompt: lastUserPrompt,
            lastAssistantMessage: lastAssistantMessage,
            currentTool: currentTool,
            currentCommandPreview: currentCommandPreview
        )
    }
}

public enum CodexRolloutReducer {
    public static func snapshot(for lines: [String]) -> CodexRolloutSnapshot {
        var snapshot = CodexRolloutSnapshot()
        lines.forEach { apply(line: $0, to: &snapshot) }
        return snapshot
    }

    public static func apply(line: String, to snapshot: inout CodexRolloutSnapshot) {
        guard let object = jsonObject(for: line) else {
            return
        }

        let timestamp = parseTimestamp(object["timestamp"] as? String)
        let payload = object["payload"] as? [String: Any] ?? [:]

        switch object["type"] as? String {
        case "event_msg":
            applyEventMessage(payload, timestamp: timestamp, to: &snapshot)
        case "response_item":
            applyResponseItem(payload, timestamp: timestamp, to: &snapshot)
        default:
            break
        }
    }

    public static func events(
        from oldSnapshot: CodexRolloutSnapshot?,
        to newSnapshot: CodexRolloutSnapshot,
        sessionID: String,
        transcriptPath: String
    ) -> [AgentEvent] {
        var events: [AgentEvent] = []
        let timestamp = newSnapshot.updatedAt ?? .now
        let oldMetadata = oldSnapshot.map {
            CodexSessionMetadata(
                transcriptPath: transcriptPath,
                initialUserPrompt: $0.initialUserPrompt,
                lastUserPrompt: $0.lastUserPrompt,
                lastAssistantMessage: $0.lastAssistantMessage,
                currentTool: $0.currentTool,
                currentCommandPreview: $0.currentCommandPreview
            )
        }
        let newMetadata = CodexSessionMetadata(
            transcriptPath: transcriptPath,
            initialUserPrompt: newSnapshot.initialUserPrompt,
            lastUserPrompt: newSnapshot.lastUserPrompt,
            lastAssistantMessage: newSnapshot.lastAssistantMessage,
            currentTool: newSnapshot.currentTool,
            currentCommandPreview: newSnapshot.currentCommandPreview
        )

        if oldMetadata != newMetadata {
            events.append(
                .sessionMetadataUpdated(
                    SessionMetadataUpdated(
                        sessionID: sessionID,
                        codexMetadata: newMetadata,
                        timestamp: timestamp
                    )
                )
            )
        }

        let oldSummary = oldSnapshot?.summary
        let oldPhase = oldSnapshot?.phase
        let oldCompleted = oldSnapshot?.isCompleted ?? false
        let oldInterrupted = oldSnapshot?.isInterrupted ?? false
        let oldPendingPermission = oldSnapshot?.pendingPermissionRequest
        let newPendingPermission = newSnapshot.pendingPermissionRequest
        let newSummary = newSnapshot.summary ?? oldSummary ?? "Codex updated the current turn."

        if oldPendingPermission != newPendingPermission {
            if let pendingPermission = newPendingPermission {
                events.append(
                    .permissionRequested(
                        PermissionRequested(
                            sessionID: sessionID,
                            request: PermissionRequest(
                                title: pendingPermission.title,
                                summary: pendingPermission.summary,
                                affectedPath: pendingPermission.affectedPath,
                                primaryActionTitle: "Open Codex",
                                secondaryActionTitle: "Later"
                            ),
                            timestamp: timestamp
                        )
                    )
                )
            } else if oldPendingPermission != nil {
                events.append(
                    .actionableStateResolved(
                        ActionableStateResolved(
                            sessionID: sessionID,
                            summary: "Approval was handled in Codex.",
                            timestamp: timestamp
                        )
                    )
                )
            }
        }

        if newSnapshot.isCompleted {
            if !oldCompleted || oldSummary != newSummary || oldInterrupted != newSnapshot.isInterrupted {
                events.append(
                    .sessionCompleted(
                        SessionCompleted(
                            sessionID: sessionID,
                            summary: newSummary,
                            timestamp: timestamp,
                            isInterrupt: newSnapshot.isInterrupted
                        )
                    )
                )
            }
        } else if newPendingPermission != nil {
            // PermissionRequested already carries the actionable waiting state.
        } else if oldSummary != newSummary || oldPhase != newSnapshot.phase {
            events.append(
                .activityUpdated(
                    SessionActivityUpdated(
                        sessionID: sessionID,
                        summary: newSummary,
                        phase: newSnapshot.phase,
                        timestamp: timestamp
                    )
                )
            )
        }

        return events
    }

    private static func applyEventMessage(
        _ payload: [String: Any],
        timestamp: Date?,
        to snapshot: inout CodexRolloutSnapshot
    ) {
        switch payload["type"] as? String {
        case "task_started":
            snapshot.pendingPermissionRequest = nil
            snapshot.phase = .running
            snapshot.isCompleted = false
            snapshot.isInterrupted = false
            snapshot.summary = snapshot.summary ?? "Codex started a new turn."
        case "user_message":
            guard let message = clipped(payload["message"] as? String), !message.isEmpty else {
                break
            }

            applyUserMessage(message, timestamp: timestamp, to: &snapshot)
            return
        case "agent_message":
            guard let message = clipped(payload["message"] as? String), !message.isEmpty else {
                break
            }

            applyAssistantMessage(message, timestamp: timestamp, to: &snapshot)
            return
        case "task_complete":
            snapshot.currentTool = nil
            snapshot.currentCommandPreview = nil
            snapshot.pendingPermissionRequest = nil
            snapshot.phase = .completed
            snapshot.isCompleted = true
            snapshot.isInterrupted = false

            if let message = payload["last_agent_message"] as? String, !message.isEmpty {
                snapshot.lastAssistantMessage = message
                snapshot.summary = message
            } else {
                snapshot.summary = snapshot.summary ?? "Codex completed the turn."
            }
        case "turn_aborted":
            snapshot.currentTool = nil
            snapshot.currentCommandPreview = nil
            snapshot.pendingPermissionRequest = nil
            snapshot.phase = .completed
            snapshot.isCompleted = true
            snapshot.isInterrupted = true
            snapshot.summary = "Codex turn was interrupted."
        case "exec_command_end":
            snapshot.currentTool = nil
            snapshot.currentCommandPreview = nil
            snapshot.pendingPermissionRequest = nil
            if !snapshot.isCompleted {
                snapshot.phase = .running
            }
            snapshot.summary = "Command finished."
        case "patch_apply_end":
            snapshot.currentTool = nil
            snapshot.currentCommandPreview = nil
            snapshot.pendingPermissionRequest = nil
            if !snapshot.isCompleted {
                snapshot.phase = .running
            }
            snapshot.summary = "Patch applied."
        default:
            break
        }

        if let timestamp {
            snapshot.updatedAt = timestamp
        }
    }

    private static func applyResponseItem(
        _ payload: [String: Any],
        timestamp: Date?,
        to snapshot: inout CodexRolloutSnapshot
    ) {
        let itemType = payload["type"] as? String
        if itemType == "message" {
            guard let role = payload["role"] as? String else {
                return
            }

            switch role {
            case "user":
                guard let message = responseMessageText(from: payload, textType: "input_text", skipsInjectedBlocks: true) else {
                    return
                }

                applyUserMessage(message, timestamp: timestamp, to: &snapshot)
            case "assistant":
                guard let message = responseMessageText(from: payload, textType: "output_text", skipsInjectedBlocks: false) else {
                    return
                }

                applyAssistantMessage(message, timestamp: timestamp, to: &snapshot)
            default:
                return
            }

            return
        }

        if itemType == "function_call_output" || itemType == "custom_tool_call_output" {
            if let pendingPermission = snapshot.pendingPermissionRequest {
                let callID = payload["call_id"] as? String
                if pendingPermission.callID == nil || callID == nil || pendingPermission.callID == callID {
                    snapshot.pendingPermissionRequest = nil
                    if !snapshot.isCompleted {
                        snapshot.phase = .running
                        snapshot.summary = "Approval was handled in Codex."
                    }
                }
            }

            if let timestamp {
                snapshot.updatedAt = timestamp
            }
            return
        }

        guard itemType == "function_call" || itemType == "custom_tool_call" else {
            return
        }

        guard let toolName = payload["name"] as? String, !toolName.isEmpty else {
            return
        }

        // After task_complete, trailing response_item entries (function_call
        // results still being flushed) should not reset the completion state.
        guard !snapshot.isCompleted else {
            if let timestamp {
                snapshot.updatedAt = timestamp
            }
            return
        }

        if let pendingPermission = permissionRequest(for: toolName, payload: payload) {
            snapshot.pendingPermissionRequest = pendingPermission
            snapshot.currentTool = toolName
            snapshot.currentCommandPreview = pendingPermission.affectedPath
            snapshot.phase = .waitingForApproval
            snapshot.isCompleted = false
            snapshot.isInterrupted = false
            snapshot.summary = pendingPermission.summary

            if let timestamp {
                snapshot.updatedAt = timestamp
            }
            return
        }

        snapshot.pendingPermissionRequest = nil
        snapshot.currentTool = toolName
        snapshot.currentCommandPreview = commandPreview(for: toolName, payload: payload)
        snapshot.phase = .running
        snapshot.isCompleted = false
        snapshot.isInterrupted = false
        snapshot.summary = "Running \(displayName(for: toolName))."

        if let timestamp {
            snapshot.updatedAt = timestamp
        }
    }

    private static func applyUserMessage(
        _ message: String,
        timestamp: Date?,
        to snapshot: inout CodexRolloutSnapshot
    ) {
        snapshot.initialUserPrompt = snapshot.initialUserPrompt ?? message
        snapshot.lastUserPrompt = message
        snapshot.currentTool = nil
        snapshot.currentCommandPreview = nil
        snapshot.pendingPermissionRequest = nil
        snapshot.phase = .running
        snapshot.isCompleted = false
        snapshot.isInterrupted = false
        snapshot.summary = "Prompt: \(message)"

        if let timestamp {
            snapshot.updatedAt = timestamp
        }
    }

    private static func applyAssistantMessage(
        _ message: String,
        timestamp: Date?,
        to snapshot: inout CodexRolloutSnapshot
    ) {
        snapshot.lastAssistantMessage = message
        snapshot.summary = message

        // After task_complete, the JSONL may still contain trailing
        // response_item entries (the final assistant message). These should
        // update content but NOT reset the completion state — only a new
        // user prompt (applyUserMessage) starts a fresh turn.
        if !snapshot.isCompleted {
            snapshot.currentTool = nil
            snapshot.currentCommandPreview = nil
            snapshot.pendingPermissionRequest = nil
            snapshot.phase = .running
            snapshot.isInterrupted = false
        }

        if let timestamp {
            snapshot.updatedAt = timestamp
        }
    }

    private static func displayName(for toolName: String) -> String {
        switch toolName {
        case "exec_command":
            "command"
        case "apply_patch":
            "patch"
        case "write_stdin":
            "input"
        default:
            toolName
        }
    }

    private static func commandPreview(for toolName: String, payload: [String: Any]) -> String? {
        guard let object = commandArgumentsObject(from: payload) else { return nil }

        switch toolName {
        case "exec_command":
            return clipped(object["cmd"] as? String)
        case "write_stdin":
            return clipped(object["chars"] as? String)
        default:
            return nil
        }
    }

    private static func permissionRequest(for toolName: String, payload: [String: Any]) -> CodexRolloutPermissionRequest? {
        guard let object = commandArgumentsObject(from: payload),
              (object["sandbox_permissions"] as? String)?.lowercased() == "require_escalated" else {
            return nil
        }

        let callID = (payload["call_id"] as? String) ?? (payload["id"] as? String)
        let affectedPath = commandPreview(for: toolName, payload: payload) ?? displayName(for: toolName)
        let summary = clipped(object["justification"] as? String, limit: 220)
            ?? "Codex needs your approval before it can continue."

        return CodexRolloutPermissionRequest(
            callID: callID,
            title: "Approval required",
            summary: summary,
            affectedPath: affectedPath
        )
    }

    private static func commandArgumentsObject(from payload: [String: Any]) -> [String: Any]? {
        guard let arguments = payload["arguments"] as? String,
              let data = arguments.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        return object
    }

    private static func responseMessageText(
        from payload: [String: Any],
        textType: String,
        skipsInjectedBlocks: Bool
    ) -> String? {
        guard let content = payload["content"] as? [[String: Any]] else {
            return nil
        }

        let segments = content.compactMap { item -> String? in
            guard item["type"] as? String == textType,
                  let text = item["text"] as? String else {
                return nil
            }

            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                return nil
            }

            if skipsInjectedBlocks, isInjectedPromptBlock(trimmed) {
                return nil
            }

            return trimmed
        }

        guard !segments.isEmpty else {
            return nil
        }

        return clipped(segments.joined(separator: " "))
    }

    private static func isInjectedPromptBlock(_ text: String) -> Bool {
        text.hasPrefix("# AGENTS.md instructions for ")
            || text.hasPrefix("<environment_context>")
            || text.hasPrefix("<permissions instructions>")
            || text.hasPrefix("<collaboration_mode>")
            || text.hasPrefix("<skills_instructions>")
    }

    private static func clipped(_ value: String?, limit: Int = 110) -> String? {
        guard let value else {
            return nil
        }

        let collapsed = value
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\t", with: " ")
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

    private static func jsonObject(for line: String) -> [String: Any]? {
        codexRolloutJSONObject(for: line)
    }

    private static func parseTimestamp(_ string: String?) -> Date? {
        codexRolloutParseTimestamp(string)
    }
}

public final class CodexRolloutWatcher: @unchecked Sendable {
    private struct Observation {
        var target: CodexRolloutWatchTarget
        var offset: UInt64 = 0
        var pendingBuffer = Data()
        var snapshot = CodexRolloutSnapshot()
        var shouldTrimLeadingPartialLine = false
    }

    public var eventHandler: (@Sendable (AgentEvent) -> Void)?

    private let pollInterval: TimeInterval
    private let initialReadLimit: UInt64
    private let initialPromptBootstrapLimit: UInt64
    private let queue = DispatchQueue(label: "app.openisland.codex.rollout-watcher")
    private var timer: DispatchSourceTimer?
    private var observations: [String: Observation] = [:]

    public init(
        pollInterval: TimeInterval = 3.0,
        initialReadLimit: UInt64 = 128 * 1_024,
        initialPromptBootstrapLimit: UInt64 = 4 * 1_024 * 1_024
    ) {
        self.pollInterval = pollInterval
        self.initialReadLimit = initialReadLimit
        self.initialPromptBootstrapLimit = initialPromptBootstrapLimit
    }

    deinit {
        stop()
    }

    public func sync(targets: [CodexRolloutWatchTarget]) {
        queue.sync {
            syncLocked(targets: targets)
        }
    }

    public func stop() {
        queue.sync {
            timer?.cancel()
            timer = nil
            observations.removeAll()
        }
    }

    private func syncLocked(targets: [CodexRolloutWatchTarget]) {
        let targetMap = Dictionary(uniqueKeysWithValues: targets.map { ($0.sessionID, $0) })

        observations = observations.reduce(into: [:]) { partialResult, pair in
            guard let updatedTarget = targetMap[pair.key] else {
                return
            }

            if pair.value.target == updatedTarget {
                partialResult[pair.key] = pair.value
            } else {
                partialResult[pair.key] = makeObservation(for: updatedTarget)
            }
        }

        for target in targets where observations[target.sessionID] == nil {
            observations[target.sessionID] = makeObservation(for: target)
        }

        if observations.isEmpty {
            timer?.cancel()
            timer = nil
            return
        }

        if timer == nil {
            let timer = DispatchSource.makeTimerSource(queue: queue)
            timer.schedule(deadline: .now() + pollInterval, repeating: pollInterval)
            timer.setEventHandler { [weak self] in
                self?.pollLocked()
            }
            self.timer = timer
            timer.resume()
        }

        pollLocked()
    }

    private func pollLocked() {
        let sessionIDs = Array(observations.keys)

        for sessionID in sessionIDs {
            guard var observation = observations[sessionID] else {
                continue
            }

            let events = refresh(observation: &observation)
            observations[sessionID] = observation
            events.forEach { eventHandler?($0) }
        }
    }

    private func refresh(observation: inout Observation) -> [AgentEvent] {
        let fileURL = URL(fileURLWithPath: observation.target.transcriptPath)
        guard FileManager.default.fileExists(atPath: fileURL.path),
              let fileHandle = try? FileHandle(forReadingFrom: fileURL) else {
            return []
        }

        defer {
            try? fileHandle.close()
        }

        let fileSize = (try? fileHandle.seekToEnd()) ?? 0
        if fileSize < observation.offset {
            observation.offset = 0
            observation.pendingBuffer.removeAll(keepingCapacity: false)
            observation.snapshot = CodexRolloutSnapshot()
        }

        do {
            try fileHandle.seek(toOffset: observation.offset)
            let data = try fileHandle.readToEnd() ?? Data()
            guard !data.isEmpty else {
                return []
            }

            observation.offset += UInt64(data.count)
            observation.pendingBuffer.append(data)

            if observation.shouldTrimLeadingPartialLine {
                trimLeadingPartialLine(from: &observation.pendingBuffer)
                observation.shouldTrimLeadingPartialLine = false
            }

            let lines = completeLines(from: &observation.pendingBuffer)
            guard !lines.isEmpty else {
                return []
            }

            let oldSnapshot = observation.snapshot
            lines.forEach { CodexRolloutReducer.apply(line: $0, to: &observation.snapshot) }

            return CodexRolloutReducer.events(
                from: oldSnapshot,
                to: observation.snapshot,
                sessionID: observation.target.sessionID,
                transcriptPath: observation.target.transcriptPath
            )
        } catch {
            return []
        }
    }

    private func completeLines(from buffer: inout Data) -> [String] {
        let newline = UInt8(ascii: "\n")
        var lines: [String] = []

        while let newlineIndex = buffer.firstIndex(of: newline) {
            let lineData = buffer.prefix(upTo: newlineIndex)
            buffer.removeSubrange(...newlineIndex)

            guard !lineData.isEmpty else {
                continue
            }

            lines.append(String(decoding: lineData, as: UTF8.self))
        }

        return lines
    }

    private func makeObservation(for target: CodexRolloutWatchTarget) -> Observation {
        let fileURL = URL(fileURLWithPath: target.transcriptPath)
        guard FileManager.default.fileExists(atPath: fileURL.path),
              let fileHandle = try? FileHandle(forReadingFrom: fileURL) else {
            return Observation(target: target)
        }

        defer {
            try? fileHandle.close()
        }

        let fileSize = (try? fileHandle.seekToEnd()) ?? 0
        guard fileSize > initialReadLimit else {
            return Observation(target: target)
        }

        let bootstrapSnapshot = bootstrapPromptSnapshot(
            fileHandle: fileHandle,
            fileSize: fileSize
        )

        return Observation(
            target: target,
            offset: fileSize - initialReadLimit,
            pendingBuffer: Data(),
            snapshot: bootstrapSnapshot,
            shouldTrimLeadingPartialLine: true
        )
    }

    private func bootstrapPromptSnapshot(
        fileHandle: FileHandle,
        fileSize: UInt64
    ) -> CodexRolloutSnapshot {
        let readLimit = min(fileSize, initialPromptBootstrapLimit)
        guard readLimit > 0 else {
            return CodexRolloutSnapshot()
        }

        let initialPrompt = bootstrapInitialPrompt(
            fileHandle: fileHandle,
            readLimit: readLimit
        )
        let lastPrompt = bootstrapLastPrompt(
            fileHandle: fileHandle,
            fileSize: fileSize,
            readLimit: readLimit
        )
        return CodexRolloutSnapshot(
            initialUserPrompt: initialPrompt,
            lastUserPrompt: lastPrompt ?? initialPrompt
        )
    }

    private func bootstrapInitialPrompt(
        fileHandle: FileHandle,
        readLimit: UInt64
    ) -> String? {
        do {
            try fileHandle.seek(toOffset: 0)
            var buffer = Data()
            var snapshot = CodexRolloutSnapshot()
            var bytesRemaining = readLimit

            while bytesRemaining > 0, snapshot.initialUserPrompt == nil {
                let chunkSize = Int(min(bytesRemaining, 64 * 1_024))
                guard let data = try fileHandle.read(upToCount: chunkSize), !data.isEmpty else {
                    break
                }

                buffer.append(data)
                bytesRemaining -= UInt64(data.count)

                let lines = completeLines(from: &buffer)
                guard !lines.isEmpty else {
                    continue
                }

                lines.forEach { CodexRolloutReducer.apply(line: $0, to: &snapshot) }
            }

            return snapshot.initialUserPrompt
        } catch {
            return nil
        }
    }

    private func bootstrapLastPrompt(
        fileHandle: FileHandle,
        fileSize: UInt64,
        readLimit: UInt64
    ) -> String? {
        do {
            let startOffset = fileSize > readLimit ? fileSize - readLimit : 0
            try fileHandle.seek(toOffset: startOffset)
            var buffer = try fileHandle.readToEnd() ?? Data()
            guard !buffer.isEmpty else {
                return nil
            }

            if startOffset > 0 {
                trimLeadingPartialLine(from: &buffer)
            }

            let tailSnapshot = CodexRolloutReducer.snapshot(for: completeLines(from: &buffer))
            return tailSnapshot.lastUserPrompt
        } catch {
            return nil
        }
    }

    private func trimLeadingPartialLine(from buffer: inout Data) {
        let newline = UInt8(ascii: "\n")

        guard let newlineIndex = buffer.firstIndex(of: newline) else {
            buffer.removeAll(keepingCapacity: false)
            return
        }

        buffer.removeSubrange(...newlineIndex)
    }
}

private func codexRolloutJSONObject(for line: String) -> [String: Any]? {
    guard let data = line.data(using: .utf8),
          let object = try? JSONSerialization.jsonObject(with: data),
          let dictionary = object as? [String: Any] else {
        return nil
    }

    return dictionary
}

private func codexRolloutParseTimestamp(_ string: String?) -> Date? {
    guard let string else {
        return nil
    }

    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter.date(from: string)
}
