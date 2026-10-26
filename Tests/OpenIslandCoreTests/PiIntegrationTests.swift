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

    @Test(arguments: [false, true])
    func sessionRegistryRoundTripsPiAndOhMyPiSessions(isRemote: Bool) throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("open-island-pi-registry-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let registry = PiSessionRegistry(fileURL: root.appendingPathComponent("sessions.json"))
        let timestamp = Date(timeIntervalSince1970: 12_345)
        let firstSeenAt = Date(timeIntervalSince1970: 12_000)
        let sessions = [AgentTool.pi, .ohMyPi].map { tool in
            var session = AgentSession(
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
            session.isRemote = isRemote
            return session
        }

        try registry.save(sessions.map(PiTrackedSessionRecord.init(session:)))
        let loaded = try registry.load()
        let restoredAt = timestamp
        let restored = loaded.map { $0.restorableSession(at: restoredAt) }

        #expect(restored.map(\.tool) == [.pi, .ohMyPi])
        #expect(restored.allSatisfy { $0.isRemote == isRemote })
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
        #expect(restored.isRemote == false)
        let legacyUpdated = ISO8601DateFormatter().date(from: "2026-01-01T00:00:00Z")
        #expect(restored.firstSeenAt == legacyUpdated)
        #expect(restored.updatedAt == legacyUpdated)
        #expect(restored.isHookManaged)
        #expect(restored.heartbeatReconnectStartedAt == restoredAt)
        #expect(restored.lastHeartbeatAt == nil)
        #expect(restored.isProcessAlive == false)
    }

    @Test
    func sessionRegistryRestoreSkipsDemoHookManagedGrace() throws {
        let restoredAt = Date(timeIntervalSince1970: 88_000)
        let startedAt = restoredAt.addingTimeInterval(-10)
        var state = SessionState()
        state.apply(
            .sessionStarted(
                SessionStarted(
                    sessionID: "pi-demo",
                    title: "Pi demo",
                    tool: .pi,
                    origin: .demo,
                    initialPhase: .completed,
                    summary: "Demo",
                    timestamp: startedAt
                )
            )
        )
        let demo = try #require(state.session(id: "pi-demo"))

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

    @Test(arguments: [PiAgentVariant.pi, .ohMyPi], [PiHookEventName.sessionStart, .heartbeat, .userPromptSubmit])
    func remoteIdentitySurvivesFirstHook(agent: PiAgentVariant, event: PiHookEventName) async throws {
        let socketURL = BridgeSocketLocation.uniqueTestURL()
        let server = BridgeServer(socketURL: socketURL)
        try server.start()
        defer { server.stop() }
        let observer = LocalBridgeClient(socketURL: socketURL)
        let stream = try observer.connect()
        defer { observer.disconnect() }
        try await observer.send(.registerClient(role: .observer))

        let json = try JSONSerialization.data(withJSONObject: [
            "hook_event_name": event.rawValue,
            "agent": agent.rawValue,
            "session_id": "remote-session",
            "cwd": "/home/user/project",
            "remote": true,
        ])
        let hook = try JSONDecoder().decode(PiHookPayload.self, from: json)
        _ = try BridgeCommandClient(socketURL: socketURL).send(.processPiHook(hook))
        var iterator = stream.makeAsyncIterator()
        let received = try #require(try await iterator.next())
        guard case let .sessionStarted(started) = received else {
            Issue.record("Expected the first remote hook to create a session")
            return
        }
        #expect(started.isRemote)
        #expect(started.tool == agent.tool)

        if event == .heartbeat {
            let heartbeat = try #require(try await iterator.next())
            guard case let .sessionHeartbeat(payload) = heartbeat else {
                Issue.record("Expected a recoverable heartbeat")
                return
            }
            #expect(payload.recoverySession?.isRemote == true)
        }
    }

    @Test(arguments: [AgentTool.pi, .ohMyPi])
    func heartbeatRepairsRemoteTerminalWithoutResettingActivity(tool: AgentTool) throws {
        let timestamp = Date(timeIntervalSince1970: 100_000)
        var state = SessionState()
        let started = SessionStarted(
            sessionID: "restored-session", title: "Working", tool: tool,
            origin: .live, initialPhase: .running, summary: "Running tool", timestamp: timestamp,
            jumpTarget: JumpTarget(
                terminalApp: "VS Code", workspaceName: "project", paneTitle: "OMP",
                workingDirectory: "/home/user/project", tmuxTarget: "%42",
                vscodeTerminalURI: "vscode://open-island.terminal-jump/focus?token=previous"
            )
        )
        state.apply(.sessionStarted(started))
        var recovery = started
        recovery.isRemote = true
        recovery.initialPhase = .completed
        let uri = "vscode://open-island.terminal-jump/focus?token=registered&windowId=7"
        recovery.jumpTarget = JumpTarget(
            terminalApp: "VS Code", workspaceName: "project", paneTitle: "OMP",
            vscodeTerminalURI: uri
        )
        state.apply(.sessionHeartbeat(SessionHeartbeat(
            sessionID: started.sessionID, timestamp: timestamp.addingTimeInterval(15), recoverySession: recovery
        )))
        let repaired = try #require(state.session(id: started.sessionID))
        #expect(repaired.isRemote)
        #expect(repaired.phase == .running)
        #expect(repaired.summary == "Running tool")
        #expect(repaired.firstSeenAt == timestamp)
        #expect(repaired.updatedAt == timestamp)
        #expect(repaired.jumpTarget?.vscodeTerminalURI == uri)
        #expect(repaired.jumpTarget?.tmuxTarget == "%42")
        #expect(repaired.jumpTarget?.workingDirectory == "/home/user/project")

        // A legacy heartbeat must not erase an established origin or terminal locator.
        var legacyRecovery = started
        legacyRecovery.jumpTarget?.vscodeTerminalURI = nil
        state.apply(.sessionHeartbeat(SessionHeartbeat(
            sessionID: started.sessionID, timestamp: timestamp.addingTimeInterval(30), recoverySession: legacyRecovery
        )))
        #expect(state.session(id: started.sessionID)?.isRemote == true)
        #expect(state.session(id: started.sessionID)?.jumpTarget?.vscodeTerminalURI == uri)
    }
}
