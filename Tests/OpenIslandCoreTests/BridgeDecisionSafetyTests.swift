import Foundation
import Testing
@testable import OpenIslandCore

struct BridgeDecisionSafetyTests {
    @Test
    func decisionsRequireExactIdentityAndCannotBeSentOverTheSocket() async throws {
        let socket = BridgeSocketLocation.uniqueTestURL()
        let server = BridgeServer(socketURL: socket)
        try server.start()
        defer { server.stop(); try? FileManager.default.removeItem(at: socket) }
        let waiter = Task.detached { try BridgeCommandClient(socketURL: socket).send(.processCodexHook(Self.payload("one")), timeout: 3) }
        let request = try await permission(on: server, sessionID: "one")
        let decision = BridgeDecision.permission(sessionID: "one", requestID: request.id, resolution: .allowOnce())

        #expect(try BridgeCommandClient(socketURL: socket).send(.resolvePermission(sessionID: "one", resolution: .allowOnce())) == .commandRejected(reason: "Decisions require the in-process controller."))
        await #expect(throws: BridgeDecisionError.self) {
            try await server.decide(.permission(sessionID: "one", requestID: UUID(), resolution: .allowOnce()))
        }
        await #expect(throws: BridgeDecisionError.self) {
            try await server.decide(.permission(sessionID: "wrong", requestID: request.id, resolution: .allowOnce()))
        }
        await #expect(throws: BridgeDecisionError.self) {
            try await server.decide(.question(sessionID: "one", requestID: request.id, response: .init(answer: "Wrong kind")))
        }
        #expect(server.sessionStateSnapshotForTests().session(id: "one")?.permissionRequest?.id == request.id)
        #expect(try await server.decide(decision) == .accepted)
        #expect(try await waiter.value == .codexHookDirective(.permissionRequest(.allow)))
        #expect(try await server.decide(decision) == .alreadyAccepted)
        await #expect(throws: BridgeDecisionError.self) {
            try await server.decide(.permission(sessionID: "one", requestID: request.id, resolution: .deny()))
        }
        let nextWaiter = Task.detached { try BridgeCommandClient(socketURL: socket).send(.processCodexHook(Self.payload("one")), timeout: 3) }
        let nextRequest = try await permission(on: server, sessionID: "one")
        #expect(nextRequest.id != request.id)
        #expect(try await server.decide(decision) == .alreadyAccepted)
        #expect(server.sessionStateSnapshotForTests().session(id: "one")?.permissionRequest?.id == nextRequest.id)
        _ = try await server.decide(.permission(sessionID: "one", requestID: nextRequest.id, resolution: .deny()))
        _ = try await nextWaiter.value
    }

    @Test
    func expiredRequestsReleaseTheirWaiterAndCannotBeApprovedLater() async throws {
        let socket = BridgeSocketLocation.uniqueTestURL()
        let clock = DecisionTestClock()
        let server = BridgeServer(socketURL: socket, decisionLifetime: 0.1, decisionClock: { clock.now })
        try server.start()
        defer { server.stop(); try? FileManager.default.removeItem(at: socket) }
        let waiter = Task.detached { try BridgeCommandClient(socketURL: socket).send(.processCodexHook(Self.payload("expired")), timeout: 2) }
        let request = try await permission(on: server, sessionID: "expired")
        clock.advance()
        guard case .codexHookDirective(.permissionRequest(.deny))? = try await waiter.value else {
            Issue.record("Expiration must explicitly deny and release the waiting hook")
            return
        }
        await #expect(throws: BridgeDecisionError.self) {
            try await server.decide(.permission(sessionID: "expired", requestID: request.id, resolution: .allowOnce()))
        }
        #expect(server.sessionStateSnapshotForTests().session(id: "expired")?.permissionRequest == nil)
    }

    @Test
    func competingRequestsAreRejectedWithoutReplacingTheOriginalWaiter() async throws {
        let socket = BridgeSocketLocation.uniqueTestURL()
        let server = BridgeServer(socketURL: socket)
        try server.start()
        defer { server.stop(); try? FileManager.default.removeItem(at: socket) }
        let first = Task.detached { try BridgeCommandClient(socketURL: socket).send(.processCodexHook(Self.payload("shared")), timeout: 3) }
        let request = try await permission(on: server, sessionID: "shared")
        let second = try BridgeCommandClient(socketURL: socket).send(.processCodexHook(Self.payload("shared")), timeout: 1)
        guard case .codexHookDirective(.permissionRequest(.deny))? = second else {
            Issue.record("A competing request must receive an explicit denial")
            return
        }
        #expect(server.sessionStateSnapshotForTests().session(id: "shared")?.permissionRequest?.id == request.id)
        _ = try await server.decide(.permission(sessionID: "shared", requestID: request.id, resolution: .allowOnce()))
        #expect(try await first.value == .codexHookDirective(.permissionRequest(.allow)))
    }

    private static func payload(_ sessionID: String) -> CodexHookPayload {
        CodexHookPayload(cwd: "/tmp", hookEventName: .permissionRequest, model: "test",
                         permissionMode: .default, sessionID: sessionID, transcriptPath: nil)
    }

    private func permission(on server: BridgeServer, sessionID: String) async throws -> PermissionRequest {
        let deadline = ContinuousClock.now + .seconds(1)
        while ContinuousClock.now < deadline {
            if let request = server.sessionStateSnapshotForTests().session(id: sessionID)?.permissionRequest { return request }
            try await Task.sleep(for: .milliseconds(2))
        }
        return try #require(server.sessionStateSnapshotForTests().session(id: sessionID)?.permissionRequest)
    }
}

private final class DecisionTestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var value: TimeInterval = 100
    var now: TimeInterval { lock.withLock { value } }
    func advance() { lock.withLock { value += 1 } }
}
