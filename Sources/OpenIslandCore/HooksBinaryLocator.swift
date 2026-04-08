import Foundation

public enum ManagedHooksBinary {
    public static let binaryName = "OpenIslandHooks"
    public static let legacyBinaryName = "VibeIslandHooks"

    public static func defaultURL(fileManager: FileManager = .default) -> URL {
        installDirectory(fileManager: fileManager)
            .appendingPathComponent(binaryName)
            .standardizedFileURL
    }

    public static func candidateURLs(fileManager: FileManager = .default) -> [URL] {
        [
            defaultURL(fileManager: fileManager),
            legacyInstallDirectory(fileManager: fileManager)
                .appendingPathComponent(legacyBinaryName)
                .standardizedFileURL,
        ]
    }

    @discardableResult
    public static func install(
        from sourceURL: URL,
        to destinationURL: URL? = nil,
        fileManager: FileManager = .default
    ) throws -> URL {
        let resolvedSourceURL = sourceURL.standardizedFileURL
        let resolvedDestinationURL = (destinationURL ?? defaultURL(fileManager: fileManager)).standardizedFileURL

        try fileManager.createDirectory(
            at: resolvedDestinationURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        if resolvedSourceURL != resolvedDestinationURL {
            if fileManager.fileExists(atPath: resolvedDestinationURL.path) {
                try fileManager.removeItem(at: resolvedDestinationURL)
            }
            try fileManager.copyItem(at: resolvedSourceURL, to: resolvedDestinationURL)
        }

        try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: resolvedDestinationURL.path)
        return resolvedDestinationURL
    }

    /// Overwrites the installed hooks binary if the bundle source differs.
    /// Returns `true` if the binary was updated.
    @discardableResult
    public static func updateIfNeeded(
        from sourceURL: URL,
        fileManager: FileManager = .default
    ) throws -> Bool {
        let installedURL = defaultURL(fileManager: fileManager)
        guard fileManager.fileExists(atPath: installedURL.path) else {
            return false
        }

        let sourceData = try Data(contentsOf: sourceURL)
        let installedData = try Data(contentsOf: installedURL)
        guard sourceData != installedData else {
            return false
        }

        try fileManager.removeItem(at: installedURL)
        try fileManager.copyItem(at: sourceURL, to: installedURL)
        try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: installedURL.path)
        return true
    }

    private static func installDirectory(fileManager: FileManager) -> URL {
        fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Application Support", isDirectory: true)
            .appendingPathComponent("OpenIsland", isDirectory: true)
            .appendingPathComponent("bin", isDirectory: true)
    }

    private static func legacyInstallDirectory(fileManager: FileManager) -> URL {
        fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Application Support", isDirectory: true)
            .appendingPathComponent("VibeIsland", isDirectory: true)
            .appendingPathComponent("bin", isDirectory: true)
    }
}

public enum HooksBinaryLocator {
    public static func locate(
        fileManager: FileManager = .default,
        currentDirectory: URL? = nil,
        executableDirectory: URL? = nil,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> URL? {
        if let explicitPath = environment["OPEN_ISLAND_HOOKS_BINARY"] ?? environment["VIBE_ISLAND_HOOKS_BINARY"],
           fileManager.isExecutableFile(atPath: explicitPath) {
            return URL(fileURLWithPath: explicitPath).standardizedFileURL
        }

        let currentDirectory = currentDirectory
            ?? URL(fileURLWithPath: fileManager.currentDirectoryPath, isDirectory: true)
        let candidates = [
            executableDirectory?.appendingPathComponent("OpenIslandHooks"),
            executableDirectory?.deletingLastPathComponent().appendingPathComponent("OpenIslandHooks"),
            executableDirectory?.deletingLastPathComponent().appendingPathComponent("Helpers/OpenIslandHooks"),
            executableDirectory?.appendingPathComponent("VibeIslandHooks"),
            executableDirectory?.deletingLastPathComponent().appendingPathComponent("VibeIslandHooks"),
            executableDirectory?.deletingLastPathComponent().appendingPathComponent("Helpers/VibeIslandHooks"),
        ].compactMap { $0 } + ManagedHooksBinary.candidateURLs(fileManager: fileManager) + {
            #if arch(arm64)
            let archTriple = "arm64-apple-macosx"
            #elseif arch(x86_64)
            let archTriple = "x86_64-apple-macosx"
            #endif
            return [
                currentDirectory.appendingPathComponent(".build/\(archTriple)/release/OpenIslandHooks"),
                currentDirectory.appendingPathComponent(".build/release/OpenIslandHooks"),
                currentDirectory.appendingPathComponent(".build/\(archTriple)/release/VibeIslandHooks"),
                currentDirectory.appendingPathComponent(".build/release/VibeIslandHooks"),
                currentDirectory.appendingPathComponent(".build/\(archTriple)/debug/OpenIslandHooks"),
                currentDirectory.appendingPathComponent(".build/debug/OpenIslandHooks"),
                currentDirectory.appendingPathComponent(".build/\(archTriple)/debug/VibeIslandHooks"),
                currentDirectory.appendingPathComponent(".build/debug/VibeIslandHooks"),
            ]
        }()

        for candidate in candidates where fileManager.isExecutableFile(atPath: candidate.path) {
            return candidate.standardizedFileURL
        }

        return nil
    }
}
