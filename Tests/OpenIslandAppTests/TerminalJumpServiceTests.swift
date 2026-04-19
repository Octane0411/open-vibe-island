import XCTest
@testable import OpenIslandApp
import OpenIslandCore
import Foundation

final class TerminalJumpServiceTests: XCTestCase {
    private final class OpenedArgumentsBox: @unchecked Sendable {
        var values: [[String]] = []
    }

    private final class ProcessInvocationBox: @unchecked Sendable {
        var values: [(String, [String])] = []
    }

    func testGhosttyJumpScriptActivatesWindowAndRetriesFocusUntilItSticks() {
        let target = JumpTarget(
            terminalApp: "Ghostty",
            workspaceName: "open-island",
            paneTitle: "codex ~/p/open-island",
            workingDirectory: "/Users/wangruobing/Personal/open-island",
            terminalSessionID: "448D7E28-24FB-46F1-9504-C252F97926C1"
        )

        let script = TerminalJumpService().ghosttyJumpScript(for: target)

        XCTAssertTrue(script.contains("activate"))
        XCTAssertTrue(script.contains("activate window targetWindow"))
        XCTAssertTrue(script.contains("select tab targetTab"))
        XCTAssertTrue(script.contains("focus targetTerminal"))
        XCTAssertTrue(script.contains("repeat 3 times"))
        XCTAssertTrue(script.contains("delay 0.04"))
        XCTAssertTrue(script.contains("delay 0.08"))
        XCTAssertTrue(script.contains("focused terminal of selected tab of front window"))
        XCTAssertTrue(script.contains("repeat with aWindow in windows"))
        XCTAssertTrue(script.contains("repeat with aTab in tabs of aWindow"))
        XCTAssertTrue(script.contains("repeat with aTerminal in terminals of aTab"))
    }

    func testGhosttyJumpScriptFallsBackToWorkingDirectoryAndTitle() {
        let target = JumpTarget(
            terminalApp: "Ghostty",
            workspaceName: "open-island",
            paneTitle: "codex ~/p/open-island",
            workingDirectory: "/Users/wangruobing/Personal/open-island"
        )

        let script = TerminalJumpService().ghosttyJumpScript(for: target)

        XCTAssertTrue(script.contains("(working directory of aTerminal as text) is \"/Users/wangruobing/Personal/open-island\""))
        XCTAssertTrue(script.contains("(name of aTerminal as text) contains \"codex ~/p/open-island\""))
        XCTAssertTrue(script.contains("if \"\" is \"\" then"))
    }

    func testGhosttyJumpIntegrationMatchesFocusedTerminalForLiveSurfaces() throws {
        guard ProcessInfo.processInfo.environment["OPEN_ISLAND_RUN_GHOSTTY_JUMP_INTEGRATION"] == "1" else {
            throw XCTSkip("Set OPEN_ISLAND_RUN_GHOSTTY_JUMP_INTEGRATION=1 to run live Ghostty jump verification.")
        }

        let terminals = try liveGhosttyTerminals()
        if terminals.isEmpty {
            throw XCTSkip("No live Ghostty terminals were found.")
        }

        let service = TerminalJumpService()
        for terminal in terminals {
            var matched = false
            var lastResult = ""
            var lastFocusedID = ""

            for _ in 0..<2 {
                lastResult = try service.jump(
                    to: JumpTarget(
                        terminalApp: "Ghostty",
                        workspaceName: URL(fileURLWithPath: terminal.workingDirectory).lastPathComponent,
                        paneTitle: terminal.title,
                        workingDirectory: terminal.workingDirectory,
                        terminalSessionID: terminal.id
                    )
                )
                lastFocusedID = try focusedGhosttyTerminalID()
                if lastResult == "Focused the matching Ghostty terminal.",
                   lastFocusedID == terminal.id {
                    matched = true
                    break
                }

                Thread.sleep(forTimeInterval: 0.25)
            }

            XCTAssertTrue(
                matched,
                "Ghostty jump did not settle on \(terminal.id). lastResult=\(lastResult) lastFocusedID=\(lastFocusedID)"
            )
        }
    }

