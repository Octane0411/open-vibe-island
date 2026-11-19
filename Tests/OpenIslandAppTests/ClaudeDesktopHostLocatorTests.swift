import Darwin
import Testing
@testable import OpenIslandApp

struct ClaudeDesktopHostLocatorTests {
    private typealias Process = ClaudeDesktopHostLocator.ProcessSnapshot

    private let official = "/Applications/Claude.app"
    private let wrapped = "/Users/me/.wrapper/Claude.app"
    private let claudeCode = "/Users/me/Library/Application Support/Claude/claude-code/2.1.0/abc/claude.app/Contents/MacOS/claude"

    private var instances: [pid_t: String] { [100: official, 200: wrapped] }

    /// wrapped (200) → helper (210) → claude in /work/a
    /// official (100) → claude in /work/b
    private var processes: [Process] {
        [
            Process(pid: 100, parentPID: 1, executablePath: "\(official)/Contents/MacOS/Claude"),
            Process(pid: 200, parentPID: 1, executablePath: "\(wrapped)/Contents/MacOS/Claude"),
            Process(pid: 210, parentPID: 200, executablePath: "\(wrapped)/Contents/Helpers/disclaimer"),
            Process(pid: 211, parentPID: 210, executablePath: claudeCode, currentDirectory: "/work/a"),
            Process(pid: 110, parentPID: 100, executablePath: claudeCode, currentDirectory: "/work/b"),
        ]
    }

    @Test func picksTheCopyHostingTheSessionsDirectory() {
        #expect(ClaudeDesktopHostLocator.hostAppPath(
            instances: instances, processes: processes, workingDirectory: "/work/a"
        ) == wrapped)
        #expect(ClaudeDesktopHostLocator.hostAppPath(
            instances: instances, processes: processes, workingDirectory: "/work/b/"
        ) == official)
    }

    @Test func fallsBackToTheCopyRunningMostClaudeCodeSessions() {
        let more = processes + [
            Process(pid: 212, parentPID: 210, executablePath: claudeCode, currentDirectory: "/work/c"),
        ]
        #expect(ClaudeDesktopHostLocator.hostAppPath(
            instances: instances, processes: more, workingDirectory: "/elsewhere"
        ) == wrapped)
    }

    @Test func singleCopyNeedsNoProcessScan() {
        #expect(ClaudeDesktopHostLocator.hostAppPath(
            instances: [100: official], processes: [], workingDirectory: nil
        ) == official)
    }

    @Test func returnsNilWhenNoCopyHostsClaudeCode() {
        let appsOnly = Array(processes.prefix(2))
        #expect(ClaudeDesktopHostLocator.hostAppPath(
            instances: instances, processes: appsOnly, workingDirectory: "/work/a"
        ) == nil)
    }
}
