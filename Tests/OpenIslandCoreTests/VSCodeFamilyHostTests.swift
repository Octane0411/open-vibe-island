import Foundation
import Testing
@testable import OpenIslandCore

struct VSCodeFamilyHostTests {
    @Test
    func resolvesCursorFromItsOwnTraceMarker() {
        let displayName = VSCodeFamilyHost.displayName(from: ["CURSOR_TRACE_ID": "abc123"])

        #expect(displayName == "Cursor")
    }

    /// Regression: Cursor builds that ship no `CURSOR_TRACE_ID` were tagged as
    /// "VS Code", so the jump targeted `com.microsoft.VSCode` and failed
    /// outright on machines without upstream VS Code installed.
    @Test
    func resolvesCursorFromBundleIdentifierWhenTraceMarkerIsAbsent() {
        let displayName = VSCodeFamilyHost.displayName(
            from: [
                "TERM_PROGRAM": "vscode",
                "__CFBundleIdentifier": "com.todesktop.230313mzl4w4u92",
            ]
        )

        #expect(displayName == "Cursor")
    }

    @Test
    func resolvesCursorFromGitAskpassBundlePath() {
        let displayName = VSCodeFamilyHost.displayName(
            from: [
                "TERM_PROGRAM": "vscode",
                "GIT_ASKPASS": "/Applications/Cursor.app/Contents/Resources/app/extensions/git/dist/askpass.sh",
            ]
        )

        #expect(displayName == "Cursor")
    }

    @Test
    func resolvesWindsurfFromBundleIdentifier() {
        let displayName = VSCodeFamilyHost.displayName(
            from: ["__CFBundleIdentifier": "com.exafunction.windsurf"]
        )

        #expect(displayName == "Windsurf")
    }

    @Test
    func fallsBackToUpstreamVSCodeWhenNoForkSignalIsPresent() {
        #expect(VSCodeFamilyHost.displayName(from: ["TERM_PROGRAM": "vscode"]) == "VS Code")
        #expect(
            VSCodeFamilyHost.displayName(
                from: ["__CFBundleIdentifier": "com.microsoft.VSCode"]
            ) == "VS Code"
        )
    }

    @Test
    func keepsCallerSuppliedDefaultForInsiders() {
        let displayName = VSCodeFamilyHost.displayName(
            from: ["TERM_PROGRAM": "vscode-insiders"],
            default: "VS Code Insiders"
        )

        #expect(displayName == "VS Code Insiders")
    }
}
