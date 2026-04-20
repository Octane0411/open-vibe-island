import Darwin
import Foundation
import Testing
@testable import OpenIslandCore

struct ClaudeHookPayloadPIDTests {
    @Test
    func agentPIDRoundTripsThroughJSON() throws {
        let payload = ClaudeHookPayload(
            cwd: "/tmp/demo",
            hookEventName: .sessionStart,
            sessionID: "s1",
            agentPID: 12_345
        )

        let encoded = try JSONEncoder().encode(payload)
        let object = try JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        #expect(object?["agent_pid"] as? Int == 12_345)

        let decoded = try JSONDecoder().decode(ClaudeHookPayload.self, from: encoded)
        #expect(decoded.agentPID == 12_345)
    }

    @Test
    func legacyPayloadWithoutAgentPIDDecodesAsNil() throws {
        let json = """
        {
            "cwd": "/tmp/demo",
            "hook_event_name": "SessionStart",
            "session_id": "legacy-1",
            "source": "startup"
        }
        """
        let data = Data(json.utf8)

        let decoded = try JSONDecoder().decode(ClaudeHookPayload.self, from: data)
        #expect(decoded.agentPID == nil)
        #expect(decoded.sessionID == "legacy-1")
        #expect(decoded.hookEventName == .sessionStart)
    }

    @Test
    func withRuntimeContextPopulatesAgentPIDFromGetppid() {
        let payload = ClaudeHookPayload(
            cwd: "/tmp/demo",
            hookEventName: .sessionStart,
            sessionID: "s1"
        ).withRuntimeContext(
            environment: [:],
            currentTTYProvider: { nil },
            terminalLocatorProvider: { _ in (sessionID: nil, tty: nil, title: nil) },
            warpPaneResolver: { _ in nil }
        )

        let pid = try? #require(payload.agentPID)
        #expect((pid ?? 0) > 1)
        #expect(payload.agentPID == getppid())
    }

    @Test
    func withRuntimeContextDoesNotOverrideExistingAgentPID() {
        let payload = ClaudeHookPayload(
            cwd: "/tmp/demo",
            hookEventName: .sessionStart,
            sessionID: "s1",
            agentPID: 999
        ).withRuntimeContext(
            environment: [:],
            currentTTYProvider: { nil },
            terminalLocatorProvider: { _ in (sessionID: nil, tty: nil, title: nil) },
            warpPaneResolver: { _ in nil }
        )

        #expect(payload.agentPID == 999)
    }
}
