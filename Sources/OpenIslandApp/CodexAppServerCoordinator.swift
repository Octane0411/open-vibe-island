import AppKit
import Foundation
import OpenIslandCore

/// Manages the lifecycle of the Codex app-server connection.
///
/// Automatically starts the app-server subprocess when Codex.app is
/// detected, and tears it down when the app quits.  Converts incoming
/// app-server notifications into `AgentEvent`s that flow through the
/// standard `SessionState` reducer.
@Observable
@MainActor
final class CodexAppServerCoordinator {
    @ObservationIgnored
    private var client: CodexAppServerClient?

    @ObservationIgnored
    private var connectTask: Task<Void, Never>?

    @ObservationIgnored
    private var pendingApprovalRequests: [String: CodexAppServerApprovalRequest] = [:]

    /// Callback to emit AgentEvents into AppModel.
    @ObservationIgnored
    var onEvent: ((AgentEvent) -> Void)?

    /// Callback to log status messages.
    @ObservationIgnored
    var onStatusMessage: ((String) -> Void)?

    /// Callback to publish authoritative Codex usage snapshots from app-server.
    @ObservationIgnored
    var onUsageSnapshot: ((CodexUsageSnapshot) -> Void)?

    /// Returns `true` if a session with the given id is already tracked.
    /// Used to avoid re-emitting `sessionStarted` (which rebuilds the
    /// session and wipes richer state from hooks/rediscovery).
    @ObservationIgnored
    var isSessionTracked: ((String) -> Bool)?

    /// Returns the currently stored Codex metadata for a tracked session.
    /// App-server item notifications only carry tool deltas, so this keeps
    /// transcript/title/user-message fields intact while updating tool state.
    @ObservationIgnored
    var codexMetadataForSession: ((String) -> CodexSessionMetadata?)?

    private(set) var isConnected = false
    var isConnecting: Bool {
        connectTask != nil
    }

    // MARK: - Public API

    /// Ensure a connection exists.  Called from the monitoring loop when
    /// Codex.app is detected as running.  Idempotent — does nothing if
    /// already connected or a connection attempt is in progress.
    func ensureConnected() {
        guard !isConnected, connectTask == nil else { return }

        // Resolve the Codex.app bundle location dynamically — users may
        // have installed Codex outside `/Applications` (e.g. ~/Applications).
        guard let bundleURL = NSWorkspace.shared.urlForApplication(
            withBundleIdentifier: "com.openai.codex"
        ) else {
            return
        }
        let codexPath = bundleURL
            .appendingPathComponent("Contents/Resources/codex")
            .path
        guard FileManager.default.isExecutableFile(atPath: codexPath) else {
            return
        }

        connectTask = Task { [weak self] in
            guard let self else { return }
            do {
                let newClient = CodexAppServerClient(codexPath: codexPath)
                newClient.onNotification = { [weak self] notification in
                    Task { @MainActor [weak self] in
                        self?.handleNotification(notification)
                    }
                }
                try await newClient.start()

                self.client = newClient
                self.isConnected = true
                self.connectTask = nil

                self.onStatusMessage?("Connected to Codex app-server.")

                // Fetch currently loaded threads and create sessions.
                await self.refreshUsageFromAppServer()
                await self.syncLoadedThreads()
                MemoryPressureRelief.releaseEmptyMallocPages()
            } catch {
                self.connectTask = nil
                self.onStatusMessage?("Failed to connect to Codex app-server: \(error.localizedDescription)")
            }
        }
    }

    /// Disconnect and clean up.  Called when Codex.app is no longer running.
    func disconnect() {
        connectTask?.cancel()
        connectTask = nil
        client?.stop()
        client = nil
        pendingApprovalRequests.removeAll()
        isConnected = false
    }

    @discardableResult
    func resolvePermission(sessionID: String, resolution: PermissionResolution) -> Bool {
        guard let client,
              let request = pendingApprovalRequests.removeValue(forKey: sessionID) else {
            return false
        }

        do {
            try client.resolveApprovalRequest(request, resolution: resolution)
            return true
        } catch {
            pendingApprovalRequests[sessionID] = request
            onStatusMessage?("Failed to resolve Codex app-server approval: \(error.localizedDescription)")
            return false
        }
    }

