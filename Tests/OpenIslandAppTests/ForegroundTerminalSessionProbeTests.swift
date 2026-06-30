import XCTest
@testable import OpenIslandApp
import OpenIslandCore

final class ForegroundTerminalSessionProbeTests: XCTestCase {
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

        XCTAssertTrue(matches)
    }

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

        XCTAssertTrue(matches)
    }

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

        XCTAssertTrue(matches)
    }

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

        XCTAssertFalse(matches)
    }

    // MARK: - Cursor fast-path (session-level)

    func testCursorSessionMatchesWhenCursorIsFrontmostEvenWithoutJumpTarget() async {
        let probe = ForegroundTerminalSessionProbe(
            frontmostBundleIdentifierProvider: { "com.todesktop.230313mzl4w4u92" },
            appleScriptRunner: { _ in "" }
        )

        let session = AgentSession(
            id: "cursor-1",
            title: "Cursor · project",
            tool: .cursor,
            origin: .live,
            attachmentState: .attached,
            phase: .running,
            summary: "Running",
            updatedAt: Date()
        )

        let result = await probe.matches(session: session)
        XCTAssertTrue(result)
    }

    func testCursorSessionDoesNotMatchWhenDifferentAppIsFrontmost() async {
        let probe = ForegroundTerminalSessionProbe(
            frontmostBundleIdentifierProvider: { "com.mitchellh.ghostty" },
            appleScriptRunner: { _ in "" }
        )

        let session = AgentSession(
            id: "cursor-1",
            title: "Cursor · project",
            tool: .cursor,
            origin: .live,
            attachmentState: .attached,
            phase: .running,
            summary: "Running",
            updatedAt: Date()
        )

        let result = await probe.matches(session: session)
        XCTAssertFalse(result)
    }

    func testNonCursorSessionWithNilJumpTargetDoesNotMatch() async {
        let probe = ForegroundTerminalSessionProbe(
            frontmostBundleIdentifierProvider: { "com.todesktop.230313mzl4w4u92" },
            appleScriptRunner: { _ in "" }
        )

        let session = AgentSession(
            id: "codex-1",
            title: "Codex · project",
            tool: .codex,
            origin: .live,
            attachmentState: .attached,
            phase: .running,
            summary: "Running",
            updatedAt: Date()
        )

        let result = await probe.matches(session: session)
        XCTAssertFalse(result)
    }
}
