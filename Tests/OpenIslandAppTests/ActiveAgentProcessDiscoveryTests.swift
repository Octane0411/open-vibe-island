import Foundation
import Testing
@testable import OpenIslandApp
import OpenIslandCore

struct ActiveAgentProcessDiscoveryTests {
    @Test
    func discoverOnlyReturnsInteractiveClaudeAndCodexProcesses() {
        let discovery = ActiveAgentProcessDiscovery { executablePath, arguments in
            if executablePath == "/bin/ps" {
                return """
                  101 1 ?? /Users/test/.local/bin/claude --resume abc
                  102 301 ttys002 claude
                  201 1 ttys000 node /Users/test/.nvm/versions/node/v22/bin/codex
                  202 401 ttys001 /Users/test/.nvm/versions/node/v22/lib/node_modules/@openai/codex/node_modules/@openai/codex-darwin-arm64/vendor/aarch64-apple-darwin/codex/codex
                  301 900 ttys002 -/opt/homebrew/bin/fish
                  401 900 ttys001 -/opt/homebrew/bin/fish
                  900 1 ?? /Applications/Ghostty.app/Contents/MacOS/ghostty
                """
            }

            guard executablePath == "/usr/sbin/lsof",
                  let pid = arguments.dropFirst(2).first else {
                return nil
            }

            switch pid {
            case "102":
                return """
                fcwd
                n/tmp/open-island
                """
            case "202":
                return """
                fcwd
                n/tmp/open-island
                n/Users/test/.codex/sessions/2026/04/03/rollout-2026-04-03T11-42-31-019d516f-71ee-7e40-bcff-502fedac0928.jsonl
                """
            default:
                Issue.record("unexpected lsof lookup for pid \(pid)")
                return nil
            }
        }

        let snapshots = discovery.discover()

        #expect(snapshots.count == 2)
        #expect(snapshots.contains(.init(
            tool: .claudeCode,
            sessionID: nil,
            workingDirectory: "/tmp/open-island",
            terminalTTY: "/dev/ttys002",
            terminalApp: "Ghostty"
        )))
        #expect(snapshots.contains(.init(
            tool: .codex,
            sessionID: "019d516f-71ee-7e40-bcff-502fedac0928",
            workingDirectory: "/tmp/open-island",
            terminalTTY: "/dev/ttys001",
            terminalApp: "Ghostty"
        )))
    }

    @Test
    func discoverClaudeSessionIDFromResumeFlagWhenTranscriptIsNotOpen() {
        let discovery = ActiveAgentProcessDiscovery { executablePath, _ in
            if executablePath == "/bin/ps" {
                return """
                  102 301 ttys002 /Users/test/.local/bin/claude --resume 9df061a9-6836-4ccb-b83b-aea3196eca43 --permission-mode acceptEdits
                  301 900 ttys002 -/opt/homebrew/bin/fish
                  900 1 ?? /Applications/Ghostty.app/Contents/MacOS/ghostty
                """
            }

            guard executablePath == "/usr/sbin/lsof" else {
                return nil
            }

            return """
            fcwd
            n/tmp/open-island
            """
        }

        let snapshots = discovery.discover()

        #expect(snapshots == [
            .init(
                tool: .claudeCode,
                sessionID: "9df061a9-6836-4ccb-b83b-aea3196eca43",
                workingDirectory: "/tmp/open-island",
                terminalTTY: "/dev/ttys002",
                terminalApp: "Ghostty"
            ),
        ])
    }

    @Test
    func codexDiscoveryUsesNewestOpenRolloutWhenProcessKeepsOldDescriptors() {
        let discovery = ActiveAgentProcessDiscovery { executablePath, arguments in
            if executablePath == "/bin/ps" {
                return """
                  202 401 ttys001 /opt/homebrew/bin/codex
                  401 900 ttys001 -/opt/homebrew/bin/fish
                  900 1 ?? /Applications/Ghostty.app/Contents/MacOS/ghostty
                """
            }

            guard executablePath == "/usr/sbin/lsof",
                  let pid = arguments.dropFirst(2).first else {
                return nil
            }

            guard pid == "202" else {
                Issue.record("unexpected lsof lookup for pid \(pid)")
                return nil
            }

            return """
            fcwd
            n/tmp/open-island
            n/Users/test/.codex/sessions/2026/05/10/rollout-2026-05-10T01-04-52-019e0db2-f3a5-7fe0-bea8-e63bd356c226.jsonl
            n/Users/test/.codex/sessions/2026/05/10/rollout-2026-05-10T01-20-29-019e0dc1-3f8b-7eb0-ae8d-04a5911e95b9.jsonl
            """
        }

        let snapshots = discovery.discover()

        #expect(snapshots == [
            .init(
                tool: .codex,
                sessionID: "019e0dc1-3f8b-7eb0-ae8d-04a5911e95b9",
                workingDirectory: "/tmp/open-island",
                terminalTTY: "/dev/ttys001",
                terminalApp: "Ghostty"
            ),
        ])
    }

    @Test
    func discoverCursorAgentProcessFromOpenChatStore() {
        let discovery = ActiveAgentProcessDiscovery { executablePath, arguments in
            if executablePath == "/bin/ps" {
                return """
                  302 401 ttys003 /Users/test/.local/bin/cursor-agent --use-system-ca /Users/test/.local/share/cursor-agent/versions/2026.06.26/index.js
                  401 500 ttys003 -/opt/homebrew/bin/fish
                  500 900 ttys003 /usr/bin/login -flp test /bin/bash --noprofile --norc -c exec -l /opt/homebrew/bin/fish
                  900 1 ?? /Applications/Ghostty.app/Contents/MacOS/ghostty
                """
            }

            guard executablePath == "/usr/sbin/lsof",
                  let pid = arguments.dropFirst(2).first else {
                return nil
            }

            guard pid == "302" else {
                Issue.record("unexpected lsof lookup for pid \(pid)")
                return nil
            }

            return """
            fcwd
            n/tmp/simple-agent-lab
            n/Users/test/.cursor/chats/cf595f65441221b71014fd6f7b9999b2/6f7b9f8a-2bd0-48b4-a497-9801dd191d03/store.db-shm
            """
        }

        let snapshots = discovery.discover()

        #expect(snapshots == [
            .init(
                tool: .cursor,
                sessionID: "6f7b9f8a-2bd0-48b4-a497-9801dd191d03",
                workingDirectory: "/tmp/simple-agent-lab",
                terminalTTY: "/dev/ttys003",
                terminalApp: "Ghostty"
            ),
        ])
    }

    @Test
    func discoverCursorAgentDeduplicatesProcessesForSameConversation() {
        let discovery = ActiveAgentProcessDiscovery { executablePath, arguments in
            if executablePath == "/bin/ps" {
                return """
                  302 401 ttys003 /Users/test/.local/bin/cursor-agent --use-system-ca /Users/test/.local/share/cursor-agent/versions/2026.06.26/index.js
                  303 402 ttys004 /Users/test/.local/bin/cursor-agent --use-system-ca /Users/test/.local/share/cursor-agent/versions/2026.06.26/index.js
                  401 900 ttys003 -/opt/homebrew/bin/fish
                  402 900 ttys004 -/opt/homebrew/bin/fish
                  900 1 ?? /Applications/Ghostty.app/Contents/MacOS/ghostty
                """
            }

            guard executablePath == "/usr/sbin/lsof",
                  let pid = arguments.dropFirst(2).first else {
                return nil
            }

            guard pid == "302" || pid == "303" else {
                Issue.record("unexpected lsof lookup for pid \(pid)")
                return nil
            }

            return """
            fcwd
            n/tmp/simple-agent-lab
            n/Users/test/.cursor/chats/cf595f65441221b71014fd6f7b9999b2/6f7b9f8a-2bd0-48b4-a497-9801dd191d03/store.db
            """
        }

        let snapshots = discovery.discover()

        #expect(snapshots.count == 1)
        #expect(snapshots.first?.sessionID == "6f7b9f8a-2bd0-48b4-a497-9801dd191d03")
    }

    /// VS Code forks (Cursor, Windsurf, Trae, Qoder) bundle Electron's "Code
    /// Helper" inside their .app bundles. Their helper paths therefore contain
    /// both "/<fork>.app/" and "/code helper", and Open Island used to match
    /// the broad "/code helper" check first → mis-attributed every fork to
    /// stock VS Code (#415). Verify each fork is recognized correctly.
    @Test(arguments: [
        ("/Applications/Cursor.app/Contents/Frameworks/Code Helper.app/Contents/MacOS/Code Helper", "Cursor"),
        ("/Applications/Windsurf.app/Contents/Frameworks/Code Helper.app/Contents/MacOS/Code Helper", "Windsurf"),
        ("/Applications/Trae.app/Contents/Frameworks/Code Helper.app/Contents/MacOS/Code Helper", "Trae"),
        ("/Applications/Qoder.app/Contents/Frameworks/Code Helper.app/Contents/MacOS/Code Helper", "Qoder"),
        ("/Applications/Visual Studio Code.app/Contents/Frameworks/Code Helper.app/Contents/MacOS/Code Helper", "VS Code"),
    ])
    func recognizesVSCodeForkBeforeFallingBackToVSCode(parentCommand: String, expectedTerminal: String) {
        let discovery = ActiveAgentProcessDiscovery { executablePath, arguments in
            if executablePath == "/bin/ps" {
                return """
                  102 301 ttys002 /Users/test/.local/bin/claude
                  301 900 ttys002 -/opt/homebrew/bin/fish
                  900 1 ?? \(parentCommand)
                """
            }
            guard executablePath == "/usr/sbin/lsof" else {
                return nil
            }
            return """
            fcwd
            n/tmp/open-island
            """
        }

        let snapshots = discovery.discover()

        #expect(snapshots == [
            .init(
                tool: .claudeCode,
                sessionID: nil,
                workingDirectory: "/tmp/open-island",
                terminalTTY: "/dev/ttys002",
                terminalApp: expectedTerminal
            ),
        ])
    }

    @Test
    func discoverDetectsOpenCodeProcessWithoutTTY() {
        let discovery = ActiveAgentProcessDiscovery { executablePath, arguments in
            if executablePath == "/bin/ps" {
                return """
                  102 1 ?? opencode
                """
            }

            guard executablePath == "/usr/sbin/lsof",
                  let pid = arguments.dropFirst(2).first else {
                return nil
            }

            switch pid {
            case "102":
                return """
                fcwd
                n/tmp/open-island
                """
            default:
                Issue.record("unexpected lsof lookup for pid \(pid)")
                return nil
            }
        }

        let snapshots = discovery.discover()

        let openCodeSnapshots = snapshots.filter { $0.tool == .openCode }
        #expect(openCodeSnapshots.count == 1)
        #expect(openCodeSnapshots.first?.workingDirectory == "/tmp/open-island")
        #expect(openCodeSnapshots.first?.terminalTTY == nil)
    }
}
