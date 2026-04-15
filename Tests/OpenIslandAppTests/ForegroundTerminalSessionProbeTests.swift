import XCTest
@testable import OpenIslandApp
import OpenIslandCore

final class ForegroundTerminalSessionProbeTests: XCTestCase {
    func testMatchesGhosttyFrontmostTerminalBySessionID() {
        let probe = ForegroundTerminalSessionProbe(
            frontmostBundleIdentifierProvider: { "com.mitchellh.ghostty" },
            appleScriptRunner: { _ in "ghostty-frontmost" }
        )

        let matches = probe.matches(
            jumpTarget: JumpTarget(
                terminalApp: "Ghostty",
                workspaceName: "open-island",
                paneTitle: "codex ~/open-island",
                terminalSessionID: "ghostty-frontmost"
            )
        )

        XCTAssertTrue(matches)
    }

    func testMatchesTerminalFrontmostTabByTTY() {
        let probe = ForegroundTerminalSessionProbe(
            frontmostBundleIdentifierProvider: { "com.apple.Terminal" },
            appleScriptRunner: { _ in "ttys001" }
        )

        let matches = probe.matches(
            jumpTarget: JumpTarget(
                terminalApp: "Terminal",
                workspaceName: "open-island",
                paneTitle: "codex ~/open-island",
                terminalTTY: "/dev/ttys001"
            )
        )

        XCTAssertTrue(matches)
    }

    func testMatchesITermFrontmostSessionByTTYFallback() {
        let probe = ForegroundTerminalSessionProbe(
            frontmostBundleIdentifierProvider: { "com.googlecode.iterm2" },
            appleScriptRunner: { _ in "different-session\u{1f}/dev/ttys002" }
        )

        let matches = probe.matches(
            jumpTarget: JumpTarget(
                terminalApp: "iTerm",
                workspaceName: "open-island",
                paneTitle: "codex ~/open-island",
                terminalSessionID: "tracked-session",
                terminalTTY: "/dev/ttys002"
            )
        )

        XCTAssertTrue(matches)
    }

    func testReturnsFalseForUnsupportedFrontmostApp() {
        let probe = ForegroundTerminalSessionProbe(
            frontmostBundleIdentifierProvider: { "com.example.Editor" },
            appleScriptRunner: { _ in "" }
        )

        let matches = probe.matches(
            jumpTarget: JumpTarget(
                terminalApp: "Ghostty",
                workspaceName: "open-island",
                paneTitle: "codex ~/open-island",
                terminalSessionID: "ghostty-frontmost"
            )
        )

        XCTAssertFalse(matches)
    }
}
