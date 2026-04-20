import Foundation
import Network
import os

// MARK: - SSE Event Types

/// Events pushed to connected iPhone clients via Server-Sent Events.
public enum WatchSSEEvent: Sendable {
    case permissionRequested(WatchPermissionEvent)
    case questionAsked(WatchQuestionEvent)
    case sessionCompleted(WatchCompletionEvent)
    /// Sent when an actionable request (permission/question) has been resolved on the Mac side.
    case actionableStateResolved(WatchResolvedEvent)

    func sseString() -> String {
        switch self {
        case let .permissionRequested(event):
            let data = (try? JSONEncoder().encode(event)) ?? Data()
            return "event: permissionRequested\ndata: \(String(data: data, encoding: .utf8) ?? "{}")\n\n"
        case let .questionAsked(event):
            let data = (try? JSONEncoder().encode(event)) ?? Data()
            return "event: questionAsked\ndata: \(String(data: data, encoding: .utf8) ?? "{}")\n\n"
        case let .sessionCompleted(event):
            let data = (try? JSONEncoder().encode(event)) ?? Data()
            return "event: sessionCompleted\ndata: \(String(data: data, encoding: .utf8) ?? "{}")\n\n"
        case let .actionableStateResolved(event):
            let data = (try? JSONEncoder().encode(event)) ?? Data()
            return "event: actionableStateResolved\ndata: \(String(data: data, encoding: .utf8) ?? "{}")\n\n"
        }
    }
}

public struct WatchPermissionEvent: Codable, Sendable {
    public var sessionID: String
    public var agentTool: String
    public var title: String
    public var summary: String
    public var workingDirectory: String?
    public var primaryAction: String
    public var secondaryAction: String
    public var requestID: String
}

public struct WatchQuestionEvent: Codable, Sendable {
    public var sessionID: String
    public var agentTool: String
    public var title: String
    public var options: [String]
    public var requestID: String
}

public struct WatchCompletionEvent: Codable, Sendable {
    public var sessionID: String
    public var agentTool: String
    public var summary: String
}

// MARK: - Resolved Event

/// Sent via SSE when an actionable request has been resolved on the Mac side.
public struct WatchResolvedEvent: Codable, Sendable {
    public var requestID: String
    public var sessionID: String

    public init(requestID: String, sessionID: String) {
        self.requestID = requestID
        self.sessionID = sessionID
    }
}

// MARK: - Resolution

public struct WatchResolutionRequest: Codable, Sendable {
    public var requestID: String
    public var action: String
}

// MARK: - Pairing

public struct WatchPairRequest: Codable, Sendable {
    public var code: String
}

public struct WatchPairResponse: Codable, Sendable {
    public var token: String
}

// MARK: - Status

public struct WatchStatusResponse: Codable, Sendable {
    public var connected: Bool
    public var activeSessionCount: Int
}

// MARK: - Resolution Handler

/// Callback invoked when the Watch/iPhone submits a resolution via `/resolution`.
public typealias WatchResolutionHandler = @Sendable (WatchResolutionRequest) -> Void

/// Callback to query current active session count for `/status`.
public typealias WatchActiveSessionCountProvider = @Sendable () -> Int

// MARK: - WatchHTTPEndpoint

/// A lightweight HTTP server embedded in the macOS app that enables iPhone/Watch communication.
///
/// Uses `NWListener` for TCP + Bonjour advertising of `_agentdeck._tcp`.
/// Implements a minimal HTTP/1.1 parser for 4 endpoints:
/// - `POST /pair` — submit 4-digit pairing code, receive session token
/// - `GET /events` — SSE stream of agent events
/// - `POST /resolution` — submit Watch action decisions
/// - `GET /status` — connection and session status
public final class WatchHTTPEndpoint: @unchecked Sendable {
    private static let logger = Logger(subsystem: "app.agentdeck", category: "WatchHTTPEndpoint")
    private static let serviceType = "_agentdeck._tcp"
    private static let pairingCodeLength = 4
    private static let pairingCodeExpiry: TimeInterval = 120 // 2 minutes

