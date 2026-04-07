import Dispatch
import Darwin
import Foundation

public final class BridgeServer: @unchecked Sendable {
    private struct ClientConnection {
        let id: UUID
        let fileDescriptor: Int32
        let readSource: DispatchSourceRead
        var role: BridgeClientRole?
        var buffer = Data()
    }

    private struct PendingApproval {
        let clientID: UUID
    }

    private struct PendingClaudeToolContext {
        let toolUseID: String?
        let toolName: String?
        let toolInput: ClaudeHookJSONValue?
    }

    private struct PendingClaudeInteraction {
        enum Kind {
            case permission(ClaudeHookPayload)
            case question(ClaudeHookPayload, QuestionPrompt)
        }

        let clientID: UUID
        let kind: Kind
    }

    private struct PendingOpenCodeInteraction {
        enum Kind {
            case permission(OpenCodeHookPayload)
            case question(OpenCodeHookPayload)
        }

        let clientID: UUID
        let kind: Kind
    }

    private let socketURL: URL
    private let queue = DispatchQueue(label: "app.openisland.bridge.server")
    private let queueKey = DispatchSpecificKey<Void>()

    private var listeningFileDescriptor: Int32 = -1
    private var acceptSource: DispatchSourceRead?
    private var clients: [UUID: ClientConnection] = [:]
    private var pendingApprovals: [String: PendingApproval] = [:]
    private var pendingClaudeToolContexts: [String: PendingClaudeToolContext] = [:]
    private var pendingClaudeInteractions: [String: PendingClaudeInteraction] = [:]
    private var pendingOpenCodeInteractions: [String: PendingOpenCodeInteraction] = [:]
    /// Caches Agent tool description from preToolUse for use by the next subagentStart.
    private var pendingAgentDescriptions: [String: String] = [:]
    private var stateSnapshot = SessionState()
    /// Local working state: tracks sessions emitted by this server between
    /// snapshot pushes from AppModel. This is NOT a duplicate of AppModel's
    /// state — it only contains sessions created via bridge hooks and is
    /// overwritten whenever AppModel pushes a fresh snapshot.
    private var localState = SessionState()

    public init(
        socketURL: URL = BridgeSocketLocation.defaultURL
    ) {
        self.socketURL = socketURL
        queue.setSpecific(key: queueKey, value: ())
    }

    deinit {
        stop()
    }

    public func start() throws {
        guard listeningFileDescriptor == -1 else {
            return
        }

        let parentURL = socketURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: parentURL, withIntermediateDirectories: true)
        try? FileManager.default.removeItem(at: socketURL)

        let listeningFileDescriptor = socket(AF_UNIX, SOCK_STREAM, 0)
        guard listeningFileDescriptor != -1 else {
            throw BridgeTransportError.systemCallFailed("socket", errno)
        }

        do {
            var reuseAddress: Int32 = 1
            guard setsockopt(
                listeningFileDescriptor,
                SOL_SOCKET,
                SO_REUSEADDR,
                &reuseAddress,
                socklen_t(MemoryLayout<Int32>.size)
            ) != -1 else {
                throw BridgeTransportError.systemCallFailed("setsockopt", errno)
            }

            try withUnixSocketAddress(path: socketURL.path) { address, length in
                guard bind(listeningFileDescriptor, address, length) != -1 else {
                    throw BridgeTransportError.systemCallFailed("bind", errno)
                }
            }

            guard listen(listeningFileDescriptor, 16) != -1 else {
                throw BridgeTransportError.systemCallFailed("listen", errno)
            }

            try makeSocketNonBlocking(listeningFileDescriptor)
        } catch {
            close(listeningFileDescriptor)
            try? FileManager.default.removeItem(at: socketURL)
            throw error
        }

        self.listeningFileDescriptor = listeningFileDescriptor

