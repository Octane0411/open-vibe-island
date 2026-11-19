import Foundation
import Testing
@testable import OpenIslandCore

struct ClaudeBackgroundSessionViewerTests {
    private typealias Resolver = ClaudeBackgroundSessionViewerResolver

    private static let backgroundEnvironment: [String: String] = [
        "CLAUDE_CODE_SESSION_KIND": "bg",
        "CLAUDE_BG_BACKEND": "daemon",
    ]

    private func viewer(
        pid: Int32,
        tty: String? = "/dev/ttys000",
        cwd: String?,
        arguments: [String],
        environment: [String: String] = [:]
    ) -> ClaudeBackgroundSessionViewer {
        ClaudeBackgroundSessionViewer(
            pid: pid,
            terminalTTY: tty,
            workingDirectory: cwd,
            arguments: arguments,
            environment: environment
        )
    }

    // MARK: - Viewer parsing

    @Test
    func viewerKindParsesAttachAndAgentsScopes() {
        #expect(Resolver.viewerKind(arguments: ["claude", "attach", "72E15398"]) == .attach(sessionID: "72e15398"))
        #expect(Resolver.viewerKind(arguments: ["/Users/me/.local/bin/claude", "agents"]) == .agents(scope: nil))
        #expect(Resolver.viewerKind(arguments: ["claude", "agents", "--cwd", ".", "--dangerously-skip-permissions"]) == .agents(scope: "."))
        #expect(Resolver.viewerKind(arguments: ["claude", "agents", "--cwd=/tmp/project"]) == .agents(scope: "/tmp/project"))
        #expect(Resolver.viewerKind(arguments: ["claude", "attach", "--help"]) == nil)
        #expect(Resolver.viewerKind(arguments: ["claude", "--resume", "abc"]) == nil)
        #expect(Resolver.viewerKind(arguments: ["claude"]) == nil)
        #expect(Resolver.viewerKind(arguments: ["node", "agents"]) == nil)
    }

    @Test
    func isBackgroundSessionRequiresDaemonMarkers() {
        #expect(Resolver.isBackgroundSession(environment: Self.backgroundEnvironment))
        #expect(Resolver.isBackgroundSession(environment: ["CLAUDE_BG_BACKEND": "daemon"]))
        #expect(!Resolver.isBackgroundSession(environment: ["TERM_PROGRAM": "iTerm.app"]))
        #expect(!Resolver.isBackgroundSession(environment: ["CLAUDE_BG_BACKEND": ""]))
    }

    // MARK: - Viewer selection

    @Test
    func attachViewerWinsOverAgentsView() {
        let agents = viewer(pid: 10, tty: "/dev/ttys000", cwd: "/Users/me/dev/local", arguments: ["claude", "agents", "--cwd", "."])
        let attach = viewer(pid: 20, tty: "/dev/ttys004", cwd: "/Users/me", arguments: ["claude", "attach", "72e15398"])

        let selected = Resolver.selectViewer(
            from: [agents, attach],
            sessionID: "72e15398-ff3d-4a74-9d70-2424686dccdc",
            sessionName: "72e15398",
            sessionWorkingDirectory: "/Users/me/dev/local"
        )

        #expect(selected == attach)
    }

    @Test
    func attachViewerMatchesSessionIDPrefixWithoutSessionName() {
        let attach = viewer(pid: 20, cwd: "/", arguments: ["claude", "attach", "72e15398"])

        let selected = Resolver.selectViewer(
            from: [attach],
            sessionID: "72E15398-ff3d-4a74-9d70-2424686dccdc",
            sessionName: nil,
            sessionWorkingDirectory: "/tmp"
        )

        #expect(selected == attach)
    }

