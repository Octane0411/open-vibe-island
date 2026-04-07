import Combine
import Foundation
import Network
import SwiftUI
import os

/// Manages the full lifecycle: Bonjour discovery → pairing → SSE connection → reconnection.
@MainActor
final class ConnectionManager: ObservableObject {
    private static let logger = Logger(subsystem: "app.openisland.mobile", category: "ConnectionManager")

    enum ConnectionState {
        case disconnected
        case discovering
        case paired
        case connected

        var displayText: String {
            switch self {
            case .disconnected: return "未连接"
            case .discovering: return "搜索中..."
            case .paired: return "已配对，连接中..."
            case .connected: return "已连接"
            }
        }

        var iconName: String {
            switch self {
            case .disconnected: return "antenna.radiowaves.left.and.right.slash"
            case .discovering: return "antenna.radiowaves.left.and.right"
            case .paired: return "link"
            case .connected: return "checkmark.circle.fill"
            }
        }

        var iconColor: SwiftUI.Color {
            switch self {
            case .disconnected: return .secondary
            case .discovering: return .orange
            case .paired: return .blue
            case .connected: return .green
            }
        }
    }

    // MARK: - Published State

    @Published private(set) var state: ConnectionState = .disconnected
    @Published var showPairing = false
    @Published private(set) var connectedMacName: String?
    @Published private(set) var recentEvents: [WatchEvent] = []

    // MARK: - Internal State

    let discovery = BonjourDiscovery()
    private var sseClient: SSEClient?
    private var resolvedURL: URL?
    private var savedToken: String? {
        get { UserDefaults.standard.string(forKey: "openisland.token") }
        set { UserDefaults.standard.set(newValue, forKey: "openisland.token") }
    }
    private var savedMacName: String? {
        get { UserDefaults.standard.string(forKey: "openisland.macName") }
        set { UserDefaults.standard.set(newValue, forKey: "openisland.macName") }
    }

    private var reconnectTask: Task<Void, Never>?
    private var discoveryObservation: Task<Void, Never>?
    private static let maxRecentEvents = 50

    // MARK: - Lifecycle

    init() {
        // If we have a saved token but no connection, we'll try to reconnect when discovering
        if savedToken != nil {
            connectedMacName = savedMacName
        }
    }

    // MARK: - Discovery

    func startDiscovery() {
        state = .discovering
        discovery.startBrowsing()

        // If we have a saved token, try auto-reconnecting when we find the Mac
        if savedToken != nil {
            observeDiscoveryForAutoReconnect()
        } else {
            showPairing = true
        }
    }

    func disconnect() {
        sseClient?.disconnect()
        sseClient = nil
        discovery.stopBrowsing()
        reconnectTask?.cancel()
        reconnectTask = nil
        discoveryObservation?.cancel()
        discoveryObservation = nil
        savedToken = nil
        savedMacName = nil
        resolvedURL = nil
        connectedMacName = nil
        state = .disconnected
    }

    // MARK: - Pairing