    private let queue = DispatchQueue(label: "app.agentdeck.watch.http", qos: .userInitiated)

    // Pairing state
    private var currentPairingCode: String = ""
    private var pairingCodeGeneratedAt: Date = .distantPast
    private var validTokens: Set<String> = []

    // SSE connections
    private var sseConnections: [UUID: NWConnection] = [:]

    // Listener
    private var listener: NWListener?

    // Callbacks
    public var onResolution: WatchResolutionHandler?
    public var activeSessionCountProvider: WatchActiveSessionCountProvider?

    public init() {
        regeneratePairingCode()
    }

    // MARK: - Lifecycle

    public func start() {
        queue.async { [weak self] in
            self?.startListener()
        }
    }

    public func stop() {
        queue.async { [weak self] in
            guard let self else { return }
            self.listener?.cancel()
            self.listener = nil
            for (id, connection) in self.sseConnections {
                connection.cancel()
                self.sseConnections.removeValue(forKey: id)
            }
        }
    }

    // MARK: - Pairing Code

    /// Returns the current pairing code. Regenerates if expired.
    public func currentCode() -> String {
        queue.sync {
            if Date().timeIntervalSince(pairingCodeGeneratedAt) > Self.pairingCodeExpiry {
                regeneratePairingCodeUnsafe()
            }
            return currentPairingCode
        }
    }

    /// Force-regenerate pairing code (thread-safe).
    public func regeneratePairingCode() {
        queue.sync {
            regeneratePairingCodeUnsafe()
        }
    }

    /// Revoke all paired tokens, forcing re-pairing.
    public func revokeAllTokens() {
        queue.sync {
            validTokens.removeAll()
        }
    }

    // MARK: - SSE Push

    /// Push an SSE event to all authenticated, connected clients.
    public func pushEvent(_ event: WatchSSEEvent) {
        queue.async { [weak self] in
            guard let self else { return }
            let payload = event.sseString()
            guard let data = payload.data(using: .utf8) else { return }
            for (id, connection) in self.sseConnections {
                connection.send(content: data, completion: .contentProcessed { error in
                    if let error {
                        Self.logger.warning("SSE send failed for \(id): \(error.localizedDescription)")
                    }
                })
            }
        }
    }

    // MARK: - Private: Listener

    private func startListener() {
        do {
            let params = NWParameters.tcp
            let listener = try NWListener(using: params)

            // Bonjour advertising
            listener.service = NWListener.Service(
                name: Host.current().localizedName ?? "Mac",
                type: Self.serviceType
            )

            listener.stateUpdateHandler = { [weak self] state in
                switch state {
                case .ready:
                    if let port = self?.listener?.port {
                        Self.logger.info("WatchHTTPEndpoint listening on port \(port.rawValue)")
                    }
                case let .failed(error):
                    Self.logger.error("WatchHTTPEndpoint listener failed: \(error.localizedDescription)")
                    // Attempt restart after delay
                    self?.queue.asyncAfter(deadline: .now() + 2) { [weak self] in
                        self?.startListener()
                    }
                case .cancelled:
                    Self.logger.info("WatchHTTPEndpoint listener cancelled")
                default:
                    break
                }
            }

            listener.newConnectionHandler = { [weak self] connection in
                self?.handleNewConnection(connection)
            }

            listener.start(queue: queue)
            self.listener = listener
        } catch {
            Self.logger.error("Failed to create NWListener: \(error.localizedDescription)")
        }
    }

    // MARK: - Private: Connection Handling

    private func handleNewConnection(_ connection: NWConnection) {
        connection.start(queue: queue)
        receiveHTTPRequest(on: connection)
    }

    private func receiveHTTPRequest(on connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] content, _, isComplete, error in
            guard let self else { return }

            if let error {
                Self.logger.debug("Connection receive error: \(error.localizedDescription)")
                connection.cancel()
                return
            }

