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
        let value = try decoder.singleValueContainer().decode(String.self)
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
    case unknown(method: String)
}

// MARK: - JSON-RPC transport

/// A lightweight JSON-RPC client that communicates with Codex app-server
/// over a stdio-based `Process`.  Uses newline-delimited JSON messages
/// (one JSON object per line, no Content-Length framing).
public final class CodexAppServerClient: @unchecked Sendable {
    private let codexPath: String
    private var process: Process?
    private var stdin: FileHandle?
    private var readBuffer = Data()
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
        struct Result: Decodable { let threads: [CodexThread] }
        let data = try await sendRequest(method: "thread/loaded/list", params: Params())
        let result = try JSONDecoder().decode(Result.self, from: data)
        return result.threads
    }

    /// List all threads (including not-loaded) from the app-server.
    public func listThreads(limit: Int? = nil) async throws -> [CodexThread] {
        struct Params: Encodable { let limit: Int? }
        struct Result: Decodable { let threads: [CodexThread] }
        let data = try await sendRequest(method: "thread/list", params: Params(limit: limit))
        let result = try JSONDecoder().decode(Result.self, from: data)
        return result.threads
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

    // MARK: - Incoming data

    private func handleIncomingData(_ data: Data) {
        readBuffer.append(data)

        while let newlineIndex = readBuffer.firstIndex(of: UInt8(ascii: "\n")) {
            let lineData = readBuffer[readBuffer.startIndex..<newlineIndex]
            readBuffer = Data(readBuffer[readBuffer.index(after: newlineIndex)...])

            guard !lineData.isEmpty,
                  let json = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any]
            else { continue }

            if let id = json["id"] as? Int {
                handleResponse(id: id, json: json)
            } else if let method = json["method"] as? String {
                handleNotification(method: method, json: json)
            }
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
        default:
            notification = .unknown(method: method)
        }

        onNotification?(notification)
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
