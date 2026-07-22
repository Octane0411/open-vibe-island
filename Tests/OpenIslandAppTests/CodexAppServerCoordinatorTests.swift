import Foundation
import Testing
@testable import OpenIslandApp
import OpenIslandCore

struct CodexAppServerCoordinatorTests {
    @MainActor
    @Test
    func threadStartUsesPersistedTitleWhenAppServerOmitsName() throws {
        let coordinator = CodexAppServerCoordinator()
        var events: [AgentEvent] = []
        coordinator.onEvent = { events.append($0) }
        coordinator.persistedThreadTitle = { threadID in
            threadID == "codex-thread-1" ? "查找 VibeIsland 项目" : nil
        }

        let thread = try JSONDecoder().decode(CodexThread.self, from: Data("""
        {
          "id": "codex-thread-1",
          "cwd": "/tmp/git",
          "name": null,
          "preview": "Find the project.",
          "modelProvider": "openai",
          "createdAt": 1,
          "updatedAt": 2,
          "ephemeral": false,
          "path": "/tmp/rollout.jsonl",
          "status": {"type": "active", "activeFlags": []},
          "source": "app-server",
          "turns": []
        }
        """.utf8))

        coordinator.handleNotification(.threadStarted(thread: thread))

        guard case let .sessionStarted(payload) = events.first else {
            Issue.record("Expected a session start")
            return
        }
        #expect(payload.title == "查找 VibeIsland 项目")
        #expect(payload.jumpTarget?.paneTitle == "查找 VibeIsland 项目")
        #expect(payload.jumpTarget?.codexThreadID == "codex-thread-1")
    }

    @MainActor
    @Test
    func trackedProjectThreadReceivesNameAndConfigurationWithoutRestartingSession() throws {
        let coordinator = CodexAppServerCoordinator()
        var events: [AgentEvent] = []
        coordinator.onEvent = { events.append($0) }
        coordinator.isSessionTracked = { $0 == "codex-thread-1" }
        coordinator.existingCodexMetadata = { _ in
            CodexSessionMetadata(initialUserPrompt: "Keep this prompt")
        }
        coordinator.existingJumpTarget = { _ in nil }
        coordinator.persistedThreadConfiguration = { _ in
            CodexSessionMetadata(model: "gpt-5.6-sol", reasoningEffort: "high", serviceTier: "priority")
        }

        let thread = try JSONDecoder().decode(CodexThread.self, from: Data("""
        {"id":"codex-thread-1","cwd":"/tmp/git","name":"查找 VibeIsland 项目","preview":"Prompt","modelProvider":"openai","createdAt":1,"updatedAt":2,"ephemeral":false,"path":"/tmp/rollout.jsonl","status":{"type":"notLoaded"},"source":"app-server","turns":[]}
        """.utf8))

        coordinator.syncThreads([thread])

        #expect(events.contains { if case .sessionTitleUpdated = $0 { true } else { false } })
        guard let jumpEvent = events.first(where: {
            if case .jumpTargetUpdated = $0 { true } else { false }
        }), case let .jumpTargetUpdated(jumpPayload) = jumpEvent else {
            Issue.record("Expected a direct Codex jump target")
            return
        }
        #expect(jumpPayload.jumpTarget.codexThreadID == "codex-thread-1")
        #expect(jumpPayload.jumpTarget.workingDirectory == "/tmp/git")
        guard let metadataEvent = events.first(where: {
            if case .sessionMetadataUpdated = $0 { true } else { false }
        }), case let .sessionMetadataUpdated(payload) = metadataEvent else {
            Issue.record("Expected a metadata update")
            return
        }
        #expect(payload.codexMetadata.initialUserPrompt == "Keep this prompt")
        #expect(payload.codexMetadata.model == "gpt-5.6-sol")
        #expect(payload.codexMetadata.reasoningEffort == "high")
        #expect(payload.codexMetadata.serviceTier == "priority")
        #expect(!events.contains { if case .sessionStarted = $0 { true } else { false } })
    }

    @MainActor
    @Test
    func threadNameNotificationEmitsTitleUpdate() {
        let coordinator = CodexAppServerCoordinator()
        var events: [AgentEvent] = []
        coordinator.onEvent = { events.append($0) }

        coordinator.handleNotification(
            .threadNameUpdated(
                threadId: "codex-thread-1",
                name: "Fix Open Island task titles"
            )
        )

        #expect(events.count == 1)
        guard case let .sessionTitleUpdated(payload) = events.first else {
            Issue.record("Expected a session title update")
            return
        }
        #expect(payload.sessionID == "codex-thread-1")
        #expect(payload.title == "Fix Open Island task titles")
    }

    @MainActor
    @Test
    func blankThreadNameNotificationIsIgnored() {
        let coordinator = CodexAppServerCoordinator()
        var events: [AgentEvent] = []
        coordinator.onEvent = { events.append($0) }

        coordinator.handleNotification(
            .threadNameUpdated(threadId: "codex-thread-1", name: "  ")
        )

        #expect(events.isEmpty)
    }
}
