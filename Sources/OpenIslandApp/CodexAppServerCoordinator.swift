import AppKit
import Foundation
import OpenIslandCore

/// Manages the lifecycle of the Codex app-server connection.
///
/// Automatically starts the app-server subprocess when Codex.app is
/// detected, and tears it down when the app quits.  Converts incoming
/// app-server notifications into `AgentEvent`s that flow through the
/// standard `SessionState` reducer.
@Observable
@MainActor
final class CodexAppServerCoordinator {
    @ObservationIgnored
    private var client: CodexAppServerClient?

    @ObservationIgnored
    private var connectTask: Task<Void, Never>?

    @ObservationIgnored
    private var threadSyncTask: Task<Void, Never>?

    @ObservationIgnored
    private var lastThreadSyncDate = Date.distantPast

    /// Callback to emit AgentEvents into AppModel.
    @ObservationIgnored
    var onEvent: ((AgentEvent) -> Void)?

    /// Callback to log status messages.
    @ObservationIgnored
    var onStatusMessage: ((String) -> Void)?

    /// Returns `true` if a session with the given id is already tracked.
    /// Used to avoid re-emitting `sessionStarted` (which rebuilds the
    /// session and wipes richer state from hooks/rediscovery).
    @ObservationIgnored
    var isSessionTracked: ((String) -> Bool)?

    /// Existing metadata is merged with configuration refreshes so a title or
    /// model sync never erases prompt/tool state gathered from rollout hooks.
    @ObservationIgnored
    var existingCodexMetadata: ((String) -> CodexSessionMetadata?) = { _ in nil }

    @ObservationIgnored
    var existingJumpTarget: ((String) -> JumpTarget?) = { _ in nil }

    /// Resolves the title persisted by Codex Desktop when app-server omits it.
    @ObservationIgnored
    var persistedThreadTitle: ((String) -> String?) = { threadID in
        CodexThreadTitleStore().title(for: threadID)
    }

    /// Reads model, reasoning effort, and the current service tier from
    /// Codex's local state without rescanning large rollout histories.
    @ObservationIgnored
    var persistedThreadConfiguration: ((String) -> CodexSessionMetadata?) = { threadID in
        CodexThreadTitleStore().configurationMetadata(for: threadID)
    }

    private(set) var isConnected = false

    // MARK: - Public API

    /// Ensure a connection exists.  Called from the monitoring loop when
    /// Codex.app is detected as running.  Idempotent — does nothing if
    /// already connected or a connection attempt is in progress.
    func ensureConnected() {
        guard !isConnected, connectTask == nil else { return }

        // Resolve the Codex.app bundle location dynamically — users may
        // have installed Codex outside `/Applications` (e.g. ~/Applications).
        guard let bundleURL = NSWorkspace.shared.urlForApplication(
            withBundleIdentifier: "com.openai.codex"
        ) else {
            return
        }
        let codexPath = bundleURL
            .appendingPathComponent("Contents/Resources/codex")
            .path
        guard FileManager.default.isExecutableFile(atPath: codexPath) else {
            return
        }

        connectTask = Task { [weak self] in
            guard let self else { return }
            do {
                let newClient = CodexAppServerClient(codexPath: codexPath)
                newClient.onNotification = { [weak self] notification in
                    Task { @MainActor [weak self] in
                        self?.handleNotification(notification)
                    }
                }
                try await newClient.start()

                self.client = newClient
                self.isConnected = true
                self.connectTask = nil

                self.onStatusMessage?("Connected to Codex app-server.")

                // Fetch all threads so already-tracked project sessions can
                // receive their current Codex Desktop name/configuration even
                // when a fresh app-server reports them as not loaded.
                await self.syncLoadedThreads()
            } catch {
                self.connectTask = nil
                self.onStatusMessage?("Failed to connect to Codex app-server: \(error.localizedDescription)")
            }
        }
    }

    /// Disconnect and clean up.  Called when Codex.app is no longer running.
    func disconnect() {
        connectTask?.cancel()
        connectTask = nil
        threadSyncTask?.cancel()
        threadSyncTask = nil
        client?.stop()
        client = nil
        isConnected = false
    }

    /// Refresh tracked project sessions after rollout discovery has populated
    /// them. The app-server connection can become ready before or after file
    /// discovery, so a one-shot sync at connection time is not sufficient.
    func refreshThreadsIfNeeded(now: Date = .now) {
        guard isConnected,
              threadSyncTask == nil,
              now.timeIntervalSince(lastThreadSyncDate) >= 5 else {
            return
        }
        lastThreadSyncDate = now
        threadSyncTask = Task { [weak self] in
            guard let self else { return }
            await self.syncLoadedThreads()
            self.threadSyncTask = nil
        }
    }

