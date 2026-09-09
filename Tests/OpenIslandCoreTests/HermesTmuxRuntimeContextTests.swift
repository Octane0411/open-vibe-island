import Foundation
import Testing
@testable import OpenIslandCore

struct HermesTmuxRuntimeContextTests {
    private let env = [
        "TERM_PROGRAM": "iTerm.app",
        "ITERM_SESSION_ID": "w0t0p0:leaked",
        "TMUX": "/private/tmp/tmux-501/default,1234,0",
    ]

    private let ttyProvider: () -> String? = { "/dev/ttys020" }

    @Test
    func tmuxPaneOverridesLeakedHostTerminalEnvironment() throws {
        // In-tmux payload: TERM_PROGRAM still says iTerm.app (leaked from the
        // host that launched the tmux client), but tmux is authoritative.
        let payload = HermesHookPayload(
            hookEventName: .postLLMCall,
            sessionID: "s1",
            cwd: "/Users/user/Codings/binance-strategy-platform-agent",
            extra: .object(["model": .string("GLM-5.3-Flash"), "platform": .string("tui")])
        )

        let resolved = payload.withRuntimeContext(
            environment: env,
            currentTTYProvider: ttyProvider,
            terminalLocatorProvider: { _ in
                Issue.record("AppleScript locator must not run for tmux sessions")
                return (sessionID: "iterm-wrong", tty: "/dev/ttys999", title: "wrong")
            },
            tmuxResolverProvider: {
                StubbedTmuxPaneResolver(
                    paneTarget: "binance-strategy-platform-agent:5.0",
                    hostApp: "VS Code"
                )
            }
        )

        #expect(resolved.tmuxTarget == "binance-strategy-platform-agent:5.0")
        #expect(resolved.terminalApp == "VS Code")
        #expect(resolved.terminalTTY == "/dev/ttys020")
        #expect(resolved.terminalSessionID == nil)
        #expect(resolved.terminalTitle == nil)
        #expect(resolved.defaultJumpTarget.tmuxTarget == "binance-strategy-platform-agent:5.0")
        #expect(resolved.defaultJumpTarget.terminalApp == "VS Code")
    }

    @Test
    func nonTmuxPayloadKeepsEnvironmentInference() {
        let payload = HermesHookPayload(
            hookEventName: .postLLMCall,
            sessionID: "s2",
            cwd: "/tmp/work",
            extra: nil
        )

        let noTmuxEnv = [
            "TERM_PROGRAM": "iTerm.app",
            "ITERM_SESSION_ID": "w0t0p0:real",
        ]
        let resolved = payload.withRuntimeContext(
            environment: noTmuxEnv,
            currentTTYProvider: { nil },
            terminalLocatorProvider: { _ in (sessionID: "iterm-1", tty: "/dev/ttys001", title: "shell") },
            tmuxResolverProvider: {
                Issue.record("tmux resolver must not run outside tmux")
                return StubbedTmuxPaneResolver(paneTarget: "x:0.0", hostApp: "VS Code")
            }
        )

        #expect(resolved.tmuxTarget == nil)
        #expect(resolved.terminalApp == "iTerm")
        #expect(resolved.terminalSessionID == "iterm-1")
    }

    @Test
    func tmuxResolverReturningNilPaneFallsBackToEnvironment() {
        let payload = HermesHookPayload(
            hookEventName: .postLLMCall,
            sessionID: "s3",
            cwd: "/tmp/work",
            extra: nil
        )

        let resolved = payload.withRuntimeContext(
            environment: env,
            currentTTYProvider: ttyProvider,
            terminalLocatorProvider: { _ in (sessionID: "iterm-2", tty: "/dev/ttys002", title: "shell") },
            tmuxResolverProvider: { StubbedTmuxPaneResolver(paneTarget: nil, hostApp: nil) }
        )

        // Pane lookup failed (e.g. tmux server gone) — fall back to env.
        #expect(resolved.tmuxTarget == nil)
        #expect(resolved.terminalApp == "iTerm")
        #expect(resolved.terminalSessionID == "iterm-2")
    }

    @Test
    func paneResolutionFallsBackToAncestorTTYs() {
        let payload = HermesHookPayload(
            hookEventName: .postLLMCall,
            sessionID: "s4",
            cwd: "/tmp/work",
            extra: nil
        )

        // Pipeline case: the direct TTY (ttys016) is a pipe-side pty that is
        // not a tmux pane; the pane shell ancestor is ttys014.
        let resolved = payload.withRuntimeContext(
            environment: env,
            currentTTYProvider: { "/dev/ttys016" },
            terminalLocatorProvider: { _ in
                Issue.record("AppleScript locator must not run for tmux sessions")
                return (sessionID: "iterm-wrong", tty: nil, title: nil)
            },
            tmuxResolverProvider: {
                AncestorStubbedTmuxPaneResolver(
                    paneTTys: ["/dev/ttys014"],
                    paneTarget: "binance-strategy-platform-agent:10.0",
                    hostApp: "VS Code"
                )
            },
            ancestorTTYProvider: { _ in ["/dev/ttys014"] },
            parentPIDProvider: { [42] }
        )

        #expect(resolved.tmuxTarget == "binance-strategy-platform-agent:10.0")
        #expect(resolved.terminalApp == "VS Code")
        #expect(resolved.terminalTTY == "/dev/ttys014")
        #expect(resolved.terminalSessionID == nil)
    }
}

/// Test double returning fixed pane/host results without touching tmux or ps.
private struct StubbedTmuxPaneResolver: TmuxPaneResolverProtocol {
    let paneTarget: String?
    let hostApp: String?
    let socketPath: String? = nil

    func pane(forTTY tty: String) -> TmuxPaneResolver.Pane? {
        paneTarget.map { TmuxPaneResolver.Pane(target: $0) }
    }

    func hostTerminalApp() -> String? {
        hostApp
    }
}

/// Stub whose pane lookup only succeeds for specific TTYs, to exercise the
/// ancestor fallback.
private struct AncestorStubbedTmuxPaneResolver: TmuxPaneResolverProtocol {
    let paneTTys: [String]
    let paneTarget: String
    let hostApp: String?
    let socketPath: String? = nil

    func pane(forTTY tty: String) -> TmuxPaneResolver.Pane? {
        paneTTys.contains(tty) ? TmuxPaneResolver.Pane(target: paneTarget) : nil
    }

    func hostTerminalApp() -> String? {
        hostApp
    }
}