    // MARK: - Thread sync

    private func syncLoadedThreads() async {
        guard let client else { return }
        do {
            let loadedThreads = try await client.listLoadedThreads()
            let recentThreads = try await client.listThreads(limit: 20)
            let threads = Self.mergedThreadSyncList(loadedThreads: loadedThreads, recentThreads: recentThreads)
            var created = 0
            var refreshed = 0
            for thread in threads where !thread.ephemeral {
                if isSessionTracked?(thread.id) == true {
                    emitSessionRefreshed(from: thread)
                    refreshed += 1
                } else {
                    emitSessionStarted(from: thread)
                    created += 1
                }
            }
            if created > 0 {
                onStatusMessage?("Synced \(created) new Codex thread(s) from app-server.")
            }
            if refreshed > 0 {
                onStatusMessage?("Refreshed \(refreshed) tracked Codex thread(s) from app-server.")
            }
        } catch {
            onStatusMessage?("Failed to list loaded Codex threads: \(error.localizedDescription)")
        }
    }

    static func mergedThreadSyncList(
        loadedThreads: [CodexThread],
        recentThreads: [CodexThread]
    ) -> [CodexThread] {
        var seenIDs: Set<String> = []
        var merged: [CodexThread] = []

        for thread in loadedThreads + recentThreads {
            guard seenIDs.insert(thread.id).inserted else { continue }
            merged.append(thread)
        }

        return merged
    }

    nonisolated static func fetchThreadTitles(
        codexPath: String = "/Applications/Codex.app/Contents/Resources/codex",
        limit: Int = 40
    ) async -> [String: String] {
        guard FileManager.default.isExecutableFile(atPath: codexPath) else {
            return [:]
        }

        let client = CodexAppServerClient(codexPath: codexPath)
        do {
            try await client.start()
            defer { client.stop() }

            let threads = try await client.listThreads(limit: limit)
            return Dictionary(uniqueKeysWithValues: threads.compactMap { thread in
                guard let title = thread.name?.trimmedForCodexSurface,
                      !title.isEmpty else {
                    return nil
                }
                return (thread.id, title)
            })
        } catch {
            client.stop()
            return [:]
        }
    }

    // MARK: - Notification handling

