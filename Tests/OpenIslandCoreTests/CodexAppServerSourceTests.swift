import Foundation
import Testing
@testable import OpenIslandCore

/// The app-server is the only channel that watches a desktop thread through
/// its whole life, and desktop sessions are the large majority of real usage.
/// These pin what each notification contributes — and, at the store level, how
/// a status placeholder yields to a hook's real request.
@Suite("Codex app-server source")
struct CodexAppServerSourceTests {
    private func thread(
        id: String = "T1",
        name: String? = "Ship the release",
        cwd: String = "/Users/dev/work/island",
        preview: String = "fix the login bug",
        status: CodexThreadStatusType = .active,
        path: String? = "/Users/dev/.codex/sessions/rollout-T1.jsonl",
        ephemeral: Bool = false
    ) -> CodexThread {
        let json = """
        {"id":"\(id)","cwd":"\(cwd)","name":\(name.map { "\"\($0)\"" } ?? "null"),
         "preview":"\(preview)","modelProvider":"openai","createdAt":1,"updatedAt":2,
         "ephemeral":\(ephemeral),"path":\(path.map { "\"\($0)\"" } ?? "null"),
         "status":{"type":"\(status.rawValue)"}}
        """
        return try! JSONDecoder().decode(CodexThread.self, from: Data(json.utf8))
    }

