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

    /// Callback to emit AgentEvents into AppModel.
    @ObservationIgnored
    var onEvent: ((AgentEvent) -> Void)?
    /// Called once per notification with the events the legacy path produced
    /// for it, so the caller can run the rewritten pipeline on the same input
    /// and compare — or, when that pipeline drives the UI, apply its events
    /// instead.
    var onNotificationObserved: ((CodexAppServerNotification, [AgentEvent]) -> Void)?
    var onLoadedThreadObserved: ((CodexThread, [AgentEvent]) -> Void)?
    /// When the rewritten pipeline drives the UI, legacy events are still
    /// produced for comparison but must not be applied.
    var suppressLegacyEvents = false
    private var legacyBuffer: [AgentEvent] = []

    private func deliver(_ event: AgentEvent) {
        legacyBuffer.append(event)
        if !suppressLegacyEvents {
            deliver(event)
        }
    }

    /// Callback to log status messages.
    @ObservationIgnored
    var onStatusMessage: ((String) -> Void)?

    /// Returns `true` if a session with the given id is already tracked.
    /// Used to avoid re-emitting `sessionStarted` (which rebuilds the
    /// session and wipes richer state from hooks/rediscovery).
    @ObservationIgnored
    var isSessionTracked: ((String) -> Bool)?

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
            // Silence here reads as "Codex.app is not running" when it may
            // simply be installed somewhere LaunchServices does not know
            // about — and desktop sessions then quietly lose their only
            // real-time source.
            onStatusMessage?("Codex.app not found; desktop sessions will fall back to transcript discovery.")
            return
        }
        let codexPath = bundleURL
            .appendingPathComponent("Contents/Resources/codex")
            .path
        guard FileManager.default.isExecutableFile(atPath: codexPath) else {
            onStatusMessage?("Codex.app has no bundled app-server; desktop sessions will fall back to transcript discovery.")
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

                // Fetch currently loaded threads and create sessions.
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
        client?.stop()
        client = nil
        isConnected = false
    }

    // MARK: - Thread sync

    private func syncLoadedThreads() async {
        guard let client else { return }
        do {
            let threads = try await client.listLoadedThreads()
            var created = 0
            for thread in threads where !thread.ephemeral {
                // Skip threads already tracked — re-emitting sessionStarted
                // rebuilds the AgentSession and would wipe richer state
                // already accumulated from hooks or rediscovery.
                if isSessionTracked?(thread.id) == true { continue }
                legacyBuffer = []
                emitSessionStarted(from: thread)
                onLoadedThreadObserved?(thread, legacyBuffer)
                created += 1
            }
            if created > 0 {
                onStatusMessage?("Synced \(created) new Codex thread(s) from app-server.")
            }
        } catch {
            onStatusMessage?("Failed to list loaded Codex threads: \(error.localizedDescription)")
        }
    }

    // MARK: - Notification handling

    private func handleNotification(_ notification: CodexAppServerNotification) {
        legacyBuffer = []
        defer { onNotificationObserved?(notification, legacyBuffer) }
        switch notification {
        case .threadStarted(let thread):
            guard !thread.ephemeral else { return }
            guard isSessionTracked?(thread.id) != true else { return }
            emitSessionStarted(from: thread)

        case .threadStatusChanged(let threadId, let status):
            switch status.type {
            case .active:
                if status.isWaitingOnApproval {
                    deliver(.permissionRequested(
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
                    deliver(.questionAsked(
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
                    deliver(.activityUpdated(
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
                deliver(.activityUpdated(
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
                deliver(.activityUpdated(
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
            deliver(.sessionCompleted(
                SessionCompleted(
                    sessionID: threadId,
                    summary: "Codex thread closed.",
                    timestamp: .now,
                    isSessionEnd: true
                )
            ))

        case .threadNameUpdated:
            // Title updates don't have a dedicated AgentEvent and we can't
            // safely overwrite phase/summary here (would clobber running or
            // waiting-for-approval state).  Skip for now — the title is
            // populated at sessionStarted time which is usually enough.
            break

        case .turnStarted(let threadId, _):
            deliver(.activityUpdated(
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
            deliver(.activityUpdated(
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
        let title = thread.name ?? workspaceName
        let summary = thread.preview.isEmpty ? "Codex session." : String(thread.preview.prefix(120))

        let phase: SessionPhase
        switch thread.status.type {
        case .active: phase = .running
        case .idle: phase = .completed
        case .notLoaded, .systemError: phase = .completed
        }

        deliver(.sessionStarted(
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
                codexMetadata: CodexSessionMetadata(
                    transcriptPath: thread.path,
                    initialUserPrompt: thread.preview.isEmpty ? nil : thread.preview
                )
            )
        ))
    }
}
