import Foundation
import Testing
@testable import OpenIslandApp
import OpenIslandCore

struct CodexUsageRefreshTests {
    @MainActor
    @Test
    func appModelMirrorsUsageChangesFromHookCoordinator() {
        let model = AppModel()
        let snapshot = makeSnapshot(usedPercentage: 23, capturedAt: 200)

        model.hooks.updateCodexUsageSnapshot(snapshot)

        #expect(model.codexUsageSnapshot == snapshot)
    }

    @MainActor
    @Test
    func olderAsyncUsageResultCannotOverwriteNewerSnapshot() {
        let coordinator = HookInstallationCoordinator()
        let newer = makeSnapshot(usedPercentage: 23, capturedAt: 200)
        let older = makeSnapshot(usedPercentage: 11, capturedAt: 100)

        coordinator.updateCodexUsageSnapshot(newer)
        coordinator.updateCodexUsageSnapshot(older)

        #expect(coordinator.codexUsageSnapshot == newer)
    }
}

private func makeSnapshot(usedPercentage: Double, capturedAt: TimeInterval) -> CodexUsageSnapshot {
    CodexUsageSnapshot(
        sourceFilePath: "/tmp/rollout.jsonl",
        capturedAt: Date(timeIntervalSince1970: capturedAt),
        limitID: "codex",
        windows: [
            CodexUsageWindow(
                key: "primary",
                label: "7d",
                usedPercentage: usedPercentage,
                leftPercentage: 100 - usedPercentage,
                windowMinutes: 10_080,
                resetsAt: nil
            ),
        ]
    )
}
