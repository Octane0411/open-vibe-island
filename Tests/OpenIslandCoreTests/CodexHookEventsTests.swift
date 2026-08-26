import Foundation
import Testing
@testable import OpenIslandCore

/// The five lifecycle events added to the managed install. Each is pinned at
/// the two layers that consume it — payload decoding and the hook source —
/// because a miss at either leaves the island blind to that part of a session.
@Suite("Codex lifecycle hook events")
struct CodexHookEventsTests {
    private func decode(_ json: String) throws -> CodexHookPayload {
        try JSONDecoder().decode(CodexHookPayload.self, from: Data(json.utf8))
    }

    private func payload(
        _ event: CodexHookEventName,
        sessionID: String = "S1",
        extra: [String: Any] = [:]
    ) -> CodexHookPayload {
        var object: [String: Any] = [
            "session_id": sessionID,
            "hook_event_name": event.rawValue,
            "cwd": "/Users/dev/work/island",
            "model": "gpt-5",
            "permission_mode": "default",
            "terminal_app": "Ghostty",
            "transcript_path": "/tmp/rollout.jsonl",
        ]
        for (key, value) in extra { object[key] = value }
        let data = try! JSONSerialization.data(withJSONObject: object)
        return try! JSONDecoder().decode(CodexHookPayload.self, from: data)
    }

    // MARK: - Decoding

    @Test("SubagentStart decodes its agent identity")
    func subagentStartDecodes() throws {
        let decoded = payload(.subagentStart, extra: [
            "agent_id": "agent-7", "agent_type": "explorer", "turn_id": "t-1",
        ])
        #expect(decoded.hookEventName == .subagentStart)
        #expect(decoded.agentID == "agent-7")
        #expect(decoded.agentType == "explorer")
    }

    @Test("SessionEnd decodes its reason")
    func sessionEndDecodes() {
        let decoded = payload(.sessionEnd, extra: ["reason": "user_exit"])
        #expect(decoded.hookEventName == .sessionEnd)
        #expect(decoded.reason == "user_exit")
    }

    @Test("PreCompact decodes its trigger")
    func preCompactDecodes() {
        let decoded = payload(.preCompact, extra: ["trigger": "auto"])
        #expect(decoded.hookEventName == .preCompact)
        #expect(decoded.trigger == "auto")
    }

    @Test("the new fields are optional so older payloads still decode")
    func newFieldsAreOptional() {
        let decoded = payload(.stop)
        #expect(decoded.agentID == nil)
        #expect(decoded.agentType == nil)
        #expect(decoded.trigger == nil)
    }

    @Test("every event has an implicit summary")
    func everyEventHasSummary() {
        for event in [CodexHookEventName.sessionEnd, .subagentStart, .subagentStop, .turnStart, .preCompact] {
            #expect(!payload(event).implicitStartSummary.isEmpty, "\(event) has no summary")
        }
    }

    // MARK: - Hook source

    @Test("SessionEnd ends the session, where Stop only ends a turn")
    func sessionEndEndsLiveness() {
        let source = CodexHookSource()

        let stop = source.observe(payload(.stop))
        #expect(stop.patch.lifecycle?.phase == .completed)
        #expect(stop.patch.liveness == nil, "Stop must not decide liveness")

        let end = source.observe(payload(.sessionEnd, extra: ["reason": "user_exit"]))
        #expect(end.patch.liveness == CodexLiveness(state: .ended(reason: .sessionEnd)))
        #expect(end.patch.narrative?.activeSubagentCount == 0)
    }

    @Test("subagent boundaries produce a running total")
    func subagentCountIsAbsolute() {
        let source = CodexHookSource()

        let first = source.observe(payload(.subagentStart, extra: ["agent_id": "a"]))
        #expect(first.patch.narrative?.activeSubagentCount == 1)

        let second = source.observe(payload(.subagentStart, extra: ["agent_id": "b"]))
        #expect(second.patch.narrative?.activeSubagentCount == 2)

        let stop = source.observe(payload(.subagentStop, extra: ["agent_id": "a"]))
        #expect(stop.patch.narrative?.activeSubagentCount == 1)
    }