        let acceptSource = DispatchSource.makeReadSource(fileDescriptor: listeningFileDescriptor, queue: queue)
        acceptSource.setEventHandler { [weak self] in
            self?.acceptPendingClients()
        }
        acceptSource.setCancelHandler { [weak self] in
            guard let self else {
                return
            }

            if self.listeningFileDescriptor != -1 {
                close(self.listeningFileDescriptor)
                self.listeningFileDescriptor = -1
            }
        }
        self.acceptSource = acceptSource
        acceptSource.resume()
    }

    public func stop() {
        if DispatchQueue.getSpecific(key: queueKey) != nil {
            stopLocked()
        } else {
            queue.sync {
                stopLocked()
            }
        }
    }

    /// Pushes the authoritative session state from AppModel so BridgeServer
    /// can read session data without maintaining its own copy.
    public func updateStateSnapshot(_ snapshot: SessionState) {
        queue.sync {
            stateSnapshot = snapshot
            localState = snapshot
        }
    }

    private func stopLocked() {
        pendingApprovals.removeAll()
        pendingClaudeInteractions.removeAll()
        pendingClaudeToolContexts.removeAll()
        pendingOpenCodeInteractions.removeAll()

        let activeConnections = Array(clients.values)
        activeConnections.forEach { $0.readSource.cancel() }
        clients.removeAll()

        acceptSource?.cancel()
        acceptSource = nil

        if listeningFileDescriptor != -1 {
            close(listeningFileDescriptor)
            listeningFileDescriptor = -1
        }

        // Do NOT delete the socket file here.  start() already cleans up
        // stale sockets before binding.  Deleting in stop() causes a race
        // when the old process is being terminated while a new process has
        // already created its socket at the same path — the old process's
        // deferred cleanup removes the new socket file, breaking the bridge.
    }

    private func acceptPendingClients() {
        guard listeningFileDescriptor != -1 else {
            return
        }

        while true {
            let clientFileDescriptor = accept(listeningFileDescriptor, nil, nil)

            if clientFileDescriptor == -1 {
                if errno == EAGAIN || errno == EWOULDBLOCK {
                    return
                }

                return
            }

            do {
                try disableSocketSigPipe(clientFileDescriptor)
                try makeSocketNonBlocking(clientFileDescriptor)
                configureClient(fileDescriptor: clientFileDescriptor)
            } catch {
                close(clientFileDescriptor)
            }
        }
    }

    private func configureClient(fileDescriptor: Int32) {
        let clientID = UUID()
        let readSource = DispatchSource.makeReadSource(fileDescriptor: fileDescriptor, queue: queue)

        readSource.setEventHandler { [weak self] in
            self?.readAvailableData(from: clientID)
        }
        readSource.setCancelHandler { [weak self] in
            guard let self else {
                return
            }

            if let client = self.clients[clientID] {
                close(client.fileDescriptor)
            } else {
                close(fileDescriptor)
            }
        }

        clients[clientID] = ClientConnection(
            id: clientID,
            fileDescriptor: fileDescriptor,
            readSource: readSource,
            role: nil
        )
        readSource.resume()

        send(.hello(BridgeHello()), to: clientID)
    }

    private func readAvailableData(from clientID: UUID) {
        guard var client = clients[clientID] else {
            return
        }

        var localBuffer = [UInt8](repeating: 0, count: 8_192)

        while true {
            let bytesRead = read(client.fileDescriptor, &localBuffer, localBuffer.count)

            if bytesRead > 0 {
                client.buffer.append(localBuffer, count: bytesRead)

                do {
                    let envelopes = try BridgeCodec.decodeLines(from: &client.buffer)
                    clients[clientID] = client

                    for envelope in envelopes {
                        if case let .command(command) = envelope {
                            handle(command, from: clientID)
                        }
                    }
                } catch {
                    removeClient(clientID)
                    return
                }

                continue
            }

            if bytesRead == 0 {
                removeClient(clientID)
                return
            }

            if errno == EAGAIN || errno == EWOULDBLOCK {
                clients[clientID] = client
                return
            }

            removeClient(clientID)
            return
        }
    }

    private func handle(_ command: BridgeCommand, from clientID: UUID) {
        switch command {
        case let .registerClient(role):
            guard var client = clients[clientID] else {
                return
            }

            client.role = role
            clients[clientID] = client
            send(.response(.acknowledged), to: clientID)

        case let .requestQuestion(sessionID, prompt):
            guard hasSession(id: sessionID) else {
                send(.response(.acknowledged), to: clientID)
                return
            }

            emit(
                .questionAsked(
                    QuestionAsked(
                        sessionID: sessionID,
                        prompt: prompt,
                        timestamp: .now
                    )
                )
            )
            send(.response(.acknowledged), to: clientID)

        case let .resolvePermission(sessionID, resolution):
            if pendingClaudeInteractions[sessionID] != nil {
                resolvePendingClaudeInteraction(sessionID: sessionID, resolution: resolution)
                send(.response(.acknowledged), to: clientID)
                return
            }

            if pendingOpenCodeInteractions[sessionID] != nil {
                resolvePendingOpenCodeInteraction(sessionID: sessionID, resolution: resolution)
                send(.response(.acknowledged), to: clientID)
                return
            }

            localState.resolvePermission(sessionID: sessionID, resolution: resolution)
            broadcast([.event(
                resolution.isApproved
                    ? .activityUpdated(
                        SessionActivityUpdated(
                            sessionID: sessionID,
                            summary: "Permission approved. Codex continued the command.",
                            phase: .running,
                            timestamp: .now
                        )
                    )
                    : .sessionCompleted(
                        SessionCompleted(
                            sessionID: sessionID,
                            summary: "Permission denied in Open Island.",
                            timestamp: .now
                        )
                    )
            )])
            resolvePendingApproval(sessionID: sessionID, approved: resolution.isApproved)
            send(.response(.acknowledged), to: clientID)

        case let .answerQuestion(sessionID, response):
            if pendingClaudeInteractions[sessionID] != nil {
                resolvePendingClaudeQuestion(sessionID: sessionID, response: response)
                send(.response(.acknowledged), to: clientID)
                return
            }

            if pendingOpenCodeInteractions[sessionID] != nil {
                resolvePendingOpenCodeQuestion(sessionID: sessionID, response: response)
                send(.response(.acknowledged), to: clientID)
                return
            }

            let summary = response.displaySummary.isEmpty
                ? "Answered the question."
                : "Answered: \(response.displaySummary)"
            emit(
                .activityUpdated(
                    SessionActivityUpdated(
                        sessionID: sessionID,
                        summary: summary,
                        phase: .running,
                        timestamp: .now
                    )
                )
            )
            send(.response(.acknowledged), to: clientID)

        case let .processCodexHook(payload):
            handleCodexHook(payload, from: clientID)

        case let .processClaudeHook(payload):
            handleClaudeHook(payload, from: clientID)

        case let .processOpenCodeHook(payload):
            handleOpenCodeHook(payload, from: clientID)
        }
    }

    private func handleCodexHook(_ payload: CodexHookPayload, from clientID: UUID) {
        switch payload.hookEventName {
        case .sessionStart:
            let event = AgentEvent.sessionStarted(
                SessionStarted(
                    sessionID: payload.sessionID,
                    title: payload.sessionTitle,
                    tool: .codex,
                    origin: .live,
                    summary: payload.implicitStartSummary,
                    timestamp: .now,
                    jumpTarget: payload.defaultJumpTarget,
                    codexMetadata: payload.defaultCodexMetadata.isEmpty ? nil : payload.defaultCodexMetadata
                )
            )

            emit(event)
            send(.response(.acknowledged), to: clientID)

        case .userPromptSubmit:
            ensureSessionExists(for: payload)
            synchronizeJumpTarget(for: payload)
            synchronizeCodexMetadata(for: payload)
            let prompt = payload.prompt ?? payload.promptPreview ?? "User submitted a prompt to Codex."
            emit(
                .activityUpdated(
                    SessionActivityUpdated(
                        sessionID: payload.sessionID,
                        summary: "Prompt: \(prompt)",
                        phase: .running,
                        timestamp: .now
                    )
                )
            )
            send(.response(.acknowledged), to: clientID)

        case .preToolUse:
            ensureSessionExists(for: payload)
            synchronizeJumpTarget(for: payload)
            synchronizeCodexMetadata(for: payload)

            let command = payload.commandPreview ?? "Bash command"

            let approvalEvent = AgentEvent.permissionRequested(
                PermissionRequested(
                    sessionID: payload.sessionID,
                    request: PermissionRequest(
                        title: "Run Bash command",
                        summary: "Codex wants to run a shell command.",
                        affectedPath: payload.commandText ?? command,
                        primaryActionTitle: "Allow",
                        secondaryActionTitle: "Deny"
                    ),
                    timestamp: .now
                )
            )

            emit(approvalEvent)

            pendingApprovals[payload.sessionID] = PendingApproval(
                clientID: clientID
            )

        case .postToolUse:
            ensureSessionExists(for: payload)
            synchronizeJumpTarget(for: payload)
            synchronizeCodexMetadata(for: payload)
            let command = payload.commandPreview ?? "Bash command"
            let responsePreview = payload.toolResponsePreview
            let summary = responsePreview.map { "Bash finished: \(command) · \($0)" } ?? "Bash finished: \(command)"

            emit(
                .activityUpdated(
                    SessionActivityUpdated(
                        sessionID: payload.sessionID,
                        summary: summary,
                        phase: .running,
                        timestamp: .now
                    )
                )
            )
            send(.response(.acknowledged), to: clientID)

        case .stop:
            ensureSessionExists(for: payload)
            synchronizeJumpTarget(for: payload)
            synchronizeCodexMetadata(for: payload)
            let summary = payload.lastAssistantMessage ?? payload.assistantMessagePreview ?? "Codex completed the turn."

            emit(
                .sessionCompleted(
                    SessionCompleted(
                        sessionID: payload.sessionID,
                        summary: summary,
                        timestamp: .now
                    )
                )
            )
            send(.response(.acknowledged), to: clientID)
        }
    }

    private func handleClaudeHook(_ payload: ClaudeHookPayload, from clientID: UUID) {
        // Subagent processes fire their own hooks with agentID set.
        // The parent session already receives SubagentStart/SubagentStop events,
        // so we suppress subagent hooks to avoid creating duplicate sessions.
        if payload.agentID != nil,
           payload.hookEventName != .subagentStart,
           payload.hookEventName != .subagentStop {
            send(.response(.acknowledged), to: clientID)
            return
        }

        switch payload.hookEventName {
        case .sessionStart:
            clearStaleClaudeInteractionIfNeeded(for: payload.sessionID)
            emit(
                .sessionStarted(
                    SessionStarted(
                        sessionID: payload.sessionID,
                        title: payload.sessionTitle,
                        tool: .claudeCode,
                        origin: .live,
                        initialPhase: .completed,
                        summary: payload.implicitStartSummary,
                        timestamp: .now,
                        jumpTarget: payload.defaultJumpTarget,
                        claudeMetadata: payload.defaultClaudeMetadata.isEmpty ? nil : payload.defaultClaudeMetadata,
                        isRemote: payload.remote == true
                    )
                )
            )
            send(.response(.acknowledged), to: clientID)

        case .userPromptSubmit:
            clearStaleClaudeInteractionIfNeeded(for: payload.sessionID)
            ensureClaudeSessionExists(for: payload)
            synchronizeClaudeJumpTarget(for: payload)
            synchronizeClaudeMetadata(for: payload)
            emit(
                .activityUpdated(
                    SessionActivityUpdated(
                        sessionID: payload.sessionID,
                        summary: payload.promptPreview.map { "Prompt: \($0)" } ?? payload.implicitStartSummary,
                        phase: .running,
                        timestamp: .now
                    )
                )
            )
            send(.response(.acknowledged), to: clientID)

        case .preToolUse:
            clearStaleClaudeInteractionIfNeeded(for: payload.sessionID)
            ensureClaudeSessionExists(for: payload)
            synchronizeClaudeJumpTarget(for: payload)
            synchronizeClaudeMetadata(for: payload)
            pendingClaudeToolContexts[payload.permissionCorrelationKey] = PendingClaudeToolContext(
                toolUseID: payload.toolUseID,
                toolName: payload.toolName,
                toolInput: payload.toolInput
            )

            // Cache Agent tool description for upcoming subagentStart
            if payload.toolName == "Agent",
               case let .object(obj) = payload.toolInput,
               case let .string(desc) = obj["description"],
               !desc.isEmpty {
                pendingAgentDescriptions[payload.sessionID] = desc
            }

            // Capture task creation/updates from TaskCreate, TaskUpdate, TaskOutput tools
            if let toolName = payload.toolName,
               (toolName == "TaskCreate" || toolName == "TaskUpdate"),
               case let .object(obj) = payload.toolInput {
                updateTask(from: obj, toolName: toolName, sessionID: payload.sessionID)
            }

            let summary = payload.toolName.map { "Running \($0)" } ?? "Running Claude tool"
            emit(
                .activityUpdated(
                    SessionActivityUpdated(
                        sessionID: payload.sessionID,
                        summary: payload.toolInputPreview.map { "\(summary): \($0)" } ?? summary,
                        phase: .running,
                        timestamp: .now
                    )
                )
            )
            send(.response(.acknowledged), to: clientID)

        case .permissionRequest:
            ensureClaudeSessionExists(for: payload)
            synchronizeClaudeJumpTarget(for: payload)
            synchronizeClaudeMetadata(for: payload)

            if let prompt = payload.questionPrompt {
                emit(
                    .questionAsked(
                        QuestionAsked(
                            sessionID: payload.sessionID,
                            prompt: prompt,
                            timestamp: .now
                        )
                    )
                )

                pendingClaudeInteractions[payload.sessionID] = PendingClaudeInteraction(
                    clientID: clientID,
                    kind: .question(payload, prompt)
                )
            } else {
                emit(
                    .permissionRequested(
                        PermissionRequested(
                            sessionID: payload.sessionID,
                            request: PermissionRequest(
                                title: payload.permissionRequestTitle,
                                summary: payload.permissionRequestSummary,
                                affectedPath: payload.permissionAffectedPath,
                                primaryActionTitle: "Allow Once",
                                secondaryActionTitle: "Deny",
                                toolName: payload.toolName,
                                toolUseID: claudeToolUseID(for: payload),
                                suggestedUpdates: payload.permissionSuggestions ?? []
                            ),
                            timestamp: .now
                        )
                    )
                )

                pendingClaudeInteractions[payload.sessionID] = PendingClaudeInteraction(
                    clientID: clientID,
                    kind: .permission(payload)
                )
            }

        case .postToolUse:
            clearStaleClaudeInteractionIfNeeded(for: payload.sessionID)
            ensureClaudeSessionExists(for: payload)
            synchronizeClaudeJumpTarget(for: payload)
            synchronizeClaudeMetadata(for: payload)
            pendingClaudeToolContexts.removeValue(forKey: payload.permissionCorrelationKey)

            let summary = {
                if payload.toolName == "AskUserQuestion" {
                    return "Claude captured your answers."
                }

                if let preview = payload.toolResponsePreview,
                   let toolName = payload.toolName {
                    return "\(toolName) finished: \(preview)"
                }

                if let toolName = payload.toolName {
                    return "\(toolName) finished."
                }

                return payload.implicitStartSummary
            }()

            emit(
                .activityUpdated(
                    SessionActivityUpdated(
                        sessionID: payload.sessionID,
                        summary: summary,
                        phase: .running,
                        timestamp: .now
                    )
                )
            )
            send(.response(.acknowledged), to: clientID)

        case .postToolUseFailure:
            clearStaleClaudeInteractionIfNeeded(for: payload.sessionID)
            ensureClaudeSessionExists(for: payload)
            synchronizeClaudeJumpTarget(for: payload)
            synchronizeClaudeMetadata(for: payload)
            pendingClaudeToolContexts.removeValue(forKey: payload.permissionCorrelationKey)

            emit(
                .activityUpdated(
                    SessionActivityUpdated(
                        sessionID: payload.sessionID,
                        summary: payload.error ?? "Claude tool failed.",
                        phase: payload.isInterrupt == true ? .completed : .running,
                        timestamp: .now
                    )
                )
            )
            send(.response(.acknowledged), to: clientID)

        case .permissionDenied:
            clearStaleClaudeInteractionIfNeeded(for: payload.sessionID)
            ensureClaudeSessionExists(for: payload)
            synchronizeClaudeJumpTarget(for: payload)
            synchronizeClaudeMetadata(for: payload)

            emit(
                .sessionCompleted(
                    SessionCompleted(
                        sessionID: payload.sessionID,
                        summary: payload.error ?? "Claude permission was denied.",
                        timestamp: .now
                    )
                )
            )
            send(.response(.acknowledged), to: clientID)

        case .notification:
            clearStaleClaudeInteractionIfNeeded(for: payload.sessionID)
            ensureClaudeSessionExists(for: payload)
            synchronizeClaudeJumpTarget(for: payload)
            synchronizeClaudeMetadata(for: payload)

            let currentPhase = localState.session(id: payload.sessionID)?.phase ?? .completed
            let notificationPhase: SessionPhase
            if payload.notificationType == "idle_prompt" {
                notificationPhase = .completed
            } else {
                // Notifications are informational — never escalate phase to running.
                notificationPhase = currentPhase
            }

            emit(
                .activityUpdated(
                    SessionActivityUpdated(
                        sessionID: payload.sessionID,
                        summary: payload.notificationPreview ?? payload.implicitStartSummary,
                        phase: notificationPhase,
                        timestamp: .now
                    )
                )
            )
            send(.response(.acknowledged), to: clientID)

        case .stop:
            clearStaleClaudeInteractionIfNeeded(for: payload.sessionID)
            ensureClaudeSessionExists(for: payload)
            synchronizeClaudeJumpTarget(for: payload)
            synchronizeClaudeMetadata(for: payload)

            emit(
                .sessionCompleted(
                    SessionCompleted(
                        sessionID: payload.sessionID,
                        summary: payload.lastAssistantMessage ?? payload.assistantMessagePreview ?? "Claude completed the turn.",
                        timestamp: .now,
                        isInterrupt: payload.isInterrupt
                    )
                )
            )
            send(.response(.acknowledged), to: clientID)

        case .stopFailure:
            clearStaleClaudeInteractionIfNeeded(for: payload.sessionID)
            ensureClaudeSessionExists(for: payload)
            synchronizeClaudeJumpTarget(for: payload)
            synchronizeClaudeMetadata(for: payload)

            emit(
                .sessionCompleted(
                    SessionCompleted(
                        sessionID: payload.sessionID,
                        summary: payload.error ?? payload.lastAssistantMessage ?? payload.assistantMessagePreview ?? "Claude failed to finish the turn.",
                        timestamp: .now,
                        isInterrupt: payload.isInterrupt
                    )
                )
            )
            send(.response(.acknowledged), to: clientID)

        case .subagentStart:
            clearStaleClaudeInteractionIfNeeded(for: payload.sessionID)
            ensureClaudeSessionExists(for: payload)
            synchronizeClaudeJumpTarget(for: payload)
            synchronizeClaudeMetadata(for: payload)

            if let agentID = payload.agentID {
                let desc = pendingAgentDescriptions.removeValue(forKey: payload.sessionID)
                addSubagent(
                    ClaudeSubagentInfo(
                        agentID: agentID,
                        agentType: payload.agentType,
                        taskDescription: desc,
                        startedAt: .now
                    ),
                    toSession: payload.sessionID
                )
            }

            let summary = payload.agentType.map { "Started \($0) subagent." } ?? "Started Claude subagent."
            emit(
                .activityUpdated(
                    SessionActivityUpdated(
                        sessionID: payload.sessionID,
                        summary: summary,
                        phase: .running,
                        timestamp: .now
                    )
                )
            )
            send(.response(.acknowledged), to: clientID)

        case .subagentStop:
            clearStaleClaudeInteractionIfNeeded(for: payload.sessionID)
            ensureClaudeSessionExists(for: payload)
            synchronizeClaudeJumpTarget(for: payload)
            synchronizeClaudeMetadata(for: payload)

            if let agentID = payload.agentID {
                removeSubagent(agentID: agentID, fromSession: payload.sessionID)
            }

            let summary = payload.lastAssistantMessage ?? payload.assistantMessagePreview
                ?? payload.agentType.map { "Finished \($0) subagent." }
                ?? "Finished Claude subagent."
            emit(
                .activityUpdated(
                    SessionActivityUpdated(
                        sessionID: payload.sessionID,
                        summary: summary,
                        phase: .running,
                        timestamp: .now
                    )
                )
            )
            send(.response(.acknowledged), to: clientID)

        case .preCompact:
            clearStaleClaudeInteractionIfNeeded(for: payload.sessionID)
            ensureClaudeSessionExists(for: payload)
            synchronizeClaudeJumpTarget(for: payload)
            synchronizeClaudeMetadata(for: payload)

            emit(
                .activityUpdated(
                    SessionActivityUpdated(
                        sessionID: payload.sessionID,
                        summary: "Claude is compacting the conversation.",
                        phase: .running,
                        timestamp: .now
                    )
                )
            )
            send(.response(.acknowledged), to: clientID)

        case .sessionEnd:
            clearStaleClaudeInteractionIfNeeded(for: payload.sessionID)
            ensureClaudeSessionExists(for: payload)
            synchronizeClaudeJumpTarget(for: payload)
            synchronizeClaudeMetadata(for: payload)

            emit(
                .sessionCompleted(
                    SessionCompleted(
                        sessionID: payload.sessionID,
                        summary: "Claude session ended.",
                        timestamp: .now,
                        isInterrupt: true
                    )
                )
            )
            send(.response(.acknowledged), to: clientID)
        }
    }

    private func handleOpenCodeHook(_ payload: OpenCodeHookPayload, from clientID: UUID) {
        switch payload.hookEventName {
        case .sessionStart:
            clearStaleOpenCodeInteractionIfNeeded(for: payload.sessionID)
            emit(
                .sessionStarted(
                    SessionStarted(
                        sessionID: payload.sessionID,
                        title: payload.sessionTitle,
                        tool: .openCode,
                        origin: .live,
                        initialPhase: .running,
                        summary: payload.implicitStartSummary,
                        timestamp: .now,
                        jumpTarget: payload.defaultJumpTarget,
                        openCodeMetadata: payload.defaultOpenCodeMetadata.isEmpty ? nil : payload.defaultOpenCodeMetadata
                    )
                )
            )
            send(.response(.acknowledged), to: clientID)

        case .userPromptSubmit:
            clearStaleOpenCodeInteractionIfNeeded(for: payload.sessionID)
            ensureOpenCodeSessionExists(for: payload)
            synchronizeOpenCodeJumpTarget(for: payload)
            synchronizeOpenCodeMetadata(for: payload)
            emit(
                .activityUpdated(
                    SessionActivityUpdated(
                        sessionID: payload.sessionID,
                        summary: payload.promptPreview.map { "Prompt: \($0)" } ?? payload.implicitStartSummary,
                        phase: .running,
                        timestamp: .now
                    )
                )
            )
            send(.response(.acknowledged), to: clientID)

        case .preToolUse:
            clearStaleOpenCodeInteractionIfNeeded(for: payload.sessionID)
            ensureOpenCodeSessionExists(for: payload)
            synchronizeOpenCodeJumpTarget(for: payload)
            synchronizeOpenCodeMetadata(for: payload)
            let summary = payload.toolName.map { "Running \($0)" } ?? "Running OpenCode tool"
            emit(
                .activityUpdated(
                    SessionActivityUpdated(
                        sessionID: payload.sessionID,
                        summary: payload.toolInputPreview.map { "\(summary): \($0)" } ?? summary,
                        phase: .running,
                        timestamp: .now
                    )
                )
            )
            send(.response(.acknowledged), to: clientID)

        case .postToolUse:
            clearStaleOpenCodeInteractionIfNeeded(for: payload.sessionID)
            ensureOpenCodeSessionExists(for: payload)
            synchronizeOpenCodeJumpTarget(for: payload)
            synchronizeOpenCodeMetadata(for: payload)
            let summary = payload.toolName.map { "\($0) finished." } ?? "OpenCode tool finished."
            emit(
                .activityUpdated(
                    SessionActivityUpdated(
                        sessionID: payload.sessionID,
                        summary: summary,
                        phase: .running,
                        timestamp: .now
                    )
                )
            )
            send(.response(.acknowledged), to: clientID)

        case .permissionRequest:
            ensureOpenCodeSessionExists(for: payload)
            synchronizeOpenCodeJumpTarget(for: payload)
            synchronizeOpenCodeMetadata(for: payload)

            emit(
                .permissionRequested(
                    PermissionRequested(
                        sessionID: payload.sessionID,
                        request: PermissionRequest(
                            title: payload.permissionTitle ?? payload.toolName.map { "Allow \($0)" } ?? "Allow OpenCode tool",
                            summary: payload.permissionDescription ?? "OpenCode needs permission to continue.",
                            affectedPath: payload.toolInputPreview ?? payload.cwd,
                            primaryActionTitle: "Allow",
                            secondaryActionTitle: "Deny",
                            toolName: payload.toolName
                        ),
                        timestamp: .now
                    )
                )
            )

            pendingOpenCodeInteractions[payload.sessionID] = PendingOpenCodeInteraction(
                clientID: clientID,
                kind: .permission(payload)
            )

        case .questionAsked:
            ensureOpenCodeSessionExists(for: payload)
            synchronizeOpenCodeJumpTarget(for: payload)
            synchronizeOpenCodeMetadata(for: payload)

            let questionTitle = payload.questionText ?? "OpenCode has a question for you."
            emit(
                .questionAsked(
                    QuestionAsked(
                        sessionID: payload.sessionID,
                        prompt: QuestionPrompt(
                            title: questionTitle,
                            options: []
                        ),
                        timestamp: .now
                    )
                )
            )

            pendingOpenCodeInteractions[payload.sessionID] = PendingOpenCodeInteraction(
                clientID: clientID,
                kind: .question(payload)
            )

        case .stop:
            clearStaleOpenCodeInteractionIfNeeded(for: payload.sessionID)
            ensureOpenCodeSessionExists(for: payload)
            synchronizeOpenCodeJumpTarget(for: payload)
            synchronizeOpenCodeMetadata(for: payload)
            emit(
                .sessionCompleted(
                    SessionCompleted(
                        sessionID: payload.sessionID,
                        summary: payload.lastAssistantMessage ?? payload.assistantMessagePreview ?? "OpenCode completed the turn.",
                        timestamp: .now
                    )
                )
            )
            send(.response(.acknowledged), to: clientID)

        case .sessionEnd:
            clearStaleOpenCodeInteractionIfNeeded(for: payload.sessionID)
            ensureOpenCodeSessionExists(for: payload)
            synchronizeOpenCodeJumpTarget(for: payload)
            synchronizeOpenCodeMetadata(for: payload)
            emit(
                .sessionCompleted(
                    SessionCompleted(
                        sessionID: payload.sessionID,
                        summary: "OpenCode session ended.",
                        timestamp: .now,
                        isInterrupt: true
                    )
                )
            )
            send(.response(.acknowledged), to: clientID)
        }
    }

    private func clearStaleOpenCodeInteractionIfNeeded(for sessionID: String) {
        guard pendingOpenCodeInteractions.removeValue(forKey: sessionID) != nil else {
            return
        }

        emit(
            .actionableStateResolved(
                ActionableStateResolved(
                    sessionID: sessionID,
                    summary: "Approval was handled outside Open Island.",
                    timestamp: .now
                )
            )
        )
    }

    private func ensureOpenCodeSessionExists(for payload: OpenCodeHookPayload) {
        guard !hasSession(id: payload.sessionID) else {
            return
        }

        emit(
            .sessionStarted(
                SessionStarted(
                    sessionID: payload.sessionID,
                    title: payload.sessionTitle,
                    tool: .openCode,
                    origin: .live,
                    initialPhase: .running,
                    summary: payload.implicitStartSummary,
                    timestamp: .now,
                    jumpTarget: payload.defaultJumpTarget,
                    openCodeMetadata: payload.defaultOpenCodeMetadata.isEmpty ? nil : payload.defaultOpenCodeMetadata
                )
            )
        )
    }

    private func synchronizeOpenCodeJumpTarget(for payload: OpenCodeHookPayload) {
        guard let existingSession = localState.session(id: payload.sessionID) else {
            return
        }

        var jumpTarget = payload.defaultJumpTarget

        if jumpTarget.terminalSessionID == nil,
           let existingID = existingSession.jumpTarget?.terminalSessionID,
           !existingID.isEmpty {
            jumpTarget.terminalSessionID = existingID
        }

        guard existingSession.jumpTarget != jumpTarget else {
            return
        }

        emit(
            .jumpTargetUpdated(
                JumpTargetUpdated(
                    sessionID: payload.sessionID,
                    jumpTarget: jumpTarget,
                    timestamp: .now
                )
            )
        )
    }

    private func synchronizeOpenCodeMetadata(for payload: OpenCodeHookPayload) {
        guard let existingSession = localState.session(id: payload.sessionID) else {
            return
        }

        let mergedMetadata = mergedOpenCodeMetadata(
            existing: existingSession.openCodeMetadata,
            update: payload.defaultOpenCodeMetadata,
            hookEventName: payload.hookEventName
        )
        guard !mergedMetadata.isEmpty else {
            return
        }

        guard existingSession.openCodeMetadata != mergedMetadata else {
            return
        }

        emit(
            .openCodeSessionMetadataUpdated(
                OpenCodeSessionMetadataUpdated(
                    sessionID: payload.sessionID,
                    openCodeMetadata: mergedMetadata,
                    timestamp: .now
                )
            )
        )
    }

    private func mergedOpenCodeMetadata(
        existing: OpenCodeSessionMetadata?,
        update: OpenCodeSessionMetadata,
        hookEventName: OpenCodeHookEventName
    ) -> OpenCodeSessionMetadata {
        OpenCodeSessionMetadata(
            initialUserPrompt: existing?.initialUserPrompt ?? update.initialUserPrompt ?? update.lastUserPrompt,
            lastUserPrompt: update.lastUserPrompt ?? existing?.lastUserPrompt,
            lastAssistantMessage: update.lastAssistantMessage ?? existing?.lastAssistantMessage,
            currentTool: mergedOpenCodeCurrentTool(
                existing: existing?.currentTool,
                update: update.currentTool,
                hookEventName: hookEventName
            ),
            currentToolInputPreview: mergedOpenCodeCurrentToolInputPreview(
                existing: existing?.currentToolInputPreview,
                update: update.currentToolInputPreview,
                hookEventName: hookEventName
            ),
            model: update.model ?? existing?.model
        )
    }

    private func mergedOpenCodeCurrentTool(
        existing: String?,
        update: String?,
        hookEventName: OpenCodeHookEventName
    ) -> String? {
        if let update {
            return update
        }

        switch hookEventName {
        case .postToolUse, .stop, .sessionEnd:
            return nil
        case .sessionStart, .userPromptSubmit, .preToolUse, .permissionRequest, .questionAsked:
            return existing
        }
    }

    private func mergedOpenCodeCurrentToolInputPreview(
        existing: String?,
        update: String?,
        hookEventName: OpenCodeHookEventName
    ) -> String? {
        if let update {
            return update
        }

        switch hookEventName {
        case .postToolUse, .stop, .sessionEnd:
            return nil
        case .sessionStart, .userPromptSubmit, .preToolUse, .permissionRequest, .questionAsked:
            return existing
        }
    }

    private func resolvePendingOpenCodeInteraction(
        sessionID: String,
        resolution: PermissionResolution
    ) {
        guard let pendingInteraction = pendingOpenCodeInteractions.removeValue(forKey: sessionID) else {
            return
        }

        let directive: OpenCodeHookDirective
        let summary: String
        let phase: SessionPhase

        switch (pendingInteraction.kind, resolution) {
        case let (.permission(payload), .allowOnce):
            directive = .allow
            summary = payload.toolName.map { "Permission approved for \($0)." } ?? "Permission approved."
            phase = .running

        case let (.permission(_), .deny(message, _)):
            directive = .deny(reason: message ?? "Permission denied in Open Island.")
            summary = message ?? "Permission denied in Open Island."
            phase = .completed

        case (.question, .allowOnce):
            directive = .allow
            summary = "OpenCode's question was answered."
            phase = .running

        case let (.question(_), .deny(message, _)):
            directive = .deny(reason: message ?? "Declined to answer.")
            summary = message ?? "Declined to answer."
            phase = .completed
        }

        emit(
            phase == .completed
                ? .sessionCompleted(
                    SessionCompleted(
                        sessionID: sessionID,
                        summary: summary,
                        timestamp: .now
                    )
                )
                : .activityUpdated(
                    SessionActivityUpdated(
                        sessionID: sessionID,
                        summary: summary,
                        phase: phase,
                        timestamp: .now
                    )
                )
        )

        send(.response(.openCodeHookDirective(directive)), to: pendingInteraction.clientID)
    }

    private func resolvePendingOpenCodeQuestion(
        sessionID: String,
        response: QuestionPromptResponse
    ) {
        guard let pendingInteraction = pendingOpenCodeInteractions.removeValue(forKey: sessionID) else {
            return
        }

        let answerText = response.rawAnswer ?? response.displaySummary
        let summary = answerText.isEmpty
            ? "Answered OpenCode's question."
            : "Answered: \(answerText)"

        emit(
            .activityUpdated(
                SessionActivityUpdated(
                    sessionID: sessionID,
                    summary: summary,
                    phase: .running,
                    timestamp: .now
                )
            )
        )

        send(
            .response(.openCodeHookDirective(.answer(text: answerText))),
            to: pendingInteraction.clientID
        )
    }

    private func clearStaleClaudeInteractionIfNeeded(for sessionID: String) {
        guard pendingClaudeInteractions.removeValue(forKey: sessionID) != nil else {
            return
        }

        emit(
            .actionableStateResolved(
                ActionableStateResolved(
                    sessionID: sessionID,
                    summary: "Approval was handled outside Open Island.",
                    timestamp: .now
                )
            )
        )
    }

    private func ensureSessionExists(for payload: CodexHookPayload) {
        guard !hasSession(id: payload.sessionID) else {
            return
        }

        emit(
            .sessionStarted(
                SessionStarted(
                    sessionID: payload.sessionID,
                    title: payload.sessionTitle,
                    tool: .codex,
                    origin: .live,
                    summary: payload.implicitStartSummary,
                    timestamp: .now,
                    jumpTarget: payload.defaultJumpTarget,
                    codexMetadata: payload.defaultCodexMetadata.isEmpty ? nil : payload.defaultCodexMetadata
                )
            )
        )
    }

    private func synchronizeJumpTarget(for payload: CodexHookPayload) {
        guard let existingSession = localState.session(id: payload.sessionID) else {
            return
        }

        var jumpTarget = payload.defaultJumpTarget

        if jumpTarget.terminalSessionID == nil,
           let existingID = existingSession.jumpTarget?.terminalSessionID,
           !existingID.isEmpty {
            jumpTarget.terminalSessionID = existingID
        }

        guard existingSession.jumpTarget != jumpTarget else {
            return
        }

        emit(
            .jumpTargetUpdated(
                JumpTargetUpdated(
                    sessionID: payload.sessionID,
                    jumpTarget: jumpTarget,
                    timestamp: .now
                )
            )
        )
    }

    private func synchronizeCodexMetadata(for payload: CodexHookPayload) {
        guard let existingSession = localState.session(id: payload.sessionID) else {
            return
        }

        let mergedMetadata = mergedCodexMetadata(
            existing: existingSession.codexMetadata,
            update: payload.defaultCodexMetadata,
            hookEventName: payload.hookEventName
        )
        guard !mergedMetadata.isEmpty else {
            return
        }

        guard existingSession.codexMetadata != mergedMetadata else {
            return
        }

        emit(
            .sessionMetadataUpdated(
                SessionMetadataUpdated(
                    sessionID: payload.sessionID,
                    codexMetadata: mergedMetadata,
                    timestamp: .now
                )
            )
        )
    }

    private func ensureClaudeSessionExists(for payload: ClaudeHookPayload) {
        guard !hasSession(id: payload.sessionID) else {
            return
        }

        let transcriptStart: Date? = payload.transcriptPath.flatMap {
            ClaudeTranscriptDiscovery.firstTimestamp(inTranscriptAt: $0)
        }

        emit(
            .sessionStarted(
                SessionStarted(
                    sessionID: payload.sessionID,
                    title: payload.sessionTitle,
                    tool: .claudeCode,
                    origin: .live,
                    initialPhase: .completed,
                    summary: payload.implicitStartSummary,
                    timestamp: transcriptStart ?? .now,
                    jumpTarget: payload.defaultJumpTarget,
                    claudeMetadata: payload.defaultClaudeMetadata.isEmpty ? nil : payload.defaultClaudeMetadata,
                    isRemote: payload.remote == true
                )
            )
        )
    }

    private func synchronizeClaudeJumpTarget(for payload: ClaudeHookPayload) {
        guard let existingSession = localState.session(id: payload.sessionID) else {
            return
        }

        var jumpTarget = payload.defaultJumpTarget

        // Preserve an existing Ghostty terminal session ID when the incoming
        // payload doesn't carry one.  Only SessionStart hooks query the
        // Ghostty focused-terminal locator; later hooks clear the field to
        // avoid capturing the wrong terminal if the user switched tabs.
        if jumpTarget.terminalSessionID == nil,
           let existingID = existingSession.jumpTarget?.terminalSessionID,
           !existingID.isEmpty {
            jumpTarget.terminalSessionID = existingID
        }

        guard existingSession.jumpTarget != jumpTarget else {
            return
        }

        emit(
            .jumpTargetUpdated(
                JumpTargetUpdated(
                    sessionID: payload.sessionID,
                    jumpTarget: jumpTarget,
                    timestamp: .now
                )
            )
        )
    }

    private func synchronizeClaudeMetadata(for payload: ClaudeHookPayload) {
        guard let existingSession = localState.session(id: payload.sessionID) else {
            return
        }

        var mergedMetadata = mergedClaudeMetadata(
            existing: existingSession.claudeMetadata,
            update: payload.defaultClaudeMetadata,
            hookEventName: payload.hookEventName
        )

        // Read session title from transcript if not yet set
        if mergedMetadata.customTitle == nil {
            let transcriptPath = mergedMetadata.transcriptPath
                ?? payload.transcriptPath
                ?? ClaudeTranscriptDiscovery.guessTranscriptPath(
                    sessionID: payload.sessionID,
                    cwd: payload.cwd
                )
            if let transcriptPath {
                mergedMetadata.customTitle = ClaudeTranscriptDiscovery.sessionTitle(inTranscriptAt: transcriptPath)
            }
        }

        guard !mergedMetadata.isEmpty else {
            return
        }

        guard existingSession.claudeMetadata != mergedMetadata else {
            return
        }

        emit(
            .claudeSessionMetadataUpdated(
                ClaudeSessionMetadataUpdated(
                    sessionID: payload.sessionID,
                    claudeMetadata: mergedMetadata,
                    timestamp: .now
                )
            )
        )
    }

    private func mergedCodexMetadata(
        existing: CodexSessionMetadata?,
        update: CodexSessionMetadata,
        hookEventName: CodexHookEventName
    ) -> CodexSessionMetadata {
        CodexSessionMetadata(
            transcriptPath: update.transcriptPath ?? existing?.transcriptPath,
            initialUserPrompt: existing?.initialUserPrompt ?? update.initialUserPrompt ?? update.lastUserPrompt,
            lastUserPrompt: update.lastUserPrompt ?? existing?.lastUserPrompt,
            lastAssistantMessage: update.lastAssistantMessage ?? existing?.lastAssistantMessage,
            currentTool: mergedCurrentTool(
                existing: existing?.currentTool,
                update: update.currentTool,
                hookEventName: hookEventName
            ),
            currentCommandPreview: mergedCurrentCommandPreview(
                existing: existing?.currentCommandPreview,
                update: update.currentCommandPreview,
                hookEventName: hookEventName
            )
        )
    }

    private func mergedCurrentTool(
        existing: String?,
        update: String?,
        hookEventName: CodexHookEventName
    ) -> String? {
        if let update {
            return update
        }

        switch hookEventName {
        case .userPromptSubmit, .postToolUse, .stop:
            return nil
        case .sessionStart, .preToolUse:
            return existing
        }
    }

    private func mergedClaudeMetadata(
        existing: ClaudeSessionMetadata?,
        update: ClaudeSessionMetadata,
        hookEventName: ClaudeHookEventName
    ) -> ClaudeSessionMetadata {
        ClaudeSessionMetadata(
            transcriptPath: update.transcriptPath ?? existing?.transcriptPath,
            initialUserPrompt: existing?.initialUserPrompt ?? update.initialUserPrompt ?? update.lastUserPrompt,
            lastUserPrompt: update.lastUserPrompt ?? existing?.lastUserPrompt,
            lastAssistantMessage: update.lastAssistantMessage ?? existing?.lastAssistantMessage,
            currentTool: mergedClaudeCurrentTool(
                existing: existing?.currentTool,
                update: update.currentTool,
                hookEventName: hookEventName
            ),
            currentToolInputPreview: mergedClaudeCurrentToolInputPreview(
                existing: existing?.currentToolInputPreview,
                update: update.currentToolInputPreview,
                hookEventName: hookEventName
            ),
            model: update.model ?? existing?.model,
            startupSource: update.startupSource ?? existing?.startupSource,
            permissionMode: update.permissionMode ?? existing?.permissionMode,
            agentID: update.agentID ?? existing?.agentID,
            agentType: update.agentType ?? existing?.agentType,
            worktreeBranch: update.worktreeBranch ?? existing?.worktreeBranch,
            customTitle: update.customTitle ?? existing?.customTitle,
            activeSubagents: existing?.activeSubagents ?? [],
            activeTasks: existing?.activeTasks ?? []
        )
    }

    private func addSubagent(_ subagent: ClaudeSubagentInfo, toSession sessionID: String) {
        guard var metadata = localState.session(id: sessionID)?.claudeMetadata else {
            return
        }

        metadata.activeSubagents.removeAll { $0.agentID == subagent.agentID }
        metadata.activeSubagents.append(subagent)

        emit(
            .claudeSessionMetadataUpdated(
                ClaudeSessionMetadataUpdated(
                    sessionID: sessionID,
                    claudeMetadata: metadata,
                    timestamp: .now
                )
            )
        )
    }

    private func removeSubagent(agentID: String, fromSession sessionID: String) {
        guard var metadata = localState.session(id: sessionID)?.claudeMetadata else {
            return
        }

        metadata.activeSubagents.removeAll { $0.agentID == agentID }

        emit(
            .claudeSessionMetadataUpdated(
                ClaudeSessionMetadataUpdated(
                    sessionID: sessionID,
                    claudeMetadata: metadata,
                    timestamp: .now
                )
            )
        )
    }

    private func updateTask(
        from input: [String: ClaudeHookJSONValue],
        toolName: String,
        sessionID: String
    ) {
        guard var metadata = localState.session(id: sessionID)?.claudeMetadata else {
            return
        }

        if toolName == "TaskCreate" {
            guard case let .string(title) = input["subject"] ?? input["description"] else { return }
            let id = (input["id"]).flatMap { if case let .string(s) = $0 { s } else { nil } }
                ?? UUID().uuidString
            let statusStr = (input["status"]).flatMap { if case let .string(s) = $0 { s } else { nil } }
            let status = statusStr.flatMap { ClaudeTaskInfo.Status(rawValue: $0) } ?? .pending
            metadata.activeTasks.append(ClaudeTaskInfo(id: id, title: title, status: status))
        } else if toolName == "TaskUpdate" {
            guard case let .string(taskId) = input["id"] else { return }
            if let idx = metadata.activeTasks.firstIndex(where: { $0.id == taskId }) {
                if let statusStr = (input["status"]).flatMap({ if case let .string(s) = $0 { s } else { nil } }),
                   let status = ClaudeTaskInfo.Status(rawValue: statusStr) {
                    metadata.activeTasks[idx].status = status
                }
            }
        }

        emit(
            .claudeSessionMetadataUpdated(
                ClaudeSessionMetadataUpdated(
                    sessionID: sessionID,
                    claudeMetadata: metadata,
                    timestamp: .now
                )
            )
        )
    }

    private func mergedClaudeCurrentTool(
        existing: String?,
        update: String?,
        hookEventName: ClaudeHookEventName
    ) -> String? {
        if let update {
            return update
        }

        switch hookEventName {
        case .postToolUse, .postToolUseFailure, .permissionDenied, .stop, .stopFailure, .sessionEnd:
            return nil
        case .sessionStart, .userPromptSubmit, .preToolUse, .permissionRequest, .notification, .subagentStart, .subagentStop, .preCompact:
            return existing
        }
    }

    private func mergedClaudeCurrentToolInputPreview(
        existing: String?,
        update: String?,
        hookEventName: ClaudeHookEventName
    ) -> String? {
        if let update {
            return update
        }

        switch hookEventName {
        case .postToolUse, .postToolUseFailure, .permissionDenied, .stop, .stopFailure, .sessionEnd:
            return nil
        case .sessionStart, .userPromptSubmit, .preToolUse, .permissionRequest, .notification, .subagentStart, .subagentStop, .preCompact:
            return existing
        }
    }

    private func mergedCurrentCommandPreview(
        existing: String?,
        update: String?,
        hookEventName: CodexHookEventName
    ) -> String? {
        if let update {
            return update
        }

        switch hookEventName {
        case .userPromptSubmit, .postToolUse, .stop:
            return nil
        case .sessionStart, .preToolUse:
            return existing
        }
    }

    private func resolvePendingApproval(sessionID: String, approved: Bool) {
        guard let pendingApproval = pendingApprovals.removeValue(forKey: sessionID) else {
            return
        }

        let response: BridgeResponse
        if approved {
            response = .acknowledged
        } else {
            response = .codexHookDirective(.deny(reason: "Permission denied in Open Island."))
        }

        send(.response(response), to: pendingApproval.clientID)
    }

    private func resolvePendingClaudeInteraction(
        sessionID: String,
        resolution: PermissionResolution
    ) {
        guard let pendingInteraction = pendingClaudeInteractions.removeValue(forKey: sessionID) else {
            return
        }

        let directive: ClaudeHookDirective
        let summary: String
        let phase: SessionPhase

        switch (pendingInteraction.kind, resolution) {
        case let (.permission(payload), .allowOnce(updatedInput, updatedPermissions)):
            let finalInput = updatedInput ?? payload.toolInput
            directive = .permissionRequest(
                .allow(updatedInput: finalInput, updatedPermissions: updatedPermissions)
            )
            summary = payload.toolName.map { "Permission approved for \($0)." } ?? "Permission approved."
            phase = .running

        case let (.permission(_), .deny(message, interrupt)):
            directive = .permissionRequest(
                .deny(message: message ?? "Permission denied in Open Island.", interrupt: interrupt)
            )
            summary = message ?? "Permission denied in Open Island."
            phase = .completed

        case let (.question(payload, _), .allowOnce(updatedInput, updatedPermissions)):
            let finalInput = updatedInput ?? payload.toolInput
            directive = .permissionRequest(
                .allow(updatedInput: finalInput, updatedPermissions: updatedPermissions)
            )
            summary = "Claude's questions were answered."
            phase = .running

        case let (.question(_, _), .deny(message, interrupt)):
            directive = .permissionRequest(
                .deny(message: message ?? "Declined to answer Claude's questions.", interrupt: interrupt)
            )
            summary = message ?? "Declined to answer Claude's questions."
            phase = .completed
        }

        emit(
            phase == .completed
                ? .sessionCompleted(
                    SessionCompleted(
                        sessionID: sessionID,
                        summary: summary,
                        timestamp: .now
                    )
                )
                : .activityUpdated(
                    SessionActivityUpdated(
                        sessionID: sessionID,
                        summary: summary,
                        phase: phase,
                        timestamp: .now
                    )
                )
        )

        send(.response(.claudeHookDirective(directive)), to: pendingInteraction.clientID)
    }

    private func resolvePendingClaudeQuestion(
        sessionID: String,
        response: QuestionPromptResponse
    ) {
        guard let pendingInteraction = pendingClaudeInteractions.removeValue(forKey: sessionID) else {
            return
        }

        guard case let .question(payload, prompt) = pendingInteraction.kind else {
            return
        }

        let updatedInput = mergedClaudeQuestionInput(
            payload: payload,
            prompt: prompt,
            response: response
        )
        let summary = response.displaySummary.isEmpty
            ? "Answered Claude's questions."
            : "Answered: \(response.displaySummary)"

        emit(
            .activityUpdated(
                SessionActivityUpdated(
                    sessionID: sessionID,
                    summary: summary,
                    phase: .running,
                    timestamp: .now
                )
            )
        )

        send(
            .response(
                .claudeHookDirective(
                    .permissionRequest(.allow(updatedInput: updatedInput))
                )
            ),
            to: pendingInteraction.clientID
        )
    }

    private func claudeToolUseID(for payload: ClaudeHookPayload) -> String? {
        payload.toolUseID ?? pendingClaudeToolContexts[payload.permissionCorrelationKey]?.toolUseID
    }

    private func mergedClaudeQuestionInput(
        payload: ClaudeHookPayload,
        prompt: QuestionPrompt,
        response: QuestionPromptResponse
    ) -> ClaudeHookJSONValue {
        let fallbackQuestion = prompt.questions.first?.question

        var answers = response.answers
        if answers.isEmpty,
           let rawAnswer = response.rawAnswer,
           !rawAnswer.isEmpty,
           let fallbackQuestion {
            answers[fallbackQuestion] = rawAnswer
        }

        var annotationsObject: [String: ClaudeHookJSONValue] = [:]
        for key in response.annotations.keys.sorted() {
            guard let annotation = response.annotations[key] else {
                continue
            }

            var object: [String: ClaudeHookJSONValue] = [:]
            if let preview = annotation.preview, !preview.isEmpty {
                object["preview"] = .string(preview)
            }
            if let notes = annotation.notes, !notes.isEmpty {
                object["notes"] = .string(notes)
            }
            if !object.isEmpty {
                annotationsObject[key] = .object(object)
            }
        }

        guard case let .object(existingObject) = payload.toolInput else {
            return .object([
                "answers": .object(answers.mapValues { .string($0) }),
                "annotations": .object(annotationsObject),
            ])
        }

        var updatedObject = existingObject
        updatedObject["answers"] = .object(answers.mapValues { .string($0) })
        if !annotationsObject.isEmpty {
            updatedObject["annotations"] = .object(annotationsObject)
        }

        return .object(updatedObject)
    }

    private func emit(_ event: AgentEvent) {
        localState.apply(event)
        broadcast([.event(event)])
    }

    private func hasSession(id: String) -> Bool {
        localState.session(id: id) != nil || localState.session(id: id) != nil
    }

    private func send(_ envelope: BridgeEnvelope, to clientID: UUID) {
        guard let client = clients[clientID] else {
            return
        }

        do {
            let data = try BridgeCodec.encodeLine(envelope)
            try writeAll(data, to: client.fileDescriptor)
        } catch {
            removeClient(clientID)
        }
    }

    private func broadcast(_ envelopes: [BridgeEnvelope]) {
        let clientIDs = Array(clients.keys)

        for clientID in clientIDs {
            for envelope in envelopes {
                send(envelope, to: clientID)
            }
        }
    }

    private func removeClient(_ clientID: UUID) {
        guard let client = clients.removeValue(forKey: clientID) else {
            return
        }

        let pendingSessionIDs = pendingApprovals.compactMap { entry -> String? in
            let (sessionID, pendingApproval) = entry
            return pendingApproval.clientID == clientID ? sessionID : nil
        }

        for sessionID in pendingSessionIDs {
            pendingApprovals.removeValue(forKey: sessionID)
        }

        let pendingClaudeSessionIDs = pendingClaudeInteractions.compactMap { entry -> String? in
            let (sessionID, pendingInteraction) = entry
            return pendingInteraction.clientID == clientID ? sessionID : nil
        }

        for sessionID in pendingClaudeSessionIDs {
            pendingClaudeInteractions.removeValue(forKey: sessionID)
            emit(
                .actionableStateResolved(
                    ActionableStateResolved(
                        sessionID: sessionID,
                        summary: "Hook process disconnected.",
                        timestamp: .now
                    )
                )
            )
        }

        let pendingOpenCodeSessionIDs = pendingOpenCodeInteractions.compactMap { entry -> String? in
            let (sessionID, pendingInteraction) = entry
            return pendingInteraction.clientID == clientID ? sessionID : nil
        }

        for sessionID in pendingOpenCodeSessionIDs {
            pendingOpenCodeInteractions.removeValue(forKey: sessionID)
            emit(
                .actionableStateResolved(
                    ActionableStateResolved(
                        sessionID: sessionID,
                        summary: "Plugin process disconnected.",
                        timestamp: .now
                    )
                )
            )
        }

        client.readSource.cancel()
    }
}