    func testGhosttyJumpDoesNotOpenNewTabWhenPreciseTargetMissesInRunningApp() throws {
        let openedArguments = OpenedArgumentsBox()
        let service = TerminalJumpService(
            applicationResolver: { bundleIdentifier in
                bundleIdentifier == "com.mitchellh.ghostty" ? URL(fileURLWithPath: "/Applications/Ghostty.app") : nil
            },
            appRunningChecker: { bundleIdentifier in
                bundleIdentifier == "com.mitchellh.ghostty"
            },
            openAction: { arguments in
                openedArguments.values.append(arguments)
            },
            appleScriptRunner: { _ in "" }
        )

        let result = try service.jump(
            to: JumpTarget(
                terminalApp: "Ghostty",
                workspaceName: "open-island",
                paneTitle: "Claude open-island",
                workingDirectory: "/Users/wangruobing/Personal/open-island",
                terminalTTY: "/dev/ttys002"
            )
        )

        XCTAssertEqual(result, "Activated Ghostty. Exact pane targeting could not find the live terminal.")
        XCTAssertEqual(openedArguments.values, [["-b", "com.mitchellh.ghostty"]])
    }

    func testCursorJumpActivatesRunningAppWithoutWorkspaceReuse() throws {
        let openedArguments = OpenedArgumentsBox()
        let service = TerminalJumpService(
            applicationResolver: { bundleIdentifier in
                bundleIdentifier == "com.todesktop.230313mzl4w4u92" ? URL(fileURLWithPath: "/Applications/Cursor.app") : nil
            },
            appRunningChecker: { bundleIdentifier in
                bundleIdentifier == "com.todesktop.230313mzl4w4u92"
            },
            openAction: { arguments in
                openedArguments.values.append(arguments)
            },
            appleScriptRunner: { _ in "" },
            processRunner: { _, _ in false }
        )

        let result = try service.jump(
            to: JumpTarget(
                terminalApp: "Cursor",
                workspaceName: "open-vibe-island",
                paneTitle: "Cursor abc123",
                workingDirectory: "/Users/test/open-vibe-island"
            )
        )

        XCTAssertEqual(result, "Activated Cursor.")
        XCTAssertEqual(openedArguments.values, [["-b", "com.todesktop.230313mzl4w4u92"]])
    }

    func testCursorJumpFallsBackToWorkspaceWhenAppNotRunning() throws {
        let openedArguments = OpenedArgumentsBox()
        let service = TerminalJumpService(
            applicationResolver: { bundleIdentifier in
                bundleIdentifier == "com.todesktop.230313mzl4w4u92" ? URL(fileURLWithPath: "/Applications/Cursor.app") : nil
            },
            appRunningChecker: { _ in false },
            openAction: { arguments in
                openedArguments.values.append(arguments)
            },
            appleScriptRunner: { _ in "" },
            processRunner: { _, _ in true }
        )

        let result = try service.jump(
            to: JumpTarget(
                terminalApp: "Cursor",
                workspaceName: "open-vibe-island",
                paneTitle: "Cursor abc123",
                workingDirectory: "/Users/test/open-vibe-island"
            )
        )

        XCTAssertEqual(result, "Focused the matching Cursor workspace.")
        XCTAssertTrue(openedArguments.values.isEmpty)
    }

    func testWarpJumpReturnsImmediatelyWhenAlreadyOnTargetPane() throws {
        let openedArguments = OpenedArgumentsBox()
        let keystroker = KeystrokeInjectorSpy()
        let targetUUID = "D1A5DF3027E44FC080FE2656FAF2BA2E"

        let service = TerminalJumpService(
            applicationResolver: { id in
                id == "dev.warp.Warp-Stable" ? URL(fileURLWithPath: "/Applications/Warp.app") : nil
            },
            appRunningChecker: { id in id == "dev.warp.Warp-Stable" },
            openAction: { arguments in openedArguments.values.append(arguments) },
            appleScriptRunner: { _ in "" },
            warpFocusedPaneReader: { targetUUID },  // already at target
            warpTabCountReader: { 3 },
            warpKeystroker: keystroker,
            warpFrontmostChecker: { true }
        )

        let result = try service.jump(
            to: JumpTarget(
                terminalApp: "Warp",
                workspaceName: "demo",
                paneTitle: "Claude demo",
                workingDirectory: "/Users/u/demo",
                warpPaneUUID: targetUUID
            )
        )

        XCTAssertEqual(result, "Focused the matching Warp tab.")
        XCTAssertEqual(keystroker.callCount, 0)
        XCTAssertEqual(openedArguments.values, [["-b", "dev.warp.Warp-Stable"]])
    }

