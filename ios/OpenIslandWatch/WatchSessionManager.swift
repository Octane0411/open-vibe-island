import Foundation
import WatchConnectivity
import os

struct PendingWatchEvent: Identifiable {
    let id: String
    let message: WatchMessage
    let receivedAt: Date
}

final class WatchSessionManager: NSObject, ObservableObject {
    static let shared = WatchSessionManager()

    private override init() {
        super.init()
    }

    @Published var pendingEvents: [PendingWatchEvent] = []
    @Published var isPhoneReachable: Bool = false

    private let logger = Logger(subsystem: "app.openisland.watch", category: "WatchSession")
    private var replyHandlers: [String: ([String: Any]) -> Void] = [:]

    func activate() {
        guard WCSession.isSupported() else {
            logger.warning("WCSession not supported on this device")
            return
        }
        let session = WCSession.default
        session.delegate = self
        session.activate()
        logger.info("WCSession activation requested")
    }

    func resolve(requestID: String, action: String) {
        let response = WatchResponse.resolution(requestID: requestID, action: action)
        guard let data = try? JSONEncoder().encode(response) else {
            logger.error("Failed to encode WatchResponse for \(requestID)")
            return
        }
        let payload: [String: Any] = ["payload": data]

        if let replyHandler = replyHandlers.removeValue(forKey: requestID) {
            replyHandler(payload)
            logger.info("Resolved \(requestID) via replyHandler")
        } else if WCSession.default.isReachable {
            WCSession.default.sendMessage(payload, replyHandler: nil) { [weak self] error in
                self?.logger.error("Failed to send resolution for \(requestID): \(error.localizedDescription)")
            }
            logger.info("Resolved \(requestID) via sendMessage fallback")
        } else {
            logger.warning("Cannot resolve \(requestID): phone not reachable and no replyHandler")
        }

        pendingEvents.removeAll { $0.id == requestID }
        HapticManager.playConfirmation()
    }

    // MARK: - Private

    private func handleIncoming(_ payload: [String: Any], replyHandler: (([String: Any]) -> Void)? = nil) {
        guard let data = payload["payload"] as? Data,
              let message = try? JSONDecoder().decode(WatchMessage.self, from: data) else {
            logger.error("Failed to decode WatchMessage from payload")
            return
        }

        let requestID: String
        switch message {
        case .permissionRequest(let p):
            requestID = p.requestID
        case .question(let q):
            requestID = q.requestID
        case .sessionCompleted(let c):
            requestID = c.sessionID
        case .resolved(let rid):
            // Remote resolution — remove matching event and return
            DispatchQueue.main.async {
                self.pendingEvents.removeAll { $0.id == rid }
            }
            return
        }

        if let replyHandler = replyHandler {
            replyHandlers[requestID] = replyHandler
        }

        let event = PendingWatchEvent(id: requestID, message: message, receivedAt: Date())
        DispatchQueue.main.async {
            self.pendingEvents.append(event)
        }

        HapticManager.play(for: message)
    }
}

// MARK: - WCSessionDelegate
extension WatchSessionManager: WCSessionDelegate {
    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        if let error = error {
            logger.error("WCSession activation failed: \(error.localizedDescription)")
        } else {
            logger.info("WCSession activated: \(activationState.rawValue)")
        }
        DispatchQueue.main.async {
            self.isPhoneReachable = session.isReachable
        }
    }

    func sessionReachabilityDidChange(_ session: WCSession) {
        DispatchQueue.main.async {
            self.isPhoneReachable = session.isReachable
        }
    }

    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        handleIncoming(message)
    }

    func session(_ session: WCSession, didReceiveMessage message: [String: Any], replyHandler: @escaping ([String: Any]) -> Void) {
        handleIncoming(message, replyHandler: replyHandler)
    }

    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        handleIncoming(userInfo)
    }
}
