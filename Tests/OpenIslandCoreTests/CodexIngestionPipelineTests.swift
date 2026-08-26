import Foundation
import Testing
@testable import OpenIslandCore

@Suite("Codex ingestion pipeline")
struct CodexIngestionPipelineTests {
    private func hookPayload(
        event: CodexHookEventName,
        sessionID: String = "S1",
        cwd: String = "/Users/dev/work/island",
        terminalApp: String? = "Ghostty",
        toolName: String? = nil
    ) -> CodexHookPayload {
        CodexHookPayload(
            cwd: cwd,
            hookEventName: event,
            model: "gpt-5",
            permissionMode: .default,
            sessionID: sessionID,
            terminalApp: terminalApp,
            terminalSessionID: "term-1",
            terminalTTY: "/dev/ttys001",
            terminalTitle: "island",
            warpPaneUUID: nil,
            transcriptPath: "/tmp/rollout.jsonl",
            source: nil,
            turnID: "turn-1",
            toolName: toolName,
            toolUseID: toolName.map { _ in "tool-1" },
            toolInput: nil,
            toolResponse: nil,
            prompt: nil,
            stopHookActive: nil,
            lastAssistantMessage: nil
        )
    }

    @Test("shadow mode returns candidates but does not drive the UI")
    func shadowModeReturnsCandidates() {
        let pipeline = CodexIngestionPipeline(mode: .shadow)

        let events = pipeline.ingest(hook: hookPayload(event: .sessionStart))

        // The candidate events are returned so the caller can compare them
        // against the legacy path …
        #expect(!events.isEmpty)
        #expect(pipeline.store.session(for: "S1") != nil)
        // … and the caller is told not to apply them.
        #expect(!pipeline.drivesUI)
    }

    @Test("live mode drives the session list")
    func liveModeEmits() {
        let pipeline = CodexIngestionPipeline(mode: .live)
        #expect(pipeline.drivesUI)

        let events = pipeline.ingest(hook: hookPayload(event: .sessionStart))

        #expect(events.count == 1)
        guard case let .sessionStarted(started) = events.first else {
            Issue.record("expected sessionStarted")
            return
        }
        #expect(started.jumpTarget?.terminalApp == "Ghostty")
        #expect(started.jumpTarget?.workspaceName == "island")
    }

    @Test("off mode does no work at all")
    func offModeIsInert() {
        let pipeline = CodexIngestionPipeline(mode: .off)

        #expect(pipeline.ingest(hook: hookPayload(event: .sessionStart)).isEmpty)
        #expect(pipeline.store.session(for: "S1") == nil)
    }

    @Test("a hook delivery ends cold-start replay")
    func hookLeavesReplayMode() {
        let pipeline = CodexIngestionPipeline(mode: .live)
        #expect(pipeline.store.currentMode == .replaying)

        _ = pipeline.ingest(hook: hookPayload(event: .sessionStart))

        #expect(pipeline.store.currentMode == .live)
    }