    func testWarpJumpCyclesThroughTabsUntilTargetIsFocused() throws {
        let openedArguments = OpenedArgumentsBox()
        let keystroker = KeystrokeInjectorSpy()
        let targetUUID = "BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB"

        // Simulate starting on some other tab, then after 2 keystrokes landing on target.
        let readSequence = ReadSequenceBox(values: [
            "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA", // initial
            "CCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCC", // after 1st keystroke
            targetUUID,                         // after 2nd keystroke — match!
        ])

        let service = TerminalJumpService(
            applicationResolver: { id in
                id == "dev.warp.Warp-Stable" ? URL(fileURLWithPath: "/Applications/Warp.app") : nil
            },
            appRunningChecker: { id in id == "dev.warp.Warp-Stable" },
            openAction: { arguments in openedArguments.values.append(arguments) },
            appleScriptRunner: { _ in "" },
            warpFocusedPaneReader: { readSequence.next() },
            warpTabCountReader: { 4 },
            warpKeystroker: keystroker,
            warpFrontmostChecker: { true }
        )

        let result = try service.jump(
            to: JumpTarget(
                terminalApp: "Warp",
                workspaceName: "demo",
                paneTitle: "Claude demo",
                workingDirectory: "/Users/u/demo",
                warpPaneUUID: targetUUID
            )
        )

        XCTAssertEqual(result, "Focused the matching Warp tab.")
        XCTAssertEqual(keystroker.callCount, 2)
        XCTAssertEqual(openedArguments.values, [["-b", "dev.warp.Warp-Stable"]])
    }

    func testWarpJumpCapsOutAfterTabCountPlusTwoAndReturnsBestEffortMessage() throws {
        let keystroker = KeystrokeInjectorSpy()
        let service = TerminalJumpService(
            applicationResolver: { id in
                id == "dev.warp.Warp-Stable" ? URL(fileURLWithPath: "/Applications/Warp.app") : nil
            },
            appRunningChecker: { id in id == "dev.warp.Warp-Stable" },
            openAction: { _ in },
            appleScriptRunner: { _ in "" },
            warpFocusedPaneReader: { "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA" },  // never matches
            warpTabCountReader: { 3 },
            warpKeystroker: keystroker,
            warpFrontmostChecker: { true }
        )

        let result = try service.jump(
            to: JumpTarget(
                terminalApp: "Warp",
                workspaceName: "demo",
                paneTitle: "Claude demo",
                workingDirectory: "/Users/u/demo",
                warpPaneUUID: "BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB"
            )
        )

        XCTAssertEqual(result, "Activated Warp but could not confirm precision focus.")
        XCTAssertEqual(keystroker.callCount, 5)  // tabCount (3) + 2
    }

    func testWarpJumpWithNilWarpPaneUUIDFallsBackToAppActivation() throws {
        let keystroker = KeystrokeInjectorSpy()
        let openedArguments = OpenedArgumentsBox()
        let service = TerminalJumpService(
            applicationResolver: { id in
                id == "dev.warp.Warp-Stable" ? URL(fileURLWithPath: "/Applications/Warp.app") : nil
            },
            appRunningChecker: { id in id == "dev.warp.Warp-Stable" },
            openAction: { arguments in openedArguments.values.append(arguments) },
            appleScriptRunner: { _ in "" },
            warpFocusedPaneReader: { "SHOULD-NOT-BE-READ" },
            warpTabCountReader: { 3 },
            warpKeystroker: keystroker,
            warpFrontmostChecker: { true }
        )

        let result = try service.jump(
            to: JumpTarget(
                terminalApp: "Warp",
                workspaceName: "demo",
                paneTitle: "Claude demo",
                workingDirectory: "/Users/u/demo",
                warpPaneUUID: nil
            )
        )

        XCTAssertEqual(result, "Activated Warp. No precise pane mapping available.")
        XCTAssertEqual(keystroker.callCount, 0)
        XCTAssertEqual(openedArguments.values, [["-b", "dev.warp.Warp-Stable"]])
    }

