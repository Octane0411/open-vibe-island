import Foundation
import Testing
@testable import OpenIslandCore

struct HermesHookInstallationManagerTests {
    private func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("hermes-hook-manager-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test
    func uninstallRemovesConfigFileThatOnlyHeldManagedHooks() throws {
        let hermesDirectory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: hermesDirectory) }

        let managedBinaryURL = hermesDirectory
            .appendingPathComponent("bin", isDirectory: true)
            .appendingPathComponent(ManagedHooksBinary.binaryName)
        try FileManager.default.createDirectory(
            at: managedBinaryURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("#!/bin/sh\nexit 0\n".utf8).write(to: managedBinaryURL)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: managedBinaryURL.path
        )

        let manager = HermesHookInstallationManager(
            hermesDirectory: hermesDirectory,
            managedHooksBinaryURL: managedBinaryURL
        )

        try manager.install(hooksBinaryURL: managedBinaryURL)

        let configURL = hermesDirectory.appendingPathComponent("config.yaml")
        #expect(FileManager.default.fileExists(atPath: configURL.path))
        #expect(try manager.status().managedHooksPresent)

        let status = try manager.uninstall()

        // The config held nothing but the managed hooks block, so uninstall
        // has to delete it — leaving the file behind would keep reporting the
        // hooks as installed after the manifest is gone.
        #expect(!status.managedHooksPresent)
        #expect(!FileManager.default.fileExists(atPath: configURL.path))
    }
}
