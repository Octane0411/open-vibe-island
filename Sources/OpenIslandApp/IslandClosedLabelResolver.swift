import Foundation
import OpenIslandCore

// MARK: - Tunable timings

/// Timings the closed pill's *vocabulary* depends on — distinct from the
/// per-theme animation curves, which live in the theme token files (AB-322).
enum IslandClosedPillTiming {

    /// How long a finished session keeps saying `Done · <workspace>` /
    /// `Interrupted · <workspace>` / `Failed · <workspace>` in the closed
    /// pill's label, measured from `session.updatedAt`. After the window the
    /// label falls back to the ordinary preference rendering.
    ///
    /// **Spec correction / tunable.** The specs only pin the *animation*
    /// settle: Flight Deck success settle `3s` (SPEC-flight-deck §K/A5), Halo
    /// success bloom `3s` and question pulse `2.6s` (SPEC-halo §6.5). None of
    /// them says how long the *word* stays. Matching the animation exactly
    /// would make the outcome word vanish on the same frame the glow finishes,
    /// which reads as a flicker rather than a settle, so the label deliberately
    /// outlives the motion at **6s**.
    ///
    /// Shared on purpose: the closed-pill label (AB-322 Part A) and the
    /// closed-pill right slot (AB-322 Part B) must appear and expire together,
    /// so both read this one constant instead of re-deriving a window.
    static let outcomeLabelWindow: TimeInterval = 6
}

// MARK: - Label resolution

/// Pure derivation of the closed island's text-lane label (AB-322).
///
/// Lifted out of `AppModel` for the same reason `IslandSessionSectioning` was:
/// every input is an argument, so the result depends only on its arguments and
/// tests can pin exact strings without standing up an overlay or reading the
/// wall clock. `AppModel.islandClosedLabel(at:)` is a thin adapter over this.
///
/// ## Preference mapping
///
/// The user-facing `IslandCenterLabel` preference is unchanged — this ticket
/// adds vocabulary, not settings:
///
/// - `.off` — no label. Untouched.
/// - `.sessionName` — workspace / title / agent name. Untouched.
/// - `.agentAction` — **extended here.** Previously always `Tool · action`
///   (e.g. `Claude · Edit`); it now speaks the narrated activity from AB-321
///   and the attention/outcome vocabulary from the redesign specs
///   (`Editing AppModel.swift`, `Refactoring · 3 agents`, `3 working`,
///   `Approve swift build?`, `Answer needed`, `Done · the-automator`). The old
///   `Tool · action` form survives as the fallback for every case the new
///   vocabulary cannot describe (no narration, completed past the settle
///   window), so nothing regresses to an empty pill.
enum IslandClosedLabelResolver {

    /// The closed pill's text-lane label, or `nil` when the pill shows none.
    ///
    /// - Parameters:
    ///   - spotlight: the session driving the pill — `AppModel`'s
    ///     `islandClosedSpotlight` (attention → running → first).
    ///   - runningCount: how many surfaced sessions are `.running` right now.
    ///     Drives the aggregate `N working` form.
    ///   - preference: the resolved `IslandCenterLabel` for the active display
    ///     profile.
    ///   - language: the language used for the fixed words. Workspace names,
    ///     commands and file names are data and are never translated.
    ///   - now: reference date for the outcome settle window. Injected so
    ///     tests never race the wall clock.
    static func label(
        spotlight: AgentSession?,
        runningCount: Int,
        preference: IslandCenterLabel,
        language: LanguageManager,
        now: Date = .now
    ) -> String? {
        guard preference != .off, let session = spotlight else { return nil }

        switch preference {
        case .off:
            return nil
        case .sessionName:
            return sessionNameLabel(for: session)
        case .agentAction:
            return agentActionLabel(
                for: session,
                runningCount: runningCount,
                language: language,
                now: now
            )
        }
    }

    // MARK: `.sessionName` (unchanged behaviour)

    static func sessionNameLabel(for session: AgentSession) -> String {
        let workspace = session.jumpTarget?.workspaceName ?? ""
        if !workspace.isEmpty { return workspace }
        return session.title.isEmpty ? session.tool.displayName : session.title
    }

    // MARK: `.agentAction` (narrated + attention + outcome vocabulary)

    static func agentActionLabel(
        for session: AgentSession,
        runningCount: Int,
        language: LanguageManager,
        now: Date
    ) -> String {
        switch session.phase {
        case .waitingForApproval:
            return approvalLabel(for: session, language: language)

        case .waitingForAnswer:
            return language.t("island.closed.label.answerNeeded")

        case .running:
            return runningLabel(
                for: session,
                runningCount: runningCount,
                language: language
            )

        case .completed:
            if let outcome = outcomeLabel(for: session, language: language, now: now) {
                return outcome
            }
            return legacyToolActionLabel(for: session)
        }
    }

