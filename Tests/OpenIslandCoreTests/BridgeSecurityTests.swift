import Darwin
import Foundation
import Testing
@testable import OpenIslandCore

struct BridgeSecurityTests {
    @Test func socketIsPrivateAndRefusesSymlinksAndFiles() throws {
        let url = BridgeSocketLocation.uniqueTestURL()
        defer { try? FileManager.default.removeItem(at: url) }
        try Data("keep".utf8).write(to: url)
        #expect(throws: (any Error).self) { try BridgeSocketSecurity.listen(at: url) }
        #expect(try Data(contentsOf: url) == Data("keep".utf8))
        try FileManager.default.removeItem(at: url)
        try FileManager.default.createSymbolicLink(atPath: url.path, withDestinationPath: "/tmp/absent-open-island-target")
        #expect(throws: (any Error).self) { try BridgeSocketSecurity.listen(at: url) }
        try FileManager.default.removeItem(at: url)
        let descriptor = try BridgeSocketSecurity.listen(at: url)
        defer { close(descriptor) }
        var attributes = stat()
        #expect(lstat(url.path, &attributes) == 0)
        #expect(attributes.st_mode & 0o777 == 0o600)
        #expect(attributes.st_uid == geteuid())
        #expect(!BridgeSocketSecurity.isCurrentUser(-1))
    }

    @Test func socketCannotApproveEvenWhenRegisteredAsObserver() async throws {
        let url = BridgeSocketLocation.uniqueTestURL()
        let server = BridgeServer(socketURL: url)
        try server.start()
        defer { server.stop(); try? FileManager.default.removeItem(at: url) }
        let observer = LocalBridgeClient(socketURL: url)
        let stream = try observer.connect()
        defer { observer.disconnect() }
        try await observer.send(.registerClient(role: .observer))
        let events = SecurityRecorder<AgentEvent>()
        let reader = Task { for try await event in stream { events.append(event) } }
        defer { reader.cancel() }
        let responses = SecurityRecorder<BridgeResponse>()
        let hook = Task { try await sendSecurityHook(url: url, responses: responses) }
        try await securityWait { events.values.contains { if case .permissionRequested = $0 { true } else { false } } }
        try await observer.send(.resolvePermission(sessionID: "security-test", resolution: .allowOnce()))
        try await Task.sleep(for: .milliseconds(150))
        #expect(responses.values.isEmpty)
        server.performUserAction(.resolvePermission(sessionID: "security-test", resolution: .deny(message: "User denied")))
        try await hook.value
        #expect(responses.values == [.codexHookDirective(.permissionRequest(.deny(message: "User denied")))])
    }
}

private func sendSecurityHook(url: URL, responses: SecurityRecorder<BridgeResponse>) async throws {
    let payload = CodexHookPayload(
        cwd: "/tmp", hookEventName: .permissionRequest, model: "test", permissionMode: .default,
        sessionID: "security-test", transcriptPath: nil, turnID: "1", toolName: "apply_patch",
        toolUseID: "1", toolInput: CodexHookToolInput(description: "Security regression test")
    )
    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
        DispatchQueue.global().async {
            do {
                if let response = try BridgeCommandClient(socketURL: url).send(.processCodexHook(payload), timeout: 10) {
                    responses.append(response)
                }
                continuation.resume()
            } catch { continuation.resume(throwing: error) }
        }
    }
}
