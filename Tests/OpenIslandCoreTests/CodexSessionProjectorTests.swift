import Foundation
import Testing
@testable import OpenIslandCore

/// End-to-end coverage for the projection layer.
///
/// Each test here corresponds to a reported defect the architecture is meant to
/// make structurally impossible, so a regression shows up as a named failure
/// rather than as a vague behaviour change.
@Suite("Codex session projector")
struct CodexSessionProjectorTests {
    private func makeStack() -> (CodexFacetStore, CodexSessionProjector) {
        let store = CodexFacetStore()
        store.enterLiveMode()
        return (store, CodexSessionProjector(store: store))
    }

    private func observation(
        _ source: CodexSource,
        seq: UInt64,
        _ patch: CodexFacetPatch,
        session: String = "S1",
        at seconds: TimeInterval = 0
    ) -> CodexObservation {
        CodexObservation(
            ref: .sessionID(session),
            source: source,
            seq: seq,
            observedAt: Date(timeIntervalSince1970: 1_700_000_000 + seconds),
            patch: patch
        )
    }

    // MARK: - Session creation

    @Test("a session is not announced until it has something to show")
    func noPrematureAnnouncement() {
        let (_, projector) = makeStack()

        // Lifecycle alone gives the row no workspace and no terminal.
        let events = projector.project(observation(.appServer, seq: 1, CodexFacetPatch(
            lifecycle: CodexLifecycle(phase: .running)
        )))

        #expect(events.isEmpty)
        #expect(!projector.hasAnnounced(sessionKey: "S1"))
    }

    @Test("a terminal session is announced once placement and workspace arrive")
    func terminalSessionAnnounced() {
        let (_, projector) = makeStack()

        let events = projector.project(observation(.hook, seq: 1, CodexFacetPatch(
            workspace: CodexWorkspace(workingDirectory: "/Users/dev/work/island"),
            placement: CodexPlacement(terminalApp: "Ghostty"),
            lifecycle: CodexLifecycle(phase: .running)
        )))

        #expect(events.count == 1)
        guard case let .sessionStarted(started) = events.first else {
            Issue.record("expected sessionStarted, got \(String(describing: events.first))")
            return
        }
        #expect(started.sessionID == "S1")
        #expect(started.tool == .codex)
        #expect(started.jumpTarget?.terminalApp == "Ghostty")
        #expect(started.jumpTarget?.workspaceName == "island")
    }

    @Test("a Codex.app session is announced without any terminal")
    func desktopSessionAnnouncedWithoutPlacement() {
        // Desktop threads never produce placement — the app-server cannot see a
        // terminal and there is none to see. Gating announcement on placement
        // would leave every Codex.app session invisible.
        let (_, projector) = makeStack()

        let events = projector.project(observation(.rollout, seq: 1, CodexFacetPatch(
            surface: .desktopApp,
            workspace: CodexWorkspace(workingDirectory: "/Users/dev/work/island")
        )))

        guard case let .sessionStarted(started) = events.first else {
            Issue.record("desktop session was not announced")
            return
        }
        #expect(started.jumpTarget?.terminalApp == "Codex.app")
        #expect(started.jumpTarget?.codexThreadID == "S1")
    }

    @Test("spawned subagent threads produce no events at all")
    func subagentProducesNothing() {
        let (_, projector) = makeStack()

        let events = projector.project(observation(.rollout, seq: 1, CodexFacetPatch(
            surface: .subagent(parentThreadID: "P1", kind: "thread_spawn"),
            workspace: CodexWorkspace(workingDirectory: "/Users/dev/work/island"),
            narrative: CodexNarrative(title: "internal worker")
        )))

        #expect(events.isEmpty)
        #expect(!projector.hasAnnounced(sessionKey: "S1"))
    }

    @Test("internal daemon transcripts produce no events")
    func internalDaemonProducesNothing() {
        let (_, projector) = makeStack()

        let events = projector.project(observation(.rollout, seq: 1, CodexFacetPatch(
            surface: .internalDaemon,
            workspace: CodexWorkspace(workingDirectory: "/Users/dev/work/island")
        )))

        #expect(events.isEmpty)
    }

    // MARK: - Title handling