    func pair(mac: DiscoveredMac, code: String) async throws {
        let url = try await resolveEndpoint(mac.endpoint)
        self.resolvedURL = url

        var request = URLRequest(url: url.appendingPathComponent("pair"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body = WatchPairRequest(code: code)
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw PairingError.invalidResponse
        }

        switch httpResponse.statusCode {
        case 200:
            let pairResponse = try JSONDecoder().decode(WatchPairResponse.self, from: data)
            savedToken = pairResponse.token
            savedMacName = mac.name
            connectedMacName = mac.name
            state = .paired
            showPairing = false
            Self.logger.info("Paired successfully with \(mac.name)")
            connectSSE()

        case 403:
            throw PairingError.invalidCode

        case 410:
            throw PairingError.codeExpired

        default:
            throw PairingError.serverError(httpResponse.statusCode)
        }
    }

    // MARK: - SSE Connection

    private func connectSSE() {
        guard let url = resolvedURL, let token = savedToken else {
            Self.logger.warning("Cannot connect SSE: missing URL or token")
            return
        }

        let client = SSEClient(baseURL: url, token: token)
        client.onEvent = { [weak self] eventType, data in
            self?.handleSSEEvent(eventType: eventType, data: data)
        }
        client.onDisconnect = { [weak self] in
            self?.handleSSEDisconnect()
        }

        self.sseClient = client
        client.connect()
        state = .connected
        Self.logger.info("SSE connected")
    }

    private func handleSSEEvent(eventType: String, data: Data) {
        let decoder = JSONDecoder()

        let event: WatchEvent?

        switch eventType {
        case "permissionRequested":
            if let e = try? decoder.decode(WatchPermissionEvent.self, from: data) {
                event = .from(e)
                Self.logger.info("Permission requested: \(e.title)")
            } else {
                event = nil
            }

        case "questionAsked":
            if let e = try? decoder.decode(WatchQuestionEvent.self, from: data) {
                event = .from(e)
                Self.logger.info("Question asked: \(e.title)")
            } else {
                event = nil
            }

        case "sessionCompleted":
            if let e = try? decoder.decode(WatchCompletionEvent.self, from: data) {
                event = .from(e)
                Self.logger.info("Session completed: \(e.summary)")
            } else {
                event = nil
            }

        default:
            Self.logger.debug("Unknown SSE event type: \(eventType)")
            event = nil
        }

        if let event {
            recentEvents.insert(event, at: 0)
            if recentEvents.count > Self.maxRecentEvents {
                recentEvents = Array(recentEvents.prefix(Self.maxRecentEvents))
            }
        }
    }

    private func handleSSEDisconnect() {
        guard state == .connected else { return }
        state = .paired
        Self.logger.info("SSE disconnected, will attempt reconnect")
        scheduleReconnect()
    }

    // MARK: - Reconnection

    private func scheduleReconnect() {
        reconnectTask?.cancel()
        reconnectTask = Task { [weak self] in
            var delay: UInt64 = 2_000_000_000 // 2 seconds initial
            let maxDelay: UInt64 = 30_000_000_000 // 30 seconds max

            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: delay)
                guard !Task.isCancelled else { return }

                Self.logger.info("Attempting SSE reconnect...")
                await self?.connectSSE()

                // Exponential backoff
                delay = min(delay * 2, maxDelay)
            }
        }
    }

    private func observeDiscoveryForAutoReconnect() {
        discoveryObservation?.cancel()
        discoveryObservation = Task { [weak self] in
            guard let self else { return }
            // Observe discoveredMacs changes via Combine instead of polling
            for await macs in self.discovery.$discoveredMacs.values {
                guard !Task.isCancelled else { return }
                guard let macName = self.savedMacName else { continue }

                if let mac = macs.first(where: { $0.name == macName }) {
                    Self.logger.info("Auto-reconnecting to \(macName)")
                    do {
                        let url = try await self.resolveEndpoint(mac.endpoint)
                        self.resolvedURL = url
                        self.connectedMacName = macName
                        self.state = .paired
                        self.connectSSE()
                        return
                    } catch {
                        Self.logger.warning("Failed to resolve endpoint: \(error.localizedDescription)")
                    }
                }
            }
        }
    }

    // MARK: - Endpoint Resolution

    /// Resolves a Bonjour NWEndpoint to an HTTP URL by briefly connecting to extract the IP and port.
    private func resolveEndpoint(_ endpoint: NWEndpoint) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            var resumed = false
            let connection = NWConnection(to: endpoint, using: .tcp)

            connection.stateUpdateHandler = { state in
                guard !resumed else { return }

                switch state {
                case .ready:
                    defer { connection.cancel() }
                    guard let remote = connection.currentPath?.remoteEndpoint,
                          case let .hostPort(host, port) = remote else {
                        resumed = true
                        continuation.resume(throwing: PairingError.resolutionFailed)
                        return
                    }

                    let hostString: String
                    switch host {
                    case let .ipv4(addr): hostString = "\(addr)"
                    case let .ipv6(addr): hostString = "[\(addr)]"
                    case let .name(name, _): hostString = name
                    @unknown default: hostString = "\(host)"
                    }

                    guard let url = URL(string: "http://\(hostString):\(port.rawValue)") else {
                        resumed = true
                        continuation.resume(throwing: PairingError.resolutionFailed)
                        return
                    }
                    resumed = true
                    continuation.resume(returning: url)

                case let .failed(error):
                    connection.cancel()
                    resumed = true
                    continuation.resume(throwing: error)

                default:
                    break
                }
            }
            connection.start(queue: .global())
        }
    }

    // MARK: - Resolution (post action back to Mac)

    func postResolution(requestID: String, action: String) async throws {
        guard let url = resolvedURL, let token = savedToken else {
            throw PairingError.notConnected
        }

        var request = URLRequest(url: url.appendingPathComponent("resolution"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let body = WatchResolutionRequest(requestID: requestID, action: action)
        request.httpBody = try JSONEncoder().encode(body)

        let (_, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw PairingError.serverError((response as? HTTPURLResponse)?.statusCode ?? 0)
        }

        Self.logger.info("Resolution posted: \(requestID) → \(action)")
    }
}

// MARK: - Errors

enum PairingError: LocalizedError {
    case invalidCode
    case codeExpired
    case invalidResponse
    case serverError(Int)
    case resolutionFailed
    case notConnected

    var errorDescription: String? {
        switch self {
        case .invalidCode: return "配对码错误"
        case .codeExpired: return "配对码已过期，请在 Mac 上重新生成"
        case .invalidResponse: return "服务器响应异常"
        case let .serverError(code): return "服务器错误 (\(code))"
        case .resolutionFailed: return "无法解析 Mac 地址"
        case .notConnected: return "未连接到 Mac"
        }
    }
}
