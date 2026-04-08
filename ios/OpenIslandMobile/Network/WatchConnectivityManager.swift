import Foundation
import WatchConnectivity
import os

final class WatchConnectivityManager: NSObject, @unchecked Sendable {
    static let shared = WatchConnectivityManager()

    private static let logger = Logger(subsystem: "app.openisland.mobile", category: "WatchConnectivity")

    /// Called when Watch sends back a resolution decision (requestID, action).
    var onResolution: ((String, String) -> Void)?

    private let session: WCSession

    private override init() {
        self.session = WCSession.default
        super.init()
    }

    func activate() {
        guard WCSession.isSupported() else {
            Self.logger.warning("WatchConnectivity not supported on this device")
            return
        }
        session.delegate = self
        session.activate()
        Self.logger.info("WCSession activation requested")
    }

    func sendEvent(_ message: WatchMessage) {
        guard session.activationState == .activated else {
            Self.logger.warning("WCSession not activated, dropping message")
            return
        }

        guard session.isPaired else {
            Self.logger.debug("No paired Watch, dropping message")
            return
        }

        let payload: [String: Any]
        do {
            let data = try JSONEncoder().encode(message)
            payload = ["payload": data]
        } catch {
            Self.logger.error("Failed to encode WatchMessage: \(error.localizedDescription)")
            return
        }

        // Always try sendMessage first (isReachable can be stale), fallback to transferUserInfo
        session.sendMessage(payload, replyHandler: { [weak self] reply in
            Self.logger.debug("Watch replied to message")
            self?.handleIncomingMessage(reply)
        }, errorHandler: { error in
            Self.logger.info("sendMessage failed, queuing via transferUserInfo: \(error.localizedDescription)")
            self.session.transferUserInfo(payload)
        })
    }
}

// MARK: - WCSessionDelegate

extension WatchConnectivityManager: WCSessionDelegate {
    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: (any Error)?) {
        if let error {
            Self.logger.error("WCSession activation failed: \(error.localizedDescription)")
        } else {
            Self.logger.info("WCSession activated: \(activationState.rawValue)")
        }
    }

    func sessionDidBecomeInactive(_ session: WCSession) {
        Self.logger.info("WCSession became inactive")
    }

    func sessionDidDeactivate(_ session: WCSession) {
        Self.logger.info("WCSession deactivated, reactivating")
        session.activate()
    }

    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        handleIncomingMessage(message)
    }

    func session(_ session: WCSession, didReceiveMessage message: [String: Any], replyHandler: @escaping ([String: Any]) -> Void) {
        handleIncomingMessage(message)
        replyHandler(["status": "ok"])
    }

    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        handleIncomingMessage(userInfo)
    }

    private func handleIncomingMessage(_ message: [String: Any]) {
        guard let data = message["payload"] as? Data else {
            Self.logger.warning("Received message without payload")
            return
        }

        do {
            let response = try JSONDecoder().decode(WatchResponse.self, from: data)
            switch response {
            case let .resolution(requestID, action):
                Self.logger.info("Watch resolution: \(requestID) -> \(action)")
                onResolution?(requestID, action)
            }
        } catch {
            Self.logger.error("Failed to decode WatchResponse: \(error.localizedDescription)")
        }
    }
}