    // MARK: - Thread sync

    private func syncLoadedThreads() async {
        guard let client else { return }
        do {
            let threads = try await client.listThreads(limit: 100)
            let created = syncThreads(threads)
            if created > 0 {
                onStatusMessage?("Synced \(created) new Codex thread(s) from app-server.")
            }
        } catch {
            onStatusMessage?("Failed to list loaded Codex threads: \(error.localizedDescription)")
        }
    }

    /// Applies a `thread/list` snapshot. Internal so the exact current
    /// app-server envelope and not-loaded project-session behavior can be
    /// pinned by regression tests.
    @discardableResult
    func syncThreads(_ threads: [CodexThread]) -> Int {
        var created = 0
        for thread in threads where !thread.ephemeral {
            if isSessionTracked?(thread.id) == true {
                emitTitleUpdated(sessionID: thread.id, title: preferredTitle(for: thread))
                emitJumpTargetUpdated(for: thread)
                emitConfigurationUpdated(for: thread)
                continue
            }

            // A newly spawned app-server labels history-only threads as
            // notLoaded. Do not import the whole history into the island; only
            // enrich those that rollout discovery already tracks.
            guard thread.status.type != .notLoaded else { continue }
            emitSessionStarted(from: thread)
            created += 1
        }
        return created
    }

    // MARK: - Notification handling

    func handleNotification(_ notification: CodexAppServerNotification) {
        switch notification {
        case .threadStarted(let thread):
            guard !thread.ephemeral else { return }
            if isSessionTracked?(thread.id) == true {
                emitTitleUpdated(sessionID: thread.id, title: preferredTitle(for: thread))
                emitJumpTargetUpdated(for: thread)
                emitConfigurationUpdated(for: thread)
                return
            }
            emitSessionStarted(from: thread)

        case .threadStatusChanged(let threadId, let status):
            switch status.type {
            case .active:
                if status.isWaitingOnApproval {
                    onEvent?(.permissionRequested(
                        PermissionRequested(
                            sessionID: threadId,
                            request: PermissionRequest(
                                title: "Approval Required",
                                summary: "Codex is waiting for approval.",
                                affectedPath: ""
                            ),
                            timestamp: .now
                        )
                    ))
                } else if status.isWaitingOnUserInput {
                    onEvent?(.questionAsked(
                        QuestionAsked(
                            sessionID: threadId,
                            prompt: QuestionPrompt(
                                title: "Codex is waiting for input.",
                                options: []
                            ),
                            timestamp: .now
                        )
                    ))
                } else {
                    onEvent?(.activityUpdated(
                        SessionActivityUpdated(
                            sessionID: threadId,
                            summary: "Codex is working…",
                            phase: .running,
                            timestamp: .now
                        )
                    ))
                }
            case .idle:
                // Idle means "between turns" in the same thread — the thread
                // is still open.  Only `thread/closed` truly ends a session.
                onEvent?(.activityUpdated(
                    SessionActivityUpdated(
                        sessionID: threadId,
                        summary: "Idle.",
                        phase: .completed,
                        timestamp: .now
                    )
                ))
            case .systemError:
                // Quota limits and other hard failures can leave the thread in
                // systemError without a turn/completed notification. Mark the
                // turn as finished so the island does not stay stuck running.
                onEvent?(.activityUpdated(
                    SessionActivityUpdated(
                        sessionID: threadId,
                        summary: "Turn failed.",
                        phase: .completed,
                        timestamp: .now
                    )
                ))
            case .notLoaded:
                break
            }

        case .threadClosed(let threadId):
            onEvent?(.sessionCompleted(
                SessionCompleted(
                    sessionID: threadId,
                    summary: "Codex thread closed.",
                    timestamp: .now,
                    isSessionEnd: true
                )
            ))

        case let .threadNameUpdated(threadId, name):
            emitTitleUpdated(sessionID: threadId, title: name)

        case .turnStarted(let threadId, _):
            onEvent?(.activityUpdated(
                SessionActivityUpdated(
                    sessionID: threadId,
                    summary: "Codex is working…",
                    phase: .running,
                    timestamp: .now
                )
            ))

        case .turnCompleted(let threadId, let turn):
            // A turn completing doesn't end the thread — the user can send
            // another message.  Use activityUpdated(phase: .completed) so the
            // session stays visible as "Completed" rather than being torn
            // down.  `thread/closed` is the authoritative end signal.
            let summary: String
            switch turn.status {
            case .completed: summary = "Turn completed."
            case .interrupted: summary = "Turn interrupted."
            case .failed: summary = "Turn failed."
            case .inProgress: summary = "Turn in progress."
            }
            onEvent?(.activityUpdated(
                SessionActivityUpdated(
                    sessionID: threadId,
                    summary: summary,
                    phase: .completed,
                    timestamp: .now
                )
            ))

        case .unknown:
            break
        }
    }