    private func handleNotification(_ notification: CodexAppServerNotification) {
        switch notification {
        case .threadStarted(let thread):
            guard !thread.ephemeral else { return }
            guard isSessionTracked?(thread.id) != true else { return }
            emitSessionStarted(from: thread)

        case .threadStatusChanged(let threadId, let status):
            if let event = Self.eventForThreadStatusChanged(threadId: threadId, status: status) {
                onEvent?(event)
            }

        case .threadClosed(let threadId):
            onEvent?(.sessionCompleted(
                SessionCompleted(
                    sessionID: threadId,
                    summary: "Codex thread closed.",
                    timestamp: .now,
                    isSessionEnd: true
                )
            ))

        case .threadNameUpdated(let threadId, _):
            refreshTrackedThread(threadID: threadId)

        case .turnStarted(let threadId, _):
            onEvent?(.activityUpdated(
                SessionActivityUpdated(
                    sessionID: threadId,
                    summary: "Codex is working…",
                    phase: .running,
                    timestamp: .now
                )
            ))

        case .turnCompleted(let threadId, let turn):
            // A turn completing doesn't end the thread — the user can send
            // another message.  Use activityUpdated(phase: .completed) so the
            // session stays visible as "Completed" rather than being torn
            // down.  `thread/closed` is the authoritative end signal.
            let summary: String
            switch turn.status {
            case .completed: summary = "Turn completed."
            case .interrupted: summary = "Turn interrupted."
            case .failed: summary = "Turn failed."
            case .inProgress: summary = "Turn in progress."
            }
            onEvent?(.activityUpdated(
                SessionActivityUpdated(
                    sessionID: threadId,
                    summary: summary,
                    phase: .completed,
                    timestamp: .now
                )
            ))
            emitCodexMetadataUpdate(
                sessionID: threadId,
                metadata: Self.codexMetadataClearingTool(
                    existing: codexMetadataForSession?(threadId)
                )
            )

        case .itemStarted(let activity):
            emitCodexMetadataUpdate(
                sessionID: activity.threadID,
                metadata: Self.codexMetadata(
                    existing: codexMetadataForSession?(activity.threadID),
                    activity: activity
                )
            )
            onEvent?(.activityUpdated(
                SessionActivityUpdated(
                    sessionID: activity.threadID,
                    summary: Self.itemActivitySummary(activity),
                    phase: .running,
                    timestamp: .now
                )
            ))

        case .itemCompleted(let activity):
            emitCodexMetadataUpdate(
                sessionID: activity.threadID,
                metadata: Self.codexMetadata(
                    existing: codexMetadataForSession?(activity.threadID),
                    activity: activity
                )
            )
            onEvent?(.activityUpdated(
                SessionActivityUpdated(
                    sessionID: activity.threadID,
                    summary: Self.itemActivitySummary(activity),
                    phase: .running,
                    timestamp: .now
                )
            ))

        case .itemOutputDelta(let activity):
            emitCodexMetadataUpdate(
                sessionID: activity.threadID,
                metadata: Self.codexMetadataForOutputDelta(
                    existing: codexMetadataForSession?(activity.threadID),
                    activity: activity
                )
            )
            onEvent?(.activityUpdated(
                SessionActivityUpdated(
                    sessionID: activity.threadID,
                    summary: Self.itemActivitySummary(activity),
                    phase: .running,
                    timestamp: .now
                )
            ))

        case .itemPatchUpdated(let activity):
            emitCodexMetadataUpdate(
                sessionID: activity.threadID,
                metadata: Self.codexMetadata(
                    existing: codexMetadataForSession?(activity.threadID),
                    activity: activity
                )
            )
            onEvent?(.activityUpdated(
                SessionActivityUpdated(
                    sessionID: activity.threadID,
                    summary: Self.itemActivitySummary(activity),
                    phase: .running,
                    timestamp: .now
                )
            ))

        case .agentMessageDelta(let delta):
            emitCodexMetadataUpdate(
                sessionID: delta.threadID,
                metadata: Self.codexMetadataForAgentMessageDelta(
                    existing: codexMetadataForSession?(delta.threadID),
                    delta: delta
                )
            )
            onEvent?(.activityUpdated(
                SessionActivityUpdated(
                    sessionID: delta.threadID,
                    summary: delta.text,
                    phase: .running,
                    timestamp: .now
                )
            ))

        case .rawResponseItemCompleted(let item):
            emitCodexMetadataUpdate(
                sessionID: item.threadID,
                metadata: Self.codexMetadataForRawResponseItem(
                    existing: codexMetadataForSession?(item.threadID),
                    item: item
                )
            )
            if let summary = Self.summary(for: item) {
                onEvent?(.activityUpdated(
                    SessionActivityUpdated(
                        sessionID: item.threadID,
                        summary: summary,
                        phase: .running,
                        timestamp: .now
                    )
                ))
            }

        case .approvalRequested(let request):
            pendingApprovalRequests[request.threadID] = request
            onEvent?(.permissionRequested(
                PermissionRequested(
                    sessionID: request.threadID,
                    request: Self.permissionRequest(from: request),
                    timestamp: .now
                )
            ))

        case .serverRequestResolved(let threadId, let requestId):
            guard let request = pendingApprovalRequests[threadId],
                  requestId == nil || request.requestID == requestId else {
                return
            }
            pendingApprovalRequests.removeValue(forKey: threadId)
            onEvent?(.actionableStateResolved(
                ActionableStateResolved(
                    sessionID: threadId,
                    summary: "Permission request is no longer active.",
                    timestamp: .now
                )
            ))

        case .accountRateLimitsUpdated(let snapshot):
            onUsageSnapshot?(snapshot)

        case .unknown:
            break
        }
    }

