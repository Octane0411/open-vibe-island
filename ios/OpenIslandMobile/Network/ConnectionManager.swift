import Combine
import Foundation
import Network
import SwiftUI
import UIKit
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
    /// User-visible error message (e.g. SSE failure, token expiry).
    @Published private(set) var connectionError: String?

    // MARK: - Notification Settings (persisted via UserDefaults)

    @Published var notifyPermissions: Bool {
        didSet { UserDefaults.standard.set(notifyPermissions, forKey: "openisland.notify.permissions") }
    }
    @Published var notifyQuestions: Bool {
        didSet { UserDefaults.standard.set(notifyQuestions, forKey: "openisland.notify.questions") }
    }
    @Published var notifyCompletions: Bool {
        didSet { UserDefaults.standard.set(notifyCompletions, forKey: "openisland.notify.completions") }
    }
    @Published var silentCompletions: Bool {
        didSet { UserDefaults.standard.set(silentCompletions, forKey: "openisland.notify.silentCompletions") }
    }

    // MARK: - Internal State

    let discovery = BonjourDiscovery()
    var notificationManager: NotificationManager?
    private var sseClient: SSEClient?
    private var connectionEndpoint: NWEndpoint?
    private var resolutionObservation: Task<Void, Never>?
    private var credentials = WatchCredentialStore.load()
    private var savedToken: String? { credentials?.token }
    private var savedMacName: String? {
        get { UserDefaults.standard.string(forKey: "openisland.macName") }
        set { UserDefaults.standard.set(newValue, forKey: "openisland.macName") }
    }
    var pairedAt: Date? {
        get {
            let interval = UserDefaults.standard.double(forKey: "openisland.pairedAt")
            return interval > 0 ? Date(timeIntervalSince1970: interval) : nil
        }
        set {
            if let date = newValue {
                UserDefaults.standard.set(date.timeIntervalSince1970, forKey: "openisland.pairedAt")
            } else {
                UserDefaults.standard.removeObject(forKey: "openisland.pairedAt")
            }
        }
    }

    private var reconnectTask: Task<Void, Never>?
    private var discoveryObservation: Task<Void, Never>?
    private var networkMonitor: NWPathMonitor?
    private var foregroundObserver: NSObjectProtocol?
    private var lastKnownNetworkSatisfied = true
    private static let maxRecentEvents = 50

    // MARK: - Lifecycle

    init() {
        UserDefaults.standard.removeObject(forKey: "openisland.token")
        let defaults = UserDefaults.standard
        self.notifyPermissions = defaults.object(forKey: "openisland.notify.permissions") as? Bool ?? true
        self.notifyQuestions = defaults.object(forKey: "openisland.notify.questions") as? Bool ?? true
        self.notifyCompletions = defaults.object(forKey: "openisland.notify.completions") as? Bool ?? true
        self.silentCompletions = defaults.object(forKey: "openisland.notify.silentCompletions") as? Bool ?? false

        // If we have a saved token but no connection, we'll try to reconnect when discovering
        if savedToken != nil {
            connectedMacName = savedMacName
        }

        // Observe notification action relay for resolution posting
        observeNotificationActions()

        // Wire Watch resolution callback to post resolution back to Mac
        WatchConnectivityManager.shared.onResolution = { [weak self] requestID, action in
            Task { @MainActor [weak self] in
                guard let self else { return }
                do {
                    try await self.postResolution(requestID: requestID, action: action)
                    self.markEventResolved(requestID: requestID, action: action)
                } catch {
                    Self.logger.error("Failed to post Watch resolution: \(error.localizedDescription)")
                }
            }
        }

        // Monitor network changes for WiFi disconnect/reconnect
        startNetworkMonitor()

        // Monitor app foreground transitions
        foregroundObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.willEnterForegroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.handleForegroundTransition()
            }
        }
    }

    // Note: networkMonitor and foregroundObserver are cleaned up in disconnect()
    // and when ConnectionManager is deallocated, ARC handles NWPathMonitor cancellation.

    private func startNetworkMonitor() {
        let monitor = NWPathMonitor(requiredInterfaceType: .wifi)
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor [weak self] in
                guard let self else { return }
                let wasSatisfied = self.lastKnownNetworkSatisfied
                let isSatisfied = path.status == .satisfied
                self.lastKnownNetworkSatisfied = isSatisfied

                if wasSatisfied && !isSatisfied {
                    // WiFi lost — proactively disconnect SSE
                    Self.logger.info("WiFi lost, disconnecting SSE")
                    self.sseClient?.disconnect()
                    self.sseClient = nil
                    if self.state == .connected {
                        self.state = .paired
                        self.connectionError = "WiFi 断开，等待网络恢复..."
                    }
                } else if !wasSatisfied && isSatisfied && self.savedToken != nil {
                    // WiFi restored — attempt reconnect via Bonjour
                    Self.logger.info("WiFi restored, attempting reconnect")
                    self.connectionError = nil
                    self.startDiscovery()
                }
            }
        }
        monitor.start(queue: DispatchQueue(label: "app.openisland.mobile.network"))
        self.networkMonitor = monitor
    }

    private func handleForegroundTransition() {
        guard savedToken != nil else { return }
        // If we were connected but SSE might have been killed in background, check and reconnect
        if state == .connected {
            // SSE may have been silently disconnected — re-establish
            if sseClient == nil {
                Self.logger.info("Foreground transition: SSE client missing, reconnecting")
                connectSSE()
            }
        } else if state == .paired || state == .disconnected {
            Self.logger.info("Foreground transition: not connected, starting discovery")
            startDiscovery()
        }
    }

    private func observeNotificationActions() {
        resolutionObservation = Task { [weak self] in
            let relay = NotificationActionRelay.shared
            for await resolution in relay.$pendingResolution.values {
                guard !Task.isCancelled, let resolution else { continue }
                do {
                    try await self?.postResolution(requestID: resolution.requestID, action: resolution.action)
                    self?.markEventResolved(requestID: resolution.requestID, action: resolution.action)
                } catch {
                    Self.logger.error("Failed to post resolution from notification: \(error.localizedDescription)")
                }
            }
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
        credentials = nil
        WatchCredentialStore.remove()
        savedMacName = nil
        pairedAt = nil
        connectionEndpoint = nil
        connectedMacName = nil
        connectionError = nil
        recentEvents.removeAll()
        state = .disconnected
    }

    // MARK: - Pairing

    func pair(mac: DiscoveredMac, code: String) async throws {
        let pairing = try WatchPairingCode(code)
        try await completePairing(endpoint: mac.endpoint, name: mac.name, pairing: pairing)
    }

    func pairManual(host: String, port: UInt16, code: String) async throws {
        let pairing = try WatchPairingCode(code)
        guard port > 0, let endpointPort = NWEndpoint.Port(rawValue: port) else { throw PairingError.resolutionFailed }
        let endpoint = NWEndpoint.hostPort(host: NWEndpoint.Host(host), port: endpointPort)
        try await completePairing(endpoint: endpoint, name: host, pairing: pairing)
    }

    private func completePairing(endpoint: NWEndpoint, name: String, pairing: WatchPairingCode) async throws {
        let body = try JSONEncoder().encode(WatchPairRequest(code: pairing.secret))
        let response = try await WatchHTTPClient.request(endpoint: endpoint, key: pairing.key, path: "pair", method: "POST", body: body)
        guard response.status == 200 else { throw PairingError.invalidCode }
        let reply = try JSONDecoder().decode(WatchPairResponse.self, from: response.body)
        let credentials = WatchCredentials(token: reply.token, key: pairing.key)
        try WatchCredentialStore.save(credentials)
        self.credentials = credentials
        connectionEndpoint = endpoint
        savedMacName = name
        pairedAt = Date()
        connectedMacName = name
        state = .paired
        showPairing = false
        connectSSE()
    }

    // MARK: - SSE Connection

    private func connectSSE() {
        guard let endpoint = connectionEndpoint, let credentials else {
            Self.logger.warning("Cannot connect SSE: missing endpoint or token")
            return
        }

        sseClient?.disconnect()
        let client = SSEClient(endpoint: endpoint, credentials: credentials)
        client.onEvent = { [weak self, weak client] eventType, data in
            guard let self, self.sseClient === client else { return }
            self.handleSSEEvent(eventType: eventType, data: data)
        }
        client.onDisconnect = { [weak self, weak client] in
            guard let self, self.sseClient === client else { return }
            self.handleSSEDisconnect()
        }
        client.onUnauthorized = { [weak self, weak client] in
            guard let self, self.sseClient === client else { return }
            Self.logger.warning("SSE 401 — token expired")
            self.handleTokenExpired()
        }

        self.sseClient = client
        client.connect()
        state = .connected
        connectionError = nil
        Self.logger.info("SSE connected")
    }

    private func handleSSEEvent(eventType: String, data: Data) {
        connectionError = nil
        let decoder = JSONDecoder()

        let event: WatchEvent?

        switch eventType {
        case "permissionRequested":
            if let e = try? decoder.decode(WatchPermissionEvent.self, from: data) {
                event = .from(e)
                if notifyPermissions {
                    notificationManager?.sendPermissionNotification(e)
                }
                WatchConnectivityManager.shared.sendEvent(.permissionRequest(.init(
                    requestID: e.requestID, sessionID: e.sessionID, agentTool: e.agentTool,
                    title: e.title, summary: e.summary, workingDirectory: e.workingDirectory
                )))
                Self.logger.info("Permission requested: \(e.title)")
            } else {
                event = nil
            }

        case "questionAsked":
            if let e = try? decoder.decode(WatchQuestionEvent.self, from: data) {
                event = .from(e)
                if notifyQuestions {
                    notificationManager?.sendQuestionNotification(e)
                }
                WatchConnectivityManager.shared.sendEvent(.question(.init(
                    requestID: e.requestID, sessionID: e.sessionID, agentTool: e.agentTool,
                    title: e.title, options: e.options
                )))
                Self.logger.info("Question asked: \(e.title)")
            } else {
                event = nil
            }

        case "sessionCompleted":
            if let e = try? decoder.decode(WatchCompletionEvent.self, from: data) {
                event = .from(e)
                if notifyCompletions {
                    notificationManager?.sendCompletionNotification(e, silent: silentCompletions)
                }
                WatchConnectivityManager.shared.sendEvent(.sessionCompleted(.init(
                    sessionID: e.sessionID, agentTool: e.agentTool, summary: e.summary
                )))
                Self.logger.info("Session completed: \(e.summary)")
            } else {
                event = nil
            }

        case "actionableStateResolved":
            if let e = try? decoder.decode(WatchResolvedEvent.self, from: data) {
                handleRemoteResolution(e)
                WatchConnectivityManager.shared.sendEvent(.resolved(requestID: e.requestID))
                Self.logger.info("Remote resolution for request \(e.requestID)")
            }
            event = nil

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
        guard state == .connected || state == .paired else { return }
        state = .paired
        connectionError = "连接中断，正在重连..."
        Self.logger.info("SSE disconnected, will attempt reconnect")
        scheduleReconnect()
    }

    // MARK: - Resolution Handling

    /// Called when Mac reports that an actionable request was resolved (e.g. user acted on Mac).
    /// Clears the corresponding notification and marks the event as resolved in the UI.
    private func handleRemoteResolution(_ event: WatchResolvedEvent) {
        notificationManager?.removeNotification(forRequestID: event.requestID)
        notificationManager?.removeQuestionCategory(forRequestID: event.requestID)
        markEventResolved(requestID: event.requestID)
    }

    /// Marks a recent event as resolved by requestID.
    func markEventResolved(requestID: String, action: String? = nil) {
        if let index = recentEvents.firstIndex(where: { $0.requestID == requestID }) {
            recentEvents[index].isResolved = true
            recentEvents[index].resolvedAt = Date()
            recentEvents[index].resolvedAction = action
        }
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
                    self.connectionEndpoint = mac.endpoint
                    self.connectedMacName = macName
                    self.state = .paired
                    self.connectSSE()
                    return
                }
            }
        }
    }

    // MARK: - Resolution (post action back to Mac)

    func postResolution(requestID: String, action: String) async throws {
        guard let endpoint = connectionEndpoint, let credentials else {
            throw PairingError.notConnected
        }

        let body = try JSONEncoder().encode(WatchResolutionRequest(requestID: requestID, action: action))
        let response = try await WatchHTTPClient.request(
            endpoint: endpoint, key: credentials.key, path: "resolution", method: "POST",
            token: credentials.token, body: body
        )

        switch response.status {
        case 200:
            Self.logger.info("Resolution posted: \(requestID) → \(action)")
        case 401:
            // Token expired or revoked — clear credentials and prompt re-pairing
            Self.logger.warning("Token expired (401), clearing credentials")
            handleTokenExpired()
            throw PairingError.tokenExpired
        default:
            throw PairingError.serverError(response.status)
        }
    }

    /// Handle token expiry: disconnect SSE, clear saved token, update UI.
    private func handleTokenExpired() {
        sseClient?.disconnect()
        sseClient = nil
        reconnectTask?.cancel()
        reconnectTask = nil
        credentials = nil
        WatchCredentialStore.remove()
        state = .disconnected
        connectionError = "配对已过期，请重新配对"
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
    case tokenExpired

    var errorDescription: String? {
        switch self {
        case .invalidCode: return "配对码错误，请检查后重试"
        case .codeExpired: return "配对码已过期，请在 Mac 上刷新配对码后重新输入"
        case .invalidResponse: return "服务器响应异常"
        case let .serverError(code): return "服务器错误 (\(code))"
        case .resolutionFailed: return "无法解析 Mac 地址"
        case .notConnected: return "未连接到 Mac"
        case .tokenExpired: return "配对已过期，请重新配对"
        }
    }
}
