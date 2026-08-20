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
    func installRemovesEmptyTopLevelHooksArrayPlaceholder() {
        let userToml = """
        default_model = "kimi-code/kimi-for-coding"
        default_thinking = true
        hooks = [] # Kimi may seed this placeholder

        [models."kimi-code/kimi-for-coding"]
        provider = "managed:kimi-code"

        [[hooks]]
        event = "PostToolUse"
        command = "user-hook"

        """
        let command = KimiHookInstaller.hookCommand(for: "/opt/open-island/OpenIslandHooks")
        let mutation = KimiHookInstaller.installConfigTOML(
            existingContents: userToml,
            hookCommand: command
        )

        let contents = try! #require(mutation.contents)
        #expect(contents.contains("hooks = []") == false)
        #expect(contents.contains("[models.\"kimi-code/kimi-for-coding\"]"))
        #expect(contents.contains("command = \"user-hook\""))
        #expect(contents.contains("event = \"SessionStart\""))
    }

    @Test
    func installKeepsNonTopLevelHooksArrayAssignments() {
        let userToml = """
        [harness]
        hooks = []
        embedded = true

        """
        let command = KimiHookInstaller.hookCommand(for: "/opt/open-island/OpenIslandHooks")
        let mutation = KimiHookInstaller.installConfigTOML(
            existingContents: userToml,
            hookCommand: command
        )

        let contents = try! #require(mutation.contents)
        #expect(contents.contains("[harness]\nhooks = []\nembedded = true"))
        #expect(contents.contains("event = \"SessionStart\""))
    }

    @Test
    func installRemovesSpacedEmptyTopLevelHooksArrayPlaceholder() {
        let userToml = """
        default_model = "kimi-code/kimi-for-coding"
        hooks = [ ] # Kimi may seed this placeholder

        """
        let command = KimiHookInstaller.hookCommand(for: "/opt/open-island/OpenIslandHooks")
        let mutation = KimiHookInstaller.installConfigTOML(
            existingContents: userToml,
            hookCommand: command
        )

        let contents = try! #require(mutation.contents)
        #expect(contents.contains("hooks = [ ] # Kimi may seed this placeholder") == false)
        #expect(contents.contains("event = \"SessionStart\""))
    }

    @Test
    func installKeepsHooksArrayAfterCommentedTableHeader() {
        let userToml = """
        [harness] # user-owned table
        hooks = [ ]
        embedded = true

        """
        let command = KimiHookInstaller.hookCommand(for: "/opt/open-island/OpenIslandHooks")
        let mutation = KimiHookInstaller.installConfigTOML(
            existingContents: userToml,
            hookCommand: command
        )

        let contents = try! #require(mutation.contents)
        #expect(contents.contains("[harness] # user-owned table\nhooks = [ ]\nembedded = true"))
        #expect(contents.contains("event = \"SessionStart\""))
    }

    @Test
    func installKeepsHooksTextInsideMultilineStrings() {
        let userToml = #"""
        basic_message = """
        hooks = []
        """
        literal_message = '''
        hooks = [ ]
        '''
        hooks = [ ] # actual placeholder

        """#
        let command = KimiHookInstaller.hookCommand(for: "/opt/open-island/OpenIslandHooks")
        let mutation = KimiHookInstaller.installConfigTOML(
            existingContents: userToml,
            hookCommand: command
        )

        let contents = try! #require(mutation.contents)
        #expect(contents.contains("hooks = [ ] # actual placeholder") == false)
        #expect(contents.contains(#"""
        basic_message = """
        hooks = []
        """
        """#))
        #expect(contents.contains("literal_message = '''\nhooks = [ ]\n'''"))
    }

    @Test
    func installKeepsNonEmptyTopLevelHooksArrayWithStrings() {
        let userToml = #"""
        default_model = "kimi-code/kimi-for-coding"
        hooks = ["user-hook"]

        """#
        let command = KimiHookInstaller.hookCommand(for: "/opt/open-island/OpenIslandHooks")
        let mutation = KimiHookInstaller.installConfigTOML(
            existingContents: userToml,
            hookCommand: command
        )

        let contents = try! #require(mutation.contents)
        #expect(contents.contains(#"hooks = ["user-hook"]"#))
        #expect(contents.contains("event = \"SessionStart\""))
    }

    @Test
    func installRemovesEmptyTopLevelHooksArrayFromCRLFConfig() {
        let userToml = "default_model = \"kimi-code/kimi-for-coding\"\r\nhooks = []\r\n"
        let command = KimiHookInstaller.hookCommand(for: "/opt/open-island/OpenIslandHooks")
        let mutation = KimiHookInstaller.installConfigTOML(
            existingContents: userToml,
            hookCommand: command
        )

        let contents = try! #require(mutation.contents)
        #expect(contents.contains("hooks = []") == false)
        #expect(contents.contains("event = \"SessionStart\""))
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
    func managerDefaultsToKimiCodeConfigDirectory() {
        let manager = KimiHookInstallationManager()
        #expect(manager.kimiDirectory.lastPathComponent == ".kimi-code")
    }

    @Test
    func managerInstallStatusUninstallRoundTripPreservesUserHooks() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("kimi-hooks-tests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let kimiDir = root.appendingPathComponent(".kimi-code", isDirectory: true)
        try FileManager.default.createDirectory(at: kimiDir, withIntermediateDirectories: true)
        let sourceBinary = root.appendingPathComponent("OpenIslandHooks-source")
        try "#!/bin/sh\nexit 0\n".write(to: sourceBinary, atomically: true, encoding: .utf8)

        let userToml = """
        default_model = "kimi-code/kimi-for-coding"

        [[hooks]]
        event = "PostToolUse"
        command = "user-hook"

        """
        let configURL = kimiDir.appendingPathComponent("config.toml")
        try userToml.write(to: configURL, atomically: true, encoding: .utf8)

        let manager = KimiHookInstallationManager(
            kimiDirectory: kimiDir,
            managedHooksBinaryURL: root.appendingPathComponent("managed/OpenIslandHooks")
        )

        let installed = try manager.install(hooksBinaryURL: sourceBinary)
        #expect(installed.managedHooksPresent)
        #expect(installed.hooksBinaryURL != nil)

        let installedContents = try String(contentsOf: configURL, encoding: .utf8)
        #expect(installedContents.contains("user-hook"))
        #expect(installedContents.contains("default_model"))

        // Reinstall must not duplicate or rewrite managed blocks.
        _ = try manager.install(hooksBinaryURL: sourceBinary)
        let reinstalledContents = try String(contentsOf: configURL, encoding: .utf8)
        #expect(reinstalledContents == installedContents)

        let uninstalled = try manager.uninstall()
        #expect(uninstalled.managedHooksPresent == false)
        let remaining = try String(contentsOf: configURL, encoding: .utf8)
        #expect(remaining.contains("user-hook"))
        #expect(remaining.contains("default_model"))
        #expect(remaining.contains(KimiHookInstaller.markerComment) == false)
        let manifestURL = kimiDir.appendingPathComponent(KimiHookInstallerManifest.fileName)
        #expect(FileManager.default.fileExists(atPath: manifestURL.path) == false)
    }

    @Test
    func managerUninstallDeletesConfigThatOnlyHadManagedHooks() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("kimi-hooks-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let sourceBinary = root.appendingPathComponent("OpenIslandHooks-source")
        try "#!/bin/sh\nexit 0\n".write(to: sourceBinary, atomically: true, encoding: .utf8)

        let kimiDir = root.appendingPathComponent(".kimi-code", isDirectory: true)
        let manager = KimiHookInstallationManager(
            kimiDirectory: kimiDir,
            managedHooksBinaryURL: root.appendingPathComponent("managed/OpenIslandHooks")
        )

        _ = try manager.install(hooksBinaryURL: sourceBinary)
        let configURL = kimiDir.appendingPathComponent("config.toml")
        #expect(FileManager.default.fileExists(atPath: configURL.path))

        _ = try manager.uninstall()
        #expect(FileManager.default.fileExists(atPath: configURL.path) == false)
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
