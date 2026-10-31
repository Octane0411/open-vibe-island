import Foundation

/// Available only to the app that owns BridgeServer, never a socket command.
public enum BridgeDecision: Equatable, Sendable {
    case permission(sessionID: String, requestID: UUID, resolution: PermissionResolution)
    case question(sessionID: String, requestID: UUID, response: QuestionPromptResponse)

    public var sessionID: String {
        switch self {
        case let .permission(id, _, _), let .question(id, _, _): id
        }
    }

    public var requestID: UUID {
        switch self {
        case let .permission(_, id, _), let .question(_, id, _): id
        }
    }
}

public enum BridgeDecisionOutcome: Equatable, Sendable {
    case accepted
    case alreadyAccepted
}

public enum BridgeDecisionError: Error, LocalizedError, Equatable {
    case expiredOrUnknown
    case mismatchedRequest
    case conflictingRetry
    case deliveryFailed

    public var errorDescription: String? {
        switch self {
        case .expiredOrUnknown: "This request expired or is no longer awaiting a decision."
        case .mismatchedRequest: "The decision does not match the displayed request."
        case .conflictingRetry: "This request already received a different decision."
        case .deliveryFailed: "The waiting agent disconnected before the decision could be delivered."
        }
    }
}