    private func emitCodexMetadataUpdate(sessionID: String, metadata: CodexSessionMetadata) {
        guard !metadata.isEmpty else { return }
        onEvent?(.sessionMetadataUpdated(
            SessionMetadataUpdated(
                sessionID: sessionID,
                codexMetadata: metadata,
                timestamp: .now
            )
        ))
    }

    func refreshUsageFromAppServer() async {
        guard let client else { return }
        do {
            guard let snapshot = try await client.readAccountRateLimits() else { return }
            onUsageSnapshot?(snapshot)
        } catch {
            onStatusMessage?("Failed to read Codex app-server rate limits: \(error.localizedDescription)")
        }
    }

    private static func itemActivitySummary(_ activity: CodexAppServerItemActivity) -> String {
        let displayName = AgentSession.currentToolDisplayName(for: activity.toolName)
        guard let preview = activity.preview?.trimmedForCodexSurface,
              !preview.isEmpty else {
            return "Running \(displayName)."
        }
        return "\(displayName) \(preview)"
    }

    static func codexMetadata(
        existing: CodexSessionMetadata?,
        activity: CodexAppServerItemActivity
    ) -> CodexSessionMetadata {
        var metadata = existing ?? CodexSessionMetadata()
        metadata.currentTool = activity.toolName
        metadata.currentCommandPreview = activity.preview?.trimmedForCodexSurface
        return metadata
    }

    static func codexMetadataForOutputDelta(
        existing: CodexSessionMetadata?,
        activity: CodexAppServerItemActivity
    ) -> CodexSessionMetadata {
        var metadata = existing ?? CodexSessionMetadata()
        if metadata.currentTool?.trimmedForCodexSurface.isEmpty != false {
            metadata.currentTool = activity.toolName
        }
        if metadata.currentCommandPreview?.trimmedForCodexSurface.isEmpty != false {
            metadata.currentCommandPreview = activity.preview?.trimmedForCodexSurface
        }
        return metadata
    }

    static func codexMetadataForRawResponseItem(
        existing: CodexSessionMetadata?,
        item: CodexAppServerRawResponseItem
    ) -> CodexSessionMetadata {
        var metadata = existing ?? CodexSessionMetadata()
        if let toolName = item.toolName?.trimmedForCodexSurface, !toolName.isEmpty {
            metadata.currentTool = toolName
            metadata.currentCommandPreview = item.preview?.trimmedForCodexSurface
        }
        if let assistantText = item.assistantText?.trimmedForCodexSurface, !assistantText.isEmpty {
            metadata.lastAssistantMessage = assistantText
        }
        return metadata
    }

    private static func summary(for item: CodexAppServerRawResponseItem) -> String? {
        if let assistantText = item.assistantText?.trimmedForCodexSurface, !assistantText.isEmpty {
            return assistantText
        }
        guard let toolName = item.toolName?.trimmedForCodexSurface, !toolName.isEmpty else {
            return nil
        }
        return itemActivitySummary(CodexAppServerItemActivity(
            threadID: item.threadID,
            turnID: item.turnID,
            itemID: item.itemID,
            toolName: toolName,
            preview: item.preview
        ))
    }

    static func codexMetadataForAgentMessageDelta(
        existing: CodexSessionMetadata?,
        delta: CodexAppServerAgentMessageDelta
    ) -> CodexSessionMetadata {
        var metadata = existing ?? CodexSessionMetadata()
        metadata.lastAssistantMessage = delta.text.trimmedForCodexSurface
        return metadata
    }

    static func codexMetadataClearingTool(existing: CodexSessionMetadata?) -> CodexSessionMetadata {
        var metadata = existing ?? CodexSessionMetadata()
        metadata.currentTool = nil
        metadata.currentCommandPreview = nil
        return metadata
    }

