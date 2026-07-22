import Foundation
import Testing
@testable import OpenIslandApp
import OpenIslandCore

struct CodexAppServerCoordinatorTests {
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
