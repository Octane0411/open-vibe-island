import Darwin
import Foundation
import Testing
@testable import OpenIslandCore

struct DSHFocusClientTests {
    @Test
    func privateSocketCarriesOnlyExactSessionSelector() throws {
        let peer = try FocusPeer()
        defer { peer.stop() }
        peer.respond(with: Data("{\"ok\":true}\n".utf8))
        let id = "chat\"\n日本"
        try DSHFocusClient.focus(DSHWebJumpTarget(sessionID: id, origin: "http://127.0.0.1:3080/", focusSocketPath: peer.socketURL.path), timeout: 1)
        let request = try #require(peer.receivedRequest())
        let decoded = try #require(JSONSerialization.jsonObject(with: request) as? [String: String])
        #expect(decoded == ["session_id": id])
    }

    @Test(arguments: ["rejected", "malformed", "oversized", "silent"])
    func rejectsBadOrUnresponsivePeers(kind: String) throws {
        let peer = try FocusPeer()
        defer { peer.stop() }
        let expected: DSHFocusError
        switch kind {
        case "rejected":
            peer.respond(with: Data("{\"ok\":false,\"error\":\"no-client\"}\n".utf8))
            expected = .rejected("no-client")
        case "malformed":
            peer.respond(with: Data("{\"ok\":\"yes\"}\n".utf8))
            expected = .malformedResponse
        case "oversized":
            peer.respond(with: Data((String(repeating: "x", count: 8193) + "\n").utf8))
            expected = .malformedResponse
        default:
            peer.respond(with: nil)
            expected = .timedOut
        }
        let target = DSHWebJumpTarget(sessionID: "session", origin: "http://127.0.0.1:3080/", focusSocketPath: peer.socketURL.path)
        let timeout: TimeInterval = kind == "silent" ? 0.1 : 2
        #expect(throws: expected) { try DSHFocusClient.focus(target, timeout: timeout) }
    }

    @Test
    func endpointValidationRejectsPublicOrRedirectedPaths() throws {
        let peer = try FocusPeer()
        defer { peer.stop() }
        try DSHFocusClient.validateEndpoint(peer.socketURL.path)
        #expect(chmod(peer.socketURL.path, 0o666) == 0)
        #expect(throws: DSHFocusError.unsafeEndpoint) { try DSHFocusClient.validateEndpoint(peer.socketURL.path) }
        #expect(chmod(peer.socketURL.path, 0o600) == 0)
        #expect(chmod(peer.directoryURL.path, 0o755) == 0)
        #expect(throws: DSHFocusError.unsafeEndpoint) { try DSHFocusClient.validateEndpoint(peer.socketURL.path) }
        #expect(chmod(peer.directoryURL.path, 0o700) == 0)
        let redirected = URL(fileURLWithPath: "/tmp/oi-dsh-focus-\(UUID().uuidString.prefix(12))", isDirectory: true)
        try FileManager.default.createDirectory(at: redirected, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: redirected) }
        let link = redirected.appendingPathComponent("focus.sock")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: peer.socketURL)
        #expect(throws: DSHFocusError.unsafeEndpoint) { try DSHFocusClient.validateEndpoint(link.path) }
        #expect(throws: DSHFocusError.unsafeEndpoint) { try DSHFocusClient.validateEndpoint("/tmp/../etc/focus.sock") }
    }

    @Test
    func heartbeatAdoptsLateFocusEndpointWithoutChangingConversationPresentation() throws {
        let timestamp = Date(timeIntervalSince1970: 1000)
        var state = SessionState()
        state.apply(.sessionStarted(SessionStarted(
            sessionID: "chat", title: "DSH", tool: .dsh, origin: .live,
            initialPhase: .running, summary: "Working", timestamp: timestamp,
            jumpTarget: JumpTarget(terminalApp: "DSH Web", workspaceName: "project", paneTitle: "DSH"),
            piMetadata: PiSessionMetadata(currentTool: "read")
        )))
        let updated = DSHHookPayload(hookEventName: .heartbeat, sessionID: "chat", cwd: "/tmp/project", webOrigin: "http://127.0.0.1:3080/", webFocusSocket: "/tmp/oi-dsh-focus-new/focus.sock")
        let recovery = SessionStarted(sessionID: "chat", title: "DSH", tool: .dsh, origin: .live, initialPhase: .completed, summary: "Idle", timestamp: timestamp.addingTimeInterval(5), jumpTarget: updated.defaultJumpTarget)
        state.apply(.sessionHeartbeat(SessionHeartbeat(sessionID: "chat", timestamp: timestamp.addingTimeInterval(5), recoverySession: recovery)))
        let session = try #require(state.session(id: "chat"))
        #expect(session.jumpTarget?.dshWeb == updated.defaultJumpTarget.dshWeb)
        #expect(session.phase == .running)
        #expect(session.summary == "Working")
        #expect(session.piMetadata?.currentTool == "read")
        #expect(session.updatedAt == timestamp)
        var missing = recovery
        missing.jumpTarget = JumpTarget(terminalApp: "DSH Web", workspaceName: "project", paneTitle: "DSH")
        state.apply(.sessionHeartbeat(SessionHeartbeat(sessionID: "chat", timestamp: timestamp.addingTimeInterval(6), recoverySession: missing)))
        #expect(state.session(id: "chat")?.jumpTarget?.dshWeb == updated.defaultJumpTarget.dshWeb)
        var refreshed = recovery
        refreshed.jumpTarget?.dshWeb?.focusSocketPath = "/tmp/oi-dsh-focus-restarted/focus.sock"
        state.apply(.sessionHeartbeat(SessionHeartbeat(sessionID: "chat", timestamp: timestamp.addingTimeInterval(7), recoverySession: refreshed)))
        #expect(state.session(id: "chat")?.jumpTarget?.dshWeb?.focusSocketPath == "/tmp/oi-dsh-focus-restarted/focus.sock")
        #expect(state.session(id: "chat")?.updatedAt == timestamp)
    }

    @Test
    func dshPayloadSpecializesRuntimeJumpTargetAndPreservesLegacyRegistryCompatibility() throws {
        let payload: any RuntimeHookPayload = DSHHookPayload(
            hookEventName: .sessionStart, sessionID: "dsh-chat", cwd: "/tmp/project",
            webOrigin: "http://127.0.0.1:3080/", webFocusSocket: "/tmp/oi-dsh-focus-test/focus.sock"
        )
        let target = payload.defaultJumpTarget
        #expect(target.terminalApp == "DSH Web")
        #expect(target.dshWeb?.sessionID == "dsh-chat")
        #expect(target.terminalTTY == nil)
        let session = AgentSession(id: "dsh-chat", title: "DSH", tool: .dsh, phase: .running, summary: "Working", updatedAt: .now, jumpTarget: target)
        let record = PiTrackedSessionRecord(session: session)
        let restored = try JSONDecoder().decode(PiTrackedSessionRecord.self, from: JSONEncoder().encode(record))
        #expect(restored.jumpTarget?.dshWeb == target.dshWeb)
        let legacy = Data("{\"terminalApp\":\"Ghostty\",\"workspaceName\":\"project\",\"paneTitle\":\"chat\"}".utf8)
        #expect(try JSONDecoder().decode(JumpTarget.self, from: legacy).dshWeb == nil)
    }
}

