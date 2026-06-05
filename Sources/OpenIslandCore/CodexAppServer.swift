import Foundation

// MARK: - Protocol models

/// A Codex thread as reported by the app-server JSON-RPC protocol.
public struct CodexThread: Codable, Sendable {
    public let id: String
    public let cwd: String
    public let name: String?
    public let preview: String
    public let modelProvider: String
    public let createdAt: Int
    public let updatedAt: Int
    public let ephemeral: Bool
    public let path: String?
    public let status: CodexThreadStatus
    public let source: CodexThreadSource?

    /// Turns are only populated on `thread/resume` and `thread/fork`
    /// responses, empty otherwise.
    public let turns: [CodexTurn]?
}

public enum CodexThreadStatusType: String, Codable, Sendable {
    case notLoaded
    case idle
    case systemError
    case active
}

public struct CodexThreadStatus: Codable, Sendable {
    public let type: CodexThreadStatusType
    /// Only present when `type == .active`.
    public let activeFlags: [String]?

    public var isWaitingOnApproval: Bool {
        activeFlags?.contains("waitingOnApproval") == true
    }

    public var isWaitingOnUserInput: Bool {
        activeFlags?.contains("waitingOnUserInput") == true
    }
}

public enum CodexThreadSource: String, Codable, Sendable {
    case cli
    case vscode
    case appServer = "app-server"
    case codexExec = "codex-exec"
    case unknown

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        guard let value = try? container.decode(String.self) else {
            self = .unknown
            return
        }
        self = CodexThreadSource(rawValue: value) ?? .unknown
    }
}

public struct CodexTurn: Codable, Sendable {
    public let id: String
    public let status: CodexTurnStatus
}

public enum CodexTurnStatus: String, Codable, Sendable {
    case completed
    case interrupted
    case failed
    case inProgress
}

// MARK: - Notifications

public enum CodexAppServerNotification: Sendable {
    case threadStarted(thread: CodexThread)
    case threadStatusChanged(threadId: String, status: CodexThreadStatus)
    case threadClosed(threadId: String)
    case threadNameUpdated(threadId: String, name: String?)
    case turnStarted(threadId: String, turn: CodexTurn)
    case turnCompleted(threadId: String, turn: CodexTurn)
    case itemStarted(CodexAppServerItemActivity)
    case itemCompleted(CodexAppServerItemActivity)
    case itemOutputDelta(CodexAppServerItemActivity)
    case itemPatchUpdated(CodexAppServerItemActivity)
    case agentMessageDelta(CodexAppServerAgentMessageDelta)
    case rawResponseItemCompleted(CodexAppServerRawResponseItem)
    case approvalRequested(CodexAppServerApprovalRequest)
    case serverRequestResolved(threadId: String, requestId: Int?)
    case accountRateLimitsUpdated(CodexUsageSnapshot)
    case unknown(method: String)
}

public struct CodexAppServerItemActivity: Equatable, Sendable {
    public var threadID: String
    public var turnID: String?
    public var itemID: String?
    public var toolName: String
    public var preview: String?

    public init(
        threadID: String,
        turnID: String? = nil,
        itemID: String? = nil,
        toolName: String,
        preview: String? = nil
    ) {
        self.threadID = threadID
        self.turnID = turnID
        self.itemID = itemID
        self.toolName = toolName
        self.preview = preview
    }
}

public struct CodexAppServerAgentMessageDelta: Equatable, Sendable {
    public var threadID: String
    public var turnID: String?
    public var itemID: String?
    public var text: String

    public init(
        threadID: String,
        turnID: String? = nil,
        itemID: String? = nil,
        text: String
    ) {
        self.threadID = threadID
        self.turnID = turnID
        self.itemID = itemID
        self.text = text
    }
}

public struct CodexAppServerRawResponseItem: Equatable, Sendable {
    public var threadID: String
    public var turnID: String?
    public var itemID: String?
    public var toolName: String?
    public var preview: String?
    public var assistantText: String?

    public init(
        threadID: String,
        turnID: String? = nil,
        itemID: String? = nil,
        toolName: String? = nil,
        preview: String? = nil,
        assistantText: String? = nil
    ) {
        self.threadID = threadID
        self.turnID = turnID
        self.itemID = itemID
        self.toolName = toolName
        self.preview = preview
        self.assistantText = assistantText
    }
}

