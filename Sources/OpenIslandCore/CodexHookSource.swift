import Foundation

/// Translates Codex hook deliveries into observations.
///
/// Hooks are the strongest contract Codex offers: they are configuration-driven,
/// documented, and invoked synchronously by the agent. They are also the only
/// channel that knows which terminal a session is running in, and — since Codex
/// moved approvals out of the transcript — the only channel that carries
/// permission requests at all.
///
/// What hooks cannot see is a desktop thread closing, which is why they rank
/// below the app-server for liveness in `CodexAuthorityMatrix`.
public final class CodexHookSource: @unchecked Sendable {
    private let lock = NSLock()
    private var nextSeq: UInt64 = 0
    /// Running subagent count per session. Hooks report boundaries, not
    /// totals, and the facet store merges narrative by "latest wins" — so the
    /// source has to keep the tally and emit an absolute number.
    private var activeSubagents: [String: Int] = [:]

    public init() {}

    private func allocateSeq() -> UInt64 {
        lock.lock()
        defer { lock.unlock() }
        nextSeq += 1
        return nextSeq
    }

    private func adjustSubagents(for sessionID: String, by delta: Int) -> Int {
        lock.lock()
        defer { lock.unlock() }
        let next = max(0, (activeSubagents[sessionID] ?? 0) + delta)
        activeSubagents[sessionID] = next
        return next
    }

    private func clearSubagents(for sessionID: String) {
        lock.lock()
        activeSubagents.removeValue(forKey: sessionID)
        lock.unlock()
    }

    /// Convert one hook payload into an observation.
    ///
    /// Every hook carries terminal identity and working directory, so placement
    /// is refreshed on each delivery — a session that moves between panes stays
    /// jumpable. The remaining facets depend on which hook fired.
    public func observe(_ payload: CodexHookPayload, at timestamp: Date = .now) -> CodexObservation {
        var patch = CodexFacetPatch()

        patch.workspace = CodexWorkspace(workingDirectory: payload.cwd)
        patch.placement = CodexPlacement(
            terminalApp: payload.terminalApp,
            terminalSessionID: payload.terminalSessionID,
            terminalTTY: payload.terminalTTY,
            terminalTitle: payload.terminalTitle,
            warpPaneUUID: payload.warpPaneUUID
        )

        switch payload.hookEventName {
        case .sessionStart:
            patch.lifecycle = CodexLifecycle(phase: .running, turnID: payload.turnID)
            patch.liveness = CodexLiveness(state: .alive)
            patch.narrative = CodexNarrative(
                title: payload.sessionTitle,
                transcriptPath: payload.transcriptPath
            )

        case .userPromptSubmit:
            patch.lifecycle = CodexLifecycle(phase: .running, turnID: payload.turnID)
            patch.liveness = CodexLiveness(state: .alive)
            patch.narrative = CodexNarrative(
                lastUserPrompt: payload.prompt,
                transcriptPath: payload.transcriptPath
            )

        case .preToolUse:
            patch.lifecycle = CodexLifecycle(phase: .running, turnID: payload.turnID)
            patch.liveness = CodexLiveness(state: .alive)
            patch.narrative = CodexNarrative(
                currentTool: payload.toolName,
                currentCommandPreview: payload.commandPreview,
                transcriptPath: payload.transcriptPath
            )

        case .permissionRequest:
            patch.lifecycle = CodexLifecycle(phase: .waitingForApproval, turnID: payload.turnID)
            patch.liveness = CodexLiveness(state: .alive)
            patch.actionable = .permission(PermissionRequest(
                title: payload.permissionRequestTitle,
                summary: payload.permissionRequestSummary,
                affectedPath: payload.permissionRequestAffectedPath,
                primaryActionTitle: "Allow",
                secondaryActionTitle: "Deny",
                toolName: payload.toolName,
                toolUseID: payload.toolUseID
            ))
            patch.narrative = CodexNarrative(
                currentTool: payload.toolName,
                currentCommandPreview: payload.commandPreview,
                transcriptPath: payload.transcriptPath
            )

        case .postToolUse:
            // A tool finishing resolves any approval that was pending on it.
            patch.lifecycle = CodexLifecycle(phase: .running, turnID: payload.turnID)
            patch.liveness = CodexLiveness(state: .alive)
            patch.actionable = .cleared
            patch.narrative = CodexNarrative(
                currentTool: payload.toolName,
                currentCommandPreview: payload.commandPreview,
                transcriptPath: payload.transcriptPath
            )

        case .stop:
            patch.lifecycle = CodexLifecycle(phase: .completed, turnID: payload.turnID)
            patch.actionable = .cleared
            patch.narrative = CodexNarrative(
                lastAssistantMessage: payload.lastAssistantMessage ?? payload.assistantMessagePreview,
                transcriptPath: payload.transcriptPath
            )
            // A finished turn is not a finished session — Codex stays resident
            // and may start another. SessionEnd is the signal for that.

        case .sessionEnd:
            // The one hook that means the session is over, as opposed to a
            // turn. Carries a reason (user exit, error, …) for the record.
            patch.lifecycle = CodexLifecycle(phase: .completed, turnID: payload.turnID)
            patch.liveness = CodexLiveness(state: .ended(reason: .sessionEnd))
            patch.actionable = .cleared
            patch.narrative = CodexNarrative(
                lastAssistantMessage: payload.reason.map { "Session ended: \($0)" },
                transcriptPath: payload.transcriptPath,
                activeSubagentCount: 0
            )
            clearSubagents(for: payload.sessionID)

        case .turnStart:
            patch.lifecycle = CodexLifecycle(phase: .running, turnID: payload.turnID)
            patch.liveness = CodexLiveness(state: .alive)
            patch.actionable = .cleared

        case .subagentStart:
            let count = adjustSubagents(for: payload.sessionID, by: 1)
            patch.lifecycle = CodexLifecycle(phase: .running, turnID: payload.turnID)
            patch.liveness = CodexLiveness(state: .alive)
            patch.narrative = CodexNarrative(
                transcriptPath: payload.transcriptPath,
                activeSubagentCount: count
            )

        case .subagentStop:
            let count = adjustSubagents(for: payload.sessionID, by: -1)
            patch.liveness = CodexLiveness(state: .alive)
            patch.narrative = CodexNarrative(
                transcriptPath: payload.transcriptPath,
                activeSubagentCount: count
            )

        case .preCompact:
            patch.lifecycle = CodexLifecycle(phase: .running, turnID: payload.turnID)
            patch.liveness = CodexLiveness(state: .alive)
            patch.narrative = CodexNarrative(
                currentTool: "Compacting context",
                currentCommandPreview: payload.trigger,
                transcriptPath: payload.transcriptPath
            )
        }

        return CodexObservation(
            ref: .sessionID(payload.sessionID),
            source: .hook,
            seq: allocateSeq(),
            observedAt: timestamp,
            patch: patch
        )
    }
}
