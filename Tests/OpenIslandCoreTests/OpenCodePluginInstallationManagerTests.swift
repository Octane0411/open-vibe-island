import Foundation
import Testing
@testable import OpenIslandCore

struct OpenCodePluginInstallationManagerTests {
    @Test
    func statusDetectsOutdatedManagedPlugin() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let manager = OpenCodePluginInstallationManager(openCodeConfigDirectory: directory)
        let currentPlugin = Data("current plugin".utf8)
        let installed = try manager.install(pluginSourceData: currentPlugin)

        #expect(installed.isCurrent)

        let updatedPlugin = Data("updated plugin".utf8)
        let outdated = try manager.status(expectedPluginData: updatedPlugin)

        #expect(outdated.isInstalled)
        #expect(!outdated.isCurrent)
    }
}