public enum CodexAppServerApprovalKind: Equatable, Sendable {
    case commandExecution
    case fileChange
    case permissions
}

public struct CodexAppServerApprovalRequest: Equatable, Sendable {
    public var requestID: Int
    public var kind: CodexAppServerApprovalKind
    public var threadID: String
    public var turnID: String?
    public var itemID: String?
    public var approvalID: String?
    public var reason: String?
    public var command: [String]
    public var cwd: String?
    public var permissions: CodexHookJSONValue?

    public init(
        requestID: Int,
        kind: CodexAppServerApprovalKind,
        threadID: String,
        turnID: String? = nil,
        itemID: String? = nil,
        approvalID: String? = nil,
        reason: String? = nil,
        command: [String] = [],
        cwd: String? = nil,
        permissions: CodexHookJSONValue? = nil
    ) {
        self.requestID = requestID
        self.kind = kind
        self.threadID = threadID
        self.turnID = turnID
        self.itemID = itemID
        self.approvalID = approvalID
        self.reason = reason
        self.command = command
        self.cwd = cwd
        self.permissions = permissions
    }
}

// MARK: - JSON-RPC transport

/// A lightweight JSON-RPC client that communicates with Codex app-server
/// over a stdio-based `Process`.  Uses newline-delimited JSON messages
/// (one JSON object per line, no Content-Length framing).
public final class CodexAppServerClient: @unchecked Sendable {
    private let codexPath: String
    private var process: Process?
    /// Internal access so tests can inject a discard `Pipe` and drive
    /// the request path without launching a real codex subprocess.
    var stdin: FileHandle?
    /// Per-request timeout. App-server RPC calls (initialize,
    /// thread/list, …) normally complete in tens of milliseconds; a
    /// hang past 30 s means codex is wedged and we must release the
    /// caller rather than pin its `Task` forever.
    var requestTimeoutSeconds: TimeInterval = 30
    private var readBuffer = Data()

    /// Test-only accessor for asserting buffer state after `handleIncomingData`.
    var readBufferCountForTests: Int {
        readBuffer.count
    }
    private var pendingRequests: [Int: CheckedContinuation<Data, any Error>] = [:]
    private var nextRequestID = 1
    private let lock = NSLock()

    public var onNotification: (@Sendable (CodexAppServerNotification) -> Void)?

    public init(codexPath: String = "/Applications/Codex.app/Contents/Resources/codex") {
        self.codexPath = codexPath
    }

    public var isRunning: Bool {
        process?.isRunning == true
    }

    // MARK: - Lifecycle

    /// Launch the app-server subprocess and perform the `initialize` handshake.
    public func start() async throws {
        guard !isRunning else { return }

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: codexPath)
        proc.arguments = ["app-server", "--listen", "stdio://"]

        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        proc.standardInput = stdinPipe
        proc.standardOutput = stdoutPipe
        proc.standardError = stderrPipe

        self.stdin = stdinPipe.fileHandleForWriting
        self.process = proc

