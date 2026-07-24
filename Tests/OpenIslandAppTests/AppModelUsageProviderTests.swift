import Foundation
import Testing
@testable import OpenIslandApp
import OpenIslandCore

/// Drives the same path the island header reads: snapshots land on the hook
/// coordinator, `AppModel` turns them into pills.
@MainActor
@Suite(.serialized)
struct AppModelUsageProviderTests {
    private static let codexOptInKey = "app.showCodexUsage"

    init() {
        UserDefaults.standard.removeObject(forKey: Self.codexOptInKey)
    }

    private func claudeSnapshot() -> ClaudeUsageSnapshot {
        ClaudeUsageSnapshot(
            fiveHour: ClaudeUsageWindow(usedPercentage: 30, resetsAt: nil),
            sevenDay: ClaudeUsageWindow(usedPercentage: 80, resetsAt: nil),
            cachedAt: Date(timeIntervalSince1970: 1_000)
        )
    }

    private func codexSnapshot() -> CodexUsageSnapshot {
        CodexUsageSnapshot(
            sourceFilePath: "/tmp/rollout.jsonl",
            capturedAt: Date(timeIntervalSince1970: 2_000),
            planType: "pro",
            windows: [
                CodexUsageWindow(
                    key: "primary",
                    label: "5h",
                    usedPercentage: 20,
                    leftPercentage: 80,
                    windowMinutes: 300,
                    resetsAt: nil
                ),
            ]
        )
    }

    @Test
    func usageStatusesFollowSnapshotsAndOptIn() {
        UserDefaults.standard.set(false, forKey: Self.codexOptInKey)
        let model = AppModel()

        #expect(model.usageProviderStatuses.isEmpty)

        model.hooks.claudeUsageSnapshot = claudeSnapshot()
        model.hooks.codexUsageSnapshot = codexSnapshot()

        // Codex is opted out, so only Claude produces a pill.
        #expect(model.usageProviderStatuses.map(\.provider) == [.claude])
        #expect(model.usageProviderStatuses.first?.peakUsagePercentage == 80)
        #expect(model.usageProviderStatuses.first?.peakWindowLabel == "7d")

        model.setUsageProvider(.codex, enabled: true)
        #expect(model.usageProviderStatuses.map(\.provider) == [.claude, .codex])
        #expect(model.usageProviderStatuses.last?.peakUsagePercentage == 20)

        model.setUsageProvider(.codex, enabled: false)
        #expect(model.usageProviderStatuses.map(\.provider) == [.claude])

        // An empty snapshot yields no pill rather than a 0% one.
        model.hooks.claudeUsageSnapshot = ClaudeUsageSnapshot(fiveHour: nil, sevenDay: nil)
        #expect(model.usageProviderStatuses.isEmpty)

        UserDefaults.standard.removeObject(forKey: Self.codexOptInKey)
    }

    @Test
    func claudeUsageNeedsNoOptInWhileCodexPersistsIts() {
        UserDefaults.standard.set(false, forKey: Self.codexOptInKey)
        let model = AppModel()

        // Claude is gated by installing the bridge, not by a toggle.
        #expect(model.isUsageProviderEnabled(.claude))
        model.setUsageProvider(.claude, enabled: false)
        #expect(model.isUsageProviderEnabled(.claude))

        #expect(model.isUsageProviderEnabled(.codex) == false)
        model.setUsageProvider(.codex, enabled: true)
        #expect(model.isUsageProviderEnabled(.codex))
        #expect(UserDefaults.standard.bool(forKey: Self.codexOptInKey))

        // The stored key is what a fresh launch reads back.
        let reloaded = AppModel()
        #expect(reloaded.isUsageProviderEnabled(.codex))

        model.setUsageProvider(.codex, enabled: false)
        #expect(UserDefaults.standard.bool(forKey: Self.codexOptInKey) == false)
        #expect(AppModel().isUsageProviderEnabled(.codex) == false)

        UserDefaults.standard.removeObject(forKey: Self.codexOptInKey)
    }

    @Test
    func codexOptInDefaultsToWhetherTheHarnessIsInstalled() {
        UserDefaults.standard.removeObject(forKey: Self.codexOptInKey)

        let probeExists = UsageProvider.codex.installationProbeURL.map {
            FileManager.default.fileExists(atPath: $0.path)
        } ?? false

        #expect(AppModel().isUsageProviderEnabled(.codex) == probeExists)
    }

    @Test
    func rolledOverWindowsStopDrivingThePill() {
        // Reproduces the reported reading: a 12h-old Claude cache whose 5h
        // window reset 7h ago still headlined the pill as "5h 10%", which reads
        // like the weekly number sitting in the wrong slot.
        let cachedAt = Date(timeIntervalSince1970: 100_000)
        let now = cachedAt.addingTimeInterval(12 * 3_600)

        let model = AppModel()
        model.hooks.claudeUsageSnapshot = ClaudeUsageSnapshot(
            fiveHour: ClaudeUsageWindow(
                usedPercentage: 10,
                resetsAt: cachedAt.addingTimeInterval(4 * 3_600)
            ),
            sevenDay: ClaudeUsageWindow(
                usedPercentage: 2,
                resetsAt: cachedAt.addingTimeInterval(6 * 86_400)
            ),
            cachedAt: cachedAt
        )

        let statuses = model.usageProviderStatuses(at: now)
        let claude = try! #require(statuses.first { $0.provider == .claude })

        // The expired 5h window is gone; the pill reports the window that is
        // still running.
        #expect(claude.windows.map(\.label) == ["7d"])
        #expect(claude.peakWindowLabel == "7d")
        #expect(claude.peakUsagePercentage == 2)

        // Before the reset, both windows count.
        let earlier = cachedAt.addingTimeInterval(3_600)
        #expect(model.usageProviderStatuses(at: earlier).first?.windows.map(\.label) == ["5h", "7d"])
        #expect(model.usageProviderStatuses(at: earlier).first?.peakWindowLabel == "5h")

        // Once every window has rolled over the provider drops out entirely
        // rather than showing dead numbers.
        #expect(model.usageProviderStatuses(at: cachedAt.addingTimeInterval(8 * 86_400)).isEmpty)
    }

    @Test
    func usageSnapshotLookupCoversEveryProvider() {
        let model = AppModel()
        model.hooks.claudeUsageSnapshot = claudeSnapshot()
        model.hooks.codexUsageSnapshot = codexSnapshot()

        // Every registered provider resolves to a cache — a new case without a
        // snapshot source would silently never render.
        for provider in UsageProvider.allCases {
            #expect(model.usageSnapshot(for: provider) != nil, "\(provider.id) has no snapshot source")
        }
    }
}