    @Test("a transcript scrape cannot overwrite the thread name the user set")
    func transcriptCannotOverwriteThreadName() {
        let (_, projector) = makeStack()

        _ = projector.project(observation(.rollout, seq: 1, CodexFacetPatch(
            surface: .desktopApp,
            workspace: CodexWorkspace(workingDirectory: "/Users/dev/work/island")
        )))
        _ = projector.project(observation(.appServer, seq: 2, CodexFacetPatch(
            narrative: CodexNarrative(title: "Ship the release")
        )))

        // Injected context arriving later must not become the visible title.
        let events = projector.project(observation(.rollout, seq: 99, CodexFacetPatch(
            narrative: CodexNarrative(title: "<system-reminder> ...")
        )))

        for event in events {
            if case let .sessionMetadataUpdated(update) = event {
                #expect(update.codexMetadata.initialUserPrompt != "<system-reminder> ...")
            }
        }
    }

    // MARK: - Liveness

    @Test("a closed desktop thread completes the session")
    func threadClosedCompletesSession() {
        let (_, projector) = makeStack()

        _ = projector.project(observation(.rollout, seq: 1, CodexFacetPatch(
            surface: .desktopApp,
            workspace: CodexWorkspace(workingDirectory: "/Users/dev/work/island")
        )))

        let events = projector.project(observation(.appServer, seq: 2, CodexFacetPatch(
            liveness: CodexLiveness(state: .ended(reason: .threadClosed))
        )))

        guard case let .sessionCompleted(completed) = events.last else {
            Issue.record("expected sessionCompleted, got \(String(describing: events.last))")
            return
        }
        #expect(completed.isSessionEnd == true)
    }

    @Test("a vanished transcript cannot end a session")
    func rolloutCannotEndSession() {
        // Codex.app archives transcripts of threads that are still open.
        // Treating the file's absence as an ending is what stranded desktop
        // rows in a permanently running state.
        let (_, projector) = makeStack()

        _ = projector.project(observation(.rollout, seq: 1, CodexFacetPatch(
            surface: .desktopApp,
            workspace: CodexWorkspace(workingDirectory: "/Users/dev/work/island")
        )))

        let events = projector.project(observation(.rollout, seq: 2, CodexFacetPatch(
            liveness: CodexLiveness(state: .ended(reason: .archived))
        )))

        #expect(!events.contains { if case .sessionCompleted = $0 { return true }; return false })
    }

    @Test("liveness settles before run phase in the same batch")
    func livenessWinsOverLifecycle() {
        let (_, projector) = makeStack()

        _ = projector.project(observation(.hook, seq: 1, CodexFacetPatch(
            workspace: CodexWorkspace(workingDirectory: "/Users/dev/work/island"),
            placement: CodexPlacement(terminalApp: "Ghostty")
        )))

        let events = projector.project(observation(.appServer, seq: 2, CodexFacetPatch(
            lifecycle: CodexLifecycle(phase: .running),
            liveness: CodexLiveness(state: .ended(reason: .threadClosed))
        )))

        // An activity update after completion would resurrect a row the user
        // just watched disappear.
        #expect(events.contains { if case .sessionCompleted = $0 { return true }; return false })
        #expect(!events.contains { if case .activityUpdated = $0 { return true }; return false })
    }

    @Test("a finished turn surfaces the island; only a real ending marks the session over")
    func finishedTurnSurfacesWithoutEndingSession() {
        // IslandSurface pops the island only for sessionCompleted, and the
        // watch relay only pushes for it. A finished turn reported as an
        // activity update silently drops both.
        let (_, projector) = makeStack()

        _ = projector.project(observation(.hook, seq: 1, CodexFacetPatch(
            workspace: CodexWorkspace(workingDirectory: "/Users/dev/work/island"),
            placement: CodexPlacement(terminalApp: "Ghostty")
        )))

        let turnDone = projector.project(observation(.hook, seq: 2, CodexFacetPatch(
            lifecycle: CodexLifecycle(phase: .completed)
        )))
        guard case let .sessionCompleted(completed) = turnDone.last else {
            Issue.record("a finished turn must surface, got \(String(describing: turnDone.last))")
            return
        }
        #expect(completed.isSessionEnd == false, "a turn ending is not the session ending")

        let sessionOver = projector.project(observation(.hook, seq: 3, CodexFacetPatch(
            liveness: CodexLiveness(state: .ended(reason: .sessionEnd))
        )))
        guard case let .ended(ending) = sessionOver.last.map({ event -> CodexLiveness.State in
            if case let .sessionCompleted(p) = event, p.isSessionEnd == true {
                return .ended(reason: .sessionEnd)
            }
            return .alive
        }) else {
            Issue.record("session end must mark the session over, got \(String(describing: sessionOver.last))")
            return
        }
        #expect(ending == .sessionEnd)
    }

