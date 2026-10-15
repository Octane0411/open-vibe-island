import Foundation
import Testing
@testable import OpenIslandCore

struct CodexInternalSessionFilterTests {
    @Test
    func onlyExplicitInternalReviewMetadataIsFiltered() {
        #expect(CodexInternalSessionFilter.isInternalReview(metadata: ["thread_source": "guardian_review"]))
        #expect(CodexInternalSessionFilter.isInternalReview(metadata: ["source": ["subagent": ["other": "guardian"]]]))
        #expect(!CodexInternalSessionFilter.isInternalReview(metadata: ["thread_source": "user", "source": "vscode"]))
        #expect(!CodexInternalSessionFilter.isInternalReview(metadata: ["source": ["subagent": ["thread_spawn": ["parent_thread_id": "parent"]]]]))
        #expect(!CodexInternalSessionFilter.isInternalReview(metadata: ["parent_thread_id": "parent"]))
        #expect(!CodexInternalSessionFilter.isInternalReview(metadata: [:]))
    }

    @Test
    func internalReviewsStayOutOfDiscoveryAndRestorationWhileUserCompactionRemains() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let variants: [(String, [String: Any], Bool)] = [
            ("review", ["thread_source": "guardian_review"], true),
            ("legacy-review", ["source": ["subagent": ["other": "guardian"]]], true),
            ("user", ["thread_source": "user", "source": "vscode"], false),
            ("worker", ["source": ["subagent": ["thread_spawn": ["parent_thread_id": "parent"]]]], false),
        ]
        for (id, source, hidden) in variants {
            var metadata: [String: Any] = ["id": id, "cwd": "/tmp/project"]
            metadata.merge(source) { _, new in new }
            let header = try JSONSerialization.data(withJSONObject: ["type": "session_meta", "payload": metadata])
            let file = root.appendingPathComponent("rollout-\(id).jsonl")
            var data = header
            data.append(Data("\n{\"type\":\"response_item\",\"payload\":{\"type\":\"compaction\"}}\n".utf8))
            try data.write(to: file)
            #expect(CodexInternalSessionFilter.isInternalReview(transcriptPath: file.path) == hidden)
            let record = CodexTrackedSessionRecord(
                sessionID: id, title: "/", origin: .live,
                summary: "Running context compaction.", phase: .running, updatedAt: .now,
                codexMetadata: CodexSessionMetadata(transcriptPath: file.path)
            )
            #expect(record.shouldRestoreToLiveState == !hidden)
        }
        let discovery = CodexRolloutDiscovery(rootURL: root)
        for _ in 0..<2 {
            let records = discovery.discoverRecentSessions()
            #expect(Set(records.map(\.sessionID)) == Set(["user", "worker"]))
            #expect(records.allSatisfy { $0.phase == .running })
        }
        // Appending to an ignored rollout must not reintroduce it on rescan.
        let handle = try FileHandle(forWritingTo: root.appendingPathComponent("rollout-review.jsonl"))
        try handle.seekToEnd()
        try handle.write(contentsOf: Data("{\"type\":\"event_msg\",\"payload\":{\"type\":\"task_started\"}}\n".utf8))
        try handle.close()
        #expect(Set(discovery.discoverRecentSessions().map(\.sessionID)) == Set(["user", "worker"]))
    }

    @Test
    func reviewHooksAreAcknowledgedWithoutCreatingSessions() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: file) }
        try Data("{\"type\":\"session_meta\",\"payload\":{\"thread_source\":\"guardian_review\"}}\n".utf8).write(to: file)
        let socket = BridgeSocketLocation.uniqueTestURL()
        let server = BridgeServer(socketURL: socket)
        try server.start()
        defer { server.stop() }
        let client = BridgeCommandClient(socketURL: socket)
        let payload = CodexHookPayload(
            cwd: "/tmp/project", hookEventName: .sessionStart, model: "test",
            permissionMode: .default, sessionID: "guardian", terminalApp: "Codex.app",
            transcriptPath: file.path
        )
        #expect(try client.send(.processCodexHook(payload)) == .acknowledged)
        #expect(server.sessionStateSnapshotForTests().sessions.isEmpty)
        try Data("{\"type\":\"session_meta\",\"payload\":{\"thread_source\":\"user\"}}\n".utf8).write(to: file)
        #expect(try client.send(.processCodexHook(payload)) == .acknowledged)
        #expect(server.sessionStateSnapshotForTests().sessions.count == 1)
    }

    @Test
    func unreadableOrIncompleteMetadataPreservesSessions() throws {
        #expect(!CodexInternalSessionFilter.isInternalReview(transcriptPath: nil))
        #expect(!CodexInternalSessionFilter.isInternalReview(transcriptPath: "/nonexistent/rollout.jsonl"))
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: file) }
        try Data("{\"type\":\"session_meta\",\"payload\":".utf8).write(to: file)
        #expect(!CodexInternalSessionFilter.isInternalReview(transcriptPath: file.path))
    }
}