    // MARK: - Helpers

    private func emitSessionStarted(from thread: CodexThread) {
        let workspaceName = URL(fileURLWithPath: thread.cwd).lastPathComponent
        let title = preferredTitle(for: thread) ?? workspaceName
        let summary = thread.preview.isEmpty ? "Codex session." : String(thread.preview.prefix(120))

        let phase: SessionPhase
        switch thread.status.type {
        case .active: phase = .running
        case .idle: phase = .completed
        case .notLoaded, .systemError: phase = .completed
        }

        onEvent?(.sessionStarted(
            SessionStarted(
                sessionID: thread.id,
                title: title,
                tool: .codex,
                origin: .live,
                initialPhase: phase,
                summary: summary,
                timestamp: .now,
                jumpTarget: JumpTarget(
                    terminalApp: "Codex.app",
                    workspaceName: workspaceName,
                    paneTitle: title,
                    workingDirectory: thread.cwd,
                    codexThreadID: thread.id
                ),
                codexMetadata: mergedMetadata(
                    sessionID: thread.id,
                    transcriptPath: thread.path,
                    initialUserPrompt: thread.preview.isEmpty ? nil : thread.preview
                )
            )
        ))
    }

    private func emitConfigurationUpdated(for thread: CodexThread) {
        let existing = existingCodexMetadata(thread.id)
        let merged = mergedMetadata(
            sessionID: thread.id,
            transcriptPath: thread.path,
            initialUserPrompt: existing?.initialUserPrompt
        )
        guard !merged.isEmpty, merged != existing else { return }

        onEvent?(.sessionMetadataUpdated(
            SessionMetadataUpdated(
                sessionID: thread.id,
                codexMetadata: merged,
                timestamp: .now
            )
        ))
    }

    private func emitJumpTargetUpdated(for thread: CodexThread) {
        let workspaceName = URL(fileURLWithPath: thread.cwd).lastPathComponent
        let title = preferredTitle(for: thread) ?? workspaceName
        let existing = existingJumpTarget(thread.id)
        let target = JumpTarget(
            terminalApp: "Codex.app",
            workspaceName: workspaceName,
            paneTitle: title,
            workingDirectory: thread.cwd,
            terminalSessionID: existing?.terminalSessionID,
            terminalTTY: existing?.terminalTTY,
            tmuxTarget: existing?.tmuxTarget,
            tmuxSocketPath: existing?.tmuxSocketPath,
            warpPaneUUID: existing?.warpPaneUUID,
            codexThreadID: thread.id
        )
        guard target != existing else { return }

        onEvent?(.jumpTargetUpdated(
            JumpTargetUpdated(
                sessionID: thread.id,
                jumpTarget: target,
                timestamp: .now
            )
        ))
    }

    private func mergedMetadata(
        sessionID: String,
        transcriptPath: String?,
        initialUserPrompt: String?
    ) -> CodexSessionMetadata {
        let existing = existingCodexMetadata(sessionID)
        let configuration = persistedThreadConfiguration(sessionID)
        return CodexSessionMetadata(
            transcriptPath: existing?.transcriptPath ?? transcriptPath,
            initialUserPrompt: existing?.initialUserPrompt ?? initialUserPrompt,
            lastUserPrompt: existing?.lastUserPrompt,
            lastAssistantMessage: existing?.lastAssistantMessage,
            currentTool: existing?.currentTool,
            currentCommandPreview: existing?.currentCommandPreview,
            model: configuration?.model ?? existing?.model,
            reasoningEffort: configuration?.reasoningEffort ?? existing?.reasoningEffort,
            serviceTier: existing?.serviceTier ?? configuration?.serviceTier
        )
    }

    private func emitTitleUpdated(sessionID: String, title: String?) {
        guard let title = title?.trimmingCharacters(in: .whitespacesAndNewlines),
              !title.isEmpty else {
            return
        }

        onEvent?(.sessionTitleUpdated(
            SessionTitleUpdated(
                sessionID: sessionID,
                title: title,
                timestamp: .now
            )
        ))
    }

    private func preferredTitle(for thread: CodexThread) -> String? {
        if let name = thread.name?.trimmingCharacters(in: .whitespacesAndNewlines),
           !name.isEmpty {
            return name
        }

        return persistedThreadTitle(thread.id)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
