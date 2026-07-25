import Foundation
import OpenIslandCore

/// Pure grouping/sorting for the opened session list.
///
/// AB-305: lifted out of `AppModel` so the live overlay and the Settings →
/// Appearance preview build their sections through the exact same logic. The
/// overlay feeds it `surfacedSessions` and the live preferences; the preview
/// feeds it fixture sessions and the *editing* profile's preferences, so a
/// preview can never drift from how the real list groups and sorts.
///
/// Every input is passed in (no `AppModel` reference), so the result depends
/// only on its arguments — the same property that lets `AppModelSessionListTests`
/// pin the grouping behaviour through `AppModel.islandSessionSections`.
enum IslandSessionSectioning {

    /// Sorts, then groups, `sessions` into the sections the list renders.
    static func sections(
        for sessions: [AgentSession],
        group: IslandSessionGroup,
        sort: IslandSessionSort,
        completedStaleThreshold: TimeInterval,
        now: Date = .now
    ) -> [IslandSessionSection] {
        let sorted = sortedSessions(sessions, sort: sort)

        switch group {
        case .none:
            return [
                IslandSessionSection(
                    id: "all",
                    title: "island.section.sessions",
                    sessions: sorted
                )
            ]
        case .state:
            return stateSections(
                for: sorted,
                completedStaleThreshold: completedStaleThreshold,
                now: now
            )
        case .agent:
            return AgentTool.allCases.compactMap { tool in
                let list = sorted.filter { $0.tool == tool }
                guard !list.isEmpty else { return nil }
                return IslandSessionSection(id: "agent-\(tool.rawValue)", title: tool.displayName, sessions: list)
            }
        case .project:
            let names = Set(sorted.map(projectGroupName(for:))).sorted {
                $0.localizedStandardCompare($1) == .orderedAscending
            }
            return names.compactMap { name in
                let list = sorted.filter { projectGroupName(for: $0) == name }
                guard !list.isEmpty else { return nil }
                return IslandSessionSection(id: "project-\(name)", title: name, sessions: list)
            }
        }
    }

    static func sortedSessions(
        _ sessions: [AgentSession],
        sort: IslandSessionSort
    ) -> [AgentSession] {
        switch sort {
        case .attention:
            // `surfacedSessions` already arrives in attention order.
            return sessions
        case .lastUpdate:
            return sessions.sorted { lhs, rhs in
                if lhs.islandActivityDate == rhs.islandActivityDate {
                    return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
                }
                return lhs.islandActivityDate > rhs.islandActivityDate
            }
        }
    }

    static func projectGroupName(for session: AgentSession) -> String {
        if let workspace = session.jumpTarget?.workspaceName.trimmingCharacters(in: .whitespacesAndNewlines),
           !workspace.isEmpty {
            return workspace
        }

        let title = session.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return session.tool.displayName }

        let pieces = title.split(separator: "·", maxSplits: 1).map {
            String($0).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return pieces.last?.isEmpty == false ? pieces.last! : title
    }

    private static func stateSections(
        for sessions: [AgentSession],
        completedStaleThreshold: TimeInterval,
        now: Date
    ) -> [IslandSessionSection] {
        let definitions: [(id: String, title: String, include: (AgentSession) -> Bool)] = [
            ("approval", "island.section.needsApproval", { $0.phase == .waitingForApproval }),
            ("answer", "island.section.needsAnswer", { $0.phase == .waitingForAnswer }),
            ("running", "island.section.inProgress", { $0.phase == .running }),
            ("done", "island.section.justDone", { session in
                session.phase == .completed
                    && !session.isStaleCompletedForIsland(at: now, threshold: completedStaleThreshold)
            }),
            ("idle", "island.section.idle", { session in
                session.phase == .completed
                    && session.isStaleCompletedForIsland(at: now, threshold: completedStaleThreshold)
            }),
        ]

        return definitions.compactMap { definition in
            let list = sessions.filter(definition.include)
            guard !list.isEmpty else { return nil }
            return IslandSessionSection(id: "state-\(definition.id)", title: definition.title, sessions: list)
        }
    }
}
