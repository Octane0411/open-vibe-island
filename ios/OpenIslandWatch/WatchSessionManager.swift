import Foundation
import WatchConnectivity
import UserNotifications
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
    @Published var lastError: String?

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
            lastError = "编码响应失败"
            return
        }
        let payload: [String: Any] = ["payload": data]

        if let replyHandler = replyHandlers.removeValue(forKey: requestID) {
            replyHandler(payload)
            logger.info("Resolved \(requestID) via replyHandler")
            lastError = nil
        } else if WCSession.default.isReachable {
            WCSession.default.sendMessage(payload, replyHandler: nil) { [weak self] error in
                self?.logger.error("Failed to send resolution for \(requestID): \(error.localizedDescription)")
                DispatchQueue.main.async {
                    self?.lastError = "发送失败: \(error.localizedDescription)"
                }
            }
            logger.info("Resolved \(requestID) via sendMessage fallback")
            lastError = nil
        } else {
            logger.warning("Cannot resolve \(requestID): phone not reachable and no replyHandler")
            lastError = "iPhone 不可达，请检查连接"
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

        // Auto-expire sessionCompleted events after 30 seconds
        if case .sessionCompleted = message {
            DispatchQueue.main.asyncAfter(deadline: .now() + 30) { [weak self] in
                self?.pendingEvents.removeAll { $0.id == requestID }
            }
        }

        HapticManager.play(for: message)
        scheduleLocalNotification(for: message, requestID: requestID)
    }

    private func scheduleLocalNotification(for message: WatchMessage, requestID: String) {
        let content = UNMutableNotificationContent()
        content.sound = .default

        switch message {
        case .permissionRequest(let p):
            content.title = p.agentTool
            content.subtitle = p.title
            content.body = p.summary
            content.categoryIdentifier = "PERMISSION_REQUEST"
            content.userInfo = ["requestID": requestID]

        case .question(let q):
            content.title = q.agentTool
            content.subtitle = q.title
            content.body = q.options.joined(separator: " / ")
            content.categoryIdentifier = "QUESTION"
            content.userInfo = ["requestID": requestID]

        case .sessionCompleted(let c):
            content.title = "✅ \(c.agentTool)"
            content.body = c.summary
            content.categoryIdentifier = "SESSION_COMPLETED"

        case .resolved:
            return
        }

        let request = UNNotificationRequest(
            identifier: "watch-\(requestID)",
            content: content,
            trigger: nil  // 立即触发
        )
        UNUserNotificationCenter.current().add(request) { error in
            if let error {
                self.logger.error("Failed to schedule Watch notification: \(error.localizedDescription)")
            }
        }
    }
}

// MARK: - UNUserNotificationCenterDelegate

extension WatchSessionManager: UNUserNotificationCenterDelegate {
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        // 即使 app 在前台也显示通知（确保震动）
        [.sound, .banner]
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse) async {
        let userInfo = response.notification.request.content.userInfo
        guard let requestID = userInfo["requestID"] as? String else { return }

        switch response.actionIdentifier {
        case "ALLOW":
            resolve(requestID: requestID, action: "allow")
        case "DENY":
            resolve(requestID: requestID, action: "deny")
        case UNNotificationDefaultActionIdentifier:
            // 用户点击了通知本体，打开 app 显示详情
            break
        default:
            break
        }
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
