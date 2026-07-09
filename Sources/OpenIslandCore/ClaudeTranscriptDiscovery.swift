import Foundation

public final class ClaudeTranscriptDiscovery: @unchecked Sendable {
    private struct Candidate {
        var fileURL: URL
        var modifiedAt: Date
    }

    private struct AgentToolMetadata {
        var description: String?
        var agentType: String?
    }

    private struct SidechainSubagentMetadata: Decodable {
        var agentType: String?
        var description: String?
        var toolUseId: String
    }

    public static var defaultRootURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/projects", isDirectory: true)
    }

    private let rootURL: URL
    private let fileManager: FileManager
    private let maxAge: TimeInterval
    private let maxFiles: Int

    public init(
        rootURL: URL = ClaudeTranscriptDiscovery.defaultRootURL,
        fileManager: FileManager = .default,
        maxAge: TimeInterval = 86_400,
        maxFiles: Int = 40
    ) {
        self.rootURL = rootURL
        self.fileManager = fileManager
        self.maxAge = maxAge
        self.maxFiles = maxFiles
    }

    public func discoverRecentSessions(now: Date = .now) -> [AgentSession] {
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
            guard fileURL.pathExtension == "jsonl",
                  !fileURL.path.contains("/subagents/") else {
                continue
            }

            let values = try? fileURL.resourceValues(forKeys: [.isRegularFileKey, .contentModificationDateKey])
            guard values?.isRegularFile == true,
                  let modifiedAt = values?.contentModificationDate,
                  modifiedAt >= cutoff else {
                continue
            }

            candidates.append(Candidate(fileURL: fileURL, modifiedAt: modifiedAt))
        }

        let sortedCandidates = candidates
            .sorted { $0.modifiedAt > $1.modifiedAt }
            .prefix(maxFiles)

        return sortedCandidates.compactMap { candidate in
            parseSession(at: candidate.fileURL, fallbackUpdatedAt: candidate.modifiedAt)
        }
    }

    private func parseSession(at fileURL: URL, fallbackUpdatedAt: Date) -> AgentSession? {
        // Stream the transcript line by line. The original
        // `String(contentsOf:)` slurped the entire jsonl, which on
        // heavy Claude users (multi-hundred-MB transcripts) caused
        // multi-GB startup peaks and OOMs on lower-RAM machines.
        // Peak memory is now one chunk plus the accumulated session
        // state.
        guard let fileHandle = try? FileHandle(forReadingFrom: fileURL) else {
            return nil
        }
        defer { try? fileHandle.close() }

        var sessionID = fileURL.deletingPathExtension().lastPathComponent
        var cwd: String?
        var updatedAt = fallbackUpdatedAt
        var initialUserPrompt: String?
        var lastUserPrompt: String?
        var lastAssistantMessage: String?
        var model: String?
        var currentTool: String?
        var currentToolInputPreview: String?
        var pendingToolUses: [String: (name: String, preview: String?)] = [:]
        var agentToolMetadataByID: [String: AgentToolMetadata] = [:]
        var asyncAgentToolUseIDs: Set<String> = []

        let processLine: (String) -> Void = { line in
            guard let data = line.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return
            }

            if let value = object["sessionId"] as? String, !value.isEmpty {
                sessionID = value
            }

            if let value = object["cwd"] as? String, !value.isEmpty {
                cwd = value
            }

            if let timestampText = object["timestamp"] as? String,
               let timestamp = ISO8601DateFormatter().date(from: timestampText) {
                updatedAt = timestamp
            }

            let topLevelType = object["type"] as? String
            let message = object["message"] as? [String: Any]
            let role = message?["role"] as? String

            if role == "user" {
                if let prompt = self.promptText(from: message?["content"]) {
                    if initialUserPrompt == nil {
                        initialUserPrompt = prompt
                    }
                    lastUserPrompt = prompt
                }

                if let toolResultIDs = self.toolResultIDs(from: message?["content"]) {
                    let toolResultStatus = self.toolUseResultStatus(from: object)
                    for toolResultID in toolResultIDs {
                        pendingToolUses.removeValue(forKey: toolResultID)

                        if agentToolMetadataByID[toolResultID] != nil {
                            switch toolResultStatus {
                            case "async_launched":
                                asyncAgentToolUseIDs.insert(toolResultID)
                            case "completed", "failed", "cancelled", "canceled":
                                asyncAgentToolUseIDs.remove(toolResultID)
                            default:
                                break
                            }
                        }
                    }

                    if pendingToolUses.isEmpty {
                        currentTool = nil
                        currentToolInputPreview = nil
                    } else if let lastPending = pendingToolUses.values.first {
                        currentTool = lastPending.name
                        currentToolInputPreview = lastPending.preview
                    }
                }
            } else if role == "assistant" {
                if let assistantText = self.assistantText(from: message?["content"]) {
                    lastAssistantMessage = assistantText
                }

                if let value = message?["model"] as? String, !value.isEmpty {
                    model = value
                }

                if let toolUses = self.toolUses(from: message?["content"]) {
                    for toolUse in toolUses {
                        pendingToolUses[toolUse.id] = (name: toolUse.name, preview: toolUse.preview)
                    }

                    if let lastToolUse = toolUses.last {
                        currentTool = lastToolUse.name
                        currentToolInputPreview = lastToolUse.preview
                    }
                }

                if let agentToolUses = self.agentToolUses(from: message?["content"]) {
                    for agentToolUse in agentToolUses {
                        agentToolMetadataByID[agentToolUse.id] = AgentToolMetadata(
                            description: agentToolUse.description,
                            agentType: agentToolUse.agentType
                        )
                    }
                }
            } else if topLevelType == "summary",
                      let summary = object["summary"] as? String,
                      !summary.isEmpty {
                lastAssistantMessage = summary
            }
        }

        var buffer = Data()
        while let chunk = try? fileHandle.read(upToCount: Self.streamingChunkSize),
              !chunk.isEmpty {
            buffer.append(chunk)
            for line in extractCompleteLines(from: &buffer) {
                processLine(line)
            }
        }

        // Honor a final line written without a trailing newline.
        if !buffer.isEmpty {
            let trailing = String(decoding: buffer, as: UTF8.self)
            if !trailing.isEmpty {
                processLine(trailing)
            }
        }

        guard let cwd else {
            return nil
        }

        let workspaceName = WorkspaceNameResolver.workspaceName(for: cwd)
        let activeSubagents = discoverActiveSidechainSubagents(
            forTranscript: fileURL,
            activeToolUseIDs: asyncAgentToolUseIDs,
            agentToolMetadataByID: agentToolMetadataByID
        )
        if let latestSubagentActivity = activeSubagents.compactMap(\.startedAt).max(),
           latestSubagentActivity > updatedAt {
            updatedAt = latestSubagentActivity
        }
        let metadata = ClaudeSessionMetadata(
            transcriptPath: fileURL.path,
            initialUserPrompt: initialUserPrompt,
            lastUserPrompt: lastUserPrompt,
            lastAssistantMessage: lastAssistantMessage,
            currentTool: currentTool,
            currentToolInputPreview: currentToolInputPreview,
            model: model,
            activeSubagents: activeSubagents
        )
        let summary = lastAssistantMessage
            ?? lastUserPrompt
            ?? "Recovered Claude session in \(workspaceName)."

        return AgentSession(
            id: sessionID,
            title: "Claude · \(workspaceName)",
            tool: .claudeCode,
            origin: .live,
            attachmentState: .stale,
            phase: .completed,
            summary: summary,
            updatedAt: updatedAt,
            jumpTarget: JumpTarget(
                terminalApp: "Unknown",
                workspaceName: workspaceName,
                paneTitle: "Claude \(sessionID.prefix(8))",
                workingDirectory: cwd
            ),
            claudeMetadata: metadata.isEmpty ? nil : metadata
        )
    }

    private func discoverActiveSidechainSubagents(
        forTranscript transcriptURL: URL,
        activeToolUseIDs: Set<String>,
        agentToolMetadataByID: [String: AgentToolMetadata]
    ) -> [ClaudeSubagentInfo] {
        guard !activeToolUseIDs.isEmpty else {
            return []
        }

        let subagentsDirectory = transcriptURL
            .deletingPathExtension()
            .appendingPathComponent("subagents", isDirectory: true)

        guard let metaURLs = try? fileManager.contentsOfDirectory(
            at: subagentsDirectory,
            includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        return metaURLs
            .filter { $0.lastPathComponent.hasSuffix(".meta.json") }
            .compactMap { metaURL -> ClaudeSubagentInfo? in
                guard let values = try? metaURL.resourceValues(forKeys: [.isRegularFileKey, .contentModificationDateKey]),
                      values.isRegularFile == true,
                      let data = try? Data(contentsOf: metaURL),
                      let metadata = try? JSONDecoder().decode(SidechainSubagentMetadata.self, from: data),
                      activeToolUseIDs.contains(metadata.toolUseId) else {
                    return nil
                }

                let fallback = agentToolMetadataByID[metadata.toolUseId]
                let metaBaseName = sidechainMetaBaseName(from: metaURL)
                let transcriptPath = subagentsDirectory.appendingPathComponent("\(metaBaseName).jsonl")
                let startedAt = latestTimestamp(in: transcriptPath)
                    ?? modificationDate(at: transcriptPath)
                    ?? values.contentModificationDate

                return ClaudeSubagentInfo(
                    agentID: sidechainAgentID(fromBaseName: metaBaseName),
                    agentType: metadata.agentType ?? fallback?.agentType,
                    taskDescription: metadata.description ?? fallback?.description,
                    startedAt: startedAt
                )
            }
            .sorted { lhs, rhs in
                (lhs.startedAt ?? .distantPast) > (rhs.startedAt ?? .distantPast)
            }
    }

    private func sidechainMetaBaseName(from metaURL: URL) -> String {
        let name = metaURL.lastPathComponent
        if name.hasSuffix(".meta.json") {
            return String(name.dropLast(".meta.json".count))
        }
        return metaURL.deletingPathExtension().lastPathComponent
    }

    private func sidechainAgentID(fromBaseName baseName: String) -> String {
        if baseName.hasPrefix("agent-") {
            return String(baseName.dropFirst("agent-".count))
        }
        return baseName
    }

    private func modificationDate(at fileURL: URL) -> Date? {
        let values = try? fileURL.resourceValues(forKeys: [.contentModificationDateKey])
        return values?.contentModificationDate
    }

    private func latestTimestamp(in fileURL: URL) -> Date? {
        guard let fileHandle = try? FileHandle(forReadingFrom: fileURL) else {
            return nil
        }
        defer { try? fileHandle.close() }

        var latest: Date?
        var buffer = Data()
        while let chunk = try? fileHandle.read(upToCount: Self.streamingChunkSize),
              !chunk.isEmpty {
            buffer.append(chunk)
            for line in extractCompleteLines(from: &buffer) {
                latest = timestamp(fromTranscriptLine: line) ?? latest
            }
        }

        if !buffer.isEmpty {
            let trailing = String(decoding: buffer, as: UTF8.self)
            if !trailing.isEmpty {
                latest = timestamp(fromTranscriptLine: trailing) ?? latest
            }
        }

        return latest
    }

    private func timestamp(fromTranscriptLine line: String) -> Date? {
        guard let data = line.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let timestampText = object["timestamp"] as? String else {
            return nil
        }
        return ISO8601DateFormatter().date(from: timestampText)
    }

    private static let streamingChunkSize = 64 * 1_024

    private func extractCompleteLines(from buffer: inout Data) -> [String] {
        let newline = UInt8(ascii: "\n")
        var lines: [String] = []
        while let newlineIndex = buffer.firstIndex(of: newline) {
            let lineData = buffer.prefix(upTo: newlineIndex)
            buffer.removeSubrange(...newlineIndex)
            guard !lineData.isEmpty else { continue }
            lines.append(String(decoding: lineData, as: UTF8.self))
        }
        return lines
    }

    private func promptText(from content: Any?) -> String? {
        if let text = content as? String {
            return normalizedText(text)
        }

        guard let blocks = content as? [[String: Any]] else {
            return nil
        }

        for block in blocks {
            if block["type"] as? String == "text",
               let text = block["text"] as? String,
               let normalized = normalizedText(text) {
                return normalized
            }
        }

        return nil
    }

    private func assistantText(from content: Any?) -> String? {
        guard let blocks = content as? [[String: Any]] else {
            return nil
        }

        for block in blocks {
            if block["type"] as? String == "text",
               let text = block["text"] as? String,
               let normalized = normalizedText(text) {
                return normalized
            }
        }

        return nil
    }

    private func toolResultIDs(from content: Any?) -> [String]? {
        guard let blocks = content as? [[String: Any]] else {
            return nil
        }

        let ids = blocks.compactMap { block -> String? in
            guard block["type"] as? String == "tool_result" else {
                return nil
            }

            return block["tool_use_id"] as? String
        }

        return ids.isEmpty ? nil : ids
    }

    private func toolUses(from content: Any?) -> [(id: String, name: String, preview: String?)]? {
        guard let blocks = content as? [[String: Any]] else {
            return nil
        }

        let uses = blocks.compactMap { block -> (id: String, name: String, preview: String?)? in
            guard block["type"] as? String == "tool_use",
                  let name = block["name"] as? String,
                  let id = block["id"] as? String else {
                return nil
            }

            let inputPreview: String?
            if let input = block["input"] {
                inputPreview = previewText(for: input)
            } else {
                inputPreview = nil
            }

            return (id: id, name: name, preview: inputPreview)
        }

        return uses.isEmpty ? nil : uses
    }

    private func agentToolUses(from content: Any?) -> [(id: String, description: String?, agentType: String?)]? {
        guard let blocks = content as? [[String: Any]] else {
            return nil
        }

        let uses = blocks.compactMap { block -> (id: String, description: String?, agentType: String?)? in
            guard block["type"] as? String == "tool_use",
                  block["name"] as? String == "Agent",
                  let id = block["id"] as? String else {
                return nil
            }

            let input = block["input"] as? [String: Any]
            return (
                id: id,
                description: input?["description"] as? String,
                agentType: input?["subagent_type"] as? String
            )
        }

        return uses.isEmpty ? nil : uses
    }

    private func toolUseResultStatus(from object: [String: Any]) -> String? {
        guard let result = object["toolUseResult"] as? [String: Any] else {
            return nil
        }
        return result["status"] as? String
    }

    private func previewText(for value: Any) -> String? {
        if let text = value as? String {
            return normalizedText(text)
        }

        guard JSONSerialization.isValidJSONObject(value),
              let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]),
              let text = String(data: data, encoding: .utf8) else {
            return nil
        }

        return normalizedText(text)
    }

    private func normalizedText(_ value: String) -> String? {
        let collapsed = value
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\t", with: " ")
            .split(separator: " ", omittingEmptySubsequences: true)
            .joined(separator: " ")

        guard !collapsed.isEmpty else {
            return nil
        }

        guard collapsed.count > 140 else {
            return collapsed
        }

        let endIndex = collapsed.index(collapsed.startIndex, offsetBy: 139)
        return "\(collapsed[..<endIndex])…"
    }
}
