import Foundation
import Testing
@testable import OpenIslandCore

/// The routing table is the whole fix for #559 and the rule from #638, so each
/// mode is pinned individually — a regression here is a user seeing a card
/// they turned off, or not seeing one they turned on.
@Suite("Codex approval routing")
struct CodexApprovalRoutingTests {
    @Test("bypassPermissions is answered allow without a card")
    func bypassAutoAllows() {
        #expect(CodexApprovalRouting.route(mode: .bypassPermissions, toolName: "shell") == .autoAllow)
        #expect(CodexApprovalRouting.route(mode: .bypassPermissions, toolName: nil) == .autoAllow)
    }

    @Test("dontAsk is answered allow without a card")
    func dontAskAutoAllows() {
        #expect(CodexApprovalRouting.route(mode: .dontAsk, toolName: "apply_patch") == .autoAllow)
        #expect(CodexApprovalRouting.route(mode: .dontAsk, toolName: "shell") == .autoAllow)
    }

    @Test("default mode asks the user")
    func defaultAsks() {
        #expect(CodexApprovalRouting.route(mode: .default, toolName: "shell") == .askUser)
        #expect(CodexApprovalRouting.route(mode: .default, toolName: "apply_patch") == .askUser)
        #expect(CodexApprovalRouting.route(mode: .default, toolName: nil) == .askUser)
    }

    @Test("acceptEdits lets file edits through and asks about everything else")
    func acceptEditsSplitsByTool() {
        #expect(CodexApprovalRouting.route(mode: .acceptEdits, toolName: "apply_patch") == .autoAllow)
        #expect(CodexApprovalRouting.route(mode: .acceptEdits, toolName: "APPLY_PATCH") == .autoAllow)
        #expect(CodexApprovalRouting.route(mode: .acceptEdits, toolName: "shell") == .askUser)
        // No tool name means it cannot be proven an edit; fall back to asking.
        #expect(CodexApprovalRouting.route(mode: .acceptEdits, toolName: nil) == .askUser)
    }

    @Test("plan mode is denied at once with a reason")
    func planDenies() {
        guard case let .autoDeny(message) = CodexApprovalRouting.route(mode: .plan, toolName: "shell") else {
            Issue.record("plan mode should auto-deny")
            return
        }
        #expect(!message.isEmpty)
    }

    @Test("every mode resolves to a route — none is left to time out")
    func everyModeResolves() {
        // The PermissionRequest contract has no "ask" value; declining to answer
        // means the agent waits for the hook timeout. Every mode must map to a
        // decision the user would recognise as theirs.
        let modes: [CodexPermissionMode] = [.default, .acceptEdits, .plan, .dontAsk, .bypassPermissions]
        for mode in modes {
            _ = CodexApprovalRouting.route(mode: mode, toolName: "shell")
        }
    }
}