    static func permissionRequest(from request: CodexAppServerApprovalRequest) -> PermissionRequest {
        let title: String
        let summary: String
        let affectedPath: String
        let toolName: String?

        switch request.kind {
        case .commandExecution:
            let command = request.command.joined(separator: " ")
            title = "Command approval"
            summary = command.isEmpty
                ? (request.reason?.trimmedForCodexSurface ?? "Codex wants to run a command.")
                : command
            affectedPath = request.cwd ?? ""
            toolName = "command"

        case .fileChange:
            title = "File change approval"
            summary = request.reason?.trimmedForCodexSurface ?? "Codex wants to modify files."
            affectedPath = request.cwd ?? ""
            toolName = "file change"

        case .permissions:
            title = "Permission approval"
            summary = request.reason?.trimmedForCodexSurface ?? "Codex is requesting additional permissions."
            affectedPath = request.cwd ?? ""
            toolName = "permissions"
        }

        return PermissionRequest(
            title: title,
            summary: summary,
            affectedPath: affectedPath,
            primaryActionTitle: "Allow",
            secondaryActionTitle: "Deny",
            toolName: toolName
        )
    }

    static func eventForThreadStatusChanged(
        threadId: String,
        status: CodexThreadStatus,
        timestamp: Date = .now
    ) -> AgentEvent? {
        switch status.type {
        case .active:
            if status.isWaitingOnUserInput {
                return .questionAsked(
                    QuestionAsked(
                        sessionID: threadId,
                        prompt: QuestionPrompt(
                            title: "Codex is waiting for input.",
                            options: []
                        ),
                        timestamp: timestamp
                    )
                )
            }

            // `waitingOnApproval` is only a status hint. Real app-server
            // approvals arrive as server-initiated `item/*/requestApproval`
            // requests with an id we can answer. Rendering a permission card
            // from the hint alone creates a fake, unresolvable approval flash.
            return .activityUpdated(
                SessionActivityUpdated(
                    sessionID: threadId,
                    summary: status.isWaitingOnApproval ? "Codex is waiting for approval." : "Codex is working…",
                    phase: .running,
                    timestamp: timestamp
                )
            )

        case .idle:
            // Idle means "between turns" in the same thread — the thread
            // is still open.  Only `thread/closed` truly ends a session.
            return .activityUpdated(
                SessionActivityUpdated(
                    sessionID: threadId,
                    summary: "Idle.",
                    phase: .completed,
                    timestamp: timestamp
                )
            )

        case .notLoaded, .systemError:
            return nil
        }
    }

    // MARK: - Helpers

    private func emitSessionStarted(from thread: CodexThread) {
        let payload = Self.threadPayload(from: thread)

        onEvent?(.sessionStarted(
            SessionStarted(
                sessionID: thread.id,
                title: payload.title,
                tool: .codex,
                origin: .live,
                initialPhase: payload.phase,
                summary: payload.summary,
                timestamp: payload.timestamp,
                jumpTarget: payload.jumpTarget,
                codexMetadata: payload.codexMetadata
            )
        ))
    }

    private func emitSessionRefreshed(from thread: CodexThread) {
        let payload = Self.threadPayload(from: thread)
        onEvent?(.sessionRefreshed(
            SessionRefreshed(
                sessionID: thread.id,
                title: payload.title,
                summary: payload.summary,
                phase: payload.phase,
                timestamp: payload.timestamp,
                jumpTarget: payload.jumpTarget,
                codexMetadata: payload.codexMetadata
            )
        ))
    }

    private func refreshTrackedThread(threadID: String) {
        guard let client else { return }
        Task { [weak self] in
            guard let self else { return }
            guard self.isSessionTracked?(threadID) == true else { return }
            guard let thread = try? await client.readThread(threadID: threadID) else { return }
            await MainActor.run {
                self.emitSessionRefreshed(from: thread)
            }
        }
    }