        // Read stdout in a background thread.
        stdoutPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            self?.handleIncomingData(data)
        }

        // Drain stderr so a full pipe can't block the child process.
        stderrPipe.fileHandleForReading.readabilityHandler = { handle in
            _ = handle.availableData
        }

        try proc.run()

        // Send initialize request.
        struct InitializeParams: Encodable {
            struct ClientInfo: Encodable {
                let name: String
                let version: String
            }
            let clientInfo: ClientInfo
        }
        _ = try await sendRequest(
            method: "initialize",
            params: InitializeParams(clientInfo: .init(name: "OpenIsland", version: "1.0.0"))
        )
    }

    /// Stop the app-server subprocess.
    public func stop() {
        process?.terminate()
        process = nil
        stdin = nil
        lock.lock()
        let pending = pendingRequests
        pendingRequests.removeAll()
        lock.unlock()
        for (_, continuation) in pending {
            continuation.resume(throwing: CodexAppServerError.disconnected)
        }
    }

    // MARK: - Requests

    /// List currently loaded threads from the app-server.
    public func listLoadedThreads() async throws -> [CodexThread] {
        struct Params: Encodable {}
        struct Result: Decodable {
            let threads: [CodexThread]?
            let data: [String]?
        }
        let data = try await sendRequest(method: "thread/loaded/list", params: Params())
        let result = try JSONDecoder().decode(Result.self, from: data)
        if let threads = result.threads {
            return threads
        }

        var threads: [CodexThread] = []
        for threadID in result.data ?? [] {
            if let thread = try? await readThread(threadID: threadID) {
                threads.append(thread)
            }
        }
        return threads
    }

    /// List all threads (including not-loaded) from the app-server.
    public func listThreads(limit: Int? = nil) async throws -> [CodexThread] {
        struct Params: Encodable { let limit: Int? }
        struct Result: Decodable {
            let threads: [CodexThread]?
            let data: [CodexThread]?
        }
        let data = try await sendRequest(method: "thread/list", params: Params(limit: limit))
        let result = try JSONDecoder().decode(Result.self, from: data)
        return result.threads ?? result.data ?? []
    }

    /// Read a single thread by id from the app-server.
    public func readThread(threadID: String) async throws -> CodexThread {
        struct Params: Encodable {
            let threadId: String
            let includeTurns: Bool
        }
        struct Result: Decodable { let thread: CodexThread }
        let data = try await sendRequest(
            method: "thread/read",
            params: Params(threadId: threadID, includeTurns: false)
        )
        let result = try JSONDecoder().decode(Result.self, from: data)
        return result.thread
    }

    /// Read account-level Codex rate limits from the app-server. This is the
    /// same authoritative source Codex.app uses, and is preferred over passive
    /// JSONL `token_count.rate_limits` observations.
    public func readAccountRateLimits() async throws -> CodexUsageSnapshot? {
        struct Params: Encodable {}
        let data = try await sendRequest(method: "account/rateLimits/read", params: Params())
        let result = try JSONDecoder().decode(AccountRateLimitsReadResult.self, from: data)
        return result.rateLimits?.usageSnapshot(source: "codex-app-server")
    }

    public func resolveApprovalRequest(
        _ request: CodexAppServerApprovalRequest,
        resolution: PermissionResolution
    ) throws {
        switch request.kind {
        case .commandExecution, .fileChange:
            let decision = Self.approvalDecision(for: resolution)
            try sendResponse(id: request.requestID, result: ["decision": decision])

        case .permissions:
            let permissions = resolution.isApproved ? request.permissions?.jsonObject : [:]
            try sendResponse(
                id: request.requestID,
                result: [
                    "permissions": permissions ?? [:],
                ]
            )
        }
    }

    // MARK: - JSON-RPC transport

    /// Returns raw JSON `result` bytes from the response.
    @discardableResult
    private func sendRequest<P: Encodable>(
        method: String,
        params: P
    ) async throws -> Data {
        guard let stdin else {
            throw CodexAppServerError.notConnected
        }

        let requestID: Int = lock.withLock {
            let id = nextRequestID
            nextRequestID += 1
            return id
        }

        // Encode params via JSONEncoder, then decode back to Any for
        // JSONSerialization so we can embed it in the JSON-RPC envelope.
        let paramsData = try JSONEncoder().encode(params)
        let paramsObj = try JSONSerialization.jsonObject(with: paramsData)
        let envelope: [String: Any] = [
            "jsonrpc": "2.0",
            "id": requestID,
            "method": method,
            "params": paramsObj,
        ]
        var line = try JSONSerialization.data(withJSONObject: envelope)
        line.append(contentsOf: [UInt8(ascii: "\n")])

        // Race the response continuation against a timeout task.
        // Without this, a wedged app-server (no disconnect, no reply)
        // would leave the `await` suspended forever — pinning the
        // continuation, the caller's Task, and any memory referenced
        // by either.
        let timeoutSeconds = requestTimeoutSeconds
        let timeoutTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(timeoutSeconds))
            guard !Task.isCancelled else { return }
            self?.failPendingRequest(id: requestID, with: .timeout)
        }
        defer { timeoutTask.cancel() }

        // Register the continuation BEFORE writing — a fast app-server can
        // reply between write() and registration, which would cause
        // handleResponse to drop the reply and hang the await forever.
        return try await withCheckedThrowingContinuation { continuation in
            lock.lock()
            pendingRequests[requestID] = continuation
            lock.unlock()
            stdin.write(line)
        }
    }

    /// Atomically removes a pending request and resumes its
    /// continuation with the given error. Safe to call concurrently
    /// with `handleResponse`: whichever side wins the dictionary
    /// removal performs the resume; the other side gets `nil` and
    /// no-ops.
    private func failPendingRequest(id: Int, with error: CodexAppServerError) {
        lock.lock()
        let continuation = pendingRequests.removeValue(forKey: id)
        lock.unlock()
        continuation?.resume(throwing: error)
    }

    private func sendResponse(id: Int, result: [String: Any]) throws {
        guard let stdin else {
            throw CodexAppServerError.notConnected
        }

        let envelope: [String: Any] = [
            "jsonrpc": "2.0",
            "id": id,
            "result": result,
        ]
        var line = try JSONSerialization.data(withJSONObject: envelope)
        line.append(contentsOf: [UInt8(ascii: "\n")])
        stdin.write(line)
    }

    private static func approvalDecision(for resolution: PermissionResolution) -> String {
        switch resolution {
        case .allowOnce:
            "accept"
        case .deny:
            "decline"
        }
    }

    // MARK: - Incoming data

    /// Maximum bytes we will accumulate without seeing a newline. Codex
    /// app-server RPC messages are line-delimited JSON; lines past this
    /// size indicate either a malformed stream or a runaway result. We
    /// drop the buffer rather than let it grow without bound (would OOM
    /// if the producer never sends `\n`).
    static let maxLineByteCount = 8 * 1_024 * 1_024

    func handleIncomingData(_ data: Data) {
        readBuffer.append(data)

        while let newlineIndex = readBuffer.firstIndex(of: UInt8(ascii: "\n")) {
            // Slice the line out, then trim the consumed prefix in place
            // with `removeSubrange`. The previous `readBuffer = Data(...)`
            // re-allocated and copied the whole tail on every line, so a
            // burst of N lines from codex was O(N²) — measurable when a
            // tool result emits hundreds of progress events back-to-back.
            let lineData = readBuffer[readBuffer.startIndex..<newlineIndex]
            let consumeUpTo = readBuffer.index(after: newlineIndex)
            defer { readBuffer.removeSubrange(readBuffer.startIndex..<consumeUpTo) }

            guard !lineData.isEmpty,
                  let json = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any]
            else { continue }

            if let id = json["id"] as? Int,
               json["method"] is String {
                handleServerRequest(id: id, json: json)
            } else if let id = json["id"] as? Int {
                handleResponse(id: id, json: json)
            } else if let method = json["method"] as? String {
                handleNotification(method: method, json: json)
            }
        }

        if readBuffer.count > Self.maxLineByteCount {
            // Drop the runaway prefix; keep the connection up so the next
            // well-framed line still has a chance. The peer will likely
            // emit a protocol error which propagates as a normal `rpcError`.
            readBuffer.removeAll(keepingCapacity: false)
        }
    }

    private func handleResponse(id: Int, json: [String: Any]) {
        lock.lock()
        let continuation = pendingRequests.removeValue(forKey: id)
        lock.unlock()

        if let error = json["error"] as? [String: Any] {
            let message = error["message"] as? String ?? "Unknown error"
            continuation?.resume(throwing: CodexAppServerError.rpcError(message))
        } else {
            let result = json["result"] ?? [String: Any]()
            let data = (try? JSONSerialization.data(withJSONObject: result)) ?? Data()
            continuation?.resume(returning: data)
        }
    }

    private func handleServerRequest(id: Int, json: [String: Any]) {
        guard let method = json["method"] as? String,
              let params = json["params"] as? [String: Any] else {
            return
        }

        switch method {
        case "item/commandExecution/requestApproval":
            guard let request = Self.commandExecutionApprovalRequest(id: id, params: params) else { return }
            onNotification?(.approvalRequested(request))

        case "item/fileChange/requestApproval":
            guard let request = Self.fileChangeApprovalRequest(id: id, params: params) else { return }
            onNotification?(.approvalRequested(request))

        case "item/permissions/requestApproval":
            guard let request = Self.permissionsApprovalRequest(id: id, params: params) else { return }
            onNotification?(.approvalRequested(request))

        default:
            onNotification?(.unknown(method: method))
        }
    }

    private func handleNotification(method: String, json: [String: Any]) {
        guard let params = json["params"] else { return }
        let paramsData = (try? JSONSerialization.data(withJSONObject: params)) ?? Data()
        let decoder = JSONDecoder()

        let notification: CodexAppServerNotification
        switch method {
        case "thread/started":
            guard let n = try? decoder.decode(ThreadStartedParams.self, from: paramsData) else { return }
            notification = .threadStarted(thread: n.thread)
        case "thread/status/changed":
            guard let n = try? decoder.decode(ThreadStatusChangedParams.self, from: paramsData) else { return }
            notification = .threadStatusChanged(threadId: n.threadId, status: n.status)
        case "thread/closed":
            guard let n = try? decoder.decode(ThreadClosedParams.self, from: paramsData) else { return }
            notification = .threadClosed(threadId: n.threadId)
        case "thread/name/updated":
            guard let n = try? decoder.decode(ThreadNameUpdatedParams.self, from: paramsData) else { return }
            notification = .threadNameUpdated(threadId: n.threadId, name: n.name)
        case "turn/started":
            guard let n = try? decoder.decode(TurnNotificationParams.self, from: paramsData) else { return }
            notification = .turnStarted(threadId: n.threadId, turn: n.turn)
        case "turn/completed":
            guard let n = try? decoder.decode(TurnNotificationParams.self, from: paramsData) else { return }
            notification = .turnCompleted(threadId: n.threadId, turn: n.turn)
        case "item/started":
            guard let activity = Self.itemActivity(from: params) else { return }
            notification = .itemStarted(activity)
        case "item/completed":
            guard let activity = Self.itemActivity(from: params) else { return }
            notification = .itemCompleted(activity)
        case "item/commandExecution/outputDelta":
            guard let activity = Self.commandOutputActivity(from: params) else { return }
            notification = .itemOutputDelta(activity)
        case "item/fileChange/patchUpdated":
            guard let activity = Self.fileChangePatchActivity(from: params) else { return }
            notification = .itemPatchUpdated(activity)
        case "item/agentMessage/delta":
            guard let delta = Self.agentMessageDelta(from: params) else { return }
            notification = .agentMessageDelta(delta)
        case "rawResponseItem/completed":
            guard let item = Self.rawResponseItem(from: params) else { return }
            notification = .rawResponseItemCompleted(item)
        case "serverRequest/resolved":
            guard let n = try? decoder.decode(ServerRequestResolvedParams.self, from: paramsData) else { return }
            notification = .serverRequestResolved(threadId: n.threadId, requestId: n.requestId)
        case "account/rateLimits/updated":
            guard let n = try? decoder.decode(AccountRateLimitsUpdatedParams.self, from: paramsData),
                  let snapshot = n.rateLimits.usageSnapshot(source: "codex-app-server-notification") else { return }
            notification = .accountRateLimitsUpdated(snapshot)
        default:
            notification = .unknown(method: method)
        }

        onNotification?(notification)
    }

    private static func commandExecutionApprovalRequest(
        id: Int,
        params: [String: Any]
    ) -> CodexAppServerApprovalRequest? {
        guard let threadID = params["threadId"] as? String else { return nil }
        return CodexAppServerApprovalRequest(
            requestID: id,
            kind: .commandExecution,
            threadID: threadID,
            turnID: params["turnId"] as? String,
            itemID: params["itemId"] as? String,
            approvalID: params["approvalId"] as? String,
            reason: params["reason"] as? String,
            command: commandParts(from: params["command"]),
            cwd: params["cwd"] as? String
        )
    }

    private static func fileChangeApprovalRequest(
        id: Int,
        params: [String: Any]
    ) -> CodexAppServerApprovalRequest? {
        guard let threadID = params["threadId"] as? String else { return nil }
        return CodexAppServerApprovalRequest(
            requestID: id,
            kind: .fileChange,
            threadID: threadID,
            turnID: params["turnId"] as? String,
            itemID: params["itemId"] as? String,
            approvalID: params["approvalId"] as? String,
            reason: params["reason"] as? String,
            cwd: params["cwd"] as? String
        )
    }

    private static func permissionsApprovalRequest(
        id: Int,
        params: [String: Any]
    ) -> CodexAppServerApprovalRequest? {
        guard let threadID = params["threadId"] as? String else { return nil }
        let permissions = params["permissions"].flatMap(CodexHookJSONValue.init(jsonObject:))
        return CodexAppServerApprovalRequest(
            requestID: id,
            kind: .permissions,
            threadID: threadID,
            turnID: params["turnId"] as? String,
            itemID: params["itemId"] as? String,
            reason: params["reason"] as? String,
            cwd: params["cwd"] as? String,
            permissions: permissions
        )
    }

    private static func itemActivity(from params: Any) -> CodexAppServerItemActivity? {
        guard let params = params as? [String: Any],
              let threadID = params["threadId"] as? String else {
            return nil
        }

        let item = params["item"] as? [String: Any] ?? params
        let rawType = item["type"] as? String
        let toolName: String
        let preview: String?

        switch rawType {
        case "commandExecution", "command_execution", "local_shell_call":
            toolName = "exec_command"
            preview = commandPreview(from: item["command"] ?? item["cmd"])
        case "fileChange", "file_change":
            toolName = "apply_patch"
            preview = fileChangePreview(from: item)
        case "dynamicToolCall", "dynamic_tool_call", "mcpToolCall", "mcp_tool_call":
            toolName = [
                item["namespace"] as? String,
                item["tool"] as? String ?? item["name"] as? String,
            ]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: ".")
            preview = jsonPreview(from: item["arguments"] ?? item["input"])
        default:
            return nil
        }

        guard !toolName.isEmpty else { return nil }
        return CodexAppServerItemActivity(
            threadID: threadID,
            turnID: params["turnId"] as? String,
            itemID: item["id"] as? String ?? params["itemId"] as? String,
            toolName: toolName,
            preview: preview
        )
    }

    private static func commandOutputActivity(from params: Any) -> CodexAppServerItemActivity? {
        guard let params = params as? [String: Any],
              let threadID = params["threadId"] as? String else {
            return nil
        }

        return CodexAppServerItemActivity(
            threadID: threadID,
            turnID: params["turnId"] as? String,
            itemID: params["itemId"] as? String,
            toolName: "exec_command",
            preview: outputDeltaPreview(from: params)
        )
    }

    private static func fileChangePatchActivity(from params: Any) -> CodexAppServerItemActivity? {
        guard let params = params as? [String: Any],
              let threadID = params["threadId"] as? String else {
            return nil
        }

        return CodexAppServerItemActivity(
            threadID: threadID,
            turnID: params["turnId"] as? String,
            itemID: params["itemId"] as? String,
            toolName: "apply_patch",
            preview: fileChangePreview(from: params)
        )
    }

    private static func agentMessageDelta(from params: Any) -> CodexAppServerAgentMessageDelta? {
        guard let params = params as? [String: Any],
              let threadID = params["threadId"] as? String,
              let text = outputDeltaPreview(from: params) else {
            return nil
        }

        return CodexAppServerAgentMessageDelta(
            threadID: threadID,
            turnID: params["turnId"] as? String,
            itemID: params["itemId"] as? String,
            text: text
        )
    }

    private static func rawResponseItem(from params: Any) -> CodexAppServerRawResponseItem? {
        guard let params = params as? [String: Any],
              let threadID = params["threadId"] as? String,
              let item = params["item"] as? [String: Any],
              let type = item["type"] as? String else {
            return nil
        }

        let turnID = params["turnId"] as? String
        let itemID = item["id"] as? String ?? params["itemId"] as? String

        if type == "message",
           item["role"] as? String == "assistant",
           let text = responseMessageText(from: item, textType: "output_text") {
            return CodexAppServerRawResponseItem(
                threadID: threadID,
                turnID: turnID,
                itemID: itemID,
                assistantText: text
            )
        }

        if (type == "function_call" || type == "custom_tool_call"),
           let toolName = item["name"] as? String,
           !toolName.isEmpty {
            return CodexAppServerRawResponseItem(
                threadID: threadID,
                turnID: turnID,
                itemID: itemID,
                toolName: toolName,
                preview: rawResponseFunctionCallPreview(toolName: toolName, item: item)
            )
        }

        let activity = itemActivity(from: [
            "threadId": threadID,
            "turnId": turnID as Any,
            "item": item,
        ])
        guard let activity else {
            return CodexAppServerRawResponseItem(
                threadID: threadID,
                turnID: turnID,
                itemID: itemID
            )
        }

        return CodexAppServerRawResponseItem(
            threadID: threadID,
            turnID: activity.turnID,
            itemID: activity.itemID,
            toolName: activity.toolName,
            preview: activity.preview
        )
    }

    private static func commandParts(from value: Any?) -> [String] {
        if let values = value as? [String] {
            return values
        }
        if let value = value as? String {
            return [value]
        }
        return []
    }

    private static func commandPreview(from value: Any?) -> String? {
        let parts = commandParts(from: value)
        guard !parts.isEmpty else { return nil }
        if parts.count >= 3, parts[1] == "-lc" {
            return parts[2]
        }
        return parts.joined(separator: " ")
    }

    private static func fileChangePreview(from item: [String: Any]) -> String? {
        if let path = item["path"] as? String {
            return URL(fileURLWithPath: path).lastPathComponent
        }
        if let paths = item["paths"] as? [String], let first = paths.first {
            return URL(fileURLWithPath: first).lastPathComponent
        }
        if let files = item["files"] as? [String], let first = files.first {
            return URL(fileURLWithPath: first).lastPathComponent
        }
        if let changes = item["changes"] as? [String: Any], let first = changes.keys.sorted().first {
            return URL(fileURLWithPath: first).lastPathComponent
        }
        if let patch = item["patch"] as? String,
           let filename = patchPreviewFilename(from: patch) {
            return filename
        }
        return nil
    }

    private static func patchPreviewFilename(from patch: String) -> String? {
        for line in patch.split(whereSeparator: \.isNewline) {
            let text = line.trimmingCharacters(in: .whitespacesAndNewlines)
            for prefix in ["*** Update File: ", "*** Add File: ", "*** Delete File: ", "+++ b/"] {
                guard text.hasPrefix(prefix) else { continue }
                let path = String(text.dropFirst(prefix.count))
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                guard !path.isEmpty, path != "/dev/null" else { continue }
                return URL(fileURLWithPath: path).lastPathComponent
            }
        }
        return nil
    }

    private static func jsonPreview(from value: Any?) -> String? {
        guard let value,
              JSONSerialization.isValidJSONObject(value),
              let data = try? JSONSerialization.data(withJSONObject: value),
              let text = String(data: data, encoding: .utf8) else {
            return nil
        }
        return text.count > 160 ? String(text.prefix(157)) + "..." : text
    }

    private static func outputDeltaPreview(from params: [String: Any]) -> String? {
        let raw = params["delta"] as? String
            ?? params["output"] as? String
            ?? params["text"] as? String
            ?? params["chunk"] as? String
        guard let raw else { return nil }

        let compact = raw
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        guard !compact.isEmpty else { return nil }
        return compact.count > 160 ? String(compact.prefix(157)) + "..." : compact
    }

    private static func responseMessageText(from item: [String: Any], textType: String) -> String? {
        guard let content = item["content"] as? [[String: Any]] else {
            return nil
        }
        let text = content.compactMap { part -> String? in
            guard part["type"] as? String == textType,
                  let text = part["text"] as? String else {
                return nil
            }
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }.joined(separator: " ")

        guard !text.isEmpty else { return nil }
        return text.count > 160 ? String(text.prefix(157)) + "..." : text
    }

    private static func rawResponseFunctionCallPreview(toolName: String, item: [String: Any]) -> String? {
        guard let arguments = item["arguments"] else {
            return nil
        }
        if let object = arguments as? [String: Any] {
            switch toolName {
            case "exec_command":
                if let cmd = object["cmd"] as? String {
                    return cmd
                }
            case "write_stdin":
                if let chars = object["chars"] as? String {
                    return chars
                }
            case "view_image":
                if let path = object["path"] as? String {
                    return path
                }
            default:
                break
            }
        }
        return jsonPreview(from: arguments)
    }
}

