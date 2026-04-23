import Foundation
import Testing
@testable import OpenIslandCore

struct CodexSessionTrackingTests {
    @Test
    func codexSessionStoreRoundTripsTrackedSessions() throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("open-island-tracking-\(UUID().uuidString)", isDirectory: true)
        let fileURL = rootURL.appendingPathComponent("session-terminals.json")
        let store = CodexSessionStore(fileURL: fileURL)

        defer {
            try? FileManager.default.removeItem(at: rootURL)
        }

        let records = [
            CodexTrackedSessionRecord(
                sessionID: "codex-session-1",
                title: "Codex · open-island",
                origin: .live,
                attachmentState: .attached,
                summary: "Inspecting rollout watcher.",
                phase: .running,
                updatedAt: Date(timeIntervalSince1970: 1_000),
                jumpTarget: JumpTarget(
                    terminalApp: "Ghostty",
                    workspaceName: "open-island",
                    paneTitle: "codex ~/Personal/open-island"
                ),
                codexMetadata: CodexSessionMetadata(
                    transcriptPath: "/tmp/rollout.jsonl",
                    initialUserPrompt: "Start by checking the rollout watcher.",
                    lastUserPrompt: "Check the rollout watcher state.",
                    lastAssistantMessage: "Inspecting rollout watcher.",
                    currentTool: "exec_command",
                    currentCommandPreview: "git status -sb"
                )
            )
        ]

        try store.save(records)
        let reloaded = try store.load()