    func testUnknownTerminalAppFallsBackToFinderInsteadOfFirstInstalledTerminal() throws {
        let openedArguments = OpenedArgumentsBox()
        // Pretend iTerm is installed. Without the "unknown" guard in
        // resolveTerminalApp, the silent "first installed known app" fallback
        // would return iTerm's descriptor and the cwd would end up being opened
        // via `open -b com.googlecode.iterm2 /path` (wrong terminal).
        let service = TerminalJumpService(
            applicationResolver: { bundleIdentifier in
                bundleIdentifier == "com.googlecode.iterm2" ? URL(fileURLWithPath: "/Applications/iTerm.app") : nil
            },
            appRunningChecker: { _ in false },
            openAction: { arguments in
                openedArguments.values.append(arguments)
            },
            appleScriptRunner: { _ in "" }
        )

        let result = try service.jump(
            to: JumpTarget(
                terminalApp: "Unknown",
                workspaceName: "my-project",
                paneTitle: "",
                workingDirectory: "/tmp"
            )
        )

        XCTAssertEqual(openedArguments.values, [["/tmp"]])
        XCTAssertTrue(
            result.contains("Finder"),
            "Expected Finder fallback, got: \(result)"
        )
    }

    func testTraeJumpActivatesRunningTraeCNApp() throws {
        let openedArguments = OpenedArgumentsBox()
        let service = TerminalJumpService(
            applicationResolver: { bundleIdentifier in
                bundleIdentifier == "cn.trae.app" ? URL(fileURLWithPath: "/Applications/Trae CN.app") : nil
            },
            appRunningChecker: { bundleIdentifier in
                bundleIdentifier == "cn.trae.app"
            },
            openAction: { arguments in
                openedArguments.values.append(arguments)
            },
            appleScriptRunner: { _ in "" }
        )

        let result = try service.jump(
            to: JumpTarget(
                terminalApp: "Trae",
                workspaceName: "open-vibe-island",
                paneTitle: "Trae abc123",
                workingDirectory: "/Users/test/open-vibe-island"
            )
        )

        XCTAssertEqual(result, "Activated Trae.")
        XCTAssertEqual(openedArguments.values, [["-b", "cn.trae.app"]])
    }

    func testTraeCNJumpPrefersCNBundleWhenBothTraeVariantsExist() throws {
        let openedArguments = OpenedArgumentsBox()
        let service = TerminalJumpService(
            applicationResolver: { bundleIdentifier in
                switch bundleIdentifier {
                case "com.trae.app":
                    return URL(fileURLWithPath: "/Applications/Trae.app")
                case "cn.trae.app":
                    return URL(fileURLWithPath: "/Applications/Trae CN.app")
                default:
                    return nil
                }
            },
            appRunningChecker: { bundleIdentifier in
                bundleIdentifier == "com.trae.app"
            },
            openAction: { arguments in
                openedArguments.values.append(arguments)
            },
            appleScriptRunner: { _ in "" }
        )

        let result = try service.jump(
            to: JumpTarget(
                terminalApp: "Trae CN",
                workspaceName: "open-vibe-island",
                paneTitle: "Trae abc123"
            )
        )

        XCTAssertEqual(result, "Activated Trae. Exact pane targeting is still best-effort.")
        XCTAssertEqual(openedArguments.values, [["-b", "cn.trae.app"]])
    }

    func testCodexAppJumpActivatesCodexDesktopApp() throws {
        let openedArguments = OpenedArgumentsBox()
        let service = TerminalJumpService(
            applicationResolver: { bundleIdentifier in
                bundleIdentifier == "com.openai.codex" ? URL(fileURLWithPath: "/Applications/Codex.app") : nil
            },
            appRunningChecker: { bundleIdentifier in
                bundleIdentifier == "com.openai.codex"
            },
            openAction: { arguments in
                openedArguments.values.append(arguments)
            },
            appleScriptRunner: { _ in "" }
        )

        let result = try service.jump(
            to: JumpTarget(
                terminalApp: "Codex.app",
                workspaceName: "my-project",
                paneTitle: "",
                workingDirectory: "/Users/test/my-project"
            )
        )

        XCTAssertEqual(result, "Activated Codex.app.")
        XCTAssertEqual(openedArguments.values, [["-b", "com.openai.codex"]])
    }

    func testCodexAppJumpOpensSpecificThreadWhenThreadIDProvided() throws {
        let openedArguments = OpenedArgumentsBox()
        let service = TerminalJumpService(
            applicationResolver: { bundleIdentifier in
                bundleIdentifier == "com.openai.codex" ? URL(fileURLWithPath: "/Applications/Codex.app") : nil
            },
            appRunningChecker: { bundleIdentifier in
                bundleIdentifier == "com.openai.codex"
            },
            openAction: { arguments in
                openedArguments.values.append(arguments)
            },
            appleScriptRunner: { _ in "" }
        )

        let threadID = "019d9a98-d3ab-7060-95b2-0a435912da57"
        let result = try service.jump(
            to: JumpTarget(
                terminalApp: "Codex.app",
                workspaceName: "my-project",
                paneTitle: "",
                workingDirectory: "/Users/test/my-project",
                codexThreadID: threadID
            )
        )

        XCTAssertEqual(result, "Focused the Codex.app conversation.")
        XCTAssertEqual(openedArguments.values, [["codex://threads/\(threadID)"]])
    }