// MARK: - Notification param structs (private)

private struct ThreadStartedParams: Codable {
    let thread: CodexThread
}

private struct ThreadStatusChangedParams: Codable {
    let threadId: String
    let status: CodexThreadStatus
}

private struct ThreadClosedParams: Codable {
    let threadId: String
}

private struct ThreadNameUpdatedParams: Codable {
    let threadId: String
    let name: String?
}

private struct TurnNotificationParams: Codable {
    let threadId: String
    let turn: CodexTurn
}

private struct ServerRequestResolvedParams: Codable {
    let threadId: String
    let requestId: Int?
}

private struct AccountRateLimitsReadResult: Decodable {
    let rateLimits: CodexAppServerRateLimitSnapshot?
}

private struct AccountRateLimitsUpdatedParams: Decodable {
    let rateLimits: CodexAppServerRateLimitSnapshot
}

private struct CodexAppServerRateLimitSnapshot: Decodable {
    let limitId: String?
    let limitName: String?
    let primary: CodexAppServerRateLimitWindow?
    let secondary: CodexAppServerRateLimitWindow?
    let planType: String?

    func usageSnapshot(source: String) -> CodexUsageSnapshot? {
        let normalizedLimitID = limitId?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard normalizedLimitID == nil || normalizedLimitID == "codex" else {
            return nil
        }

        let windows = [
            primary?.usageWindow(key: "primary"),
            secondary?.usageWindow(key: "secondary"),
        ].compactMap { $0 }
        guard !windows.isEmpty else {
            return nil
        }

        let snapshot = CodexUsageSnapshot(
            sourceFilePath: source,
            capturedAt: .now,
            planType: planType,
            limitID: limitId,
            windows: windows
        )
        return snapshot.isAllZeroPlaceholder ? nil : snapshot
    }
}

