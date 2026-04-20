# OpenCode Stability Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make OpenCode support as stable as Claude Code by adding session persistence, startup discovery, and refined liveness detection.

**Architecture:** Implement `OpenCodeSessionRegistry` for persistence, integrate it into `SessionDiscoveryCoordinator` for startup recovery, and update `ProcessMonitoringCoordinator` to handle OpenCode sessions more robustly.

**Tech Stack:** Swift, Observation framework, JSON persistence.

---

### Task 1: Create OpenCodeSessionRegistry

**Files:**
- Create: `Sources/AgentDeckCore/OpenCodeSessionRegistry.swift`

- [ ] **Step 1: Implement OpenCodeTrackedSessionRecord and OpenCodeSessionRegistry**

```swift
import Foundation

public struct OpenCodeTrackedSessionRecord: Equatable, Codable, Sendable {
    public var sessionID: String
    public var title: String
    public var origin: SessionOrigin?
    public var attachmentState: SessionAttachmentState
    public var summary: String
    public var phase: SessionPhase
    public var updatedAt: Date
    public var jumpTarget: JumpTarget?
    public var openCodeMetadata: OpenCodeSessionMetadata?

    public init(
        sessionID: String,
        title: String,
        origin: SessionOrigin? = nil,
        attachmentState: SessionAttachmentState = .stale,
        summary: String,
        phase: SessionPhase,
        updatedAt: Date,
        jumpTarget: JumpTarget? = nil,
        openCodeMetadata: OpenCodeSessionMetadata? = nil
    ) {
        self.sessionID = sessionID
        self.title = title
        self.origin = origin
        self.attachmentState = attachmentState
        self.summary = summary
        self.phase = phase
        self.updatedAt = updatedAt
        self.jumpTarget = jumpTarget
        self.openCodeMetadata = openCodeMetadata
    }

    public init(session: AgentSession) {
        self.init(
            sessionID: session.id,
            title: session.title,
            origin: session.origin,
            attachmentState: session.attachmentState,
            summary: session.summary,
            phase: session.phase,
            updatedAt: session.updatedAt,
            jumpTarget: session.jumpTarget,
            openCodeMetadata: session.openCodeMetadata
        )
    }

    public var session: AgentSession {
        AgentSession(
            id: sessionID,
            title: title,
            tool: .openCode,
            origin: origin,
            attachmentState: attachmentState,
            phase: phase,
            summary: summary,
            updatedAt: updatedAt,
            jumpTarget: jumpTarget,
            openCodeMetadata: openCodeMetadata
        )
    }

    public var restorableSession: AgentSession {
        var session = session
        session.attachmentState = .stale
        return session
    }
}

public final class OpenCodeSessionRegistry: @unchecked Sendable {
    public let fileURL: URL
    private let fileManager: FileManager

    public static var defaultDirectoryURL: URL {
        CodexSessionStore.defaultDirectoryURL
    }

    public static var defaultFileURL: URL {
        defaultDirectoryURL.appendingPathComponent("opencode-session-registry.json")
    }

    public init(
        fileURL: URL = OpenCodeSessionRegistry.defaultFileURL,
        fileManager: FileManager = .default
    ) {
        self.fileURL = fileURL
        self.fileManager = fileManager
    }

    public func load() throws -> [OpenCodeTrackedSessionRecord] {
        guard fileManager.fileExists(atPath: fileURL.path) else {
            return []
        }

        let data = try Data(contentsOf: fileURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode([OpenCodeTrackedSessionRecord].self, from: data)
    }

    public func save(_ records: [OpenCodeTrackedSessionRecord]) throws {
        let directoryURL = fileURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        let data = try encoder.encode(records)
        try data.write(to: fileURL, options: .atomic)
    }
}
```

- [ ] **Step 2: Commit**

```bash
git add Sources/AgentDeckCore/OpenCodeSessionRegistry.swift
git commit -m "feat: add OpenCodeSessionRegistry for session persistence"
```

---

### Task 2: Integrate into SessionDiscoveryCoordinator

**Files:**
- Modify: `Sources/AgentDeckApp/SessionDiscoveryCoordinator.swift`

- [ ] **Step 1: Add OpenCode fields to StartupDiscoveryPayload**

```swift
    struct StartupDiscoveryPayload: Sendable {
        // ...
        var openCodeRecords: [OpenCodeTrackedSessionRecord]
        var openCodeRecordsNeedPrune: Bool
        // ...
    }
```

- [ ] **Step 2: Initialize OpenCodeSessionRegistry and add persistence task**

```swift
    @ObservationIgnored
    private let openCodeSessionRegistry = OpenCodeSessionRegistry()

    @ObservationIgnored
    private var openCodeSessionPersistenceTask: Task<Void, Never>?
```

- [ ] **Step 3: Update loadStartupDiscoveryPayload to load OpenCode records**

```swift
    nonisolated func loadStartupDiscoveryPayload() -> StartupDiscoveryPayload {
        // ...
        let allOpenCode = (try? openCodeSessionRegistry.load()) ?? []
        let openCodeRecords = allOpenCode.filter { $0.updatedAt >= cutoff }
        // ...
        return StartupDiscoveryPayload(
            // ...
            openCodeRecords: openCodeRecords,
            openCodeRecordsNeedPrune: openCodeRecords != allOpenCode,
            // ...
        )
    }
```

