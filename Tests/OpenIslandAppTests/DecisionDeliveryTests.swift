import Foundation
import Testing
@testable import OpenIslandApp
import OpenIslandCore

@MainActor
struct DecisionDeliveryTests {
    @Test
    func failedAnswerKeepsTheQuestionActionable() async throws {
        let environment = AppModelTestEnvironment()
        let model = environment.makeModel(decisionHandler: { _ in throw BridgeDecisionError.deliveryFailed })
        let prompt = QuestionPrompt(title: "Choose", options: ["A", "B"])
        model.state = SessionState(sessions: [AgentSession(id: "question", title: "Question", tool: .claudeCode,
            phase: .waitingForAnswer, summary: "Choose", updatedAt: .now, questionPrompt: prompt)])
        let task = try #require(model.answerQuestion(for: "question", requestID: prompt.id, answer: .init(answer: "A")))
        await task.value
        #expect(model.state.session(id: "question")?.questionPrompt == prompt)
        guard case .failed = model.decisionDeliveryStates[prompt.id] else { Issue.record("Failure must be visible"); return }
    }

    @Test
    func deliveryFailureKeepsTheRequestActionable() async throws {
        let environment = AppModelTestEnvironment()
        let model = environment.makeModel(decisionHandler: { _ in throw BridgeDecisionError.deliveryFailed })
        let request = PermissionRequest(title: "Approve", summary: "Edit", affectedPath: "/tmp/file")
        model.state = SessionState(sessions: [session(request)])
        let task = try #require(model.approvePermission(for: "one", requestID: request.id, approved: true))
        #expect(model.state.session(id: "one")?.permissionRequest == request)
        #expect(model.decisionDeliveryStates[request.id] == .sending)
        await task.value
        #expect(model.state.session(id: "one")?.permissionRequest == request)
        guard case .failed = model.decisionDeliveryStates[request.id] else { Issue.record("Failure must be visible"); return }
    }

    @Test
    func acknowledgmentCannotClearANewerRequest() async throws {
        let environment = AppModelTestEnvironment()
        let gate = DecisionGate()
        let model = environment.makeModel(decisionHandler: { _ in await gate.wait(); return .accepted })
        let first = PermissionRequest(title: "First", summary: "A", affectedPath: "/tmp/A")
        let second = PermissionRequest(title: "Second", summary: "B", affectedPath: "/tmp/B")
        model.state = SessionState(sessions: [session(first)])
        let task = try #require(model.approvePermission(for: "one", requestID: first.id, approved: true))
        #expect(model.approvePermission(for: "one", requestID: first.id, approved: true) == nil)
        model.state = SessionState(sessions: [session(second)])
        await gate.release()
        await task.value
        #expect(model.state.session(id: "one")?.permissionRequest == second)
        #expect(model.decisionDeliveryStates[first.id] == .acknowledged)
        #expect(model.approvePermission(for: "one", requestID: first.id, approved: true) == nil)
    }

    private func session(_ request: PermissionRequest) -> AgentSession {
        AgentSession(id: "one", title: "One", tool: .codex, phase: .waitingForApproval,
                     summary: "Approve", updatedAt: .now, permissionRequest: request)
    }
}

private actor DecisionGate {
    private var released = false
    private var continuation: CheckedContinuation<Void, Never>?
    func wait() async {
        if released { return }
        await withCheckedContinuation { continuation = $0 }
    }
    func release() { released = true; continuation?.resume(); continuation = nil }
}