    private func status(_ type: CodexThreadStatusType, waiting: String? = nil) -> CodexThreadStatus {
        let json = waiting.map { #"{"type":"\#(type.rawValue)","activeFlags":["\#($0)"]}"# }
            ?? #"{"type":"\#(type.rawValue)"}"#
        return try! JSONDecoder().decode(CodexThreadStatus.self, from: Data(json.utf8))
    }

    // MARK: - Thread listing

    @Test("a listed thread carries workspace, title, and transcript")
    func loadedThreadCarriesEverything() {
        let observation = CodexAppServerSource().observeLoadedThread(thread())!
        let patch = observation.patch

        #expect(patch.surface == .desktopApp)
        #expect(patch.workspace?.workingDirectory == "/Users/dev/work/island")
        #expect(patch.narrative?.title == "Ship the release")
        #expect(patch.narrative?.initialUserPrompt == "fix the login bug")
        #expect(patch.narrative?.transcriptPath?.hasSuffix("rollout-T1.jsonl") == true)
        #expect(patch.lifecycle?.phase == .running)
        // A desktop thread has no terminal; placement must stay unset so the
        // projector derives the jump from the surface instead.
        #expect(patch.placement == nil)
    }

    @Test("an idle listed thread starts as completed")
    func idleThreadStartsCompleted() {
        let observation = CodexAppServerSource().observeLoadedThread(thread(status: .idle))
        #expect(observation?.patch.lifecycle?.phase == .completed)
    }

    @Test("a listed thread projects to a Codex.app session with a thread jump")
    func loadedThreadProjectsToSession() {
        let pipeline = CodexIngestionPipeline(mode: .live)
        let events = pipeline.ingest(loadedThread: thread())

        guard case let .sessionStarted(started) = events.first else {
            Issue.record("expected sessionStarted, got \(events)")
            return
        }
        #expect(started.title == "Ship the release")
        #expect(started.jumpTarget?.terminalApp == "Codex.app")
        #expect(started.jumpTarget?.codexThreadID == "T1")
        #expect(started.jumpTarget?.workspaceName == "island")
    }

    // MARK: - Internal threads

    @Test("a thread Codex.app spawned for itself never becomes a session")
    func ephemeralThreadIsIgnored() {
        // Codex.app opens an ephemeral thread to generate a conversation
        // title. Surfacing it shows a bogus session and — once its turn
        // finishes — tells the user their agent is done when it is not.
        let source = CodexAppServerSource()
        let internalThread = thread(id: "E1", name: nil, preview: "You are a helpful assistant.", ephemeral: true)

        #expect(source.observeLoadedThread(internalThread) == nil)
        #expect(source.observe(.threadStarted(thread: internalThread)) == nil)
    }

    @Test("later notifications about an internal thread are also ignored")
    func ephemeralThreadStaysIgnored() {
        // turn/completed carries only a thread id, so the id has to be
        // remembered or the finishing turn looks like a real session ending.
        let source = CodexAppServerSource()
        _ = source.observe(.threadStarted(thread: thread(id: "E1", ephemeral: true)))

        let turn = try! JSONDecoder().decode(
            CodexTurn.self, from: Data(#"{"id":"t1","status":"completed"}"#.utf8)
        )
        #expect(source.observe(.turnCompleted(threadId: "E1", turn: turn)) == nil)
        #expect(source.observe(.threadStatusChanged(threadId: "E1", status: status(.idle))) == nil)
        // A real thread is unaffected.
        #expect(source.observe(.turnCompleted(threadId: "T1", turn: turn)) != nil)
    }

    // MARK: - Status changes

    @Test("notLoaded produces no observation")
    func notLoadedIsIgnored() {
        let observation = CodexAppServerSource().observe(
            .threadStatusChanged(threadId: "T1", status: status(.notLoaded))
        )
        #expect(observation == nil)
    }

    @Test("idle and systemError end the turn but not the thread")
    func idleAndErrorCompleteTurn() {
        let source = CodexAppServerSource()
        for type in [CodexThreadStatusType.idle, .systemError] {
            let observation = source.observe(.threadStatusChanged(threadId: "T1", status: status(type)))
            #expect(observation?.patch.lifecycle?.phase == .completed, "\(type)")
            #expect(observation?.patch.liveness?.isAlive == true, "\(type) must not end the thread")
        }
    }

    @Test("only thread/closed ends a desktop session")
    func threadClosedEnds() {
        let observation = CodexAppServerSource().observe(.threadClosed(threadId: "T1"))
        #expect(observation?.patch.liveness == CodexLiveness(state: .ended(reason: .threadClosed)))
    }

    // MARK: - Placeholders yield to hooks

    @Test("a waiting-on-approval status raises a placeholder card")
    func waitingStatusRaisesPlaceholder() {
        let observation = CodexAppServerSource().observe(
            .threadStatusChanged(threadId: "T1", status: status(.active, waiting: "waitingOnApproval"))
        )
        guard case let .permission(request) = observation?.patch.actionable else {
            Issue.record("expected a placeholder permission, got \(String(describing: observation?.patch.actionable))")
            return
        }
        #expect(request.toolName == nil, "the app-server does not know the tool")
    }

    @Test("a hook's real request outranks the app-server placeholder")
    func hookOutranksPlaceholder() {
        let store = CodexFacetStore()
        store.enterLiveMode()

        let placeholder = CodexObservation(
            ref: .sessionID("T1"), source: .appServer, seq: 5, observedAt: .now,
            patch: CodexFacetPatch(actionable: .permission(PermissionRequest(
                title: "Approval Required", summary: "waiting", affectedPath: ""
            )))
        )
        let real = CodexObservation(
            ref: .sessionID("T1"), source: .hook, seq: 1, observedAt: .now,
            patch: CodexFacetPatch(actionable: .permission(PermissionRequest(
                title: "Run command", summary: "rm -rf build", affectedPath: "/x",
                primaryActionTitle: "Allow", secondaryActionTitle: "Deny",
                toolName: "shell", toolUseID: "t-1"
            )))
        )

        // Placeholder arrives with a higher sequence; the hook still wins.
        store.apply(placeholder, sessionKey: "T1")
        store.apply(real, sessionKey: "T1")
        guard case let .permission(held) = store.session(for: "T1")?.actionable?.value else {
            Issue.record("no actionable held")
            return
        }
        #expect(held.toolName == "shell")

        // And a later placeholder cannot displace it.
        store.apply(CodexObservation(
            ref: .sessionID("T1"), source: .appServer, seq: 9, observedAt: .now,
            patch: placeholder.patch
        ), sessionKey: "T1")
        guard case let .permission(stillHeld) = store.session(for: "T1")?.actionable?.value else {
            Issue.record("actionable lost")
            return
        }
        #expect(stillHeld.toolName == "shell")
    }
}
