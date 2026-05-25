import XCTest

final class WorkSafeBuildSurfaceTests: XCTestCase {
    private var repositoryRoot: URL {
        URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    }

    func testPackageDoesNotCompileNetworkUpdateOrNonApprovedAgentIntegrations() throws {
        let package = try contents("Package.swift")

        XCTAssertFalse(package.contains("Sparkle"), "Work-safe build must not compile Sparkle auto-update support.")
        XCTAssertFalse(package.contains("swift-markdown-ui"), "Work-safe build should avoid external UI dependencies that are not needed for Codex/Claude monitoring.")
    }

    func testMacAppEntitlementsDoNotRequestNetworkClientAccess() throws {
        let entitlements = try contents("config/packaging/OpenIslandApp.entitlements")

        XCTAssertFalse(entitlements.contains("com.apple.security.network.client"), "Work-safe macOS app must not request generic outbound network access.")
    }

    func testRemovedRuntimeSurfacesStayOutOfTheBuild() throws {
        let package = try contents("Package.swift")
        let appModel = try contents("Sources/OpenIslandApp/AppModel.swift")
        let hookCoordinator = try contents("Sources/OpenIslandApp/HookInstallationCoordinator.swift")

        XCTAssertTrue(package.contains(#""WatchHTTPEndpoint.swift""#), "Watch/LAN endpoint must be explicitly excluded from the target.")
        XCTAssertTrue(package.contains(#""WatchNotificationRelay.swift""#), "Watch/LAN relay must be explicitly excluded from the target.")
        XCTAssertTrue(package.contains(#""Resources/open-island-opencode.js""#), "OpenCode plugin resource must be explicitly excluded from the target.")
        XCTAssertTrue(package.contains(#""UpdateChecker.swift""#), "Sparkle update checker must be explicitly excluded from the target.")

        XCTAssertFalse(appModel.contains("WatchNotificationRelay"), "Watch/LAN relay must not be reachable from AppModel.")
        XCTAssertFalse(appModel.contains("updateChecker"), "Network update checks must not run at startup.")
        XCTAssertFalse(appModel.contains("scheduleOpenCodeSessionPersistence"), "OpenCode session persistence must not run in the work-safe app.")
        XCTAssertFalse(appModel.contains("scheduleCursorSessionPersistence"), "Cursor session persistence must not run in the work-safe app.")
        XCTAssertFalse(hookCoordinator.contains("OpenCodePluginInstallationManager"), "OpenCode plugin installer must not be reachable.")
        XCTAssertFalse(hookCoordinator.contains("CursorHookInstallationManager"), "Cursor hook installer must not be reachable.")
        XCTAssertFalse(hookCoordinator.contains("GeminiHookInstallationManager"), "Gemini hook installer must not be reachable.")
        XCTAssertFalse(hookCoordinator.contains("KimiHookInstallationManager"), "Kimi hook installer must not be reachable.")
    }

    private func contents(_ relativePath: String) throws -> String {
        let url = repositoryRoot.appendingPathComponent(relativePath)
        return try String(contentsOf: url, encoding: .utf8)
    }
}