        #expect(reloaded == records)
        #expect(reloaded.first?.session.codexMetadata?.transcriptPath == "/tmp/rollout.jsonl")
        #expect(reloaded.first?.session.codexMetadata?.initialUserPrompt == "Start by checking the rollout watcher.")
        #expect(reloaded.first?.session.codexMetadata?.lastUserPrompt == "Check the rollout watcher state.")
        #expect(reloaded.first?.session.origin == .live)
        #expect(reloaded.first?.session.attachmentState == .attached)
        #expect(reloaded.first?.session.lifecyclePolicy == .hookDrivenWithProcessFallback)
    }

    @Test
    func codexTrackedSessionRecordRejectsDemoAndLegacyMockSessions() {
        let liveRecord = CodexTrackedSessionRecord(
            sessionID: "codex-live-1",
            title: "Codex · live",
            origin: .live,
            attachmentState: .attached,
            summary: "Working",
            phase: .running,
            updatedAt: .now
        )
        let demoRecord = CodexTrackedSessionRecord(
            sessionID: "codex-demo-1",
            title: "Codex · demo",
            origin: .demo,
            attachmentState: .attached,
            summary: "Working",
            phase: .running,
            updatedAt: .now
        )
        let legacyMockRecord = CodexTrackedSessionRecord(
            sessionID: "codex-backend-server",
            title: "backend server",
            summary: "REST endpoints built. Tests are green.",
            phase: .completed,
            updatedAt: .now
        )
        let debugScenarioRecord = CodexTrackedSessionRecord(
            sessionID: "session-approval",
            title: "Codex · open-island",
            origin: .live,
            attachmentState: .attached,
            summary: "Approval needed",
            phase: .waitingForApproval,
            updatedAt: .now
        )
        let endedRecord = CodexTrackedSessionRecord(
            sessionID: "codex-ended-1",
            title: "Codex · ended",
            origin: .live,
            attachmentState: .stale,
            summary: "Finished",
            phase: .completed,
            updatedAt: .now,
            isSessionEnded: true
        )

        #expect(liveRecord.shouldRestoreToLiveState)
        #expect(!demoRecord.shouldRestoreToLiveState)
        #expect(!legacyMockRecord.shouldRestoreToLiveState)
        #expect(!debugScenarioRecord.shouldRestoreToLiveState)
        #expect(!endedRecord.shouldRestoreToLiveState)
    }

    @Test
    func codexRestorableSessionAlwaysStartsStale() {
        let record = CodexTrackedSessionRecord(
            sessionID: "codex-live-1",
            title: "Codex · open-island",
            origin: .live,
            attachmentState: .attached,
            summary: "Working",
            phase: .running,
            updatedAt: .now
        )

        #expect(record.session.attachmentState == .attached)
        #expect(record.session.lifecyclePolicy == .hookDrivenWithProcessFallback)
        #expect(record.restorableSession.attachmentState == .stale)
        #expect(record.restorableSession.lifecyclePolicy == .hookDrivenWithProcessFallback)
    }

    @Test
    func codexSessionClampsStaleAppDrivenPolicyForNonCodexApp() {
        let record = CodexTrackedSessionRecord(
            sessionID: "codex-live-1",
            title: "Codex · open-island",
            origin: .live,
            attachmentState: .attached,
            summary: "Working",
            phase: .running,
            updatedAt: .now,
            jumpTarget: JumpTarget(
                terminalApp: "Ghostty",
                workspaceName: "open-island",
                paneTitle: "codex ~/Personal/open-island"
            ),
            lifecyclePolicy: .appDriven
        )

        let session = record.session

        #expect(session.lifecyclePolicy == .hookDrivenWithProcessFallback)
        #expect(session.livenessObservation.lastRuntimePositiveCycle == nil)
        #expect(session.livenessObservation.strongestRuntimeMatch == nil)
    }

    @Test
    func legacyCodexRecordWithoutOriginDecodesAsHookDriven() throws {
        let legacyJSON = """
        {
          "sessionID": "codex-legacy-1",
          "title": "Codex · legacy",
          "attachmentState": "attached",
          "summary": "Restored from a pre-origin registry.",
          "phase": "running",
          "updatedAt": 0,
          "jumpTarget": {
            "terminalApp": "Ghostty",
            "workspaceName": "open-island",
            "paneTitle": "codex ~/src/open-vibe-island"
          },
          "codexMetadata": {
            "transcriptPath": "/tmp/codex-legacy.jsonl",
            "lastAssistantMessage": "Restored legacy Codex session."
          }
        }
        """.data(using: .utf8)!

        let record = try JSONDecoder().decode(CodexTrackedSessionRecord.self, from: legacyJSON)
        let session = record.session

        #expect(record.origin == nil)
        #expect(record.lifecyclePolicy == .hookDrivenWithProcessFallback)
        #expect(session.lifecyclePolicy == .hookDrivenWithProcessFallback)
        #expect(session.jumpTarget?.terminalApp == "Ghostty")
        #expect(session.codexMetadata?.transcriptPath == "/tmp/codex-legacy.jsonl")
        #expect(session.livenessObservation.lastRuntimePositiveCycle == nil)
        #expect(session.livenessObservation.strongestRuntimeMatch == nil)
    }

    @Test
    func codexSessionStoreLoadsLegacyRecordsWithoutAttachmentState() throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("open-island-legacy-tracking-\(UUID().uuidString)", isDirectory: true)
        let fileURL = rootURL.appendingPathComponent("session-terminals.json")
        let store = CodexSessionStore(fileURL: fileURL)

        defer {
            try? FileManager.default.removeItem(at: rootURL)
        }

        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        let legacyJSON = """
        [
          {
            "codexMetadata" : {
              "currentTool" : "exec_command",
              "lastAssistantMessage" : "Inspecting rollout watcher.",
              "transcriptPath" : "/tmp/rollout.jsonl"
            },
            "origin" : "live",
            "phase" : "running",
            "sessionID" : "codex-session-legacy",
            "summary" : "Inspecting rollout watcher.",
            "title" : "Codex · open-island",
            "updatedAt" : "1970-01-01T00:16:40Z"
          }
        ]
        """
        try legacyJSON.write(to: fileURL, atomically: true, encoding: .utf8)

        let records = try store.load()

        #expect(records.count == 1)
        #expect(records.first?.attachmentState == .stale)
        #expect(records.first?.session.attachmentState == .stale)
        #expect(records.first?.session.lifecyclePolicy == .hookDrivenWithProcessFallback)
    }

    @Test
    func codexRolloutReducerTracksPromptCommandAndCompletion() {
        let initialLines = [
            rolloutLine(
                timestamp: "2026-04-02T04:03:44.500Z",
                type: "event_msg",
                payload: [
                    "type": "user_message",
                    "message": "Check the rollout watcher status.",
                ]
            ),
            rolloutLine(
                timestamp: "2026-04-02T04:03:44.894Z",
                type: "response_item",
                payload: [
                    "type": "function_call",
                    "name": "exec_command",
                    "arguments": "{\"cmd\":\"git status -sb\"}",
                ]
            ),
        ]
        let initialSnapshot = CodexRolloutReducer.snapshot(for: initialLines)
        let initialEvents = CodexRolloutReducer.events(
            from: nil,
            to: initialSnapshot,
            sessionID: "codex-session-1",
            transcriptPath: "/tmp/rollout.jsonl"
        )

        #expect(initialSnapshot.initialUserPrompt == "Check the rollout watcher status.")
        #expect(initialSnapshot.lastUserPrompt == "Check the rollout watcher status.")
        #expect(initialSnapshot.currentTool == "exec_command")
        #expect(initialSnapshot.currentCommandPreview == "git status -sb")
        #expect(initialEvents.contains(where: { $0.trackedMetadataUpdate?.codexMetadata.initialUserPrompt == "Check the rollout watcher status." }))
        #expect(initialEvents.contains(where: { $0.trackedMetadataUpdate?.codexMetadata.lastUserPrompt == "Check the rollout watcher status." }))
        #expect(initialEvents.contains(where: { $0.trackedMetadataUpdate?.codexMetadata.currentCommandPreview == "git status -sb" }))
        #expect(initialEvents.contains(where: { $0.trackedActivityUpdate?.summary == "Running command." }))

        let finalSnapshot = CodexRolloutReducer.snapshot(
            for: initialLines + [
                rolloutLine(
                    timestamp: "2026-04-02T04:03:45.000Z",
                    type: "event_msg",
                    payload: [
                        "type": "agent_message",
                        "message": "Inspecting README and current hooks config.",
                    ]
                ),
                rolloutLine(
                    timestamp: "2026-04-02T04:03:46.000Z",
                    type: "event_msg",
                    payload: [
                        "type": "task_complete",
                        "last_agent_message": "Rollout watcher is wired and verified.",
                    ]
                ),
            ]
        )
        let finalEvents = CodexRolloutReducer.events(
            from: initialSnapshot,
            to: finalSnapshot,
            sessionID: "codex-session-1",
            transcriptPath: "/tmp/rollout.jsonl"
        )

        #expect(finalSnapshot.phase == .completed)
        #expect(finalSnapshot.currentTool == nil)
        #expect(finalSnapshot.currentCommandPreview == nil)
        #expect(finalEvents.contains(where: { $0.trackedSessionCompletion?.summary == "Rollout watcher is wired and verified." }))
        #expect(finalEvents.contains(where: { $0.trackedSessionCompletion?.isInterrupt != true }))
        #expect(finalEvents.contains(where: { $0.trackedMetadataUpdate?.codexMetadata.currentTool == nil }))
        #expect(finalEvents.contains(where: { $0.trackedMetadataUpdate?.codexMetadata.currentCommandPreview == nil }))
    }

    @Test
    func codexRolloutReducerMarksTurnAbortedAsInterruptedCompletion() {
        let initialSnapshot = CodexRolloutReducer.snapshot(for: [
            rolloutLine(
                timestamp: "2026-04-02T04:03:44.500Z",
                type: "event_msg",
                payload: [
                    "type": "user_message",
                    "message": "Inspect the completion notification behavior.",
                ]
            ),
        ])
        let interruptedSnapshot = CodexRolloutReducer.snapshot(for: [
            rolloutLine(
                timestamp: "2026-04-02T04:03:44.500Z",
                type: "event_msg",
                payload: [
                    "type": "user_message",
                    "message": "Inspect the completion notification behavior.",
                ]
            ),
            rolloutLine(
                timestamp: "2026-04-02T04:03:45.000Z",
                type: "event_msg",
                payload: [
                    "type": "turn_aborted",
                    "reason": "interrupted",
                ]
            ),
        ])
        let events = CodexRolloutReducer.events(
            from: initialSnapshot,
            to: interruptedSnapshot,
            sessionID: "codex-session-1",
            transcriptPath: "/tmp/rollout.jsonl"
        )

        #expect(interruptedSnapshot.phase == .completed)
        #expect(interruptedSnapshot.isInterrupted)
        #expect(events.contains(where: {
            $0.trackedSessionCompletion?.summary == "Codex turn was interrupted."
                && $0.trackedSessionCompletion?.isInterrupt == true
        }))
    }

    @Test
    func codexRolloutReducerPreservesInitialPromptAcrossLaterPrompts() {
        let snapshot = CodexRolloutReducer.snapshot(for: [
            rolloutLine(
                timestamp: "2026-04-02T04:03:44.500Z",
                type: "event_msg",
                payload: [
                    "type": "user_message",
                    "message": "Start with the island hover behavior.",
                ]
            ),
            rolloutLine(
                timestamp: "2026-04-02T04:05:10.000Z",
                type: "event_msg",
                payload: [
                    "type": "user_message",
                    "message": "Now make the overlay height fit the content.",
                ]
            ),
        ])

        #expect(snapshot.initialUserPrompt == "Start with the island hover behavior.")
        #expect(snapshot.lastUserPrompt == "Now make the overlay height fit the content.")
    }

    @Test
    func codexRolloutReducerTracksMessageResponsePromptsWithoutInjectedBlocks() {
        let snapshot = CodexRolloutReducer.snapshot(for: [
            rolloutLine(
                timestamp: "2026-04-02T14:37:27.780Z",
                type: "response_item",
                payload: [
                    "type": "message",
                    "role": "user",
                    "content": [
                        [
                            "type": "input_text",
                            "text": "# AGENTS.md instructions for /tmp/repo\n\n<INSTRUCTIONS>\nRepository guide\n</INSTRUCTIONS>",
                        ],
                        [
                            "type": "input_text",
                            "text": "<environment_context>\n  <cwd>/tmp/repo</cwd>\n</environment_context>",
                        ],
                    ],
                ]
            ),
            rolloutLine(
                timestamp: "2026-04-02T14:37:28.346Z",
                type: "response_item",
                payload: [
                    "type": "message",
                    "role": "user",
                    "content": [
                        [
                            "type": "input_text",
                            "text": "读一下这篇论文 https://arxiv.org/html/2603.28052v1，然后对比一下 autoresearch 的实现。",
                        ],
                    ],
                ]
            ),
            rolloutLine(
                timestamp: "2026-04-02T14:37:34.441Z",
                type: "response_item",
                payload: [
                    "type": "message",
                    "role": "assistant",
                    "content": [
                        [
                            "type": "output_text",
                            "text": "我先读论文内容并在仓库里定位 autoresearch 相关实现，再把两边的机制做一版对照。",
                        ],
                    ],
                ]
            ),
        ])

        #expect(snapshot.initialUserPrompt == "读一下这篇论文 https://arxiv.org/html/2603.28052v1，然后对比一下 autoresearch 的实现。")
        #expect(snapshot.lastUserPrompt == "读一下这篇论文 https://arxiv.org/html/2603.28052v1，然后对比一下 autoresearch 的实现。")
        #expect(snapshot.lastAssistantMessage == "我先读论文内容并在仓库里定位 autoresearch 相关实现，再把两边的机制做一版对照。")
        #expect(snapshot.summary == "我先读论文内容并在仓库里定位 autoresearch 相关实现，再把两边的机制做一版对照。")
    }

    @Test
    func codexRolloutWatcherTracksAppendedLines() async throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("open-island-rollout-\(UUID().uuidString)", isDirectory: true)
        let rolloutURL = rootURL.appendingPathComponent("rollout.jsonl")
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        try Data().write(to: rolloutURL)

        defer {
            try? FileManager.default.removeItem(at: rootURL)
        }

        let recorder = ObservedEventRecorder()
        let watcher = CodexRolloutWatcher(pollInterval: 0.05)
        watcher.eventHandler = { observed in
            Task {
                await recorder.append(observed)
            }
        }
        watcher.sync(targets: [
            CodexRolloutWatchTarget(
                sessionID: "codex-session-1",
                transcriptPath: rolloutURL.path
            )
        ])

        try appendRolloutLine(
            rolloutLine(
                timestamp: "2026-04-02T04:03:44.894Z",
                type: "event_msg",
                payload: [
                    "type": "user_message",
                    "message": "Inspect the README.",
                ]
            ),
            to: rolloutURL
        )
        try appendRolloutLine(
            rolloutLine(
                timestamp: "2026-04-02T04:03:45.000Z",
                type: "event_msg",
                payload: [
                    "type": "task_started",
                ]
            ),
            to: rolloutURL
        )
        try appendRolloutLine(
            rolloutLine(
                timestamp: "2026-04-02T04:03:45.200Z",
                type: "response_item",
                payload: [
                    "type": "function_call",
                    "name": "exec_command",
                    "arguments": "{\"cmd\":\"git status -sb\"}",
                ]
            ),
            to: rolloutURL
        )

        try await Task.sleep(for: .milliseconds(200))

        try appendRolloutLine(
            rolloutLine(
                timestamp: "2026-04-02T04:03:46.000Z",
                type: "event_msg",
                payload: [
                    "type": "task_complete",
                    "last_agent_message": "Finished the rollout tracking slice.",
                ]
            ),
            to: rolloutURL
        )

        try await Task.sleep(for: .milliseconds(200))
        watcher.stop()

        let events = await recorder.snapshotEvents()
        #expect(events.contains(where: { $0.trackedMetadataUpdate?.codexMetadata.lastUserPrompt == "Inspect the README." }))
        #expect(events.contains(where: { $0.trackedMetadataUpdate?.codexMetadata.currentTool == "exec_command" }))
        #expect(events.contains(where: { $0.trackedMetadataUpdate?.codexMetadata.currentCommandPreview == "git status -sb" }))
        #expect(events.contains(where: { $0.trackedSessionCompletion?.summary == "Finished the rollout tracking slice." }))
    }

    @Test
    func codexRolloutWatcherBootstrapsPromptMetadataFromHeadWhenTailMissesIt() async throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("open-island-rollout-head-bootstrap-\(UUID().uuidString)", isDirectory: true)
        let rolloutURL = rootURL.appendingPathComponent("rollout.jsonl")
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)

        defer {
            try? FileManager.default.removeItem(at: rootURL)
        }

        let fillerBeforeLatePrompt = (0..<8).map { index in
            rolloutLine(
                timestamp: String(format: "2026-04-02T14:37:%02d.000Z", 29 + index),
                type: "event_msg",
                payload: [
                    "type": "agent_message",
                    "message": "Filler analysis \(index): \(String(repeating: "segment-", count: 16))",
                ]
            )
        }
        let fillerAfterLatePrompt = (0..<8).map { index in
            rolloutLine(
                timestamp: String(format: "2026-04-02T14:38:%02d.000Z", 10 + index),
                type: "event_msg",
                payload: [
                    "type": "agent_message",
                    "message": "Post-user filler \(index): \(String(repeating: "segment-", count: 16))",
                ]
            )
        }

        let lines = [
            rolloutLine(
                timestamp: "2026-04-02T14:37:27.780Z",
                type: "response_item",
                payload: [
                    "type": "message",
                    "role": "user",
                    "content": [
                        [
                            "type": "input_text",
                            "text": "# AGENTS.md instructions for /tmp/repo\n\n<INSTRUCTIONS>\nRepository guide\n</INSTRUCTIONS>",
                        ],
                        [
                            "type": "input_text",
                            "text": "<environment_context>\n  <cwd>/tmp/repo</cwd>\n</environment_context>",
                        ],
                    ],
                ]
            ),
            rolloutLine(
                timestamp: "2026-04-02T14:37:28.346Z",
                type: "response_item",
                payload: [
                    "type": "message",
                    "role": "user",
                    "content": [
                        [
                            "type": "input_text",
                            "text": "读一下这篇论文 https://arxiv.org/html/2603.28052v1，然后对比一下 autoresearch 的实现。",
                        ],
                    ],
                ]
            ),
        ] + fillerBeforeLatePrompt + [
            rolloutLine(
                timestamp: "2026-04-02T14:38:05.000Z",
                type: "response_item",
                payload: [
                    "type": "message",
                    "role": "user",
                    "content": [
                        [
                            "type": "input_text",
                            "text": "时间你看图对比吧 我说的不对",
                        ],
                    ],
                ]
            ),
        ] + fillerAfterLatePrompt + [
            rolloutLine(
                timestamp: "2026-04-02T14:38:30.000Z",
                type: "response_item",
                payload: [
                    "type": "message",
                    "role": "assistant",
                    "content": [
                        [
                            "type": "output_text",
                            "text": "我先读论文内容并在仓库里定位 autoresearch 相关实现，再把两边的机制做一版对照。",
                        ],
                    ],
                ]
            ),
        ]

        try lines.joined(separator: "\n").appending("\n").write(to: rolloutURL, atomically: true, encoding: .utf8)

        let recorder = ObservedEventRecorder()
        let watcher = CodexRolloutWatcher(
            pollInterval: 0.05,
            initialReadLimit: 512,
            initialPromptBootstrapLimit: 4_096
        )
        watcher.eventHandler = { observed in
            Task {
                await recorder.append(observed)
            }
        }
        watcher.sync(targets: [
            CodexRolloutWatchTarget(
                sessionID: "codex-session-head-bootstrap",
                transcriptPath: rolloutURL.path
            )
        ])

        try await Task.sleep(for: .milliseconds(200))
        watcher.stop()

        let events = await recorder.snapshotEvents()
        #expect(events.contains(where: {
            $0.trackedMetadataUpdate?.codexMetadata.initialUserPrompt == "读一下这篇论文 https://arxiv.org/html/2603.28052v1，然后对比一下 autoresearch 的实现。"
        }))
        #expect(events.contains(where: {
            $0.trackedMetadataUpdate?.codexMetadata.lastUserPrompt == "时间你看图对比吧 我说的不对"
        }))
        #expect(events.contains(where: {
            $0.trackedActivityUpdate?.summary == "我先读论文内容并在仓库里定位 autoresearch 相关实现，再把两边的机制做一版对照。"
        }))
    }

    @Test
    func codexRolloutWatcherBootstrapsFromBoundedTailWindow() async throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("open-island-rollout-tail-\(UUID().uuidString)", isDirectory: true)
        let rolloutURL = rootURL.appendingPathComponent("rollout.jsonl")
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)

        defer {
            try? FileManager.default.removeItem(at: rootURL)
        }

        let oldMessage = String(repeating: "old-", count: 120)
        let oldLine = rolloutLine(
            timestamp: "2026-04-02T04:03:40.000Z",
            type: "event_msg",
            payload: [
                "type": "agent_message",
                "message": oldMessage,
            ]
        )
        let recentLine = rolloutLine(
            timestamp: "2026-04-02T04:03:45.000Z",
            type: "event_msg",
            payload: [
                "type": "agent_message",
                "message": "Tail bootstrap kept the watcher responsive.",
            ]
        )

        try [oldLine, recentLine]
            .joined(separator: "\n")
            .appending("\n")
            .write(to: rolloutURL, atomically: true, encoding: .utf8)

        let recorder = ObservedEventRecorder()
        let watcher = CodexRolloutWatcher(pollInterval: 0.05, initialReadLimit: 160)
        watcher.eventHandler = { observed in
            Task {
                await recorder.append(observed)
            }
        }
        watcher.sync(targets: [
            CodexRolloutWatchTarget(
                sessionID: "codex-session-tail",
                transcriptPath: rolloutURL.path
            )
        ])

        try await Task.sleep(for: .milliseconds(200))
        watcher.stop()

        let events = await recorder.snapshotEvents()
        #expect(events.contains(where: { $0.trackedActivityUpdate?.summary == "Tail bootstrap kept the watcher responsive." }))
        #expect(!events.contains(where: { $0.trackedActivityUpdate?.summary == oldMessage }))
    }

    @Test
    func codexRolloutWatcherLabelsBootstrapAndLiveEventsSeparately() async throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("open-island-rollout-freshness-\(UUID().uuidString)", isDirectory: true)
        let rolloutURL = rootURL.appendingPathComponent("rollout.jsonl")
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)

        defer {
            try? FileManager.default.removeItem(at: rootURL)
        }

        let initialLines = [
            sessionMetaLine(
                sessionID: "codex-session-freshness",
                timestamp: "2026-04-02T04:03:44.000Z",
                cwd: "/Users/wangruobing/Personal/open-island"
            ),
            rolloutLine(
                timestamp: "2026-04-02T04:03:45.000Z",
                type: "event_msg",
                payload: [
                    "type": "agent_message",
                    "message": "Bootstrap snapshot should stay metadata-only.",
                ]
            ),
        ]
        try initialLines.joined(separator: "\n").appending("\n").write(to: rolloutURL, atomically: true, encoding: .utf8)

        let recorder = ObservedEventRecorder()
        let watcher = CodexRolloutWatcher(pollInterval: 0.05)
        watcher.eventHandler = { observed in
            Task {
                await recorder.append(observed)
            }
        }
        watcher.sync(targets: [
            CodexRolloutWatchTarget(
                sessionID: "codex-session-freshness",
                transcriptPath: rolloutURL.path
            )
        ])
        defer {
            watcher.stop()
        }

        _ = try await waitForObservedEvent(in: recorder) {
            $0.freshness == .bootstrap
                && $0.event.trackedActivityUpdate?.summary == "Bootstrap snapshot should stay metadata-only."
        }
        try appendRolloutLine(
            rolloutLine(
                timestamp: "2026-04-02T04:03:46.000Z",
                type: "event_msg",
                payload: [
                    "type": "agent_message",
                    "message": "Live append should count as keepalive evidence.",
                ]
            ),
            to: rolloutURL
        )
        _ = try await waitForObservedEvent(in: recorder) {
            $0.freshness == .live
                && $0.event.trackedActivityUpdate?.summary == "Live append should count as keepalive evidence."
        }

        let observed = await recorder.snapshot()
        #expect(observed.contains(where: {
            $0.freshness == .bootstrap
                && $0.event.trackedActivityUpdate?.summary == "Bootstrap snapshot should stay metadata-only."
        }))
        #expect(observed.contains(where: {
            $0.freshness == .live
                && $0.event.trackedActivityUpdate?.summary == "Live append should count as keepalive evidence."
        }))
    }

    @Test
    func codexRolloutDiscoveryFindsRecentSessionsFromLocalRollouts() throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("open-island-discovery-\(UUID().uuidString)", isDirectory: true)
        let recentDirectoryURL = rootURL.appendingPathComponent("2026/04/02", isDirectory: true)
        let staleDirectoryURL = rootURL.appendingPathComponent("2026/03/30", isDirectory: true)
        let recentRolloutURL = recentDirectoryURL.appendingPathComponent("rollout-recent.jsonl")
        let staleRolloutURL = staleDirectoryURL.appendingPathComponent("rollout-stale.jsonl")
        let now = Date(timeIntervalSince1970: 1_743_555_200)

        try FileManager.default.createDirectory(at: recentDirectoryURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: staleDirectoryURL, withIntermediateDirectories: true)

        defer {
            try? FileManager.default.removeItem(at: rootURL)
        }

        let recentLines = [
            sessionMetaLine(
                sessionID: "codex-session-1",
                timestamp: "2026-04-02T04:03:44.000Z",
                cwd: "/Users/wangruobing/Personal/open-island"
            ),
            rolloutLine(
                timestamp: "2026-04-02T04:03:45.000Z",
                type: "response_item",
                payload: [
                    "type": "function_call",
                    "name": "exec_command",
                    "arguments": "{\"cmd\":\"git status -sb\"}",
                ]
            ),
            rolloutLine(
                timestamp: "2026-04-02T04:03:45.500Z",
                type: "event_msg",
                payload: [
                    "type": "user_message",
                    "message": "Inspect the local rollout files.",
                ]
            ),
            rolloutLine(
                timestamp: "2026-04-02T04:03:46.000Z",
                type: "event_msg",
                payload: [
                    "type": "agent_message",
                    "message": "Inspecting the local rollout files.",
                ]
            ),
        ]
        let staleLines = [
            sessionMetaLine(
                sessionID: "codex-session-stale",
                timestamp: "2026-03-30T04:03:44.000Z",
                cwd: "/Users/wangruobing/Personal/old-repo"
            ),
        ]

        try recentLines.joined(separator: "\n").appending("\n").write(to: recentRolloutURL, atomically: true, encoding: .utf8)
        try staleLines.joined(separator: "\n").appending("\n").write(to: staleRolloutURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.modificationDate: now], ofItemAtPath: recentRolloutURL.path)
        try FileManager.default.setAttributes([.modificationDate: now.addingTimeInterval(-172_800)], ofItemAtPath: staleRolloutURL.path)

        let discovery = CodexRolloutDiscovery(
            rootURL: rootURL,
            fileManager: .default,
            maxAge: 86_400,
            maxFiles: 10
        )

        let records = discovery.discoverRecentSessions(now: now)

        #expect(records.count == 1)
        #expect(records.first?.sessionID == "codex-session-1")
        #expect(records.first?.title == "Codex · open-island")
        #expect(records.first?.summary == "Inspecting the local rollout files.")
        #expect(records.first?.phase == .running)
        #expect(
            records.first?.codexMetadata?.transcriptPath.map {
                URL(fileURLWithPath: $0).resolvingSymlinksInPath().path
            } == recentRolloutURL.resolvingSymlinksInPath().path
        )
        #expect(records.first?.codexMetadata?.lastAssistantMessage == "Inspecting the local rollout files.")
        #expect(records.first?.codexMetadata?.lastUserPrompt == "Inspect the local rollout files.")
        #expect(records.first?.codexMetadata?.currentTool == nil)
        #expect(records.first?.codexMetadata?.currentCommandPreview == nil)
        #expect(records.first?.origin == .live)
        #expect(records.first?.attachmentState == .stale)
    }
}

