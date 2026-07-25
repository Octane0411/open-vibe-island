import Foundation
import OpenIslandCore

/// AB-323: list-level duplicate-workspace disambiguation.
///
/// BRIEF §1.4 calls out "three identical `the-automator` rows with no
/// disambiguation" as a defect of the current list. The fix is deliberately
/// *list-level*: a single session can never be ambiguous, so the suffix is
/// computed once per rendered list and handed back per session id.
///
/// Rules (in order):
///
/// 1. Sessions are bucketed by `AgentSession.spotlightDisplayName` — the exact
///    string a row headline leads with. Reusing that one accessor is what stops
///    the collision key and the rendered name from drifting apart.
/// 2. A bucket with a single session gets nothing (`nil`). Unique rows stay
///    clean; this is the reason the old *unconditional* `(branch)` suffix in
///    `spotlightHeadlineText` is gone.
/// 3. Inside a collided bucket, a Claude session whose worktree branch is
///    unique *within that bucket* is labelled with the branch.
/// 4. Everything else in the bucket — non-Claude sessions, Claude sessions with
///    no branch, and Claude sessions whose branch is shared with a sibling
///    (a branch two rows agree on disambiguates nothing) — falls back to a
///    recency phrase derived from `updatedAt`.
///
/// The honesty gate in rule 3 is load-bearing: `worktreeBranch` is only ever
/// persisted for Claude (`ClaudeSessionMetadata`). `CodexHookPayload` *computes*
/// one and throws it away, so surfacing a branch on a Codex row would be
/// inventing data the session does not carry. See SPEC-flight-deck §6.
enum SessionDisambiguation {
    /// Branches shorter than this render verbatim; at or beyond it they are
    /// middle-truncated with the last path segment preserved, because the tail
    /// (`…/bridge-auth`) is what a human actually reads a branch by.
    static let maxVerbatimBranchLength = 24

    /// Maps session id → disambiguator for every session that shares its
    /// display name with at least one sibling. Sessions with a unique display
    /// name are absent from the result (i.e. their disambiguator is `nil`).
    static func disambiguators(
        for sessions: [AgentSession],
        now: Date = .now
    ) -> [String: String] {
        guard sessions.count > 1 else { return [:] }

        var buckets: [String: [AgentSession]] = [:]
        for session in sessions {
            buckets[session.spotlightDisplayName, default: []].append(session)
        }

        var result: [String: String] = [:]
        for (_, collided) in buckets where collided.count > 1 {
            // A branch only disambiguates if no sibling in the bucket claims
            // the same one; otherwise both rows fall back to recency.
            var branchOccurrences: [String: Int] = [:]
            for session in collided {
                if let branch = branch(for: session) {
                    branchOccurrences[branch, default: 0] += 1
                }
            }

            for session in collided {
                if let branch = branch(for: session), branchOccurrences[branch] == 1 {
                    result[session.id] = displayBranch(branch)
                } else {
                    result[session.id] = recencyPhrase(for: session, now: now)
                }
            }
        }

        return result
    }

    /// The disambiguator for one session inside a known list, or `nil` when its
    /// display name is unique. Convenience over ``disambiguators(for:now:)`` for
    /// callers holding a single session.
    static func disambiguator(
        for session: AgentSession,
        in sessions: [AgentSession],
        now: Date = .now
    ) -> String? {
        disambiguators(for: sessions, now: now)[session.id]
    }

    /// Honesty gate: a worktree branch is only real for Claude sessions.
    static func branch(for session: AgentSession) -> String? {
        guard session.tool == .claudeCode else { return nil }

        guard let branch = session.claudeMetadata?.worktreeBranch?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !branch.isEmpty else {
            return nil
        }

        return branch
    }

    static func displayBranch(_ branch: String) -> String {
        guard branch.count >= maxVerbatimBranchLength else { return branch }

        // `middleTruncated` only cuts past `maxLength`, so the limit is one
        // below the verbatim ceiling to make "≥ 24 chars truncates" exact.
        return ActivityNarrator.middleTruncated(
            branch,
            maxLength: maxVerbatimBranchLength - 1
        )
    }

    /// Recency phrase built on the list's existing age vocabulary
    /// (`spotlightAgeBadge`: `<1m` / `12m` / `2h` / `3d`) so a disambiguator and
    /// the row's own age badge can never disagree about how old a session is.
    static func recencyPhrase(for session: AgentSession, now: Date) -> String {
        "\(session.spotlightAgeBadge(at: now)) ago"
    }
}
