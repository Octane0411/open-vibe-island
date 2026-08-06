import Testing
@testable import OpenIslandCore

struct TerminalAppInferenceTests {
    @Test
    func vscodeTermProgramWithoutCursorSignalsIsVSCode() {
        let host = TerminalAppInference.resolveVSCodeFamilyHost(from: [
            "TERM_PROGRAM": "vscode",
        ])
        #expect(host == "VS Code")
        #expect(TerminalAppInference.isCursorEnvironment(["TERM_PROGRAM": "vscode"]) == false)
    }

    @Test
    func cursorTraceIdDisambiguatesCursorFromVSCode() {
        let host = TerminalAppInference.resolveVSCodeFamilyHost(from: [
            "TERM_PROGRAM": "vscode",
            "CURSOR_TRACE_ID": "abc-123",
        ])
        #expect(host == "Cursor")
    }

    @Test
    func cursorBundleIdentifierDisambiguatesCursorFromVSCode() {
        let host = TerminalAppInference.resolveVSCodeFamilyHost(from: [
            "TERM_PROGRAM": "vscode",
            "__CFBundleIdentifier": "com.todesktop.230313mzl4w4u92",
        ])
        #expect(host == "Cursor")
    }

    @Test
    func cursorAppPathInVSCodeHelperEnvDisambiguatesCursor() {
        let host = TerminalAppInference.resolveVSCodeFamilyHost(from: [
            "TERM_PROGRAM": "vscode",
            "VSCODE_GIT_ASKPASS_NODE": "/Applications/Cursor.app/Contents/Resources/app/resources/helpers/node",
        ])
        #expect(host == "Cursor")
    }

    @Test
    func plainVSCodeAskpassPathStaysVSCode() {
        let host = TerminalAppInference.resolveVSCodeFamilyHost(from: [
            "TERM_PROGRAM": "vscode",
            "VSCODE_GIT_ASKPASS_NODE": "/Applications/Visual Studio Code.app/Contents/Resources/app/resources/helpers/node",
        ])
        #expect(host == "VS Code")
    }
}
