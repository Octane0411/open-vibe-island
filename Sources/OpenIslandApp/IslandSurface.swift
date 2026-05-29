import Foundation
import OpenIslandCore

enum IslandSurface: Equatable {
    case sessionList(actionableSessionID: String? = nil)

    var sessionID: String? {
        switch self {
        case let .sessionList(actionableSessionID):
            actionableSessionID
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
            .sessionList(actionableSessionID: payload.sessionID)
        case let .questionAsked(payload):
            .sessionList(actionableSessionID: payload.sessionID)
        case let .sessionCompleted(payload):
            payload.isInterrupt == true ? nil : .sessionList(actionableSessionID: payload.sessionID)
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
            return session.permissionRequest != nil || session.questionPrompt != nil
        }
    }
}