    @Test("subagent counts are tracked per session")
    func subagentCountIsPerSession() {
        let source = CodexHookSource()
        _ = source.observe(payload(.subagentStart, sessionID: "A"))
        _ = source.observe(payload(.subagentStart, sessionID: "A"))
        let other = source.observe(payload(.subagentStart, sessionID: "B"))
        #expect(other.patch.narrative?.activeSubagentCount == 1)
    }

    @Test("a stop with no prior start does not go negative")
    func subagentCountClampsAtZero() {
        let source = CodexHookSource()
        let stop = source.observe(payload(.subagentStop))
        #expect(stop.patch.narrative?.activeSubagentCount == 0)
    }

    @Test("PreCompact reads as activity with a named tool")
    func preCompactIsActivity() {
        let source = CodexHookSource()
        let observation = source.observe(payload(.preCompact, extra: ["trigger": "auto"]))
        #expect(observation.patch.lifecycle?.phase == .running)
        #expect(observation.patch.narrative?.currentTool == "Compacting context")
        #expect(observation.patch.narrative?.currentCommandPreview == "auto")
    }

    @Test("TurnStart marks the session running and clears any stale approval")
    func turnStartRuns() {
        let source = CodexHookSource()
        let observation = source.observe(payload(.turnStart, extra: ["turn_id": "t-9"]))
        #expect(observation.patch.lifecycle == CodexLifecycle(phase: .running, turnID: "t-9"))
        #expect(observation.patch.actionable == .cleared)
    }

    // MARK: - Installer

    @Test("the managed install registers every lifecycle event")
    func installerRegistersLifecycleEvents() throws {
        let mutation = try CodexHookInstaller.installHooksJSON(
            existingData: nil,
            hookCommand: "'/tmp/OpenIslandHooks'"
        )
        let contents = try #require(mutation.contents)
        let object = try #require(JSONSerialization.jsonObject(with: contents) as? [String: Any])
        let hooks = try #require(object["hooks"] as? [String: Any])
        let registered = Set(hooks.keys)

        // Per-command hooks stay out on purpose (terminal spam); everything
        // that fires a handful of times per session is in.
        let expected: Set<String> = [
            "SessionStart", "SessionEnd", "UserPromptSubmit", "TurnStart",
            "PermissionRequest", "SubagentStart", "SubagentStop", "PreCompact", "Stop",
        ]
        #expect(registered == expected, "registered: \(registered.sorted())")
        #expect(!registered.contains("PreToolUse"))
        #expect(!registered.contains("PostToolUse"))
    }

    // MARK: - Pipeline

    @Test("the subagent count reaches session metadata end to end")
    func subagentCountReachesMetadata() {
        let pipeline = CodexIngestionPipeline(mode: .live)
        _ = pipeline.ingest(hook: payload(.sessionStart))
        _ = pipeline.ingest(hook: payload(.subagentStart, extra: ["agent_id": "a"]))
        let events = pipeline.ingest(hook: payload(.subagentStart, extra: ["agent_id": "b"]))

        let metadata = events.compactMap { event -> CodexSessionMetadata? in
            if case let .sessionMetadataUpdated(update) = event { return update.codexMetadata }
            return nil
        }.last
        #expect(metadata?.activeSubagentCount == 2)
    }

    @Test("SessionEnd completes the session through the pipeline")
    func sessionEndCompletesThroughPipeline() {
        let pipeline = CodexIngestionPipeline(mode: .live)
        _ = pipeline.ingest(hook: payload(.sessionStart))
        let events = pipeline.ingest(hook: payload(.sessionEnd, extra: ["reason": "user_exit"]))

        let completed = events.contains { event in
            if case let .sessionCompleted(payload) = event { return payload.isSessionEnd == true }
            return false
        }
        #expect(completed)
    }
}