private actor ObservedEventRecorder {
    private var observedEvents: [CodexRolloutObservedEvent] = []

    func append(_ observed: CodexRolloutObservedEvent) {
        observedEvents.append(observed)
    }

    func snapshot() -> [CodexRolloutObservedEvent] {
        observedEvents
    }

    func snapshotEvents() -> [AgentEvent] {
        observedEvents.map(\.event)
    }
}

private func waitForObservedEvent(
    in recorder: ObservedEventRecorder,
    timeout: Duration = .seconds(1),
    pollInterval: Duration = .milliseconds(10),
    matching predicate: (CodexRolloutObservedEvent) -> Bool
) async throws -> CodexRolloutObservedEvent {
    let clock = ContinuousClock()
    let deadline = clock.now.advanced(by: timeout)

    repeat {
        let observed = await recorder.snapshot()
        if let event = observed.first(where: predicate) {
            return event
        }

        try await Task.sleep(for: pollInterval)
    } while clock.now < deadline

    let observed = await recorder.snapshot()
    if let event = observed.first(where: predicate) {
        return event
    }

    Issue.record("Expected matching Codex rollout observation within \(timeout); observed \(observed.count) events")
    throw CancellationError()
}

private func appendRolloutLine(_ line: String, to fileURL: URL) throws {
    guard let data = "\(line)\n".data(using: .utf8) else {
        return
    }

    let handle = try FileHandle(forWritingTo: fileURL)
    defer {
        try? handle.close()
    }

    try handle.seekToEnd()
    try handle.write(contentsOf: data)
}

private func rolloutLine(
    timestamp: String,
    type: String,
    payload: [String: Any]
) -> String {
    let object: [String: Any] = [
        "timestamp": timestamp,
        "type": type,
        "payload": payload,
    ]
    let data = try! JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    return String(decoding: data, as: UTF8.self)
}

private func sessionMetaLine(
    sessionID: String,
    timestamp: String,
    cwd: String
) -> String {
    rolloutLine(
        timestamp: timestamp,
        type: "session_meta",
        payload: [
            "id": sessionID,
            "timestamp": timestamp,
            "cwd": cwd,
            "originator": "codex-tui",
            "source": "cli",
        ]
    )
}

private extension AgentEvent {
    var trackedActivityUpdate: SessionActivityUpdated? {
        if case let .activityUpdated(payload) = self {
            payload
        } else {
            nil
        }
    }

    var trackedSessionCompletion: SessionCompleted? {
        if case let .sessionCompleted(payload) = self {
            payload
        } else {
            nil
        }
    }

    var trackedMetadataUpdate: SessionMetadataUpdated? {
        if case let .sessionMetadataUpdated(payload) = self {
            payload
        } else {
            nil
        }
    }
}