    func testTraeCNJumpFallsBackToWorkspaceViaTraeCLI() throws {
        let openedArguments = OpenedArgumentsBox()
        let processInvocations = ProcessInvocationBox()
        let service = TerminalJumpService(
            applicationResolver: { bundleIdentifier in
                bundleIdentifier == "cn.trae.app" ? URL(fileURLWithPath: "/Applications/Trae CN.app") : nil
            },
            appRunningChecker: { _ in false },
            openAction: { arguments in
                openedArguments.values.append(arguments)
            },
            appleScriptRunner: { _ in "" },
            processRunner: { executable, arguments in
                processInvocations.values.append((executable, arguments))
                return true
            }
        )

        let result = try service.jump(
            to: JumpTarget(
                terminalApp: "Trae CN",
                workspaceName: "open-vibe-island",
                paneTitle: "Trae abc123",
                workingDirectory: "/Users/test/open-vibe-island"
            )
        )

        XCTAssertEqual(result, "Focused the matching Trae workspace.")
        XCTAssertTrue(openedArguments.values.isEmpty)
        XCTAssertEqual(processInvocations.values.count, 1)
        XCTAssertEqual(processInvocations.values.first?.0, "trae")
        XCTAssertEqual(processInvocations.values.first?.1, ["-r", "/Users/test/open-vibe-island"])
    }
}

final class ReadSequenceBox: @unchecked Sendable {
    private var values: [String?]
    init(values: [String?]) { self.values = values }
    func next() -> String? {
        guard !values.isEmpty else { return nil }
        return values.removeFirst()
    }
}

private struct LiveGhosttyTerminal: Equatable {
    let id: String
    let workingDirectory: String
    let title: String
}

private let fieldSeparator = "\u{1f}"
private let recordSeparator = "\u{1e}"

private func liveGhosttyTerminals() throws -> [LiveGhosttyTerminal] {
    let script = """
    tell application "Ghostty"
        if not (it is running) then return ""
        set outputRecords to {}
        repeat with aWindow in windows
            repeat with aTab in tabs of aWindow
                repeat with aTerminal in terminals of aTab
                    set end of outputRecords to (id of aTerminal as text) & "\(fieldSeparator)" & (working directory of aTerminal as text) & "\(fieldSeparator)" & (name of aTerminal as text)
                end repeat
            end repeat
        end repeat
        set previousDelimiters to AppleScript's text item delimiters
        set AppleScript's text item delimiters to "\(recordSeparator)"
        set joinedOutput to outputRecords as text
        set AppleScript's text item delimiters to previousDelimiters
        return joinedOutput
    end tell
    """

    let output = try runAppleScript(script)
    if output.isEmpty {
        return []
    }

    return output
        .components(separatedBy: recordSeparator)
        .compactMap { record in
            let fields = record.components(separatedBy: fieldSeparator)
            guard fields.count == 3 else {
                return nil
            }

            return LiveGhosttyTerminal(id: fields[0], workingDirectory: fields[1], title: fields[2])
        }
}

private func focusedGhosttyTerminalID() throws -> String {
    let script = """
    tell application "Ghostty"
        if not (it is running) then return ""
        return id of focused terminal of selected tab of front window as text
    end tell
    """

    return try runAppleScript(script)
}

private func runAppleScript(_ script: String) throws -> String {
    let task = Process()
    task.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
    task.arguments = ["-e", script]

    let outputPipe = Pipe()
    let errorPipe = Pipe()
    task.standardOutput = outputPipe
    task.standardError = errorPipe

    try task.run()
    task.waitUntilExit()

    let output = String(data: outputPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
        .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

    guard task.terminationStatus == 0 else {
        let stderr = String(data: errorPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        XCTFail(stderr.isEmpty ? "AppleScript command failed." : stderr)
        throw NSError(domain: "TerminalJumpServiceTests", code: Int(task.terminationStatus))
    }

    return output
}