- [ ] **Step 4: Update applyStartupDiscoveryPayload to restore OpenCode sessions**

```swift
    func applyStartupDiscoveryPayload(_ payload: StartupDiscoveryPayload) {
        // ...
        if payload.openCodeRecordsNeedPrune {
            try? openCodeSessionRegistry.save(payload.openCodeRecords)
        }

        // Restore persisted OpenCode sessions.
        if !payload.openCodeRecords.isEmpty {
            let restoredSessions = payload.openCodeRecords.map(\.restorableSession)
            state = SessionState(sessions: mergeDiscoveredSessions(restoredSessions))
            onStatusMessage?("Restored \(payload.openCodeRecords.count) recent OpenCode session(s) from local registry.")
        }
        // ...
    }
```

- [ ] **Step 5: Add scheduleOpenCodeSessionPersistence method**

```swift
    func scheduleOpenCodeSessionPersistence() {
        openCodeSessionPersistenceTask?.cancel()

        let records = state.sessions
            .filter {
                $0.tool == .openCode
                    && $0.isTrackedLiveSession
                    && $0.updatedAt >= Date.now.addingTimeInterval(-86_400)
            }
            .map(OpenCodeTrackedSessionRecord.init(session:))
        let registry = openCodeSessionRegistry

        openCodeSessionPersistenceTask = Task.detached(priority: .utility) {
            try? await Task.sleep(for: .milliseconds(250))
            try? registry.save(records)
        }
    }
```

- [ ] **Step 6: Update merge method to handle OpenCode metadata**

```swift
    private func merge(discovered: AgentSession, into existing: AgentSession) -> AgentSession {
        // ...
        merged.openCodeMetadata = mergeOpenCodeMetadata(existing.openCodeMetadata, discovered.openCodeMetadata)
        // ...
    }

    private func mergeOpenCodeMetadata(
        _ existing: OpenCodeSessionMetadata?,
        _ discovered: OpenCodeSessionMetadata?
    ) -> OpenCodeSessionMetadata? {
        guard let existing else {
            return discovered?.isEmpty == true ? nil : discovered
        }

        guard let discovered else {
            return existing.isEmpty ? nil : existing
        }

        let merged = OpenCodeSessionMetadata(
            initialUserPrompt: existing.initialUserPrompt ?? discovered.initialUserPrompt ?? discovered.lastUserPrompt,
            lastUserPrompt: discovered.lastUserPrompt ?? existing.lastUserPrompt,
            lastAssistantMessage: discovered.lastAssistantMessage ?? existing.lastAssistantMessage,
            currentTool: discovered.currentTool ?? existing.currentTool,
            currentToolInputPreview: discovered.currentToolInputPreview ?? existing.currentToolInputPreview,
            model: discovered.model ?? existing.model
        )
        return merged.isEmpty ? nil : merged
    }
```

- [ ] **Step 7: Commit**

```bash
git add Sources/AgentDeckApp/SessionDiscoveryCoordinator.swift
git commit -m "feat: integrate OpenCode session persistence into SessionDiscoveryCoordinator"
```

---

### Task 3: Update AppModel and ProcessMonitoringCoordinator

**Files:**
- Modify: `Sources/AgentDeckApp/AppModel.swift`
- Modify: `Sources/AgentDeckApp/ProcessMonitoringCoordinator.swift`

- [ ] **Step 1: Call scheduleOpenCodeSessionPersistence in AppModel**

In `AppModel.handleBridgeCommand`, specifically in `processOpenCodeHook` case, call `discovery.scheduleOpenCodeSessionPersistence()`.

- [ ] **Step 2: Update ProcessMonitoringCoordinator to trigger persistence on reconciliation**

Ensure `onPersistenceNeeded?()` is called when OpenCode sessions change.

- [ ] **Step 3: Refine liveness detection in ProcessMonitoringCoordinator**

Actually, OpenCode is already managed by hooks (`SessionStart`, `SessionEnd`). We should mark it as `isHookManaged = true`.

Modify `AppModel.swift` in `handleOpenCodeHook`:
```swift
    private func handleOpenCodeHook(_ payload: OpenCodeHookPayload) {
        // ...
        var session = sessions.first { $0.id == payload.sessionID } ?? AgentSession(...)
        session.isHookManaged = true
        // ...
    }
```

- [ ] **Step 4: Commit**

```bash
git add Sources/AgentDeckApp/AppModel.swift Sources/AgentDeckApp/ProcessMonitoringCoordinator.swift
git commit -m "feat: mark OpenCode sessions as hook-managed and trigger persistence"
```

---

### Task 4: Verification

- [ ] **Step 1: Verify OpenCode sessions are saved and restored**
1. Start OpenCode session (via script or real usage).
2. Check `~/Library/Application Support/agent-deck/opencode-session-registry.json`.
3. Restart Agent Deck.
4. Verify session is restored in the UI.

- [ ] **Step 2: Verify metadata merging**
1. Trigger multiple updates for the same OpenCode session.
2. Verify metadata is merged correctly in `AgentSession`.
