import Foundation
import OpenIslandCore

enum IslandSurface: Equatable {
    case sessionList(actionableSessionID: String? = nil, eventType: NotificationEventType? = nil)

    var sessionID: String? {
        switch self {
        case let .sessionList(actionableSessionID, _):
            actionableSessionID
        }
    }

    var eventType: NotificationEventType? {
        switch self {
        case let .sessionList(_, eventType):
            eventType
        }
    }

    var isNotificationCard: Bool {
        sessionID != nil
    }

    func autoDismissesWhenPresentedAsNotification(session: AgentSession?) -> Bool {
        guard sessionID != nil else { return false }
        // 只有会话完成时才自动关闭通知卡片
        // 正在运行的会话（有 pending 请求或问答）不自动关闭
        guard let session else { return false }
        if session.permissionRequest != nil || session.questionPrompt != nil {
            return false
        }
        return session.phase == .completed
    }

    static func notificationSurface(for event: AgentEvent) -> IslandSurface? {
        switch event {
        case let .permissionRequested(payload):
            .sessionList(actionableSessionID: payload.sessionID, eventType: .permission)
        case let .questionAsked(payload):
            .sessionList(actionableSessionID: payload.sessionID, eventType: .question)
        case let .sessionCompleted(payload):
            // Always show completion notification regardless of isInterrupt
            // This ensures consistent behavior when AI finishes answering
            .sessionList(actionableSessionID: payload.sessionID, eventType: .completion)
        default:
            nil
        }
    }

    func matchesCurrentState(of session: AgentSession?) -> Bool {
        guard sessionID != nil else {
            return true
        }

        guard let session else {
            return true
        }

        switch session.phase {
        case .waitingForApproval:
            return session.permissionRequest != nil
        case .waitingForAnswer:
            return session.questionPrompt != nil
        case .completed:
            return true
        case .running:
            // Keep running sessions visible - they should stay in the island
            // whether they have permission requests/questions or not
            return true
        }
    }
}