    static func threadPayload(
        from thread: CodexThread,
        now: Date = .now
    ) -> (
        title: String,
        summary: String,
        phase: SessionPhase,
        timestamp: Date,
        jumpTarget: JumpTarget,
        codexMetadata: CodexSessionMetadata
    ) {
        let workspaceName = URL(fileURLWithPath: thread.cwd).lastPathComponent
        let rolloutSnapshot = Self.rolloutSnapshot(atPath: thread.path)
        let isSubagentSession = Self.rolloutIsSubagentSession(atPath: thread.path)
        let title = Self.threadTitle(
            rawName: thread.name,
            workspaceName: workspaceName,
            rolloutSnapshot: rolloutSnapshot
        )
        let summary = Self.threadSummary(from: thread, rolloutSnapshot: rolloutSnapshot)
        let threadUpdatedAt = Self.threadUpdatedAtDate(from: thread.updatedAt)
        let timestamp = Self.latestDate(
            rolloutSnapshot?.updatedAt,
            Self.rolloutActivityDate(atPath: thread.path),
            threadUpdatedAt
        )
            ?? .now

        let phase = Self.threadPhase(
            from: thread.status,
            rolloutSnapshot: rolloutSnapshot,
            threadUpdatedAt: threadUpdatedAt,
            now: now
        )

        let jumpTarget = JumpTarget(
            terminalApp: "Codex.app",
            workspaceName: workspaceName,
            paneTitle: title,
            workingDirectory: thread.cwd,
            codexThreadID: thread.id
        )

        let metadata = CodexSessionMetadata(
            transcriptPath: thread.path,
            initialUserPrompt: rolloutSnapshot?.initialUserPrompt,
            lastUserPrompt: rolloutSnapshot?.lastUserPrompt,
            lastAssistantMessage: rolloutSnapshot?.lastAssistantMessage,
            currentTool: rolloutSnapshot?.currentTool,
            currentCommandPreview: rolloutSnapshot?.currentCommandPreview,
            isSubagentSession: isSubagentSession
        )

        return (title, summary, phase, timestamp, jumpTarget, metadata)
    }

    static func threadTitle(
        rawName: String?,
        workspaceName: String,
        rolloutSnapshot: CodexRolloutSnapshot?
    ) -> String {
        if let rawName = rawName?.trimmedForCodexSurface,
           !rawName.isEmpty,
           !Self.isWorkspaceFallbackTitle(rawName, workspaceName: workspaceName) {
            return rawName
        }

        if let prompt = rolloutSnapshot?.initialUserPrompt?.trimmedForCodexSurface,
           !prompt.isEmpty {
            return Self.promptTitle(prompt)
        }

        if let prompt = rolloutSnapshot?.lastUserPrompt?.trimmedForCodexSurface,
           !prompt.isEmpty {
            return Self.promptTitle(prompt)
        }

        return workspaceName
    }

    static func threadSummary(
        from thread: CodexThread,
        rolloutSnapshot: CodexRolloutSnapshot?
    ) -> String {
        if let summary = rolloutSnapshot?.summary?.trimmedForCodexSurface, !summary.isEmpty {
            return summary
        }

        return thread.preview.isEmpty ? "Codex session." : String(thread.preview.prefix(120))
    }

    static func threadPhase(
        from status: CodexThreadStatus,
        rolloutSnapshot: CodexRolloutSnapshot?,
        threadUpdatedAt: Date? = nil,
        now: Date = .now
    ) -> SessionPhase {
        switch status.type {
        case .active:
            if status.isWaitingOnApproval {
                return .waitingForApproval
            }
            if status.isWaitingOnUserInput {
                return .waitingForAnswer
            }
            return .running
        case .idle:
            guard let rolloutSnapshot else {
                return .completed
            }
            if rolloutSnapshot.isCompleted {
                return .completed
            }
            if let updatedAt = rolloutSnapshot.updatedAt,
               now.timeIntervalSince(updatedAt) <= 10 * 60 {
                return rolloutSnapshot.phase
            }
            if Self.isRecentThreadActivity(threadUpdatedAt, now: now) {
                return .running
            }
            return .completed
        case .notLoaded, .systemError:
            if let rolloutSnapshot,
               !rolloutSnapshot.isCompleted,
               let updatedAt = rolloutSnapshot.updatedAt,
               now.timeIntervalSince(updatedAt) <= 10 * 60 {
                return rolloutSnapshot.phase
            }
            if let rolloutSnapshot, rolloutSnapshot.isCompleted {
                return .completed
            }
            if Self.isRecentThreadActivity(threadUpdatedAt, now: now) {
                return .running
            }
            return .completed
        }
    }

