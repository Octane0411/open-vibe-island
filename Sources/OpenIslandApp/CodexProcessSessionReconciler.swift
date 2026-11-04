import Foundation
import OpenIslandCore

/// Keeps terminal discovery independent of Codex's transcript storage format.
enum CodexProcessSessionReconciler {
    private static let syntheticPrefix = "codex-process:"

    struct Result {
        var sessions: [AgentSession]
        var processes: [ActiveProcessSnapshot]
    }

    static func reconcile(
        sessions: [AgentSession],
        processes: [ActiveProcessSnapshot],
        now: Date = .now
    ) -> Result {
        // Rebuild process-only rows on each poll so exited processes disappear
        // and hook-backed sessions replace their placeholders automatically.
        var reconciled = sessions.filter { !isSynthetic($0) }
        let resolved = resolvedProcesses(sessions: reconciled, processes: processes)
        var knownIDs = Set(reconciled.map(\.id))

        for process in resolved where process.tool == .codex {
            guard let sessionID = process.sessionID,
                  knownIDs.insert(sessionID).inserted else { continue }

            let workspace = process.workingDirectory.map {
                WorkspaceNameResolver.workspaceName(for: $0)
            } ?? "Workspace"
            let terminalApp = process.terminalApp ?? "Unknown"
            var session = AgentSession(
                id: sessionID,
                title: "Codex · \(workspace)",
                tool: .codex,
                origin: .live,
                attachmentState: .attached,
                phase: .completed,
                summary: "Codex session detected from \(terminalApp).",
                updatedAt: now,
                jumpTarget: JumpTarget(
                    terminalApp: terminalApp,
                    workspaceName: workspace,
                    paneTitle: "Codex \(workspace)",
                    workingDirectory: process.workingDirectory,
                    terminalTTY: process.terminalTTY,
                    tmuxTarget: process.tmuxTarget,
                    tmuxSocketPath: process.tmuxSocketPath
                )
            )
            session.isProcessAlive = true
            reconciled.append(session)
        }

        return Result(sessions: reconciled, processes: resolved)
    }

    static func resolvedProcesses(
        sessions: [AgentSession],
        processes: [ActiveProcessSnapshot]
    ) -> [ActiveProcessSnapshot] {
        // Explicit conversation IDs always win over terminal heuristics.
        var claimedIDs = Set(processes.filter { $0.tool == .codex }.compactMap(\.sessionID))
        return processes.map { process in
            guard process.tool == .codex, process.sessionID == nil else { return process }
            var resolved = process
            let candidates = sessions.filter { session in
                guard session.tool == .codex, !session.isDemoSession,
                      !session.isCodexAppSession, !isSynthetic(session),
                      !claimedIDs.contains(session.id),
                      let tty = normalizedTTY(process.terminalTTY),
                      normalizedTTY(session.jumpTarget?.terminalTTY) == tty else { return false }
                if let processCWD = process.workingDirectory,
                   let sessionCWD = session.jumpTarget?.workingDirectory {
                    return URL(fileURLWithPath: processCWD).standardizedFileURL
                        == URL(fileURLWithPath: sessionCWD).standardizedFileURL
                }
                return true
            }

            if candidates.count == 1 {
                resolved.sessionID = candidates[0].id
            } else if let identity = process.processID ?? normalizedTTY(process.terminalTTY) {
                // Never guess a conversation from CWD alone: multiple Codex
                // terminals often share a project, and approvals must stay local.
                resolved.sessionID = syntheticPrefix + identity
            }
            if let sessionID = resolved.sessionID { claimedIDs.insert(sessionID) }
            return resolved
        }
    }

    private static func isSynthetic(_ session: AgentSession) -> Bool {
        session.tool == .codex && session.id.hasPrefix(syntheticPrefix)
    }

    private static func normalizedTTY(_ value: String?) -> String? {
        guard let value, !value.isEmpty else { return nil }
        return value.hasPrefix("/dev/") ? value : "/dev/" + value
    }
}
