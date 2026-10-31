import Foundation
import Testing
import OpenIslandCore
@testable import OpenIslandApp

@MainActor
struct RestrictedCapabilityTests {
    @Test
    func savedEnablementCannotStartRestrictedCapabilities() {
        let environment = AppModelTestEnvironment()
        environment.defaults.set(true, forKey: "watch.notification.enabled")
        environment.defaults.set(true, forKey: "feature.completionReply.enabled")
        let model = environment.makeModel()
        #expect(!model.watchNotificationEnabled)
        #expect(!model.completionReplyEnabled)
        #expect(model.watchRelay == nil)
        model.watchNotificationEnabled = true
        model.completionReplyEnabled = true
        #expect(!model.watchNotificationEnabled)
        #expect(!model.completionReplyEnabled)
        #expect(model.watchRelay == nil)
        #expect(!WatchHTTPEndpoint().start())
        #expect(!environment.defaults.bool(forKey: "watch.notification.enabled"))
        #expect(!environment.defaults.bool(forKey: "feature.completionReply.enabled"))
    }

    @Test
    func terminalRepliesRemainUnavailableEvenWhenRequested() {
        let session = AgentSession(id: "stale", title: "Stale terminal", tool: .claudeCode,
            phase: .completed, summary: "Done", updatedAt: .now, jumpTarget: JumpTarget(terminalApp: "Ghostty", workspaceName: "test", paneTitle: "same title", workingDirectory: "/tmp"))
        #expect(!TerminalTextSender.canReply(to: session, enabled: true))
        #expect(!TerminalTextSender.send("must not reach a terminal", to: session))
    }
}
