import Foundation
import Testing
@testable import OpenIslandApp
import OpenIslandCore

@MainActor
struct AppModelIsolationTests {
    @Test
    func preferencesPersistOnlyWithinTheirEnvironment() {
        let first = AppModelTestEnvironment()
        let second = AppModelTestEnvironment()
        let model = first.makeModel()
        model.keepNotchOpenUntilDecision = true
        model.selectedSoundName = "Glass"

        #expect(first.makeModel().keepNotchOpenUntilDecision)
        #expect(first.makeModel().selectedSoundName == "Glass")
        #expect(!second.makeModel().keepNotchOpenUntilDecision)
        #expect(second.makeModel().selectedSoundName == NotificationSoundService.defaultSoundName)
    }

    @Test
    func persistenceUsesOnlyTheInjectedDirectory() async throws {
        let first = AppModelTestEnvironment()
        let sentinel = AppModelTestEnvironment()
        try FileManager.default.createDirectory(at: sentinel.directory, withIntermediateDirectories: true)
        let names = ["session-terminals.json", "claude-session-registry.json", "opencode-session-registry.json",
                     "cursor-session-registry.json", "pi-session-registry.json"]
        let original = Data("sentinel: must not change".utf8)
        for name in names {
            try original.write(to: sentinel.directory.appendingPathComponent(name))
        }

        let model = first.makeModel()
        model.discovery.scheduleCodexSessionPersistence()
        model.discovery.scheduleClaudeSessionPersistence()
        model.discovery.scheduleOpenCodeSessionPersistence()
        model.discovery.scheduleCursorSessionPersistence()
        model.discovery.schedulePiSessionPersistence()

        let deadline = ContinuousClock.now + .seconds(3)
        while names.contains(where: { !FileManager.default.fileExists(atPath: first.directory.appendingPathComponent($0).path) }),
              ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        for name in names {
            #expect(FileManager.default.fileExists(atPath: first.directory.appendingPathComponent(name).path))
            #expect(try Data(contentsOf: sentinel.directory.appendingPathComponent(name)) == original)
        }
    }
}
