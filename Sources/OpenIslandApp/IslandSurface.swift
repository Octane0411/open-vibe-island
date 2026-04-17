import Foundation
import OpenIslandCore

enum IslandSurface: Equatable {
    case sessionList(actionableSessionID: String? = nil)
    case chat(sessionID: String)

    var sessionID: String? {
        switch self {
        case let .sessionList(actionableSessionID):
            actionableSessionID
        case let .chat(sessionID):
            sessionID
        }
    }

    var isNotificationCard: Bool {
        switch self {
        case .sessionList:
            return sessionID != nil
        case .chat:
            return false
        }
    }

    func autoDismissesWhenPresentedAsNotification(session: AgentSession?) -> Bool {
        switch self {
        case .sessionList:
            guard sessionID != nil else { return false }
            return session?.phase == .completed
        case .chat:
            return false
        }
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
        switch self {
        case .sessionList:
            guard sessionID != nil else {
                return true
            }

            guard let session else {
                return false
            }

            switch session.phase {
            case .waitingForApproval:
                return session.permissionRequest != nil
            case .waitingForAnswer:
                return session.questionPrompt != nil
            case .completed:
                return true
            case .running:
                return false
            }
        case .chat:
            return true
        }
    }
}
