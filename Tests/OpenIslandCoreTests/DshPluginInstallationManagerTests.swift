import Foundation
import Testing
@testable import OpenIslandCore

/// DSH plugin installation manager against a sandboxed `~/.dsh` tree.
/// Never touches the user's real `~/.dsh` (IRON RULE).
struct DshPluginInstallationManagerTests {
    private func makeSandbox(pluginJS: String = "export default class {}\n") throws -> (dshRoot: URL, pluginSource: URL) {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("dsh-install-\(UUID().uuidString)", isDirectory: true)
        let dshRoot = root.appendingPathComponent(".dsh", isDirectory: true)
        let pluginSource = root.appendingPathComponent("plugin-source", isDirectory: true)
        try FileManager.default.createDirectory(at: dshRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: pluginSource, withIntermediateDirectories: true)
        try Data(pluginJS.utf8).write(to: pluginSource.appendingPathComponent("index.js"))
        try Data(#"{"name":"open-island-dsh"}"#.utf8).write(to: pluginSource.appendingPathComponent("package.json"))
        return (dshRoot, pluginSource)
    }

    /// Creates `~/.dsh/profiles/<name>/` with user-authored files that must
    /// survive install and uninstall byte-for-byte.
    private func makeProfile(_ dshRoot: URL, name: String, existingPatch: String?) throws {
        let profileDir = dshRoot.appendingPathComponent("profiles", isDirectory: true).appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: profileDir, withIntermediateDirectories: true)
        try Data(#"{"name":"dsh-profile-\#(name)","private":true}"#.utf8)
            .write(to: profileDir.appendingPathComponent("package.json"))
        if let existingPatch {
            try Data(existingPatch.utf8).write(to: profileDir.appendingPathComponent("cordis.patch.yml"))
        }
    }

    @Test
    func statusOnMissingDshHomeReturnsEmptyProfiles() throws {
        let (dshRoot, pluginSource) = try makeSandbox()
        defer { try? FileManager.default.removeItem(at: dshRoot.deletingLastPathComponent()) }

        let manager = DshPluginInstallationManager(dshDirectory: dshRoot, pluginSourceURL: pluginSource)
        let status = try manager.status()
        #expect(status.profiles.isEmpty)
        #expect(!status.pluginInstalledInAllDetectedProfiles)
    }

    @Test
    func installInjectsEveryDetectedProfileAndPreservesUserEntries() throws {
        let (dshRoot, pluginSource) = try makeSandbox()
        defer { try? FileManager.default.removeItem(at: dshRoot.deletingLastPathComponent()) }

        let userPatch = """
        # user-authored hook
        - insert:
            - id: zotero
              name: dsh-zotero
              config: {}
        """
        try makeProfile(dshRoot, name: "desktop", existingPatch: userPatch)
        try makeProfile(dshRoot, name: "tui", existingPatch: nil)

        let manager = DshPluginInstallationManager(dshDirectory: dshRoot, pluginSourceURL: pluginSource)
        try manager.install()

        let status = try manager.status()
        #expect(status.profiles.map(\.name).sorted() == ["desktop", "tui"])
        #expect(status.pluginInstalledInAllDetectedProfiles)

        for profile in status.profiles {
            #expect(profile.patchEntryPresent)
            #expect(profile.nodeModulesPresent)
            #expect(profile.installed)

            let patch = try String(contentsOf: profile.directory.appendingPathComponent("cordis.patch.yml"), encoding: .utf8)
            #expect(patch.contains("name: open-island-dsh"))
            // User entry survives.
            #expect(patch.contains("name: dsh-zotero") || profile.name == "tui")
            // The unmodified package.json is byte-identical.
            let packageJSON = try String(contentsOf: profile.directory.appendingPathComponent("package.json"), encoding: .utf8)
            #expect(packageJSON.contains(#""name":"dsh-profile-\#(profile.name)""#))
            // A backup of the pre-install state exists exactly when the
            // profile already had a patch file (desktop had one, tui did not).
            if profile.name == "desktop" {
                #expect(!profile.backups.isEmpty)
            } else {
                #expect(profile.backups.isEmpty)
            }
        }

        // Plugin payload landed inside node_modules.
        let installedIndex = status.profiles[0]
            .directory.appendingPathComponent("node_modules")
            .appendingPathComponent("open-island-dsh")
            .appendingPathComponent("index.js")
        #expect(FileManager.default.fileExists(atPath: installedIndex.path))
    }

    @Test
    func installIsIdempotentAcrossRepeatedRuns() throws {
        let (dshRoot, pluginSource) = try makeSandbox()
        defer { try? FileManager.default.removeItem(at: dshRoot.deletingLastPathComponent()) }
        try makeProfile(dshRoot, name: "desktop", existingPatch: nil)

        let manager = DshPluginInstallationManager(dshDirectory: dshRoot, pluginSourceURL: pluginSource)
        try manager.install()
        try manager.install()

        let patch = try String(contentsOf: dshRoot.appendingPathComponent("profiles/desktop/cordis.patch.yml"), encoding: .utf8)
        #expect(patch.components(separatedBy: "name: open-island-dsh").count - 1 == 1)
    }

    @Test
    func installReplacesPristineEmptyArrayTemplateInPlace() throws {
        let (dshRoot, pluginSource) = try makeSandbox()
        defer { try? FileManager.default.removeItem(at: dshRoot.deletingLastPathComponent()) }

        // Pristine profile: the whole patch document is a bare `[]`.
        let pristineTemplate = """
        # Your patch layer for this dsh profile, applied after every bundle layer:
        # a top-level YAML array of loader patch entries.
        []
        """
        try makeProfile(dshRoot, name: "headless", existingPatch: pristineTemplate)
        let patchURL = dshRoot.appendingPathComponent("profiles/headless/cordis.patch.yml")

        let manager = DshPluginInstallationManager(dshDirectory: dshRoot, pluginSourceURL: pluginSource)
        try manager.install()

        let installed = try String(contentsOf: patchURL, encoding: .utf8)
        // The managed entry replaced the `[]` line; comments survive.
        #expect(installed.contains("name: open-island-dsh"))
        #expect(!installed.contains("\n[]"))
        #expect(installed.contains("# a top-level YAML array of loader patch entries."))

        // Uninstall restores the pristine `[]` template byte-for-byte.
        try manager.uninstall()
        let restored = try String(contentsOf: patchURL, encoding: .utf8)
        #expect(restored == pristineTemplate)
    }

    @Test
    func uninstallRestoresUserStateExactly() throws {
        let (dshRoot, pluginSource) = try makeSandbox()
        defer { try? FileManager.default.removeItem(at: dshRoot.deletingLastPathComponent()) }

        let userPatch = """
        # user-authored hook
        - insert:
            - id: zotero
              name: dsh-zotero
              config: {}
        """
        try makeProfile(dshRoot, name: "desktop", existingPatch: userPatch)
        let patchURL = dshRoot.appendingPathComponent("profiles/desktop/cordis.patch.yml")
        let originalPatch = try String(contentsOf: patchURL, encoding: .utf8)

        let manager = DshPluginInstallationManager(dshDirectory: dshRoot, pluginSourceURL: pluginSource)
        try manager.install()
        try manager.uninstall()

        let status = try manager.status()
        #expect(!status.pluginInstalledInAllDetectedProfiles)
        #expect(!status.profiles[0].installed)
        // The patch file is restored to its exact pre-install contents.
        let restoredPatch = try String(contentsOf: patchURL, encoding: .utf8)
        #expect(restoredPatch == originalPatch)
        // node_modules payload is gone, package.json untouched.
        #expect(!FileManager.default.fileExists(
            atPath: dshRoot.appendingPathComponent("profiles/desktop/node_modules/open-island-dsh").path
        ))
        #expect(FileManager.default.fileExists(atPath: dshRoot.appendingPathComponent("profiles/desktop/package.json").path))
    }
}
