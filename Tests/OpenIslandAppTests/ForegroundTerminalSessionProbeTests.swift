import Testing
@testable import OpenIslandApp
import OpenIslandCore

struct ForegroundTerminalSessionProbeTests {
    @Test
    func testMatchesGhosttyFrontmostTerminalBySessionID() async {
        let probe = ForegroundTerminalSessionProbe(
            frontmostBundleIdentifierProvider: { "com.mitchellh.ghostty" },
            appleScriptRunner: { _ in "ghostty-frontmost" }
        )

        let matches = await probe.matches(
            jumpTarget: JumpTarget(
                terminalApp: "Ghostty",
                workspaceName: "open-island",
                paneTitle: "codex ~/open-island",
                terminalSessionID: "ghostty-frontmost"
            )
        )

        #expect(matches)
    }

    @Test
    func testMatchesTerminalFrontmostTabByTTY() async {
        let probe = ForegroundTerminalSessionProbe(
            frontmostBundleIdentifierProvider: { "com.apple.Terminal" },
            appleScriptRunner: { _ in "ttys001" }
        )

        let matches = await probe.matches(
            jumpTarget: JumpTarget(
                terminalApp: "Terminal",
                workspaceName: "open-island",
                paneTitle: "codex ~/open-island",
                terminalTTY: "/dev/ttys001"
            )
        )

        #expect(matches)
    }

    @Test
    func testMatchesITermFrontmostSessionByTTYFallback() async {
        let probe = ForegroundTerminalSessionProbe(
            frontmostBundleIdentifierProvider: { "com.googlecode.iterm2" },
            appleScriptRunner: { _ in "different-session\u{1f}/dev/ttys002" }
        )

        let matches = await probe.matches(
            jumpTarget: JumpTarget(
                terminalApp: "iTerm",
                workspaceName: "open-island",
                paneTitle: "codex ~/open-island",
                terminalSessionID: "tracked-session",
                terminalTTY: "/dev/ttys002"
            )
        )

        #expect(matches)
    }

    @Test
    func testReturnsFalseForUnsupportedFrontmostApp() async {
        let probe = ForegroundTerminalSessionProbe(
            frontmostBundleIdentifierProvider: { "com.example.Editor" },
            appleScriptRunner: { _ in "" }
        )

        let matches = await probe.matches(
            jumpTarget: JumpTarget(
                terminalApp: "Ghostty",
                workspaceName: "open-island",
                paneTitle: "codex ~/open-island",
                terminalSessionID: "ghostty-frontmost"
            )
        )

        #expect(!matches)
    }
}
