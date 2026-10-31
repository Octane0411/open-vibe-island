import Foundation

public struct CodexHookInstallationStatus: Equatable, Sendable {
    public var codexDirectory: URL
    public var configURL: URL
    public var hooksURL: URL
    public var manifestURL: URL
    public var hooksBinaryURL: URL?
    public var featureFlagEnabled: Bool
    public var managedHooksPresent: Bool
    public var manifest: CodexHookInstallerManifest?

    public init(
        codexDirectory: URL,
        configURL: URL,
        hooksURL: URL,
        manifestURL: URL,
        hooksBinaryURL: URL?,
        featureFlagEnabled: Bool,
        managedHooksPresent: Bool,
        manifest: CodexHookInstallerManifest?
    ) {
        self.codexDirectory = codexDirectory
        self.configURL = configURL
        self.hooksURL = hooksURL
        self.manifestURL = manifestURL
        self.hooksBinaryURL = hooksBinaryURL
        self.featureFlagEnabled = featureFlagEnabled
        self.managedHooksPresent = managedHooksPresent
        self.manifest = manifest
    }
}

public final class CodexHookInstallationManager: @unchecked Sendable {
    public let codexDirectory: URL
    public let managedHooksBinaryURL: URL
    private let fileManager: FileManager
    private let featureKeyProvider: @Sendable () -> CodexHooksFeatureFlagKey

    public init(
        codexDirectory: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex", isDirectory: true),
        managedHooksBinaryURL: URL = ManagedHooksBinary.defaultURL(),
        fileManager: FileManager = .default,
        featureKeyProvider: @escaping @Sendable () -> CodexHooksFeatureFlagKey = CodexHookInstaller.preferredCodexHooksFeatureKey
    ) {
        self.codexDirectory = codexDirectory
        self.managedHooksBinaryURL = managedHooksBinaryURL.standardizedFileURL
        self.fileManager = fileManager
        self.featureKeyProvider = featureKeyProvider
    }

    public func status(hooksBinaryURL: URL? = nil) throws -> CodexHookInstallationStatus {
        let configURL = codexDirectory.appendingPathComponent("config.toml")
        let hooksURL = codexDirectory.appendingPathComponent("hooks.json")
        let manifestURL = resolvedManifestURL()
        let resolvedHooksBinaryURL = resolvedHooksBinaryURL(explicitURL: hooksBinaryURL)

        let configContents = (try? String(contentsOf: configURL, encoding: .utf8)) ?? ""
        let hooksData = try? Data(contentsOf: hooksURL)
        let manifest = try loadManifest(at: manifestURL)
        let managedCommand = manifest?.hookCommand ?? resolvedHooksBinaryURL.map { CodexHookInstaller.hookCommand(for: $0.path) }
        let managedHooksPresent = ((try? CodexHookInstaller.uninstallHooksJSON(
            existingData: hooksData,
            managedCommand: managedCommand
        ))?.changed) == true

        return CodexHookInstallationStatus(
            codexDirectory: codexDirectory,
            configURL: configURL,
            hooksURL: hooksURL,
            manifestURL: manifestURL,
            hooksBinaryURL: resolvedHooksBinaryURL,
            featureFlagEnabled: CodexHookInstaller.isCodexHooksFeatureEnabled(in: configContents),
            managedHooksPresent: managedHooksPresent,
            manifest: manifest
        )
    }

