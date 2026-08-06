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
        let firstSeenAt = Date(timeIntervalSince1970: 12_000)
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
                firstSeenAt: firstSeenAt,
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
        let loaded = try registry.load()
        let restoredAt = timestamp
        let restored = loaded.map { $0.restorableSession(at: restoredAt) }

        #expect(restored.map(\.tool) == [.pi, .ohMyPi])
        #expect(restored.allSatisfy { $0.piMetadata?.model == "gpt-5.6" })
        #expect(restored.allSatisfy { $0.jumpTarget?.terminalApp == "Ghostty" })
        #expect(loaded.allSatisfy { $0.firstSeenAt == firstSeenAt })
        #expect(restored.allSatisfy { $0.firstSeenAt == firstSeenAt })
        #expect(restored.allSatisfy { $0.updatedAt == timestamp })
        #expect(restored.allSatisfy { $0.isHookManaged })
        #expect(restored.allSatisfy { $0.isProcessAlive == false })
        #expect(restored.allSatisfy { $0.lastHeartbeatAt == nil })
        #expect(restored.allSatisfy { $0.heartbeatReconnectStartedAt == restoredAt })
        #expect(restored.allSatisfy { $0.attachmentState == .stale })
        #expect(restored.allSatisfy { $0.phase == .running })
    }

    @Test
    func sessionRegistryDecodesLegacyRecordsWithoutFirstSeenAt() throws {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let legacyJSON = Data(
            """
            {
              "sessionID": "pi-legacy",
              "title": "Pi",
              "tool": "pi",
              "attachmentState": "attached",
              "summary": "Working",
              "phase": "running",
              "updatedAt": "2026-01-01T00:00:00Z"
            }
            """.utf8
        )

        let record = try decoder.decode(PiTrackedSessionRecord.self, from: legacyJSON)
        #expect(record.firstSeenAt == nil)

        let restoredAt = Date(timeIntervalSince1970: 99_000)
        let restored = record.restorableSession(at: restoredAt)
        let legacyUpdated = ISO8601DateFormatter().date(from: "2026-01-01T00:00:00Z")
        #expect(restored.firstSeenAt == legacyUpdated)
        #expect(restored.updatedAt == legacyUpdated)
        #expect(restored.isHookManaged)
        #expect(restored.heartbeatReconnectStartedAt == restoredAt)
        #expect(restored.lastHeartbeatAt == nil)
        #expect(restored.isProcessAlive == false)
    }

    @Test
    func sessionRegistryRestoreSkipsDemoHookManagedGrace() {
        let restoredAt = Date(timeIntervalSince1970: 88_000)
        var demo = AgentSession(
            id: "pi-demo",
            title: "Pi demo",
            tool: .pi,
            origin: .demo,
            attachmentState: .attached,
            phase: .completed,
            summary: "Demo",
            updatedAt: restoredAt.addingTimeInterval(-10),
            firstSeenAt: restoredAt.addingTimeInterval(-20)
        )
        demo.isHookManaged = false

        let restored = PiTrackedSessionRecord(session: demo).restorableSession(at: restoredAt)
        #expect(restored.attachmentState == .stale)
        #expect(restored.isHookManaged == false)
        #expect(restored.heartbeatReconnectStartedAt == nil)
        #expect(restored.lastHeartbeatAt == nil)
    }

    @Test
    func sessionRegistryRestoreTreatsNilOriginAsLive() {
        let restoredAt = Date(timeIntervalSince1970: 77_000)
        let legacy = AgentSession(
            id: "omp-legacy",
            title: "OMP legacy",
            tool: .ohMyPi,
            origin: nil,
            attachmentState: .attached,
            phase: .running,
            summary: "Working",
            updatedAt: restoredAt.addingTimeInterval(-3_600),
            firstSeenAt: restoredAt.addingTimeInterval(-7_200)
        )

        let restored = PiTrackedSessionRecord(session: legacy).restorableSession(at: restoredAt)
        #expect(restored.isHookManaged)
        #expect(restored.heartbeatReconnectStartedAt == restoredAt)
        #expect(restored.lastHeartbeatAt == nil)
        #expect(restored.updatedAt == restoredAt.addingTimeInterval(-3_600))
    }
}
