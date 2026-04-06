import Foundation
import Testing
@testable import OpenIslandApp
import OpenIslandCore

struct IslandSurfaceTests {
    @Test
    func permissionEventsRouteToActionableSurface() {
        let event = AgentEvent.permissionRequested(
            PermissionRequested(
                sessionID: "session-1",
                request: PermissionRequest(
                    title: "Approve command",
                    summary: "Allow exec_command to modify files?",
                    affectedPath: "/tmp/project"
                ),
                timestamp: .now
            )
        )

        #expect(IslandSurface.notificationSurface(for: event) == .sessionList(actionableSessionID: "session-1"))
    }

    @Test
    func questionEventsRouteToActionableSurface() {
        let event = AgentEvent.questionAsked(
            QuestionAsked(
                sessionID: "session-2",
                prompt: QuestionPrompt(
                    title: "Which environment?",
                    options: ["Production", "Staging"]
                ),
                timestamp: .now
            )
        )

        #expect(IslandSurface.notificationSurface(for: event) == .sessionList(actionableSessionID: "session-2"))
    }

    @Test
    func actionableSurfaceMatchesApprovalState() {
        let session = AgentSession(
            id: "session-1",
            title: "Codex · repo",
            tool: .codex,
            attachmentState: .attached,
            phase: .waitingForApproval,
            summary: "Approve command",
            updatedAt: .now,
            permissionRequest: PermissionRequest(
                title: "Approve command",
                summary: "Allow exec_command to modify files?",
                affectedPath: "/tmp/project"
            )
        )

        let surface = IslandSurface.sessionList(actionableSessionID: "session-1")
        #expect(surface.matchesCurrentState(of: session))
    }

    @Test
    func actionableSurfaceMatchesRunningState() {
        let session = AgentSession(
            id: "session-1",
            title: "Codex · repo",
            tool: .codex,
            attachmentState: .attached,
            phase: .running,
            summary: "Working...",
            updatedAt: .now
        )

        let surface = IslandSurface.sessionList(actionableSessionID: "session-1")
        #expect(surface.matchesCurrentState(of: session))
    }

    @Test
    func completionEventsRouteToActionableSurface() {
        let event = AgentEvent.sessionCompleted(
            SessionCompleted(
                sessionID: "session-3",
                summary: "Finished task",
                timestamp: .now
            )
        )

        #expect(IslandSurface.notificationSurface(for: event) == .sessionList(actionableSessionID: "session-3"))
    }

    @Test
    func interruptedCompletionEventsDoNotRouteToSurface() {
        let event = AgentEvent.sessionCompleted(
            SessionCompleted(
                sessionID: "session-3",
                summary: "Codex turn was interrupted.",
                timestamp: .now,
                isInterrupt: true
            )
        )

        #expect(IslandSurface.notificationSurface(for: event) == nil)
    }

    @Test
    func autoDismissOnlyForCompletedSessions() {
        let approvalSession = AgentSession(
            id: "session-1",
            title: "Test",
            tool: .codex,
            attachmentState: .attached,
            phase: .waitingForApproval,
            summary: "Approve",
            updatedAt: .now,
            permissionRequest: PermissionRequest(title: "T", summary: "S", affectedPath: "/tmp")
        )
        let completedSession = AgentSession(
            id: "session-3",
            title: "Test",
            tool: .codex,
            attachmentState: .attached,
            phase: .completed,
            summary: "Done",
            updatedAt: .now
        )

        let surface = IslandSurface.sessionList(actionableSessionID: "session-1")
        #expect(!surface.autoDismissesWhenPresentedAsNotification(session: approvalSession))
        #expect(surface.autoDismissesWhenPresentedAsNotification(session: completedSession))
    }
}