    @Test("a running turn is still an activity update")
    func runningTurnIsActivity() {
        let (_, projector) = makeStack()
        _ = projector.project(observation(.hook, seq: 1, CodexFacetPatch(
            workspace: CodexWorkspace(workingDirectory: "/Users/dev/work/island"),
            placement: CodexPlacement(terminalApp: "Ghostty"),
            lifecycle: CodexLifecycle(phase: .completed)
        )))

        let running = projector.project(observation(.hook, seq: 2, CodexFacetPatch(
            lifecycle: CodexLifecycle(phase: .running)
        )))
        #expect(running.contains { if case .activityUpdated = $0 { return true }; return false })
    }

    // MARK: - Approvals

    @Test("a hook permission request surfaces as an approval")
    func permissionSurfaces() {
        let (_, projector) = makeStack()

        _ = projector.project(observation(.hook, seq: 1, CodexFacetPatch(
            workspace: CodexWorkspace(workingDirectory: "/Users/dev/work/island"),
            placement: CodexPlacement(terminalApp: "Ghostty")
        )))

        let request = PermissionRequest(
            title: "Run command",
            summary: "rm -rf build",
            affectedPath: "/Users/dev/work/island",
            primaryActionTitle: "Allow",
            secondaryActionTitle: "Deny",
            toolName: "shell",
            toolUseID: "t-1"
        )
        let events = projector.project(observation(.hook, seq: 2, CodexFacetPatch(
            actionable: .permission(request)
        )))

        guard case let .permissionRequested(payload) = events.first else {
            Issue.record("expected permissionRequested, got \(String(describing: events.first))")
            return
        }
        #expect(payload.request.toolUseID == "t-1")
    }

    @Test("neither the transcript nor process observation can raise an approval")
    func transcriptAndProcessCannotRaiseApprovals() {
        let (_, projector) = makeStack()

        _ = projector.project(observation(.hook, seq: 1, CodexFacetPatch(
            workspace: CodexWorkspace(workingDirectory: "/Users/dev/work/island"),
            placement: CodexPlacement(terminalApp: "Ghostty")
        )))

        let request = PermissionRequest(
            title: "x", summary: "y", affectedPath: "/tmp",
            primaryActionTitle: "Allow", secondaryActionTitle: "Deny",
            toolName: nil, toolUseID: nil
        )
        // The app-server is allowed a placeholder (it can see a thread is
        // waiting); the transcript and the process table cannot know at all.
        for source in [CodexSource.rollout, .process] {
            let events = projector.project(observation(source, seq: 10, CodexFacetPatch(
                actionable: .permission(request)
            )))
            #expect(!events.contains {
                if case .permissionRequested = $0 { return true }; return false
            }, "\(source.displayName) raised an approval")
        }
    }

    // MARK: - Ordering

    @Test("a late observation does not rewind an already-completed session")
    func lateObservationDoesNotRewind() {
        let (store, projector) = makeStack()

        _ = projector.project(observation(.hook, seq: 1, CodexFacetPatch(
            workspace: CodexWorkspace(workingDirectory: "/Users/dev/work/island"),
            placement: CodexPlacement(terminalApp: "Ghostty")
        )))
        _ = projector.project(observation(.appServer, seq: 9, CodexFacetPatch(
            lifecycle: CodexLifecycle(phase: .completed)
        )))
        _ = projector.project(observation(.appServer, seq: 3, CodexFacetPatch(
            lifecycle: CodexLifecycle(phase: .running)
        )))

        #expect(store.session(for: "S1")?.lifecycle?.value.phase == .completed)
    }
}
