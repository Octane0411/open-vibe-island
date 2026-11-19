import Foundation
import Testing
@testable import OpenIslandCore

struct HostAppResolverTests {
    @Test
    func resolvesOutermostBundleForNestedHelpers() {
        #expect(HostAppResolver.outermostAppBundle(containing: "/Applications/Superset.app/Contents/MacOS/Superset")?.path == "/Applications/Superset.app")
        #expect(HostAppResolver.outermostAppBundle(
            containing: "/Applications/Yab.app/Contents/Frameworks/Yab Helper.app/Contents/MacOS/Yab Helper"
        )?.path == "/Applications/Yab.app")
        #expect(HostAppResolver.outermostAppBundle(containing: "/opt/homebrew/bin/fish") == nil)
    }

    @Test
    func appNamePrefersInfoPlistOverBundleFolderName() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let bundle = root.appendingPathComponent("yab.app")
        try FileManager.default.createDirectory(at: bundle.appendingPathComponent("Contents"), withIntermediateDirectories: true)

        #expect(HostAppResolver.appName(for: bundle) == "yab")

        try (["CFBundleName": "Yab"] as NSDictionary).write(to: bundle.appendingPathComponent("Contents/Info.plist"))
        #expect(HostAppResolver.appName(for: bundle) == "Yab")
    }
}
