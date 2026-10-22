import Foundation
import Testing
@testable import OpenIslandCore

struct HooksBinaryLocatorTests {
    @Test
    func locateFindsBundledHelperBinaryInsideAppBundle() throws {
        let rootURL = temporaryRootURL(named: "hooks-binary-locator")
        let executableDirectory = rootURL
            .appendingPathComponent("Open Island.app", isDirectory: true)
            .appendingPathComponent("Contents", isDirectory: true)
            .appendingPathComponent("MacOS", isDirectory: true)
        let helperBinaryURL = rootURL
            .appendingPathComponent("Open Island.app", isDirectory: true)
            .appendingPathComponent("Contents", isDirectory: true)
            .appendingPathComponent("Helpers", isDirectory: true)
            .appendingPathComponent("OpenIslandHooks")

        defer {
            try? FileManager.default.removeItem(at: rootURL)
        }

        try makeExecutable(at: helperBinaryURL, contents: "bundled-helper")

        let locatedURL = HooksBinaryLocator.locate(
            currentDirectory: rootURL,
            executableDirectory: executableDirectory,
            environment: [:]
        )

        #expect(locatedURL?.path == helperBinaryURL.standardizedFileURL.path)
    }

    @Test
    func locateFindsLegacyBundledHelperBinaryInsideAppBundle() throws {
        let rootURL = temporaryRootURL(named: "hooks-binary-locator-legacy")
        let executableDirectory = rootURL
            .appendingPathComponent("Open Island.app", isDirectory: true)
            .appendingPathComponent("Contents", isDirectory: true)
            .appendingPathComponent("MacOS", isDirectory: true)
        let helperBinaryURL = rootURL
            .appendingPathComponent("Open Island.app", isDirectory: true)
            .appendingPathComponent("Contents", isDirectory: true)
            .appendingPathComponent("Helpers", isDirectory: true)
            .appendingPathComponent("VibeIslandHooks")

        defer {
            try? FileManager.default.removeItem(at: rootURL)
        }

        try makeExecutable(at: helperBinaryURL, contents: "legacy-bundled-helper")

        let locatedURL = HooksBinaryLocator.locate(
            currentDirectory: rootURL,
            executableDirectory: executableDirectory,
            environment: [:]
        )

        #expect(locatedURL?.path == helperBinaryURL.standardizedFileURL.path)
    }

    @Test
    func updateIfNeededRestoresMissingInstalledBinary() throws {
        let rootURL = temporaryRootURL(named: "hooks-binary-restore")
        let fileManager = HomeOverridingFileManager(
            homeDirectory: rootURL.appendingPathComponent("home", isDirectory: true)
        )
        let sourceURL = rootURL.appendingPathComponent("Helpers/OpenIslandHooks")
        let installedURL = ManagedHooksBinary.defaultURL(fileManager: fileManager)

        defer {
            try? FileManager.default.removeItem(at: rootURL)
        }

        try makeExecutable(at: sourceURL, contents: "bundled-helper")

        let updated = try ManagedHooksBinary.updateIfNeeded(from: sourceURL, fileManager: fileManager)

        #expect(updated)
        #expect(try Data(contentsOf: installedURL) == Data("bundled-helper".utf8))
        let permissions = try FileManager.default.attributesOfItem(atPath: installedURL.path)[.posixPermissions] as? Int
        #expect(permissions == 0o755)
    }

    @Test
    func updateIfNeededReplacesOutdatedInstalledBinary() throws {
        let rootURL = temporaryRootURL(named: "hooks-binary-replace")
        let fileManager = HomeOverridingFileManager(
            homeDirectory: rootURL.appendingPathComponent("home", isDirectory: true)
        )
        let sourceURL = rootURL.appendingPathComponent("Helpers/OpenIslandHooks")
        let installedURL = ManagedHooksBinary.defaultURL(fileManager: fileManager)

        defer {
            try? FileManager.default.removeItem(at: rootURL)
        }

        try makeExecutable(at: sourceURL, contents: "new-helper")
        try makeExecutable(at: installedURL, contents: "old-helper")

        let updated = try ManagedHooksBinary.updateIfNeeded(from: sourceURL, fileManager: fileManager)

        #expect(updated)
        #expect(try Data(contentsOf: installedURL) == Data("new-helper".utf8))
    }

    @Test
    func updateIfNeededLeavesMatchingInstalledBinaryAlone() throws {
        let rootURL = temporaryRootURL(named: "hooks-binary-current")
        let fileManager = HomeOverridingFileManager(
            homeDirectory: rootURL.appendingPathComponent("home", isDirectory: true)
        )
        let sourceURL = rootURL.appendingPathComponent("Helpers/OpenIslandHooks")
        let installedURL = ManagedHooksBinary.defaultURL(fileManager: fileManager)

        defer {
            try? FileManager.default.removeItem(at: rootURL)
        }

        try makeExecutable(at: sourceURL, contents: "helper")
        try makeExecutable(at: installedURL, contents: "helper")
        let fileNumberBefore = try #require(try fileNumber(at: installedURL))

        let updated = try ManagedHooksBinary.updateIfNeeded(from: sourceURL, fileManager: fileManager)

        #expect(!updated)
        #expect(try fileNumber(at: installedURL) == fileNumberBefore)
    }
}

/// Points `homeDirectoryForCurrentUser` at a temporary directory so tests can
/// exercise `ManagedHooksBinary.defaultURL` without touching the real home.
private final class HomeOverridingFileManager: FileManager, @unchecked Sendable {
    private let homeDirectory: URL

    init(homeDirectory: URL) {
        self.homeDirectory = homeDirectory
        super.init()
    }

    override var homeDirectoryForCurrentUser: URL {
        homeDirectory
    }
}

private func temporaryRootURL(named name: String) -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("open-island-\(name)-\(UUID().uuidString)", isDirectory: true)
}

private func makeExecutable(at url: URL, contents: String) throws {
    try FileManager.default.createDirectory(
        at: url.deletingLastPathComponent(),
        withIntermediateDirectories: true
    )
    try Data(contents.utf8).write(to: url)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
}

private func fileNumber(at url: URL) throws -> Int? {
    try FileManager.default.attributesOfItem(atPath: url.path)[.systemFileNumber] as? Int
}
