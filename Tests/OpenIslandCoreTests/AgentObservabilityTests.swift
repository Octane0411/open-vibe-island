import Foundation
import Testing
@testable import OpenIslandCore

struct AgentObservabilityTests {
    @Test
    func reducerBuildsSessionTimelineAndMetrics() {
        let startedAt = Date(timeIntervalSince1970: 10_000)
        var state = SessionState()

        state.apply(
            .sessionStarted(
                SessionStarted(
                    sessionID: "observed-session",
                    title: "Observed session",
                    tool: .codex,
                    summary: "Starting",
                    timestamp: startedAt
                )
            )
        )
        state.apply(
            .sessionMetadataUpdated(
                SessionMetadataUpdated(
                    sessionID: "observed-session",
                    codexMetadata: CodexSessionMetadata(
                        currentTool: "exec_command",
                        currentCommandPreview: "swift test"
                    ),
                    timestamp: startedAt.addingTimeInterval(2)
                )
            )
        )
        state.apply(
            .permissionRequested(
                PermissionRequested(
                    sessionID: "observed-session",
                    request: PermissionRequest(
                        title: "Run command",
                        summary: "Needs permission",
                        affectedPath: "/tmp/worktree",
                        toolName: "exec_command"
                    ),
                    timestamp: startedAt.addingTimeInterval(4)
                )
            )
        )
        state.apply(
            .actionableStateResolved(
                ActionableStateResolved(
                    sessionID: "observed-session",
                    summary: "Permission handled",
                    timestamp: startedAt.addingTimeInterval(6)
                )
            )
        )
        state.apply(
            .sessionCompleted(
                SessionCompleted(
                    sessionID: "observed-session",
                    summary: "Finished",
                    timestamp: startedAt.addingTimeInterval(10)
                )
            )
        )

        let observability = state.session(id: "observed-session")?.observability
        #expect(observability?.timeline.map(\.kind) == [
            .lifecycle,
            .tool,
            .permission,
            .status,
            .completion,
        ])
        #expect(observability?.metrics.eventCount == 5)
        #expect(observability?.metrics.toolEventCount == 1)
        #expect(observability?.metrics.attentionEventCount == 1)
        #expect(observability?.metrics.completionCount == 1)
        #expect(observability?.metrics.elapsed(at: startedAt.addingTimeInterval(10)) == 10)
    }

    @Test
    func repeatedMetadataDoesNotInflateMetrics() {
        let startedAt = Date(timeIntervalSince1970: 20_000)
        var state = SessionState()
        state.apply(
            .sessionStarted(
                SessionStarted(
                    sessionID: "deduplicated-session",
                    title: "Deduplicated session",
                    tool: .codex,
                    summary: "Starting",
                    timestamp: startedAt
                )
            )
        )

        for offset in [1.0, 2.0, 3.0] {
            state.apply(
                .sessionMetadataUpdated(
                    SessionMetadataUpdated(
                        sessionID: "deduplicated-session",
                        codexMetadata: CodexSessionMetadata(
                            currentTool: "exec_command",
                            currentCommandPreview: "swift test"
                        ),
                        timestamp: startedAt.addingTimeInterval(offset)
                    )
                )
            )
        }

        let observability = state.session(id: "deduplicated-session")?.observability
        #expect(observability?.metrics.eventCount == 2)
        #expect(observability?.metrics.toolEventCount == 1)
        #expect(observability?.timeline.last?.timestamp == startedAt.addingTimeInterval(3))
    }

    @Test
    func timelineIsBoundedWithoutLosingAggregateCount() {
        var observability = AgentSessionObservability()

        for index in 0..<4 {
            observability.record(
                AgentTimelineEvent(
                    timestamp: Date(timeIntervalSince1970: TimeInterval(index)),
                    kind: .status,
                    title: "Status \(index)"
                ),
                timelineLimit: 2
            )
        }

        #expect(observability.timeline.map(\.title) == ["Status 2", "Status 3"])
        #expect(observability.metrics.eventCount == 4)
    }

    @Test
    func observabilityPersistsThroughTrackedSessionRegistryRecord() throws {
        var observability = AgentSessionObservability()
        observability.record(
            AgentTimelineEvent(
                timestamp: Date(timeIntervalSince1970: 30_000),
                kind: .tool,
                title: "Using web scraper",
                toolName: "web_scraper"
            )
        )
        let session = AgentSession(
            id: "persisted-session",
            title: "Persisted session",
            tool: .codex,
            phase: .running,
            summary: "Collecting sources",
            updatedAt: Date(timeIntervalSince1970: 30_000),
            observability: observability
        )
        let record = CodexTrackedSessionRecord(session: session)

        let data = try JSONEncoder().encode(record)
        let decoded = try JSONDecoder().decode(CodexTrackedSessionRecord.self, from: data)

        #expect(decoded.session.observability == observability)
    }
}
