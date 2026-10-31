import Foundation
import Testing
@testable import OpenIslandCore

extension BridgeServer {
    /// Existing agent contract fixtures now exercise the trusted controller.
    /// Stale identity and socket authority are tested in BridgeDecisionSafetyTests.
    func decideCurrentRequestForTest(_ command: BridgeCommand) async throws {
        switch command {
        case let .resolvePermission(sessionID, resolution):
            let id = try #require(sessionStateSnapshotForTests().session(id: sessionID)?.permissionRequest?.id)
            _ = try await decide(.permission(sessionID: sessionID, requestID: id, resolution: resolution))
        case let .answerQuestion(sessionID, response):
            let id = try #require(sessionStateSnapshotForTests().session(id: sessionID)?.questionPrompt?.id)
            _ = try await decide(.question(sessionID: sessionID, requestID: id, response: response))
        default: Issue.record("Expected a decision command")
        }
    }
}

/// Blocking hook clients must not occupy Swift's cooperative task threads:
/// the controller under test needs those threads to deliver their decisions.
func sendBridgeCommandOffExecutor(
    _ command: BridgeCommand,
    socketURL: URL,
    timeout: TimeInterval = 3
) async throws -> BridgeResponse? {
    try await withCheckedThrowingContinuation { continuation in
        DispatchQueue.global().async {
            continuation.resume(with: Result {
                try BridgeCommandClient(socketURL: socketURL).send(command, timeout: timeout)
            })
        }
    }
}