            guard let data = content, !data.isEmpty else {
                if isComplete {
                    connection.cancel()
                }
                return
            }

            self.routeHTTPRequest(data: data, connection: connection)
        }
    }

    // MARK: - Private: HTTP Routing

    private func routeHTTPRequest(data: Data, connection: NWConnection) {
        guard let requestString = String(data: data, encoding: .utf8) else {
            sendHTTPResponse(connection: connection, status: "400 Bad Request", body: #"{"error":"invalid request"}"#)
            return
        }

        let (method, path, headers, body) = parseHTTPRequest(requestString)

        switch (method, path) {
        case ("POST", "/pair"):
            handlePair(body: body, connection: connection)

        case ("GET", "/events"):
            handleEventsSSE(headers: headers, connection: connection)

        case ("POST", "/resolution"):
            handleResolution(body: body, headers: headers, connection: connection)

        case ("GET", "/status"):
            handleStatus(headers: headers, connection: connection)

        default:
            sendHTTPResponse(connection: connection, status: "404 Not Found", body: #"{"error":"not found"}"#)
        }
    }

    // MARK: - Private: Endpoint Handlers

    private func handlePair(body: String?, connection: NWConnection) {
        guard let body, let bodyData = body.data(using: .utf8),
              let request = try? JSONDecoder().decode(WatchPairRequest.self, from: bodyData) else {
            sendHTTPResponse(connection: connection, status: "400 Bad Request", body: #"{"error":"invalid body"}"#)
            return
        }

        // Check if pairing code expired
        if Date().timeIntervalSince(pairingCodeGeneratedAt) > Self.pairingCodeExpiry {
            regeneratePairingCodeUnsafe()
            sendHTTPResponse(connection: connection, status: "410 Gone", body: #"{"error":"pairing code expired"}"#)
            return
        }

        guard request.code == currentPairingCode else {
            sendHTTPResponse(connection: connection, status: "403 Forbidden", body: #"{"error":"invalid pairing code"}"#)
            return
        }

        // Generate token
        let token = UUID().uuidString
        validTokens.insert(token)

        // Regenerate pairing code after successful pair
        regeneratePairingCodeUnsafe()

        let response = WatchPairResponse(token: token)
        if let responseData = try? JSONEncoder().encode(response),
           let responseString = String(data: responseData, encoding: .utf8) {
            sendHTTPResponse(connection: connection, status: "200 OK", body: responseString)
        }
    }

    private func handleEventsSSE(headers: [String: String], connection: NWConnection) {
        guard authenticateRequest(headers: headers) else {
            sendHTTPResponse(connection: connection, status: "401 Unauthorized", body: #"{"error":"unauthorized"}"#)
            return
        }

        // Send SSE headers and keep connection open
        let sseHeaders = """
        HTTP/1.1 200 OK\r
        Content-Type: text/event-stream\r
        Cache-Control: no-cache\r
        Connection: keep-alive\r
        Access-Control-Allow-Origin: *\r
        \r

        """

        guard let headerData = sseHeaders.data(using: .utf8) else { return }

        let connectionID = UUID()
        sseConnections[connectionID] = connection

        let queue = self.queue
        connection.send(content: headerData, completion: .contentProcessed { [weak self] error in
            if let error {
                Self.logger.warning("Failed to send SSE headers: \(error.localizedDescription)")
                queue.async { [weak self] in
                    self?.sseConnections.removeValue(forKey: connectionID)
                }
                connection.cancel()
                return
            }

            // Send initial keepalive comment
            guard let keepalive = ": connected\n\n".data(using: .utf8) else { return }
            connection.send(content: keepalive, completion: .contentProcessed { _ in })
        })

        // Monitor for disconnect
        connection.viabilityUpdateHandler = { [weak self] isViable in
            if !isViable {
                queue.async { [weak self] in
                    self?.sseConnections.removeValue(forKey: connectionID)
                }
            }
        }

        // Detect connection close
        monitorSSEConnection(connectionID: connectionID, connection: connection)
    }

    private func monitorSSEConnection(connectionID: UUID, connection: NWConnection) {
        let queue = self.queue
        connection.receive(minimumIncompleteLength: 1, maximumLength: 1) { [weak self] _, _, isComplete, error in
            if isComplete || error != nil {
                queue.async { [weak self] in
                    self?.sseConnections.removeValue(forKey: connectionID)
                }
                connection.cancel()
            } else {
                self?.monitorSSEConnection(connectionID: connectionID, connection: connection)
            }
        }
    }

    private func handleResolution(body: String?, headers: [String: String], connection: NWConnection) {
        guard authenticateRequest(headers: headers) else {
            sendHTTPResponse(connection: connection, status: "401 Unauthorized", body: #"{"error":"unauthorized"}"#)
            return
        }

        guard let body, let bodyData = body.data(using: .utf8),
              let request = try? JSONDecoder().decode(WatchResolutionRequest.self, from: bodyData) else {
            sendHTTPResponse(connection: connection, status: "400 Bad Request", body: #"{"error":"invalid body"}"#)
            return
        }

        onResolution?(request)
        sendHTTPResponse(connection: connection, status: "200 OK", body: #"{"status":"accepted"}"#)
    }

    private func handleStatus(headers: [String: String], connection: NWConnection) {
        guard authenticateRequest(headers: headers) else {
            sendHTTPResponse(connection: connection, status: "401 Unauthorized", body: #"{"error":"unauthorized"}"#)
            return
        }

        let response = WatchStatusResponse(
            connected: !sseConnections.isEmpty,
            activeSessionCount: activeSessionCountProvider?() ?? 0
        )

        if let responseData = try? JSONEncoder().encode(response),
           let responseString = String(data: responseData, encoding: .utf8) {
            sendHTTPResponse(connection: connection, status: "200 OK", body: responseString)
        }
    }

    // MARK: - Private: Auth

    private func authenticateRequest(headers: [String: String]) -> Bool {
        guard let auth = headers["authorization"] ?? headers["Authorization"],
              auth.hasPrefix("Bearer ") else {
            return false
        }
        let token = String(auth.dropFirst("Bearer ".count))
        return validTokens.contains(token)
    }

    // MARK: - Private: HTTP Helpers

    private func parseHTTPRequest(_ raw: String) -> (method: String, path: String, headers: [String: String], body: String?) {
        let parts = raw.components(separatedBy: "\r\n\r\n")
        let headerSection = parts[0]
        let body = parts.count > 1 ? parts[1] : nil

        let lines = headerSection.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else {
            return ("", "", [:], nil)
        }

        let requestParts = requestLine.split(separator: " ", maxSplits: 2)
        let method = requestParts.count > 0 ? String(requestParts[0]) : ""
        let path = requestParts.count > 1 ? String(requestParts[1]) : ""

        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            if let colonIndex = line.firstIndex(of: ":") {
                let key = String(line[line.startIndex..<colonIndex]).trimmingCharacters(in: .whitespaces)
                let value = String(line[line.index(after: colonIndex)...]).trimmingCharacters(in: .whitespaces)
                headers[key] = value
            }
        }

        return (method, path, headers, body?.isEmpty == true ? nil : body)
    }

    private func sendHTTPResponse(connection: NWConnection, status: String, body: String, contentType: String = "application/json") {
        let response = """
        HTTP/1.1 \(status)\r
        Content-Type: \(contentType)\r
        Content-Length: \(body.utf8.count)\r
        Connection: close\r
        \r
        \(body)
        """

        guard let data = response.data(using: .utf8) else { return }
        connection.send(content: data, isComplete: true, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    // MARK: - Private: Pairing Code Generation

    /// Must be called on `queue`.
    private func regeneratePairingCodeUnsafe() {
        let digits = (0..<Self.pairingCodeLength).map { _ in String(Int.random(in: 0...9)) }
        currentPairingCode = digits.joined()
        pairingCodeGeneratedAt = Date()
        Self.logger.info("New pairing code generated")
    }
}
