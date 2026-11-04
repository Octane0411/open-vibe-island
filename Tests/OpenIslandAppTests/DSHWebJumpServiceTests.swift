import AppKit
import Foundation
import Testing
@testable import OpenIslandApp
import OpenIslandCore

struct DSHWebJumpServiceTests {
    private final class Calls: @unchecked Sendable {
        var values: [String] = []
    }

    @Test
    func installedPWABecomesFrontmostWithoutNavigatingAnyConversation() throws {
        guard ProcessInfo.processInfo.environment["OPEN_ISLAND_RUN_DSH_PWA_INTEGRATION"] == "1" else {
            try Test.cancel("Set OPEN_ISLAND_RUN_DSH_PWA_INTEGRATION=1 for native PWA activation verification.")
        }
        let pwa = try #require(DSHWebJumpService.installedPWAs().first { $0.origin.absoluteString == "http://127.0.0.1:3080/" })
        let service = DSHWebJumpService(installations: { [pwa] }, focus: { _ in })
        let target = JumpTarget(terminalApp: "DSH Web", workspaceName: "verification", paneTitle: "DSH", dshWeb: DSHWebJumpTarget(sessionID: "activation-only", origin: pwa.origin.absoluteString, focusSocketPath: "/tmp/oi-dsh-focus-test/focus.sock"))
        _ = try service.jump(to: target)
        #expect(NSWorkspace.shared.frontmostApplication?.bundleIdentifier == pwa.bundleIdentifier)
    }

    @Test
    func manifestParserUsesExactAppIdentityWithoutRetainingAuthentication() throws {
        let app = URL(fileURLWithPath: "/Users/test/Applications/Chrome Apps.localized/DSH.app")
        let identifier = String(repeating: "a", count: 32)
        var properties: [String: Any] = [
            "CrBundleIdentifier": "com.google.Chrome",
            "CrAppModeShortcutID": identifier,
            "CFBundleIdentifier": "com.google.Chrome.app.\(identifier)",
            "CrAppModeShortcutURL": "http://127.0.0.1:3080/?token=must-not-persist",
        ]
        let encode = { try PropertyListSerialization.data(fromPropertyList: properties, format: .binary, options: 0) }
        let parsed = try #require(DSHPWAInstallation.decode(applicationURL: app, propertyList: encode()))
        #expect(parsed.origin.absoluteString == "http://127.0.0.1:3080/")
        #expect(parsed.applicationURL == app)
        properties["CFBundleIdentifier"] = "com.google.Chrome"
        #expect(DSHPWAInstallation.decode(applicationURL: app, propertyList: try encode()) == nil)
        properties["CFBundleIdentifier"] = "com.google.Chrome.app.\(identifier)"
        properties["CrAppModeShortcutURL"] = "https://example.com/"
        #expect(DSHPWAInstallation.decode(applicationURL: app, propertyList: try encode()) == nil)
        #expect(DSHPWAInstallation.decode(applicationURL: app, propertyList: Data("not a plist".utf8)) == nil)
    }

    @Test
    func selectsRunningMatchingPWAThenRequestsExactChatWithoutOpeningURLs() throws {
        let calls = Calls()
        let desired = URL(string: "http://127.0.0.1:3080/")!
        let other = DSHPWAInstallation(applicationURL: URL(fileURLWithPath: "/Apps/Other.app"), bundleIdentifier: "other", origin: URL(string: "http://127.0.0.1:9999/")!)
        let first = DSHPWAInstallation(applicationURL: URL(fileURLWithPath: "/Apps/ProfileA.app"), bundleIdentifier: "a", origin: desired)
        let running = DSHPWAInstallation(applicationURL: URL(fileURLWithPath: "/Apps/ProfileB.app"), bundleIdentifier: "b", origin: desired)
        let service = DSHWebJumpService(
            installations: { [other, first, running] },
            runningApps: { [running.applicationURL] },
            activate: { calls.values.append("activate:\($0.path)") },
            focus: { calls.values.append("focus:\($0.sessionID)") }
        )
        let web = DSHWebJumpTarget(sessionID: "exact-session", origin: desired.absoluteString, focusSocketPath: "/tmp/oi-dsh-focus-test.sock")
        _ = try service.jump(to: JumpTarget(terminalApp: "DSH Web", workspaceName: "project", paneTitle: "DSH", dshWeb: web))
        #expect(calls.values == ["activate:/Apps/ProfileB.app", "focus:exact-session"])
    }

    @Test(arguments: ["https://example.com/", "http://localhost:3080/?token=secret", "http://user:password@localhost:3080/", "http://localhost:3080/#chat", "file:///tmp/app", "http://localhost:0/"])
    func rejectsUntrustedOriginsWithoutLaunchingAnything(origin: String) {
        let calls = Calls()
        let service = DSHWebJumpService(installations: { [] }, runningApps: { [] }, activate: { _ in calls.values.append("activate") }, focus: { _ in calls.values.append("focus") })
        let target = JumpTarget(terminalApp: "DSH Web", workspaceName: "project", paneTitle: "DSH", dshWeb: DSHWebJumpTarget(sessionID: "session", origin: origin, focusSocketPath: "/tmp/oi-dsh-focus-test.sock"))
        #expect(throws: DSHWebJumpError.invalidOrigin) { try service.jump(to: target) }
        #expect(calls.values.isEmpty)
    }

    @Test
    func missingOrAmbiguousPWAAndOldPluginNeverFallBackToBrowserOrFinder() {
        let calls = Calls()
        let origin = URL(string: "http://127.0.0.1:3080/")!
        let a = DSHPWAInstallation(applicationURL: URL(fileURLWithPath: "/Apps/A.app"), bundleIdentifier: "a", origin: origin)
        let b = DSHPWAInstallation(applicationURL: URL(fileURLWithPath: "/Apps/B.app"), bundleIdentifier: "b", origin: origin)
        let target = JumpTarget(terminalApp: "DSH Web", workspaceName: "project", paneTitle: "DSH", dshWeb: DSHWebJumpTarget(sessionID: "session", origin: origin.absoluteString, focusSocketPath: "/tmp/oi-dsh-focus-test.sock"))
        for (apps, error) in [([], DSHWebJumpError.pwaNotInstalled), ([a, b], .ambiguousPWA)] {
            let service = DSHWebJumpService(installations: { apps }, runningApps: { [] }, activate: { _ in calls.values.append("activate") }, focus: { _ in calls.values.append("focus") })
            #expect(throws: error) { try service.jump(to: target) }
        }
        let service = DSHWebJumpService(installations: { [a] }, runningApps: { [] }, activate: { _ in calls.values.append("activate") }, focus: { _ in calls.values.append("focus") })
        #expect(throws: DSHWebJumpError.pluginNeedsUpdate) {
            try service.jump(to: JumpTarget(terminalApp: "DSH Web", workspaceName: "project", paneTitle: "DSH"))
        }
        #expect(calls.values.isEmpty)
    }
}