    /// `Approve swift build?` — the first two words of the command awaiting
    /// approval. Falls back to `Approval needed` when the request carries no
    /// usable command preview (file edits, MCP calls, transcript-recovered
    /// sessions).
    static func approvalLabel(for session: AgentSession, language: LanguageManager) -> String {
        guard let command = permissionCommandPreview(for: session) else {
            return language.t("island.closed.label.approvalNeeded")
        }
        return language.t("island.closed.label.approve", commandHead(of: command))
    }

    /// The command text behind a pending approval, in the same precedence the
    /// notification card already uses: the live tool-input preview first, then
    /// the request's `affectedPath` — which is where Codex puts the literal
    /// command text (its `summary` is boilerplate prose). The `affectedPath`
    /// fallback only applies when the value reads like a command rather than a
    /// file path, so an Edit approval never narrates `Approve /Users/a?`.
    static func permissionCommandPreview(for session: AgentSession) -> String? {
        if let preview = ActivityNarrator.sanitizedPreview(session.currentCommandPreviewText) {
            return preview
        }

        if let affected = ActivityNarrator.sanitizedPreview(session.permissionRequest?.affectedPath),
           looksLikeCommand(affected) {
            return affected
        }

        return nil
    }

    /// A path is not a command: anything whose leading token is absolute,
    /// home-relative, or contains a separator is treated as a file reference.
    static func looksLikeCommand(_ value: String) -> Bool {
        guard let first = value.split(separator: " ").first else { return false }
        return !first.hasPrefix("~") && !first.contains("/")
    }

    /// First two words of a command — `swift build -c release` → `swift build`,
    /// `swift` → `swift`. A leading flag is not a command word, so `ls -la`
    /// narrates as `ls` rather than the noisier `ls -la`.
    static func commandHead(of command: String) -> String {
        let words = command.split(separator: " ").map(String.init)
        guard let first = words.first else { return command }
        guard words.count > 1 else { return first }

        let second = words[1]
        if second.hasPrefix("-") { return first }
        return "\(first) \(second)"
    }

    /// `3 working` when several sessions run at once (the aggregate is the
    /// honest reading of a pill that can only show one line), otherwise the
    /// spotlight session's own narration — suffixed with `· N agents` when it
    /// is fanning work out to subagents.
    static func runningLabel(
        for session: AgentSession,
        runningCount: Int,
        language: LanguageManager
    ) -> String {
        if runningCount > 1 {
            return language.t("island.closed.label.working", runningCount)
        }

        let subagentCount = session.claudeMetadata?.activeSubagents.count ?? 0
        if subagentCount > 0 {
            let verb = (session.narratedActivity ?? NarratedActivity(.working)).localizedVerb(language)
            return "\(verb) · \(language.t("island.closed.label.agents", subagentCount))"
        }

        if let narrated = session.narratedActivity?.localizedText(language) {
            return narrated
        }

        return legacyToolActionLabel(for: session)
    }

    /// `Done · the-automator` / `Interrupted · niche-radar` /
    /// `Failed · open-vibe-island` — but only inside
    /// ``IslandClosedPillTiming/outcomeLabelWindow`` of the session's last
    /// update. `nil` afterwards, so the caller falls back to the ordinary
    /// preference rendering instead of leaving a stale verdict on the pill.
    static func outcomeLabel(
        for session: AgentSession,
        language: LanguageManager,
        now: Date,
        window: TimeInterval = IslandClosedPillTiming.outcomeLabelWindow
    ) -> String? {
        guard session.phase == .completed else { return nil }

        let age = now.timeIntervalSince(session.updatedAt)
        guard age >= 0, age < window else { return nil }

        let word: String
        switch session.outcome {
        case .success:
            word = language.t("island.closed.label.done")
        case .interrupted:
            word = language.t("island.closed.label.interrupted")
        case .failed:
            word = language.t("island.closed.label.failed")
        }

        let workspace = session.spotlightWorkspaceName
        return workspace.isEmpty ? word : "\(word) · \(workspace)"
    }

    /// The pre-AB-322 `.agentAction` rendering, kept as the universal fallback.
    static func legacyToolActionLabel(for session: AgentSession) -> String {
        if let action = session.displayCurrentToolName, !action.isEmpty {
            return "\(session.tool.displayName) · \(action)"
        }
        return session.tool.displayName
    }
}
