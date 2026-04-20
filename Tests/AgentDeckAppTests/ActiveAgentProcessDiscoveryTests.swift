import Foundation
import Testing
@testable import AgentDeckApp
import AgentDeckCore

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
                n/tmp/agent-deck
                """
            case "202":
                return """
                fcwd
                n/tmp/agent-deck
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
            workingDirectory: "/tmp/agent-deck",
            terminalTTY: "/dev/ttys002",
            terminalApp: "Ghostty"
        )))
        #expect(snapshots.contains(.init(
            tool: .codex,
            sessionID: "019d516f-71ee-7e40-bcff-502fedac0928",
            workingDirectory: "/tmp/agent-deck",
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
            n/tmp/agent-deck
            """
        }

        let snapshots = discovery.discover()

        #expect(snapshots == [
            .init(
                tool: .claudeCode,
                sessionID: "9df061a9-6836-4ccb-b83b-aea3196eca43",
                workingDirectory: "/tmp/agent-deck",
                terminalTTY: "/dev/ttys002",
                terminalApp: "Ghostty"
            ),
        ])
    }
}