    @Test("an approval flows end to end from a hook")
    func approvalFlows() {
        let pipeline = CodexIngestionPipeline(mode: .live)
        _ = pipeline.ingest(hook: hookPayload(event: .sessionStart))

        let events = pipeline.ingest(
            hook: hookPayload(event: .permissionRequest, toolName: "shell")
        )

        #expect(events.contains {
            if case .permissionRequested = $0 { return true }; return false
        })
    }

    @Test("a persisted record restores its terminal identity")
    func restoredRecordKeepsTerminal() {
        let pipeline = CodexIngestionPipeline(mode: .live)
        let record = CodexTrackedSessionRecord(
            sessionID: "S1",
            title: "Fix login",
            origin: .live,
            attachmentState: .stale,
            summary: "",
            phase: .completed,
            updatedAt: .now,
            jumpTarget: JumpTarget(
                terminalApp: "Ghostty",
                workspaceName: "island",
                paneTitle: "island",
                workingDirectory: "/Users/dev/work/island",
                terminalSessionID: "term-7",
                terminalTTY: "/dev/ttys004"
            ),
            codexMetadata: CodexSessionMetadata(transcriptPath: "/tmp/r.jsonl")
        )

        let events = pipeline.ingest(restored: record)

        guard case let .sessionStarted(started) = events.first else {
            Issue.record("expected sessionStarted, got \(events)")
            return
        }
        #expect(started.title == "Fix login")
        #expect(started.jumpTarget?.terminalApp == "Ghostty")
        #expect(started.jumpTarget?.terminalTTY == "/dev/ttys004")
        #expect(started.initialPhase == .completed)
        // Remembered data must not end cold-start replay.
        #expect(pipeline.store.currentMode == .replaying)
    }

    @Test("a transcript read after a persisted record cannot downgrade its terminal")
    func rolloutCannotDowngradeRestoredTerminal() {
        let pipeline = CodexIngestionPipeline(mode: .live)
        let record = CodexTrackedSessionRecord(
            sessionID: "aaaa",
            title: "Fix login",
            origin: .live,
            attachmentState: .stale,
            summary: "",
            phase: .completed,
            updatedAt: .now,
            jumpTarget: JumpTarget(
                terminalApp: "Ghostty", workspaceName: "island", paneTitle: "island",
                workingDirectory: "/Users/dev/work/island"
            )
        )
        _ = pipeline.ingest(restored: record)

        // The transcript for the same session, as cold start would read it.
        let lines = [
            #"{"type":"session_meta","timestamp":"2026-08-24T00:00:00Z","payload":{"id":"aaaa","cwd":"/Users/dev/work/island","originator":"codex-tui","cli_version":"9.9.9","source":"cli"}}"#
        ]
        let reading = pipeline.rollout.read(lines: lines, transcriptPath: "/tmp/x.jsonl")
        if let observation = reading.observation {
            _ = pipeline.projector.project(observation)
        }

        #expect(pipeline.store.session(for: "aaaa")?.placement?.value.terminalApp == "Ghostty")
    }

    @Test("a cold-start mismatch names the sessions that differ")
    func coldStartComparisonNamesIDs() {
        let pipeline = CodexIngestionPipeline(mode: .shadow)
        _ = pipeline.ingest(hook: hookPayload(event: .sessionStart, sessionID: "candidate-only-1"))

        pipeline.recordColdStartComparison(legacySessionIDs: ["legacy-only-1"])

        let report = pipeline.divergenceReport()
        #expect(report.count == 1)
        #expect(report[0].contains("legacy-o"))
        #expect(report[0].contains("candidat"))
    }

    @Test("identical event streams report no divergence")
    func matchingStreamsAgree() {
        let pipeline = CodexIngestionPipeline(mode: .shadow)
        let event = AgentEvent.activityUpdated(SessionActivityUpdated(
            sessionID: "S1", summary: "a", phase: .running, timestamp: .now
        ))
        // Wording and timestamps differ harmlessly between implementations, so
        // only perceivable fields are compared.
        let sameShapeDifferentWording = AgentEvent.activityUpdated(SessionActivityUpdated(
            sessionID: "S1", summary: "b", phase: .running, timestamp: .now.addingTimeInterval(5)
        ))

        pipeline.recordDivergence(legacy: [event], candidate: [sameShapeDifferentWording])

        #expect(pipeline.divergenceReport().isEmpty)
    }

    @Test("a differing phase is reported as divergence")
    func differingPhaseReported() {
        let pipeline = CodexIngestionPipeline(mode: .shadow)
        let legacy = AgentEvent.activityUpdated(SessionActivityUpdated(
            sessionID: "S1", summary: "a", phase: .running, timestamp: .now
        ))
        let candidate = AgentEvent.activityUpdated(SessionActivityUpdated(
            sessionID: "S1", summary: "a", phase: .completed, timestamp: .now
        ))

        pipeline.recordDivergence(legacy: [legacy], candidate: [candidate])

        let report = pipeline.divergenceReport()
        #expect(report.count == 1)
        #expect(report[0].contains("missing"))
        #expect(report[0].contains("extra"))
    }

    @Test("divergence recording is bounded")
    func divergenceIsBounded() {
        let pipeline = CodexIngestionPipeline(mode: .shadow)
        let legacy = AgentEvent.sessionCompleted(SessionCompleted(
            sessionID: "S1", summary: "", timestamp: .now, isInterrupt: nil, isSessionEnd: nil
        ))

        for _ in 0..<600 {
            pipeline.recordDivergence(legacy: [legacy], candidate: [])
        }

        // A systematic mismatch must not grow without limit.
        #expect(pipeline.divergenceReport().count == 500)
    }
}
