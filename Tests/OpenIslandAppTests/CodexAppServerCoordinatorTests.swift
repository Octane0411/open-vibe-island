import Foundation
import Testing
@testable import OpenIslandApp
import OpenIslandCore

struct CodexAppServerCoordinatorTests {
    @MainActor
    @Test
    func trackedDesktopThreadWithVSCodeSourceReceivesPersistedTitleAndJumpTarget() throws {
        let coordinator = CodexAppServerCoordinator()
        var events: [AgentEvent] = []
        coordinator.onEvent = { events.append($0) }
        coordinator.trackedRuntimeSurface = { threadID in
            threadID == "codex-thread-1" ? .desktopApp : nil
        }
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
          "source": "vscode",
          "turns": []
        }
        """.utf8))

        coordinator.handleNotification(.threadStarted(thread: thread))

        guard let titleEvent = events.first(where: {
            if case .sessionTitleUpdated = $0 { true } else { false }
        }), case let .sessionTitleUpdated(titlePayload) = titleEvent else {
            Issue.record("Expected a title update for the tracked Desktop thread")
            return
        }
        #expect(titlePayload.title == "查找 VibeIsland 项目")

        guard let jumpEvent = events.first(where: {
            if case .jumpTargetUpdated = $0 { true } else { false }
        }), case let .jumpTargetUpdated(jumpPayload) = jumpEvent else {
            Issue.record("Expected a Desktop jump target")
            return
        }
        #expect(jumpPayload.jumpTarget.paneTitle == "查找 VibeIsland 项目")
        #expect(jumpPayload.jumpTarget.codexThreadID == "codex-thread-1")
        #expect(!events.contains { if case .sessionStarted = $0 { true } else { false } })
    }

    @MainActor
    @Test
    func trackedProjectThreadReceivesNameAndConfigurationWithoutRestartingSession() throws {
        let coordinator = CodexAppServerCoordinator()
        var events: [AgentEvent] = []
        coordinator.onEvent = { events.append($0) }
        coordinator.trackedRuntimeSurface = { threadID in
            threadID == "codex-thread-1" ? .desktopApp : nil
        }
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
    func trackedExternalVSCodeThreadIsNotStampedAsCodexDesktop() throws {
        let coordinator = CodexAppServerCoordinator()
        var events: [AgentEvent] = []
        coordinator.onEvent = { events.append($0) }
        coordinator.trackedRuntimeSurface = { threadID in
            threadID == "codex-vscode-thread" ? .external : nil
        }

        let thread = try JSONDecoder().decode(CodexThread.self, from: Data("""
        {"id":"codex-vscode-thread","cwd":"/tmp/git","name":"VS Code task","preview":"Prompt","modelProvider":"openai","createdAt":1,"updatedAt":2,"ephemeral":false,"path":"/tmp/rollout.jsonl","status":{"type":"active","activeFlags":[]},"source":"vscode","turns":[]}
        """.utf8))

        coordinator.syncThreads([thread])

        #expect(!events.contains { if case .jumpTargetUpdated = $0 { true } else { false } })
        #expect(!events.contains { if case .sessionStarted = $0 { true } else { false } })
    }

    @MainActor
    @Test
    func trackedThreadWithUnknownOwnershipRequestsRolloutRediscovery() throws {
        let coordinator = CodexAppServerCoordinator()
        var events: [AgentEvent] = []
        var rediscoveryRequestCount = 0
        coordinator.onEvent = { events.append($0) }
        coordinator.trackedRuntimeSurface = { threadID in
            threadID == "codex-unknown-thread" ? .unknown : nil
        }
        coordinator.onRolloutRediscoveryNeeded = { rediscoveryRequestCount += 1 }

        let thread = try JSONDecoder().decode(CodexThread.self, from: Data("""
        {"id":"codex-unknown-thread","cwd":"/tmp/git","name":"Unclassified task","preview":"Prompt","modelProvider":"openai","createdAt":1,"updatedAt":2,"ephemeral":false,"path":"/tmp/rollout.jsonl","status":{"type":"active","activeFlags":[]},"source":"vscode","turns":[]}
        """.utf8))

        coordinator.syncThreads([thread])

        #expect(rediscoveryRequestCount == 1)
        #expect(!events.contains { if case .jumpTargetUpdated = $0 { true } else { false } })
        #expect(!events.contains { if case .sessionStarted = $0 { true } else { false } })
    }

    @MainActor
    @Test
    func untrackedVSCodeThreadListRequestsOneRolloutRediscovery() throws {
        let coordinator = CodexAppServerCoordinator()
        var events: [AgentEvent] = []
        var rediscoveryRequestCount = 0
        coordinator.onEvent = { events.append($0) }
        coordinator.onRolloutRediscoveryNeeded = { rediscoveryRequestCount += 1 }

        let thread = try JSONDecoder().decode(CodexThread.self, from: Data("""
        {"id":"untracked-desktop-thread","cwd":"/tmp/git","name":"Desktop task","preview":"Prompt","modelProvider":"openai","createdAt":1,"updatedAt":2,"ephemeral":false,"path":"/tmp/real-desktop-rollout.jsonl","status":{"type":"active","activeFlags":[]},"source":"vscode","turns":[]}
        """.utf8))
        let secondThread = try JSONDecoder().decode(CodexThread.self, from: Data("""
        {"id":"another-untracked-thread","cwd":"/tmp/other","name":"Another task","preview":"Prompt","modelProvider":"openai","createdAt":1,"updatedAt":2,"ephemeral":false,"path":"/tmp/another-rollout.jsonl","status":{"type":"notLoaded"},"source":"vscode","turns":[]}
        """.utf8))

        coordinator.syncThreads([thread, secondThread])

        #expect(rediscoveryRequestCount == 1)
        #expect(!events.contains { if case .sessionStarted = $0 { true } else { false } })
        #expect(!events.contains { if case .jumpTargetUpdated = $0 { true } else { false } })
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