    private static func isRecentThreadActivity(_ threadUpdatedAt: Date?, now: Date) -> Bool {
        guard let threadUpdatedAt else { return false }
        let age = now.timeIntervalSince(threadUpdatedAt)
        return age >= 0 && age <= 10 * 60
    }

    private static func latestDate(_ dates: Date?...) -> Date? {
        dates.compactMap { $0 }.max()
    }

    static func rolloutSnapshot(atPath path: String?) -> CodexRolloutSnapshot? {
        guard let path,
              !path.isEmpty,
              FileManager.default.fileExists(atPath: path),
              let handle = try? FileHandle(forReadingFrom: URL(fileURLWithPath: path)) else {
            return nil
        }
        defer { try? handle.close() }

        do {
            let fileSize = try handle.seekToEnd()
            guard fileSize > 0 else { return nil }

            let headLimit = min(fileSize, 256 * 1_024)
            try handle.seek(toOffset: 0)
            var headBuffer = try handle.read(upToCount: Int(headLimit)) ?? Data()
            var snapshot = CodexRolloutSnapshot()
            consumeCompleteRolloutLines(from: &headBuffer) { line in
                CodexRolloutReducer.apply(line: String(decoding: line, as: UTF8.self), to: &snapshot)
            }

            let tailLimit = min(fileSize, 512 * 1_024)
            if fileSize > headLimit {
                try handle.seek(toOffset: fileSize - tailLimit)
                var tailBuffer = try handle.readToEnd() ?? Data()
                if fileSize > tailLimit {
                    trimLeadingPartialRolloutLine(from: &tailBuffer)
                }
                consumeCompleteRolloutLines(from: &tailBuffer) { line in
                    CodexRolloutReducer.apply(line: String(decoding: line, as: UTF8.self), to: &snapshot)
                }
            }

            guard snapshot.updatedAt != nil
                || snapshot.initialUserPrompt != nil
                || snapshot.lastUserPrompt != nil
                || snapshot.lastAssistantMessage != nil else {
                return nil
            }
            return snapshot
        } catch {
            return nil
        }
    }

    static func rolloutIsSubagentSession(atPath path: String?) -> Bool {
        guard let path,
              !path.isEmpty,
              FileManager.default.fileExists(atPath: path),
              let handle = try? FileHandle(forReadingFrom: URL(fileURLWithPath: path)) else {
            return false
        }
        defer { try? handle.close() }

        var buffer = Data()
        let newline = UInt8(ascii: "\n")
        while let chunk = try? handle.read(upToCount: 64 * 1_024), !chunk.isEmpty {
            buffer.append(chunk)
            while let newlineIndex = buffer.firstIndex(of: newline) {
                let line = buffer.prefix(upTo: newlineIndex)
                buffer.removeSubrange(...newlineIndex)
                if let result = Self.rolloutLineIsSubagentSession(line) {
                    return result
                }
            }
        }

        if !buffer.isEmpty, let result = Self.rolloutLineIsSubagentSession(buffer) {
            return result
        }

        return false
    }

    private static func rolloutLineIsSubagentSession(_ line: Data) -> Bool? {
        autoreleasepool {
            guard let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
                  object["type"] as? String == "session_meta" else {
                return nil
            }

            let payload = object["payload"] as? [String: Any] ?? [:]
            return (payload["thread_source"] as? String) == "subagent"
        }
    }

