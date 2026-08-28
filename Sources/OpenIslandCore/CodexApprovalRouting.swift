import Foundation

/// Decides whether a Codex permission request needs a human, before anything
/// is shown or held.
///
/// Codex fires the `PermissionRequest` hook regardless of the user's approval
/// mode — it cannot know whether an observer intends to weigh in. The previous
/// implementation treated every request as one to hold and display, so a user
/// running with `bypassPermissions` still saw each action queue up for as long
/// as an hour waiting for a click. That is the failure reported in #559, and
/// #638 states the rule this type enforces: Codex's own approval setting is
/// authoritative; Open Island intervenes only where the user has asked to be
/// asked.
///
/// The `PermissionRequest` output contract allows exactly `allow` and `deny`.
/// There is no "ask" — declining to answer means waiting for the timeout, which
/// is worse for the user than answering. So every mode resolves to one of the
/// three routes below.
public enum CodexApprovalRoute: Equatable, Sendable {
    /// Answer `allow` immediately; show nothing.
    case autoAllow
    /// Answer `deny` immediately with a short reason; show nothing.
    case autoDeny(message: String)
    /// Hold the hook and surface the request for the user to decide.
    case askUser
}

public enum CodexApprovalRouting {
    /// Tool names Codex uses for file edits. `acceptEdits` lets these through
    /// unprompted and asks about everything else.
    static let editToolNames: Set<String> = ["apply_patch"]

    public static func route(
        mode: CodexPermissionMode,
        toolName: String?
    ) -> CodexApprovalRoute {
        switch mode {
        case .bypassPermissions, .dontAsk:
            // The user has opted out of being asked. Honour that, and do not
            // show a card they never wanted to see.
            return .autoAllow

        case .acceptEdits:
            if let toolName, editToolNames.contains(toolName.lowercased()) {
                return .autoAllow
            }
            return .askUser

        case .plan:
            // Plan mode does not execute. Deny rather than hold, so the agent
            // learns immediately instead of stalling on a prompt the user did
            // not expect to see.
            return .autoDeny(message: "Codex is in plan mode; actions are not executed.")

        case .default:
            return .askUser
        }
    }
}
