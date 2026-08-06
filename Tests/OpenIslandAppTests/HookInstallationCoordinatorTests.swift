import Foundation
import Testing
@testable import OpenIslandApp
@testable import OpenIslandCore

@MainActor
struct HookInstallationCoordinatorTests {
    @Test
    func loadPiExtensionStatusesIsolatesCorruptedPiManifest() throws {
        let roots = try makeIsolatedRoots()
        defer { roots.cleanup() }

        let piManager = PiExtensionInstallationManager(agent: .pi, agentDirectory: roots.pi)
        let ompManager = PiExtensionInstallationManager(agent: .ohMyPi, agentDirectory: roots.omp)
        try installValidExtension(on: ompManager)
        try writeCorruptedManifest(at: piManager.manifestURL)

        let messages = StatusMessageBox()
        let coordinator = HookInstallationCoordinator(
            piExtensionInstallationManager: piManager,
            ohMyPiExtensionInstallationManager: ompManager
        )
        coordinator.onStatusMessage = { messages.append($0) }

        coordinator.loadPiExtensionStatuses()

        #expect(coordinator.piExtensionStatus == nil)
        #expect(coordinator.ohMyPiExtensionStatus?.isInstalled == true)
        #expect(messages.values.count == 1)
        #expect(messages.values[0].contains("Failed to read Pi extension status:"))
        #expect(!messages.values[0].contains("Oh My Pi"))
    }

    @Test
    func loadPiExtensionStatusesIsolatesCorruptedOhMyPiManifest() throws {
        let roots = try makeIsolatedRoots()
        defer { roots.cleanup() }

        let piManager = PiExtensionInstallationManager(agent: .pi, agentDirectory: roots.pi)
        let ompManager = PiExtensionInstallationManager(agent: .ohMyPi, agentDirectory: roots.omp)
        try installValidExtension(on: piManager)
        try writeCorruptedManifest(at: ompManager.manifestURL)

        let messages = StatusMessageBox()
        let coordinator = HookInstallationCoordinator(
            piExtensionInstallationManager: piManager,
            ohMyPiExtensionInstallationManager: ompManager
        )
        coordinator.onStatusMessage = { messages.append($0) }

        coordinator.loadPiExtensionStatuses()

        #expect(coordinator.piExtensionStatus?.isInstalled == true)
        #expect(coordinator.ohMyPiExtensionStatus == nil)
        #expect(messages.values.count == 1)
        #expect(messages.values[0].contains("Failed to read Oh My Pi extension status:"))
        #expect(!messages.values[0].hasPrefix("Failed to read Pi extension status:"))
    }

    @Test
    func loadPiExtensionStatusesUpdatesBothWhenHealthy() throws {
        let roots = try makeIsolatedRoots()
        defer { roots.cleanup() }

        let piManager = PiExtensionInstallationManager(agent: .pi, agentDirectory: roots.pi)
        let ompManager = PiExtensionInstallationManager(agent: .ohMyPi, agentDirectory: roots.omp)
        try installValidExtension(on: piManager)
        try installValidExtension(on: ompManager)

        let messages = StatusMessageBox()
        let coordinator = HookInstallationCoordinator(
            piExtensionInstallationManager: piManager,
            ohMyPiExtensionInstallationManager: ompManager
        )
        coordinator.onStatusMessage = { messages.append($0) }

        coordinator.loadPiExtensionStatuses()

        #expect(coordinator.piExtensionStatus?.isInstalled == true)
        #expect(coordinator.ohMyPiExtensionStatus?.isInstalled == true)
        #expect(messages.values.isEmpty)
    }

    @Test
    func loadPiExtensionStatusesReportsBothFailuresIndependently() throws {
        let roots = try makeIsolatedRoots()
        defer { roots.cleanup() }

        let piManager = PiExtensionInstallationManager(agent: .pi, agentDirectory: roots.pi)
        let ompManager = PiExtensionInstallationManager(agent: .ohMyPi, agentDirectory: roots.omp)
        try writeCorruptedManifest(at: piManager.manifestURL)
        try writeCorruptedManifest(at: ompManager.manifestURL)

        let messages = StatusMessageBox()
        let coordinator = HookInstallationCoordinator(
            piExtensionInstallationManager: piManager,
            ohMyPiExtensionInstallationManager: ompManager
        )
        coordinator.onStatusMessage = { messages.append($0) }

        coordinator.loadPiExtensionStatuses()

        #expect(coordinator.piExtensionStatus == nil)
        #expect(coordinator.ohMyPiExtensionStatus == nil)
        #expect(messages.values.count == 2)
        #expect(messages.values.contains(where: { $0.contains("Failed to read Pi extension status:") }))
        #expect(messages.values.contains(where: { $0.contains("Failed to read Oh My Pi extension status:") }))
    }

    private func makeIsolatedRoots() throws -> (pi: URL, omp: URL, cleanup: () -> Void) {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("open-island-hook-coord-\(UUID().uuidString)", isDirectory: true)
        let pi = root.appendingPathComponent("pi", isDirectory: true)
        let omp = root.appendingPathComponent("omp", isDirectory: true)
        try FileManager.default.createDirectory(at: pi, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: omp, withIntermediateDirectories: true)
        return (pi, omp, { try? FileManager.default.removeItem(at: root) })
    }

    private func installValidExtension(on manager: PiExtensionInstallationManager) throws {
        let source = "const source = \"__OPEN_ISLAND_PI_SOURCE__\";\n"
        _ = try manager.install(extensionSourceData: Data(source.utf8))
    }

    private func writeCorruptedManifest(at url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("{ not-json".utf8).write(to: url, options: .atomic)
    }
}

@MainActor
private final class StatusMessageBox {
    private(set) var values: [String] = []

    func append(_ message: String) {
        values.append(message)
    }
}
