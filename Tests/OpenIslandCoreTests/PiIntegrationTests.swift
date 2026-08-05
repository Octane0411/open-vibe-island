import Foundation
import Testing
@testable import OpenIslandCore

struct PiIntegrationTests {
    @Test(arguments: [PiAgentVariant.pi, .ohMyPi])
    func extensionInstallStatusAndUninstallRoundTrip(agent: PiAgentVariant) throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("open-island-pi-install-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let manager = PiExtensionInstallationManager(agent: agent, agentDirectory: root)
        let source = "const source = \"__OPEN_ISLAND_PI_SOURCE__\";\n"

        let initial = try manager.status()
        #expect(initial.isInstalled == false)

        let installed = try manager.install(extensionSourceData: Data(source.utf8))
        #expect(installed.isInstalled)
        #expect(try String(contentsOf: installed.extensionURL, encoding: .utf8).contains("\"\(agent.rawValue)\""))
        #expect(installed.isCurrent)
        #expect(try String(contentsOf: installed.extensionURL, encoding: .utf8).contains(PiExtensionInstallationManager.agentPlaceholder) == false)

        let sibling = manager.extensionsDirectory.appendingPathComponent("user-extension.ts")
        try Data("export default () => {};\n".utf8).write(to: sibling)
        let removed = try manager.uninstall()

        #expect(removed.isInstalled == false)
        #expect(FileManager.default.fileExists(atPath: sibling.path))
    }

    @Test(arguments: [PiAgentVariant.pi, .ohMyPi])
    func extensionInstallDetectsOutdatedManagedSource(agent: PiAgentVariant) throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("open-island-pi-update-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let manager = PiExtensionInstallationManager(agent: agent, agentDirectory: root)
        let source = "const source = \"__OPEN_ISLAND_PI_SOURCE__\";\n"
        _ = try manager.install(extensionSourceData: Data(source.utf8))

        let outdatedManifest = PiExtensionInstallerManifest(
            agent: agent,
            extensionPath: manager.extensionURL.path,
            version: PiExtensionInstallerManifest.currentVersion - 1
        )
        try JSONEncoder().encode(outdatedManifest).write(to: manager.manifestURL)

        let status = try manager.status()
        #expect(status.isInstalled)
        #expect(!status.isCurrent)
    }

    @Test
    func extensionInstallRejectsSourceWithoutAgentPlaceholder() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("open-island-pi-invalid-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let manager = PiExtensionInstallationManager(agent: .pi, agentDirectory: root)

        #expect(throws: PiExtensionInstallationError.missingAgentPlaceholder) {
            try manager.install(extensionSourceData: Data("export default () => {};".utf8))
        }
    }

    @Test
    func sessionRegistryRoundTripsPiAndOhMyPiSessions() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("open-island-pi-registry-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let registry = PiSessionRegistry(fileURL: root.appendingPathComponent("sessions.json"))
        let timestamp = Date(timeIntervalSince1970: 12_345)
        let sessions = [AgentTool.pi, .ohMyPi].map { tool in
            AgentSession(
                id: "\(tool.rawValue)-session",
                title: tool.displayName,
                tool: tool,
                origin: .live,
                attachmentState: .attached,
                phase: .running,
                summary: "Working",
                updatedAt: timestamp,
                firstSeenAt: timestamp,
                jumpTarget: JumpTarget(
                    terminalApp: "Ghostty",
                    workspaceName: "open-island",
                    paneTitle: tool.displayName,
                    workingDirectory: "/tmp/open-island",
                    terminalTTY: "/dev/ttys003"
                ),
                piMetadata: PiSessionMetadata(
                    initialUserPrompt: "Add Pi support",
                    model: "gpt-5.6",
                    transcriptPath: "/tmp/\(tool.rawValue).jsonl"
                )
            )
        }

        try registry.save(sessions.map(PiTrackedSessionRecord.init(session:)))
        let restored = try registry.load().map(\.restorableSession)

        #expect(restored.map(\.tool) == [.pi, .ohMyPi])
        #expect(restored.allSatisfy { $0.piMetadata?.model == "gpt-5.6" })
        #expect(restored.allSatisfy { $0.jumpTarget?.terminalApp == "Ghostty" })
    }
}
