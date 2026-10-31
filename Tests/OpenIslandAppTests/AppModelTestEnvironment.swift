import Foundation
import OpenIslandCore
@testable import OpenIslandApp

/// Each test owns its preferences and registry directory, including model reloads.
@MainActor
final class AppModelTestEnvironment {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let suiteName = "OpenIslandTests.\(UUID().uuidString)"
    let defaults: UserDefaults

    init() {
        defaults = UserDefaults(suiteName: suiteName)!
        defaults.set(true, forKey: "overlay.sound.muted")
    }

    isolated deinit {
        defaults.removePersistentDomain(forName: suiteName)
        try? FileManager.default.removeItem(at: directory)
    }

    func makeModel(
        terminalJumpAction: @escaping @Sendable (JumpTarget) throws -> String = { _ in "Test jump" },
        jumpDismissDelay: @escaping @Sendable () async throws -> Void = { try await Task.sleep(for: .milliseconds(20)) },
        isNotificationSessionAlreadyFrontmost: @escaping @Sendable (AgentSession) async -> Bool = { _ in false }
    ) -> AppModel {
        AppModel(
            defaults: defaults,
            discovery: SessionDiscoveryCoordinator(storageDirectory: directory),
            panelController: HeadlessOverlayPanelController(),
            terminalJumpAction: terminalJumpAction,
            jumpDismissDelay: jumpDismissDelay,
            isNotificationSessionAlreadyFrontmost: isNotificationSessionAlreadyFrontmost
        )
    }
}

@MainActor
private struct HeadlessOverlayPanelController: OverlayPanelControlling {
    func availableDisplayOptions() -> [OverlayDisplayOption] { [] }
    func ensurePanel(model: AppModel, preferredScreenID: String?) {}
    func show(model: AppModel, preferredScreenID: String?) -> OverlayPlacementDiagnostics? { nil }
    func setInteractive(_ interactive: Bool) {}
    func reposition(preferredScreenID: String?) -> OverlayPlacementDiagnostics? { nil }
    func isPointInExpandedArea(_ point: NSPoint) -> Bool { false }
}
