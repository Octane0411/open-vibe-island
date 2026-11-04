import AppKit
import Foundation
import OpenIslandCore

struct DSHPWAInstallation: Equatable, Sendable {
    var applicationURL: URL
    var bundleIdentifier: String
    var origin: URL

    static func decode(applicationURL: URL, propertyList: Data) -> DSHPWAInstallation? {
        guard let properties = try? PropertyListSerialization.propertyList(from: propertyList, format: nil) as? [String: Any],
              let browser = properties["CrBundleIdentifier"] as? String,
              ["com.google.Chrome", "com.microsoft.edgemac", "com.brave.Browser"].contains(browser),
              let id = properties["CrAppModeShortcutID"] as? String,
              id.count == 32, id.allSatisfy({ ("a"..."p").contains(String($0)) }),
              let bundleID = properties["CFBundleIdentifier"] as? String,
              bundleID == "\(browser).app.\(id)",
              let shortcut = properties["CrAppModeShortcutURL"] as? String,
              let origin = DSHWebJumpService.loopbackOrigin(shortcut, allowLaunchPath: true) else {
            return nil
        }
        return DSHPWAInstallation(applicationURL: applicationURL, bundleIdentifier: bundleID, origin: origin)
    }
}

enum DSHWebJumpError: Error, LocalizedError, Equatable {
    case pluginNeedsUpdate
    case invalidOrigin
    case pwaNotInstalled
    case ambiguousPWA
    case activationFailed

    var errorDescription: String? {
        switch self {
        case .pluginNeedsUpdate: "Update the DSH plugin in Setup, restart DSH Web, and reload its PWA."
        case .invalidOrigin: "The DSH jump target is not a credential-free local Web origin."
        case .pwaNotInstalled: "Install this DSH Web address as an app in Chrome, then try again."
        case .ambiguousPWA: "More than one installed DSH app matches. Open the intended app before jumping."
        case .activationFailed: "Could not bring the installed DSH Web app to the front."
        }
    }
}

struct DSHWebJumpService {
    typealias InstallationProvider = @Sendable () -> [DSHPWAInstallation]
    typealias RunningAppProvider = @Sendable () -> [URL]
    typealias Activation = @Sendable (URL) throws -> Void
    typealias Focus = @Sendable (DSHWebJumpTarget) throws -> Void

    private let installations: InstallationProvider
    private let runningApps: RunningAppProvider
    private let activate: Activation
    private let focus: Focus

    init(
        installations: @escaping InstallationProvider = Self.installedPWAs,
        runningApps: @escaping RunningAppProvider = {
            NSWorkspace.shared.runningApplications.compactMap(\.bundleURL)
        },
        activate: @escaping Activation = Self.activateApplication,
        focus: @escaping Focus = { try DSHFocusClient.focus($0) }
    ) {
        self.installations = installations
        self.runningApps = runningApps
        self.activate = activate
        self.focus = focus
    }

    func jump(to target: JumpTarget) throws -> String {
        guard let web = target.dshWeb else { throw DSHWebJumpError.pluginNeedsUpdate }
        guard let origin = Self.loopbackOrigin(web.origin) else { throw DSHWebJumpError.invalidOrigin }
        let matching = installations().filter { $0.origin == origin }
        let runningURLs = Set(runningApps().map { $0.standardizedFileURL })
        let running = matching.filter { runningURLs.contains($0.applicationURL.standardizedFileURL) }
        let selected: DSHPWAInstallation
        if running.count == 1 {
            selected = running[0]
        } else if matching.count == 1 {
            selected = matching[0]
        } else if matching.isEmpty {
            throw DSHWebJumpError.pwaNotInstalled
        } else {
            throw DSHWebJumpError.ambiguousPWA
        }
        // No URL is opened here. The installed PWA retains its own login state.
        try activate(selected.applicationURL)
        try Task.checkCancellation()
        try focus(web)
        return "Focused the DSH Web conversation."
    }

    /// Keeps authentication query parameters from native PWA manifests out of jump metadata.
    static func loopbackOrigin(_ value: String, allowLaunchPath: Bool = false) -> URL? {
        guard var components = URLComponents(string: value),
              components.scheme == "http" || components.scheme == "https",
              let host = components.host?.lowercased(),
              ["127.0.0.1", "localhost", "[::1]", "::1"].contains(host),
              components.user == nil, components.password == nil,
              components.port.map({ (1...65535).contains($0) }) ?? true else { return nil }
        if !allowLaunchPath {
            guard components.path.isEmpty || components.path == "/",
                  components.query == nil, components.fragment == nil else { return nil }
        }
        components.host = host
        components.path = "/"
        components.query = nil
        components.fragment = nil
        if components.scheme == "http", components.port == 80 { components.port = nil }
        if components.scheme == "https", components.port == 443 { components.port = nil }
        return components.url
    }

    static func installedPWAs() -> [DSHPWAInstallation] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let roots = [home.appendingPathComponent("Applications"), URL(fileURLWithPath: "/Applications")]
        let locations = roots.flatMap { root in
            [root, root.appendingPathComponent("Chrome Apps.localized"), root.appendingPathComponent("Edge Apps.localized"), root.appendingPathComponent("Brave Browser Apps.localized")]
        }
        return locations.flatMap { directory in
            let apps = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
            return apps.filter { $0.pathExtension == "app" }.compactMap { app -> DSHPWAInstallation? in
                guard let data = try? Data(contentsOf: app.appendingPathComponent("Contents/Info.plist")) else { return nil }
                return DSHPWAInstallation.decode(applicationURL: app, propertyList: data)
            }
        }
    }

    private static func activateApplication(_ url: URL) throws {
        // A Chrome app shim can acknowledge `open -a` without becoming frontmost.
        // Prefer explicit activation of that exact installed app, never Chrome itself.
        let matchingApplication = {
            NSWorkspace.shared.runningApplications.first { $0.bundleURL?.standardizedFileURL == url.standardizedFileURL }
        }
        if let app = matchingApplication(), app.activate(options: [.activateAllWindows]) {
            try waitUntilFrontmost(url)
            return
        }
        // A cold app launch uses its saved Chrome profile and login state.
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = ["-a", url.path]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        let completed = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in completed.signal() }
        try process.run()
        guard completed.wait(timeout: .now() + 3) == .success else {
            process.terminate()
            throw DSHWebJumpError.activationFailed
        }
        guard process.terminationStatus == 0 else { throw DSHWebJumpError.activationFailed }
        _ = matchingApplication()?.activate(options: [.activateAllWindows])
        try waitUntilFrontmost(url)
    }

    private static func waitUntilFrontmost(_ url: URL) throws {
        let deadline = ProcessInfo.processInfo.systemUptime + 2
        while ProcessInfo.processInfo.systemUptime < deadline {
            try Task.checkCancellation()
            if NSWorkspace.shared.frontmostApplication?.bundleURL?.standardizedFileURL == url.standardizedFileURL {
                return
            }
            Thread.sleep(forTimeInterval: 0.025)
        }
        throw DSHWebJumpError.activationFailed
    }
}