private final class FocusPeer: @unchecked Sendable {
    let directoryURL: URL
    let socketURL: URL
    private let fd: Int32
    private let completed = DispatchGroup()
    private let lock = NSLock()
    private var request: Data?

    init() throws {
        directoryURL = URL(fileURLWithPath: "/tmp/oi-dsh-focus-\(UUID().uuidString.prefix(12))", isDirectory: true)
        socketURL = directoryURL.appendingPathComponent("focus.sock")
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw DSHFocusError.unavailable }
        let bound = try withUnixSocketAddress(path: socketURL.path) { bind(fd, $0, $1) }
        guard bound == 0, chmod(socketURL.path, 0o600) == 0, listen(fd, 1) == 0 else {
            throw DSHFocusError.unavailable
        }
    }

    func respond(with data: Data?) {
        completed.enter()
        DispatchQueue.global().async { [self] in
            defer { completed.leave() }
            var ready = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
            guard poll(&ready, 1, 2000) > 0 else { return }
            let client = accept(fd, nil, nil)
            guard client >= 0 else { return }
            defer { close(client) }
            try? disableSocketSigPipe(client)
            var buffer = [UInt8](repeating: 0, count: 8192)
            let count = read(client, &buffer, buffer.count)
            if count > 0 {
                lock.lock()
                request = Data(buffer.prefix(count))
                lock.unlock()
            }
            if let data {
                try? writeAll(data, to: client)
            } else {
                var closed = pollfd(fd: client, events: Int16(POLLIN), revents: 0)
                _ = poll(&closed, 1, 500)
            }
        }
    }

    func receivedRequest() -> Data? {
        _ = completed.wait(timeout: .now() + 2)
        lock.lock()
        defer { lock.unlock() }
        return request
    }

    func stop() {
        guard completed.wait(timeout: .now() + 3) == .success else {
            Issue.record("Focus peer did not stop before cleanup")
            return
        }
        close(fd)
        precondition(directoryURL.path.hasPrefix("/tmp/oi-dsh-focus-"))
        try? FileManager.default.removeItem(at: directoryURL)
    }
}