    @Test
    func agentsViewWithMostSpecificScopeWins() {
        let unscoped = viewer(pid: 5, tty: "/dev/ttys009", cwd: "/Users/me", arguments: ["claude", "agents"])
        let local = viewer(pid: 10, tty: "/dev/ttys000", cwd: "/Users/me/dev/local", arguments: ["claude", "agents", "--cwd", "."])
        let myvillage = viewer(
            pid: 11,
            tty: "/dev/ttys004",
            cwd: "/Users/me/dev/myvillage/guru-backend",
            arguments: ["claude", "agents", "--cwd", "."]
        )
        let candidates = [unscoped, local, myvillage]

        #expect(Resolver.selectViewer(
            from: candidates,
            sessionID: "a",
            sessionName: nil,
            sessionWorkingDirectory: "/Users/me/dev/local"
        ) == local)
        #expect(Resolver.selectViewer(
            from: candidates,
            sessionID: "b",
            sessionName: nil,
            sessionWorkingDirectory: "/Users/me/dev/myvillage/guru-backend/api"
        ) == myvillage)
        #expect(Resolver.selectViewer(
            from: candidates,
            sessionID: "c",
            sessionName: nil,
            sessionWorkingDirectory: "/Users/me/dev/other"
        ) == unscoped)
    }

    @Test
    func agentsScopeDoesNotMatchSiblingDirectoryWithSharedPrefix() {
        let scoped = viewer(pid: 10, cwd: "/Users/me/dev", arguments: ["claude", "agents", "--cwd", "proj"])

        #expect(Resolver.selectViewer(
            from: [scoped],
            sessionID: "a",
            sessionName: nil,
            sessionWorkingDirectory: "/Users/me/dev/project"
        ) == nil)
        #expect(Resolver.selectViewer(
            from: [scoped],
            sessionID: "a",
            sessionName: nil,
            sessionWorkingDirectory: "/Users/me/dev/proj/"
        ) == scoped)
    }

    @Test
    func viewersWithoutTerminalOrMatchingScopeAreIgnored() {
        let detached = viewer(pid: 10, tty: nil, cwd: "/tmp/project", arguments: ["claude", "agents", "--cwd", "."])
        let relativeWithoutCWD = viewer(pid: 11, cwd: nil, arguments: ["claude", "agents", "--cwd", "."])

        #expect(Resolver.selectViewer(
            from: [detached, relativeWithoutCWD],
            sessionID: "a",
            sessionName: nil,
            sessionWorkingDirectory: "/tmp/project"
        ) == nil)
    }

    // MARK: - Environment helpers

    @Test
    func terminalEnvironmentReplacesLeakedTerminalKeysWithViewerKeys() {
        let viewer = viewer(pid: 1, cwd: "/", arguments: ["claude", "agents"], environment: [
            "TERM_PROGRAM": "iTerm.app",
            "ITERM_SESSION_ID": "w1t0p0:E0568687-6BD1-4764-AFCB-723A070EA014",
            "HOME": "/Users/other",
            "CLAUDE_CODE_ENTRYPOINT": "cli",
        ])
        let leaked = [
            "CLAUDE_PID": "53912",
            "TERM_SESSION_ID": "w0t0p0:BF4CAE15-CFAB-4204-85C2-048613CB13C3",
            "ITERM_PROFILE": "Dev",
        ]

        let replaced = Resolver.terminalEnvironment(replacing: leaked, with: viewer)

        #expect(replaced["TERM_PROGRAM"] == "iTerm.app")
        #expect(replaced["ITERM_SESSION_ID"] == "w1t0p0:E0568687-6BD1-4764-AFCB-723A070EA014")
        #expect(replaced["TERM_SESSION_ID"] == nil)
        #expect(replaced["ITERM_PROFILE"] == nil)
        #expect(replaced["CLAUDE_PID"] == "53912")
        #expect(replaced["HOME"] == nil)
        #expect(replaced["CLAUDE_CODE_ENTRYPOINT"] == nil)

        let withoutViewer = Resolver.terminalEnvironment(replacing: leaked, with: nil)
        #expect(withoutViewer == ["CLAUDE_PID": "53912"])
    }

    @Test
    func backgroundAgentPIDReadsDaemonMarkersFromEngineWhenHookEnvironmentIsScrubbed() {
        // Claude Code strips CLAUDE_CODE_SESSION_KIND / CLAUDE_BG_BACKEND
        // from hook environments; the engine (CLAUDE_PID) still has them.
        let scrubbedHookEnvironment = ["CLAUDE_PID": "53912", "CLAUDE_CODE_SESSION_ID": "s"]

        #expect(Resolver.backgroundAgentPID(
            environment: scrubbedHookEnvironment,
            processEnvironment: { $0 == 53912 ? ["CLAUDE_CODE_SESSION_KIND": "bg"] : nil }
        ) == 53912)
        #expect(Resolver.backgroundAgentPID(
            environment: scrubbedHookEnvironment,
            processEnvironment: { _ in ["TERM_PROGRAM": "iTerm.app"] }
        ) == nil)
        #expect(Resolver.backgroundAgentPID(
            environment: ["TERM_PROGRAM": "iTerm.app"],
            processEnvironment: { _ in
                Issue.record("no engine PID to inspect")
                return nil
            }
        ) == nil)
        #expect(Resolver.backgroundAgentPID(
            environment: ["CLAUDE_BG_BACKEND": "daemon", "CLAUDE_PID": "77"],
            processEnvironment: { _ in nil }
        ) == 77)
    }

    @Test
    func iTermSessionIDDropsWindowTabPanePrefix() {
        #expect(Resolver.iTermSessionID(from: "w0t0p0:BF4CAE15-CFAB-4204-85C2-048613CB13C3") == "BF4CAE15-CFAB-4204-85C2-048613CB13C3")
        #expect(Resolver.iTermSessionID(from: "BF4CAE15") == "BF4CAE15")
        #expect(Resolver.iTermSessionID(from: "") == nil)
        #expect(Resolver.iTermSessionID(from: nil) == nil)
    }

    @Test
    func parseProcArgs2ReadsArgumentsAndEnvironment() {
        var bytes: [UInt8] = []
        withUnsafeBytes(of: Int32(4).littleEndian) { bytes.append(contentsOf: $0) }
        func append(_ string: String) {
            bytes.append(contentsOf: Array(string.utf8))
            bytes.append(0)
        }
        append("/Users/me/.local/bin/claude")
        bytes.append(contentsOf: [0, 0, 0])
        append("claude")
        append("agents")
        append("--cwd")
        append(".")
        append("TERM_PROGRAM=iTerm.app")
        append("ITERM_SESSION_ID=w0t0p0:ABC")
        append("EMPTY=")
        append("TERM_PROGRAM=duplicate")
        append("")
        append("ignored=after-terminator")

        let parsed = Resolver.parseProcArgs2(bytes)

        #expect(parsed?.arguments == ["claude", "agents", "--cwd", "."])
        #expect(parsed?.environment == [
            "TERM_PROGRAM": "iTerm.app",
            "ITERM_SESSION_ID": "w0t0p0:ABC",
            "EMPTY": "",
        ])
    }

    @Test
    func parseProcArgs2RejectsTruncatedBuffers() {
        #expect(Resolver.parseProcArgs2([]) == nil)
        #expect(Resolver.parseProcArgs2([2, 0, 0, 0, 0x61, 0, 0x62, 0]) == nil)
    }

    @Test
    func processArgumentsReadsCurrentProcess() {
        let parsed = Resolver.processArguments(pid: getpid())

        #expect(parsed?.arguments.isEmpty == false)
        #expect(parsed?.environment.isEmpty == false)
    }

    // MARK: - Hook runtime context

    @Test
    func backgroundSessionBorrowsViewerTerminalContext() {
        let payload = ClaudeHookPayload(
            cwd: "/Users/me/dev/local",
            hookEventName: .stop,
            sessionID: "72e15398-ff3d-4a74-9d70-2424686dccdc"
        )
        let iTermViewer = viewer(
            pid: 10,
            tty: "/dev/ttys000",
            cwd: "/Users/me/dev/local",
            arguments: ["claude", "agents", "--cwd", "."],
            environment: [
                "TERM_PROGRAM": "iTerm.app",
                "ITERM_SESSION_ID": "w0t0p0:BF4CAE15-CFAB-4204-85C2-048613CB13C3",
            ]
        )

        var requestedSessionID: String?
        let enriched = payload.withRuntimeContext(
            environment: ["CLAUDE_PID": "53912", "TERM_SESSION_ID": "w9t0p0:LEAKED"],
            currentTTYProvider: {
                Issue.record("the engine pty belongs to the daemon")
                return "/dev/ttys002"
            },
            terminalLocatorProvider: { _ in
                Issue.record("focused-terminal locator must not run for background sessions")
                return (sessionID: "focused-tab", tty: "/dev/ttys004", title: "wrong")
            },
            warpPaneResolver: { _ in nil },
            backgroundAgentPIDProvider: { $0["CLAUDE_PID"].flatMap { Int32($0) } },
            backgroundViewerProvider: { payload in
                requestedSessionID = payload.sessionID
                return iTermViewer
            }
        )

        #expect(requestedSessionID == "72e15398-ff3d-4a74-9d70-2424686dccdc")
        #expect(enriched.terminalApp == "iTerm")
        #expect(enriched.terminalSessionID == "BF4CAE15-CFAB-4204-85C2-048613CB13C3")
        #expect(enriched.terminalTTY == "/dev/ttys000")
        #expect(enriched.terminalTitle == nil)
        #expect(enriched.backgroundAgentPID == 53912)
        #expect(enriched.defaultJumpTarget.backgroundAgentPID == 53912)
    }

    @Test
    func backgroundSessionWithoutViewerDropsLeakedTerminalContext() {
        let payload = ClaudeHookPayload(
            cwd: "/Users/me/dev/myvillage",
            hookEventName: .stop,
            sessionID: "f52f1ced-3bcb-44e1-907d-8b582c52658c"
        )

        let enriched = payload.withRuntimeContext(
            environment: [
                "CLAUDE_PID": "54030",
                "TERM_SESSION_ID": "w0t0p0:BF4CAE15-CFAB-4204-85C2-048613CB13C3",
                "ITERM_PROFILE": "Dev",
            ],
            currentTTYProvider: { "/dev/ttys002" },
            terminalLocatorProvider: { _ in (sessionID: "focused-tab", tty: "/dev/ttys000", title: "wrong") },
            warpPaneResolver: { _ in nil },
            backgroundAgentPIDProvider: { _ in 54030 },
            backgroundViewerProvider: { _ in nil }
        )

        #expect(enriched.terminalApp == nil)
        #expect(enriched.terminalSessionID == nil)
        #expect(enriched.terminalTTY == nil)
        #expect(enriched.backgroundAgentPID == 54030)
        #expect(enriched.defaultJumpTarget.terminalApp == "Unknown")
    }

    @Test
    func foregroundSessionNeverQueriesBackgroundViewers() {
        let payload = ClaudeHookPayload(
            cwd: "/Users/me/dev/local",
            hookEventName: .userPromptSubmit,
            sessionID: "s1"
        )

        let enriched = payload.withRuntimeContext(
            environment: ["TERM_PROGRAM": "Apple_Terminal"],
            currentTTYProvider: { "/dev/ttys007" },
            terminalLocatorProvider: { _ in (sessionID: nil, tty: "/dev/ttys007", title: "zsh") },
            warpPaneResolver: { _ in nil },
            backgroundAgentPIDProvider: { _ in nil },
            backgroundViewerProvider: { _ in
                Issue.record("background viewer lookup must only run for daemon sessions")
                return nil
            }
        )

        #expect(enriched.terminalApp == "Terminal")
        #expect(enriched.terminalTTY == "/dev/ttys007")
        #expect(enriched.backgroundAgentPID == nil)
    }

    @Test
    func backgroundAgentPIDRoundTripsThroughHookJSON() throws {
        var payload = ClaudeHookPayload(cwd: "/tmp", hookEventName: .stop, sessionID: "s1")
        payload.backgroundAgentPID = 53912

        let data = try JSONEncoder().encode(payload)
        let json = try #require(String(data: data, encoding: .utf8))
        #expect(json.contains("\"background_agent_pid\":53912"))
        #expect(try JSONDecoder().decode(ClaudeHookPayload.self, from: data).backgroundAgentPID == 53912)

        let legacy = try JSONDecoder().decode(
            JumpTarget.self,
            from: Data(#"{"terminalApp":"iTerm","workspaceName":"local","paneTitle":"Claude"}"#.utf8)
        )
        #expect(legacy.backgroundAgentPID == nil)
    }
}