    static func isWorkspaceFallbackTitle(_ title: String, workspaceName: String) -> Bool {
        if title.localizedCaseInsensitiveCompare(workspaceName) == .orderedSame {
            return true
        }

        let codexDotPrefix = "Codex · "
        if title.range(of: codexDotPrefix, options: [.caseInsensitive, .anchored]) != nil {
            let stripped = String(title.dropFirst(codexDotPrefix.count)).trimmedForCodexSurface
            return stripped.localizedCaseInsensitiveCompare(workspaceName) == .orderedSame
        }

        if title.range(of: "Codex ", options: [.caseInsensitive, .anchored]) != nil {
            return true
        }

        return false
    }

    static func promptTitle(_ prompt: String) -> String {
        var title = prompt
            .split(whereSeparator: \.isNewline)
            .first
            .map(String.init)?
            .trimmedForCodexSurface ?? prompt.trimmedForCodexSurface

        while let range = title.range(of: #"^https?://\S+\s*"#, options: .regularExpression) {
            title.removeSubrange(range)
            title = title.trimmedForCodexSurface
        }

        guard title.count > 40 else {
            return title
        }
        let endIndex = title.index(title.startIndex, offsetBy: 39)
        return "\(title[..<endIndex])…"
    }

    static func threadUpdatedAtDate(from rawValue: Int) -> Date? {
        guard rawValue > 0 else { return nil }

        let seconds: TimeInterval
        if rawValue > 10_000_000_000 {
            seconds = TimeInterval(rawValue) / 1_000
        } else {
            seconds = TimeInterval(rawValue)
        }

        let date = Date(timeIntervalSince1970: seconds)
        guard date.timeIntervalSince1970 > 0 else { return nil }
        return date
    }

    static func rolloutActivityDate(atPath path: String?) -> Date? {
        guard let path,
              !path.isEmpty,
              FileManager.default.fileExists(atPath: path),
              let handle = try? FileHandle(forReadingFrom: URL(fileURLWithPath: path)) else {
            return nil
        }
        defer { try? handle.close() }

        do {
            let fileSize = try handle.seekToEnd()
            guard fileSize > 0 else { return nil }

            let tailLimit = min(fileSize, 512 * 1_024)
            try handle.seek(toOffset: fileSize - tailLimit)
            var buffer = try handle.readToEnd() ?? Data()
            if fileSize > tailLimit {
                trimLeadingPartialRolloutLine(from: &buffer)
            }

            var latest: Date?
            consumeCompleteRolloutLines(from: &buffer) { line in
                if let date = Self.rolloutLineTimestamp(line) {
                    latest = max(latest ?? date, date)
                }
            }
            if !buffer.isEmpty, let date = Self.rolloutLineTimestamp(buffer) {
                latest = max(latest ?? date, date)
            }

            return latest
        } catch {
            return nil
        }
    }

    private static func rolloutLineTimestamp(_ lineData: Data) -> Date? {
        autoreleasepool {
            guard !lineData.isEmpty,
                  let object = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any] else {
                return nil
            }

            let rawTimestamp = (object["timestamp"] as? String)
                ?? ((object["payload"] as? [String: Any])?["timestamp"] as? String)
            guard let rawTimestamp else { return nil }

            let fractionalFormatter = ISO8601DateFormatter()
            fractionalFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = fractionalFormatter.date(from: rawTimestamp) {
                return date
            }

            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime]
            return formatter.date(from: rawTimestamp)
        }
    }

    private static func consumeCompleteRolloutLines(from buffer: inout Data, _ consume: (Data) -> Void) {
        let newline = UInt8(ascii: "\n")
        while let newlineIndex = buffer.firstIndex(of: newline) {
            let line = buffer.prefix(upTo: newlineIndex)
            buffer.removeSubrange(...newlineIndex)
            guard !line.isEmpty else { continue }
            consume(Data(line))
        }
    }

    private static func trimLeadingPartialRolloutLine(from buffer: inout Data) {
        let newline = UInt8(ascii: "\n")
        guard let newlineIndex = buffer.firstIndex(of: newline) else {
            buffer.removeAll(keepingCapacity: false)
            return
        }
        buffer.removeSubrange(...newlineIndex)
    }
}

private extension String {
    var trimmedForCodexSurface: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
