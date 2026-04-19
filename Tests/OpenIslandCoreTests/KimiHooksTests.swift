import Foundation
import Testing
@testable import OpenIslandCore

struct KimiHooksTests {
    @Test
    func installIntoEmptyConfigEmitsAllManagedBlocks() {
        let command = KimiHookInstaller.hookCommand(for: "/opt/open-island/OpenIslandHooks")
        let mutation = KimiHookInstaller.installConfigTOML(
            existingContents: nil,
            hookCommand: command
        )

        #expect(mutation.changed)
        #expect(mutation.managedHooksPresent)
        let contents = try! #require(mutation.contents)

        for event in ["SessionStart", "UserPromptSubmit", "Stop", "Notification", "PreToolUse", "PostToolUse"] {
            #expect(contents.contains("event = \"\(event)\""))
        }

        #expect(contents.contains(KimiHookInstaller.markerComment))
        #expect(contents.contains("--source kimi"))
        #expect(contents.contains("timeout = \(KimiHookInstaller.managedTimeout)"))
    }

    @Test
    func installPreservesUnrelatedUserHooks() {
        let userToml = """
        default_model = "kimi-for-coding"

        [[hooks]]
        event = "PostToolUse"
        matcher = "WriteFile"
        command = "prettier --write"

        """
        let command = KimiHookInstaller.hookCommand(for: "/opt/open-island/OpenIslandHooks")
        let mutation = KimiHookInstaller.installConfigTOML(
            existingContents: userToml,
            hookCommand: command
        )

        let contents = try! #require(mutation.contents)
        #expect(contents.contains("prettier --write"))
        #expect(contents.contains("default_model = \"kimi-for-coding\""))
        #expect(contents.contains(KimiHookInstaller.markerComment))
    }

    @Test
    func reinstallIsIdempotent() {
        let command = KimiHookInstaller.hookCommand(for: "/opt/open-island/OpenIslandHooks")
        let firstInstall = KimiHookInstaller.installConfigTOML(
            existingContents: nil,
            hookCommand: command
        )
        let secondInstall = KimiHookInstaller.installConfigTOML(
            existingContents: firstInstall.contents,
            hookCommand: command
        )

        #expect(secondInstall.contents == firstInstall.contents)
        #expect(secondInstall.changed == false)
    }

    @Test
    func uninstallRemovesManagedBlocksAndKeepsUserHooks() {
        let command = KimiHookInstaller.hookCommand(for: "/opt/open-island/OpenIslandHooks")
        let userToml = """
        default_model = "kimi-for-coding"

        [[hooks]]
        event = "PostToolUse"
        matcher = "WriteFile"
        command = "prettier --write"

        """
        let installed = KimiHookInstaller.installConfigTOML(
            existingContents: userToml,
            hookCommand: command
        )

        let uninstall = KimiHookInstaller.uninstallConfigTOML(
            existingContents: installed.contents,
            managedCommand: command
        )

        #expect(uninstall.changed)
        let remaining = try! #require(uninstall.contents)
        #expect(remaining.contains("prettier --write"))
        #expect(remaining.contains("default_model"))
        #expect(remaining.contains(KimiHookInstaller.markerComment) == false)
        #expect(remaining.contains("--source kimi") == false)
    }

    @Test
    func uninstallHandlesEmptyInputGracefully() {
        let emptyMutation = KimiHookInstaller.uninstallConfigTOML(
            existingContents: nil,
            managedCommand: nil
        )
        #expect(emptyMutation.contents == nil)
        #expect(emptyMutation.changed == false)

        let blankMutation = KimiHookInstaller.uninstallConfigTOML(
            existingContents: "",
            managedCommand: "anything"
        )
        #expect(blankMutation.contents == nil)
        #expect(blankMutation.changed == false)
    }

    @Test
    func uninstallFallsBackToCommandMatchForMarkerlessEntries() {
        // Older installs (or third-party tooling mimicking our command) may lack the marker.
        // Uninstall should still clean them up when given the exact managed command.
        let command = KimiHookInstaller.hookCommand(for: "/opt/open-island/OpenIslandHooks")
        let legacyToml = """
        [[hooks]]
        event = "UserPromptSubmit"
        command = \(tomlQuoted(command))
        timeout = 45

        [[hooks]]
        event = "PostToolUse"
        command = "other-tool"

        """

        let mutation = KimiHookInstaller.uninstallConfigTOML(
            existingContents: legacyToml,
            managedCommand: command
        )

        #expect(mutation.changed)
        let remaining = try! #require(mutation.contents)
        #expect(remaining.contains("other-tool"))
        #expect(remaining.contains("--source kimi") == false)
    }

    @Test
    func uninstallReducesToNilWhenFileOnlyHadManagedContent() {
        let command = KimiHookInstaller.hookCommand(for: "/opt/open-island/OpenIslandHooks")
        let installed = KimiHookInstaller.installConfigTOML(
            existingContents: nil,
            hookCommand: command
        )

        let mutation = KimiHookInstaller.uninstallConfigTOML(
            existingContents: installed.contents,
            managedCommand: command
        )

        #expect(mutation.changed)
        #expect(mutation.contents == nil)
    }

    @Test
    func resolvedAgentToolMapsKimiSource() {
        var payload = ClaudeHookPayload(
            cwd: "/tmp",
            hookEventName: .sessionStart,
            sessionID: "kimi-session-1"
        )
        payload.hookSource = "kimi"

        #expect(payload.resolvedAgentTool == .kimiCLI)
    }

    // Matches the quoting KimiHookInstaller writes into config.toml so the test's
    // synthetic "legacy" entry decodes through the same path the installer uses.
    private func tomlQuoted(_ value: String) -> String {
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }
}
