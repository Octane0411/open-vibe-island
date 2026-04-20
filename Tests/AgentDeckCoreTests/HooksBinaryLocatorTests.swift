import Foundation
import Testing
@testable import AgentDeckCore

struct HooksBinaryLocatorTests {
    @Test
    func locateFindsBundledHelperBinaryInsideAppBundle() throws {
        let rootURL = temporaryRootURL(named: "hooks-binary-locator")
        let executableDirectory = rootURL
            .appendingPathComponent("Agent Deck.app", isDirectory: true)
            .appendingPathComponent("Contents", isDirectory: true)
            .appendingPathComponent("MacOS", isDirectory: true)
        let helperBinaryURL = rootURL
            .appendingPathComponent("Agent Deck.app", isDirectory: true)
            .appendingPathComponent("Contents", isDirectory: true)
            .appendingPathComponent("Helpers", isDirectory: true)
            .appendingPathComponent("AgentDeckHooks")

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
            .appendingPathComponent("Agent Deck.app", isDirectory: true)
            .appendingPathComponent("Contents", isDirectory: true)
            .appendingPathComponent("MacOS", isDirectory: true)
        let helperBinaryURL = rootURL
            .appendingPathComponent("Agent Deck.app", isDirectory: true)
            .appendingPathComponent("Contents", isDirectory: true)
            .appendingPathComponent("Helpers", isDirectory: true)
            .appendingPathComponent("AgentDeckHooks")

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
}

private func temporaryRootURL(named name: String) -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("agent-deck-\(name)-\(UUID().uuidString)", isDirectory: true)
}

private func makeExecutable(at url: URL, contents: String) throws {
    try FileManager.default.createDirectory(
        at: url.deletingLastPathComponent(),
        withIntermediateDirectories: true
    )
    try Data(contents.utf8).write(to: url)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
}