private struct CodexAppServerRateLimitWindow: Decodable {
    let usedPercent: Double
    let windowDurationMins: Int
    let resetsAt: Double?

    func usageWindow(key: String) -> CodexUsageWindow {
        CodexUsageWindow(
            key: key,
            label: CodexUsageLoader.windowLabel(forMinutes: windowDurationMins),
            usedPercentage: usedPercent,
            leftPercentage: max(0, 100 - usedPercent),
            windowMinutes: windowDurationMins,
            resetsAt: resetsAt.map(Date.init(timeIntervalSince1970:))
        )
    }
}

private extension CodexHookJSONValue {
    init?(jsonObject: Any) {
        switch jsonObject {
        case let value as String:
            self = .string(value)
        case let value as Bool:
            self = .boolean(value)
        case let value as Int:
            self = .number(Double(value))
        case let value as Double:
            self = .number(value)
        case let value as [Any]:
            self = .array(value.compactMap(CodexHookJSONValue.init(jsonObject:)))
        case let value as [String: Any]:
            var object: [String: CodexHookJSONValue] = [:]
            for (key, child) in value {
                guard let jsonValue = CodexHookJSONValue(jsonObject: child) else {
                    return nil
                }
                object[key] = jsonValue
            }
            self = .object(object)
        case _ as NSNull:
            self = .null
        default:
            return nil
        }
    }

    var jsonObject: Any {
        switch self {
        case let .string(value):
            value
        case let .number(value):
            value
        case let .boolean(value):
            value
        case let .object(value):
            value.mapValues(\.jsonObject)
        case let .array(value):
            value.map(\.jsonObject)
        case .null:
            NSNull()
        }
    }
}

// MARK: - Errors

public enum CodexAppServerError: Error, LocalizedError {
    case notConnected
    case disconnected
    case rpcError(String)
    case timeout

    public var errorDescription: String? {
        switch self {
        case .notConnected: "Codex app-server is not connected."
        case .disconnected: "Codex app-server connection was lost."
        case .rpcError(let msg): "Codex app-server error: \(msg)"
        case .timeout: "Codex app-server request timed out."
        }
    }
}
