import Foundation
import Testing
@testable import OpenIslandCore

/// End-to-end smoke: a real BridgeServer on a test socket receives events
/// produced by the real OpenIslandHooks CLI decoding real Hermes wire
/// payloads. The CLI is spawned as a subprocess with OPEN_ISLAND_SOCKET_PATH
/// pointing at the test socket, exactly like the installed hook runs.
struct HermesHookEndToEndTests {
    private var hookBinaryURL: URL {
        if let env = ProcessInfo.processInfo.environment["OPEN_ISLAND_HOOKS_BINARY"],
           FileManager.default.fileExists(atPath: env) {
            return URL(fileURLWithPath: env)
        }
        return URL(fileURLWithPath: ".build/debug/OpenIslandHooks")
    }

    private func runHook(_ json: String, socketPath: String) -> (exitCode: Int32, stdout: String, stderr: String) {
        let process = Process()
        process.executableURL = hookBinaryURL
        process.arguments = ["--source", "hermes"]
        process.environment = [
            "PATH": "/usr/bin:/bin:/usr/sbin:/sbin",
            "OPEN_ISLAND_SOCKET_PATH": socketPath,
        ]

        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        try? process.run()
        stdinPipe.fileHandleForWriting.write(Data(json.utf8))
        stdinPipe.fileHandleForWriting.closeFile()
        process.waitUntilExit()

        let stdout = String(decoding: stdoutPipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        let stderr = String(decoding: stderrPipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        return (process.terminationStatus, stdout, stderr)
    }

    private func waitForSession(_ sessionID: String, on server: BridgeServer, timeout: TimeInterval = 3) -> AgentSession? {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if let session = server.sessionStateSnapshotForTests().sessions.first(where: { $0.id == sessionID }) {
                return session
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }
        return server.sessionStateSnapshotForTests().sessions.first { $0.id == sessionID }
    }

    private func waitForSessionPhase(
        _ sessionID: String,
        _ phase: SessionPhase,
        on server: BridgeServer,
        timeout: TimeInterval = 3
    ) -> AgentSession? {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            let session = server.sessionStateSnapshotForTests().sessions.first { $0.id == sessionID }
            if session?.phase == phase {
                return session
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }
        return server.sessionStateSnapshotForTests().sessions.first { $0.id == sessionID }
    }

    @Test
    func hookBinaryDrivesSessionLifecycleOnRealBridge() throws {
        let binary = hookBinaryURL
        guard FileManager.default.isExecutableFile(atPath: binary.path) else {
            Issue.record("OpenIslandHooks binary not found at \(binary.path); build it first.")
            return
        }

        let socketURL = BridgeSocketLocation.uniqueTestURL()
        let server = BridgeServer(socketURL: socketURL)
        try server.start()
        defer { server.stop() }

        // 1. Session start creates a Hermes session.
        let start = """
        {"hook_event_name":"on_session_start","session_id":"e2e-hermes-1","cwd":"/tmp/e2e","extra":{"model":"glm-5.3","platform":"tui"}}
        """
        let startResult = runHook(start, socketPath: socketURL.path)
        #expect(startResult.exitCode == 0)
        #expect(startResult.stdout.isEmpty)

        // 2. A completed turn surfaces the assistant response.
        let postLLM = """
        {"hook_event_name":"post_llm_call","session_id":"e2e-hermes-1","cwd":"/tmp/e2e","extra":{"user_message":"fix it","assistant_response":"Done.","model":"glm-5.3","platform":"tui"}}
        """
        let turnResult = runHook(postLLM, socketPath: socketURL.path)
        #expect(turnResult.exitCode == 0)
        #expect(turnResult.stdout.isEmpty)

        // 3. Session end closes it out.
        let end = """
        {"hook_event_name":"on_session_end","session_id":"e2e-hermes-1","cwd":"/tmp/e2e","extra":{"completed":true}}
        """
        let endResult = runHook(end, socketPath: socketURL.path)
        #expect(endResult.exitCode == 0)
        #expect(endResult.stdout.isEmpty)

        // Give the server a beat to apply the emitted events.
        let finished = try #require(waitForSessionPhase("e2e-hermes-1", .completed, on: server), "Hermes session was not completed on the bridge")
        #expect(finished.tool == .hermes)
    }

    @Test
    func hookBinarySurfacesClarifyQuestionOnRealBridge() throws {
        let binary = hookBinaryURL
        guard FileManager.default.isExecutableFile(atPath: binary.path) else {
            Issue.record("OpenIslandHooks binary not found at \(binary.path); build it first.")
            return
        }

        let socketURL = BridgeSocketLocation.uniqueTestURL()
        let server = BridgeServer(socketURL: socketURL)
        try server.start()
        defer { server.stop() }

        let clarify = """
        {"hook_event_name":"pre_tool_call","session_id":"e2e-hermes-hitl","cwd":"/tmp/e2e","tool_name":"clarify","tool_input":{"questions":[{"question":"Deploy where?","header":"env","options":[{"label":"QA","description":"qa cluster"},{"label":"PROD","description":"production"}]}]}}
        """
        let result = runHook(clarify, socketPath: socketURL.path)
        #expect(result.exitCode == 0)
        #expect(result.stdout.isEmpty)

        let hitl = try #require(waitForSessionPhase("e2e-hermes-hitl", .waitingForAnswer, on: server), "HITL session did not reach waitingForAnswer")
        #expect(hitl.tool == .hermes)
    }
}
