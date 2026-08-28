import Foundation
import Testing
@testable import OpenIslandCore

@Suite("Codex identity and surface classification")
struct CodexIdentityResolverTests {
    // MARK: - Desktop naming

    @Test("both desktop originator spellings classify as Codex.app")
    func bothDesktopSpellingsRecognized() {
        // Codex renamed the desktop client, and a single machine keeps
        // transcripts from before and after the rename indefinitely. Honouring
        // only the current spelling would orphan half a user's history.
        #expect(CodexIdentityResolver.surface(
            originator: "Codex Desktop", source: .named("vscode")
        ) == .desktopApp)
        #expect(CodexIdentityResolver.surface(
            originator: "codex_work_desktop", source: .named("vscode")
        ) == .desktopApp)
    }

    @Test("the CLI and exec originators are distinguished from the desktop app")
    func cliAndExecClassified() {
        #expect(CodexIdentityResolver.surface(originator: "codex-tui", source: .named("cli")) == .cli)
        #expect(CodexIdentityResolver.surface(originator: "codex_exec", source: .named("exec")) == .exec)
    }

    @Test("internal daemons are classified and kept out of the session list")
    func internalDaemonHidden() {
        let surface = CodexIdentityResolver.surface(originator: "slock-daemon", source: .unknown)
        #expect(surface == .internalDaemon)
        #expect(!surface.isUserVisible)
    }

    @Test("an unrecognized originator is reported rather than guessed at")
    func unknownOriginatorReported() {
        let diagnostics = CodexDiagnostics()
        let surface = CodexIdentityResolver.surface(
            originator: "codex_something_new",
            source: .unknown,
            diagnostics: diagnostics
        )

        #expect(surface == .unknown(originator: "codex_something_new"))
        // Unknown still shows: better a plain session than a missing one.
        #expect(surface.isUserVisible)
        #expect(diagnostics.snapshot().unknownOriginators["codex_something_new"] == 1)
    }

    // MARK: - Subagent detection

    @Test("spawned subagent threads are never user-visible")
    func spawnedSubagentHidden() {
        let surface = CodexIdentityResolver.surface(
            originator: "Codex Desktop",
            source: .subagent(parentThreadID: "parent-1", kind: "thread_spawn")
        )
        #expect(surface.isSubagent)
        #expect(!surface.isUserVisible)
    }

    @Test("a guardian thread is treated as a subagent, not a session")
    func guardianHidden() {
        let surface = CodexIdentityResolver.surface(
            originator: "Codex Desktop",
            source: .subagent(parentThreadID: nil, kind: "guardian")
        )
        #expect(!surface.isUserVisible)
    }

    @Test("subagent detection wins over the originator")
    func subagentOverridesOriginator() {
        // Even a desktop-spawned worker must stay out of the list.
        let surface = CodexIdentityResolver.surface(
            originator: "codex_work_desktop",
            source: .subagent(parentThreadID: "p", kind: "thread_spawn")
        )
        #expect(!surface.isDesktopApp)
        #expect(surface.isSubagent)
    }

    // MARK: - Polymorphic source field

    @Test("the source field decodes from both a string and an object")
    func polymorphicSourceDecodes() {
        // Decoding this as String threw on the object form and took the whole
        // record down with it — roughly a fifth of real transcripts.
        #expect(CodexMetaSource(json: "cli") == .named("cli"))
        #expect(CodexMetaSource(json: "vscode") == .named("vscode"))

        let spawn: [String: Any] = ["subagent": ["thread_spawn": ["parent_thread_id": "p-9"]]]
        #expect(CodexMetaSource(json: spawn) == .subagent(parentThreadID: "p-9", kind: "thread_spawn"))

        let guardian: [String: Any] = ["subagent": ["other": "guardian"]]
        #expect(CodexMetaSource(json: guardian) == .subagent(parentThreadID: nil, kind: "guardian"))
    }

    @Test("an unrecognized source shape does not crash decoding")
    func unknownSourceShapeTolerated() {
        #expect(CodexMetaSource(json: ["something": "else"]) == .unknown)
        #expect(CodexMetaSource(json: 42) == .unknown)
        #expect(CodexMetaSource(json: nil) == .unknown)
    }

    // MARK: - Session keys

    @Test("a rollout filename yields its session id")
    func sessionIDFromFilename() {
        let name = "rollout-2026-08-24T17-02-16-01a03301-945c-7c11-b002-cf280fbc4a26.jsonl"
        #expect(CodexIdentityResolver.sessionID(fromRolloutFilename: name)
            == "01a03301-945c-7c11-b002-cf280fbc4a26")
    }

    @Test("a filename that is not a rollout yields nothing")
    func nonRolloutFilenameRejected() {
        #expect(CodexIdentityResolver.sessionID(fromRolloutFilename: "notes.jsonl") == nil)
        #expect(CodexIdentityResolver.sessionID(fromRolloutFilename: "rollout-broken.jsonl") == nil)
    }

    @Test("thread and session references map to the same key space")
    func referencesResolve() {
        #expect(CodexIdentityResolver.sessionKey(for: .threadID("abc")) == "abc")
        #expect(CodexIdentityResolver.sessionKey(for: .sessionID("abc")) == "abc")
        #expect(CodexIdentityResolver.sessionKey(for: .sessionID("")) == nil)
        // A pid alone never identifies a session.
        #expect(CodexIdentityResolver.sessionKey(for: .processID(123)) == nil)
    }
}