    @discardableResult
    public func install(hooksBinaryURL: URL) throws -> CodexHookInstallationStatus {
        ConfigurationTransaction.installationLock.lock()
        defer { ConfigurationTransaction.installationLock.unlock() }
        let config = try ConfigurationTransaction.File(codexDirectory.appendingPathComponent("config.toml"))
        let hooks = try ConfigurationTransaction.File(codexDirectory.appendingPathComponent("hooks.json"))
        let manifestFile = try ConfigurationTransaction.File(codexDirectory.appendingPathComponent(CodexHookInstallerManifest.fileName))
        let legacy = try ConfigurationTransaction.File(codexDirectory.appendingPathComponent(CodexHookInstallerManifest.legacyFileName))
        let binary = try ConfigurationTransaction.File(managedHooksBinaryURL)
        let existingManifest = try loadManifest(at: resolvedManifestURL())
        let configText = try configurationText(config)
        let feature = try CodexHookInstaller.validatedFeatureMutation(in: configText, enabling: featureKeyProvider())
        let command = CodexHookInstaller.hookCommand(for: managedHooksBinaryURL.path)
        let hookMutation = try CodexHookInstaller.installHooksJSON(existingData: hooks.original, hookCommand: command)
        let sourceData = try Data(contentsOf: hooksBinaryURL)
        let manifest = CodexHookInstallerManifest(hookCommand: command,
            enabledCodexHooksFeature: existingManifest?.enabledCodexHooksFeature == true || feature.featureEnabledByInstaller)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try ConfigurationTransaction.apply([
            .init(file: binary, contents: sourceData, permissions: 0o755),
            .init(file: hooks, contents: hookMutation.contents),
            .init(file: config, contents: Data(feature.contents.utf8)),
            .init(file: manifestFile, contents: try encoder.encode(manifest)),
            .init(file: legacy, contents: nil)
        ], recoveryRoot: codexDirectory)
        return try status(hooksBinaryURL: managedHooksBinaryURL)
    }

    @discardableResult
    public func uninstall() throws -> CodexHookInstallationStatus {
        ConfigurationTransaction.installationLock.lock()
        defer { ConfigurationTransaction.installationLock.unlock() }
        let config = try ConfigurationTransaction.File(codexDirectory.appendingPathComponent("config.toml"))
        let hooks = try ConfigurationTransaction.File(codexDirectory.appendingPathComponent("hooks.json"))
        let primary = try ConfigurationTransaction.File(codexDirectory.appendingPathComponent(CodexHookInstallerManifest.fileName))
        let legacy = try ConfigurationTransaction.File(codexDirectory.appendingPathComponent(CodexHookInstallerManifest.legacyFileName))
        let manifest = try loadManifest(at: resolvedManifestURL())
        let hookMutation = try CodexHookInstaller.uninstallHooksJSON(existingData: hooks.original, managedCommand: manifest?.hookCommand)
        var configData = config.original
        if manifest?.enabledCodexHooksFeature == true && !hookMutation.hasRemainingHooks {
            let feature = try CodexHookInstaller.validatedFeatureMutation(in: configurationText(config), enabling: nil)
            if feature.changed { configData = Data(feature.contents.utf8) }
        }
        try ConfigurationTransaction.apply([
            .init(file: hooks, contents: hookMutation.contents),
            .init(file: config, contents: configData),
            .init(file: primary, contents: nil),
            .init(file: legacy, contents: nil)
        ], recoveryRoot: codexDirectory)
        return try status()
    }

    private func configurationText(_ file: ConfigurationTransaction.File) throws -> String {
        guard let data = file.original else { return "" }
        guard let text = String(data: data, encoding: .utf8) else { throw ConfigurationError.invalidFormat(file.url.path) }
        return text
    }

    private func loadManifest(at url: URL) throws -> CodexHookInstallerManifest? {
        guard fileManager.fileExists(atPath: url.path) else {
            return nil
        }

        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(CodexHookInstallerManifest.self, from: data)
    }

    private func resolvedManifestURL() -> URL {
        let primaryURL = codexDirectory.appendingPathComponent(CodexHookInstallerManifest.fileName)
        if fileManager.fileExists(atPath: primaryURL.path) {
            return primaryURL
        }

        let legacyURL = codexDirectory.appendingPathComponent(CodexHookInstallerManifest.legacyFileName)
        return fileManager.fileExists(atPath: legacyURL.path) ? legacyURL : primaryURL
    }

    private func resolvedHooksBinaryURL(explicitURL: URL?) -> URL? {
        if let explicitURL {
            return explicitURL.standardizedFileURL
        }

        guard fileManager.isExecutableFile(atPath: managedHooksBinaryURL.path) else {
            return nil
        }

        return managedHooksBinaryURL
    }

}
