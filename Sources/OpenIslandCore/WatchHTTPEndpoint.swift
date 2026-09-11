import Foundation
import Network
import os
import OpenIslandTransport

// MARK: - WatchHTTPEndpoint

/// A lightweight HTTP server embedded in the macOS app that enables iPhone/Watch communication.
///
/// Uses authenticated TLS + Bonjour advertising of `_openisland2._tcp`.
/// Implements a minimal HTTP/1.1 parser for 4 endpoints:
/// - `POST /pair` — submit a one-time pairing secret over TLS, receive session token
/// - `GET /events` — SSE stream of agent events
/// - `POST /resolution` — submit Watch action decisions
/// - `GET /status` — connection and session status
public final class WatchHTTPEndpoint: @unchecked Sendable {
    private static let logger = Logger(subsystem: "app.openisland", category: "WatchHTTPEndpoint")
    private static let serviceType = WatchSecureTransport.serviceType

    private let queue = DispatchQueue(label: "app.openisland.watch.http", qos: .userInitiated)

    private var pairing = WatchPairingState()
    private var running = false
    private var connections: [UUID: NWConnection] = [:]
    private var activeSessionCount = 0

    // SSE connections
    private var sseConnections: [UUID: NWConnection] = [:]

    // Listener
    private var listener: NWListener?

    // Callbacks
    public var onResolution: WatchResolutionHandler?
    public func setActiveSessionCount(_ count: Int) {
        queue.async { [self] in activeSessionCount = count }
    }

    public var listeningPort: UInt16? {
        queue.sync {
            guard let listener, case .ready = listener.state else { return nil }
            return listener.port?.rawValue
        }
    }
    public var connectedDeviceCount: Int { queue.sync { sseConnections.count } }

    public init() {}

    // MARK: - Lifecycle

    public func start() {
        queue.async { [self] in
            guard !running else { return }
            running = true
            startListener()
        }
    }

    public func stop() {
        queue.sync {
            running = false
            cancelConnections()
            pairing.revoke()
        }
    }

    public func currentCode() -> String { queue.sync { pairing.currentCode() } }

    /// Pairing opens only after a deliberate action on the Mac.
    public func regeneratePairingCode() { queue.sync { _ = pairing.begin() } }

    public func revokeAllTokens() {
        queue.sync {
            cancelConnections()
            pairing.revoke()
            if running { startListener() }
        }
    }

    private func cancelConnections() {
        listener?.stateUpdateHandler = nil
        listener?.newConnectionHandler = nil
        listener?.cancel()
        listener = nil
        for connection in connections.values { connection.cancel() }
        connections.removeAll()
        sseConnections.removeAll()
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
            guard running, listener == nil else { return }
            let params = try WatchSecureTransport.parameters(key: pairing.transportKey)
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
                    self?.listener?.cancel()
                    self?.listener = nil
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
        guard running, connections.count < 32 else { connection.cancel(); return }
        let id = UUID()
        connections[id] = connection
        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .cancelled, .failed:
                self?.connections.removeValue(forKey: id)
            default: break
            }
        }
        connection.start(queue: queue)
        receiveHTTPRequest(on: connection, buffer: Data())
        queue.asyncAfter(deadline: .now() + 10) { [weak self, weak connection] in
            guard let self, let connection,
                  !self.sseConnections.values.contains(where: { $0 === connection }) else { return }
            connection.cancel()
        }
    }

    private func receiveHTTPRequest(on connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 8_192) { [weak self] content, _, ended, error in
            guard let self else { connection.cancel(); return }
            if error != nil { connection.cancel(); return }
            let bytes = buffer + (content ?? Data())
            do {
                if let request = try WatchHTTPRequest.parse(bytes) {
                    self.routeHTTPRequest(request, connection: connection)
                } else if ended { connection.cancel() }
                else { self.receiveHTTPRequest(on: connection, buffer: bytes) }
            } catch {
                self.sendHTTPResponse(connection: connection, status: "400 Bad Request", body: #"{"error":"invalid request"}"#)
            }
        }
    }

    private func routeHTTPRequest(_ request: WatchHTTPRequest, connection: NWConnection) {
        switch (request.method, request.path) {
        case ("POST", "/pair"): handlePair(body: request.body, connection: connection)
        case ("GET", "/events"): handleEventsSSE(headers: request.headers, connection: connection)
        case ("POST", "/resolution"): handleResolution(body: request.body, headers: request.headers, connection: connection)
        case ("GET", "/status"): handleStatus(headers: request.headers, connection: connection)
        default: sendHTTPResponse(connection: connection, status: "404 Not Found", body: #"{"error":"not found"}"#)
        }
    }

    // MARK: - Private: Endpoint Handlers

    private func handlePair(body: String?, connection: NWConnection) {
        guard let body, let bodyData = body.data(using: .utf8),
              let request = try? JSONDecoder().decode(WatchPairRequest.self, from: bodyData) else {
            sendHTTPResponse(connection: connection, status: "400 Bad Request", body: #"{"error":"invalid body"}"#)
            return
        }

        guard let token = pairing.pair(secret: request.code) else {
            sendHTTPResponse(connection: connection, status: "403 Forbidden", body: #"{"error":"pairing closed or invalid key"}"#)
            return
        }

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
            activeSessionCount: activeSessionCount
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
        return pairing.tokens.contains(token)
    }

    // MARK: - Private: HTTP Helpers

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

}
