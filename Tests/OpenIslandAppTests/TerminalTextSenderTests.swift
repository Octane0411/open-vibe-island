import Foundation
import Testing
@testable import OpenIslandApp
@testable import OpenIslandCore

@MainActor
struct TerminalTextSenderTests {
    private func makeSession(
        phase: SessionPhase,
        terminalApp: String,
        tmuxTarget: String? = nil
    ) -> AgentSession {
        AgentSession(
            id: "s",
            title: "test",
            tool: .claudeCode,
            origin: .live,
            attachmentState: .attached,
            phase: phase,
            summary: "",
            updatedAt: Date(),
            jumpTarget: JumpTarget(
                terminalApp: terminalApp,
                workspaceName: "ws",
                paneTitle: "t",
                workingDirectory: "/tmp",
                terminalSessionID: nil,
                tmuxTarget: tmuxTarget
            )
        )
    }

    // MARK: - enabled gate

    @Test
    func disabledFlagBlocksReplyEvenWhenSupported() {
        let session = makeSession(phase: .completed, terminalApp: "Ghostty")
        #expect(!TerminalTextSender.canReply(to: session, enabled: false))
    }

    // MARK: - phase gate

    @Test
    func runningPhaseDoesNotAcceptReply() {
        let session = makeSession(phase: .running, terminalApp: "Ghostty")
        #expect(!TerminalTextSender.canReply(to: session, enabled: true))
    }

    @Test
    func completedPhaseAcceptsReply() {
        let session = makeSession(phase: .completed, terminalApp: "Ghostty")
        #expect(TerminalTextSender.canReply(to: session, enabled: true))
    }

    @Test
    func waitingForAnswerAcceptsReply() {
        let session = makeSession(phase: .waitingForAnswer, terminalApp: "Ghostty")
        #expect(TerminalTextSender.canReply(to: session, enabled: true))
    }

    @Test
    func waitingForApprovalAcceptsReply() {
        let session = makeSession(phase: .waitingForApproval, terminalApp: "Ghostty")
        #expect(TerminalTextSender.canReply(to: session, enabled: true))
    }

    // MARK: - terminal whitelist (case-insensitive)

    @Test
    func ghosttyIsSupported() {
        for variant in ["Ghostty", "ghostty", "GHOSTTY"] {
            let session = makeSession(phase: .completed, terminalApp: variant)
            #expect(TerminalTextSender.canReply(to: session, enabled: true), "Variant \(variant) should be supported")
        }
    }

    @Test
    func iTerm2IsSupportedUnderBothNames() {
        for variant in ["iTerm2", "iTerm", "iterm", "iterm2"] {
            let session = makeSession(phase: .completed, terminalApp: variant)
            #expect(TerminalTextSender.canReply(to: session, enabled: true), "Variant \(variant) should be supported")
        }
    }

    @Test
    func terminalAppIsSupported() {
        let session = makeSession(phase: .completed, terminalApp: "Terminal")
        #expect(TerminalTextSender.canReply(to: session, enabled: true))
    }

    @Test
    func unknownTerminalIsNotSupportedWithoutTmux() {
        for app in ["WezTerm", "Alacritty", "Hyper", ""] {
            let session = makeSession(phase: .completed, terminalApp: app)
            #expect(!TerminalTextSender.canReply(to: session, enabled: true), "App \(app) should be unsupported")
        }
    }

    // MARK: - tmux override

    @Test
    func tmuxTargetEnablesReplyEvenForUnknownTerminal() {
        let session = makeSession(phase: .completed, terminalApp: "WezTerm", tmuxTarget: "main:0.0")
        #expect(TerminalTextSender.canReply(to: session, enabled: true))
    }

    @Test
    func tmuxTargetEnablesReplyForCmuxHost() {
        let session = makeSession(phase: .waitingForApproval, terminalApp: "cmux", tmuxTarget: "cmux:1.0")
        #expect(TerminalTextSender.canReply(to: session, enabled: true))
    }

    // MARK: - missing jumpTarget

    @Test
    func missingJumpTargetBlocksReply() {
        let session = AgentSession(
            id: "s",
            title: "t",
            tool: .claudeCode,
            origin: .live,
            attachmentState: .attached,
            phase: .completed,
            summary: "",
            updatedAt: Date(),
            jumpTarget: nil
        )
        #expect(!TerminalTextSender.canReply(to: session, enabled: true))
    }
}
