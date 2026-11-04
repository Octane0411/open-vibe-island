import Foundation
import Testing
@testable import OpenIslandApp
import OpenIslandCore

@MainActor
struct DSHInteractionUITests {
    @Test
    func nativeFormPreservesExactSelectionsAndRequiresEachAnswer() throws {
        let questions = [
            QuestionPromptItem(question: "Which?", header: "First", options: [
                QuestionOption(label: "Read, then write"),
                QuestionOption(label: "Other response", allowsFreeform: true),
            ], multiSelect: true, nativeID: "first"),
            QuestionPromptItem(question: "Which?", header: "Second", options: [], nativeID: "second"),
        ]
        let selections: [String: Set<String>] = ["first": ["Read, then write", "Other response"]]
        let texts = ["first|Other response": "  Add a migration  ", "second": "使用本地数据"]
        let result = try #require(NativeQuestionAnswerBuilder.response(questions: questions, selections: selections, freeformTexts: texts))
        #expect(result.structuredAnswers?["first"]?.selectedOptions == ["Read, then write"])
        #expect(result.structuredAnswers?["first"]?.customText == "Add a migration")
        #expect(result.structuredAnswers?["second"]?.selectedOptions == [])
        #expect(result.structuredAnswers?["second"]?.customText == texts["second"])
        for invalid in [[:], ["first|Other response": " ", "second": "x"], ["first|Other response": "x"]] {
            #expect(NativeQuestionAnswerBuilder.response(questions: questions, selections: selections, freeformTexts: invalid) == nil)
        }
        #expect(NativeQuestionAnswerBuilder.response(questions: questions, selections: ["first": ["Invented"]], freeformTexts: texts) == nil)
    }

    @Test
    func staleAndDuplicateClicksCannotAnswerNewRequestsOrOptimisticallyClearCards() async throws {
        let calls = InteractionCalls()
        let model = AppModel(
            dshQuestionAction: { session, id, _ in
                await calls.recordQuestion(session, id)
                try await Task.sleep(for: .milliseconds(50))
                throw SimulatedConnectionError.unavailable
            },
            dshPermissionAction: { session, id, resolution in
                await calls.recordPermission(session, id, resolution.isApproved)
            }
        )
        model.state.apply(.sessionStarted(SessionStarted(sessionID: "synthetic", title: "DSH", tool: .dsh, origin: .live, summary: "Working", timestamp: .now, piMetadata: PiSessionMetadata(isSubagent: false))))
        model.selectedSessionID = "synthetic"
        let original = QuestionPrompt(title: "First question", options: ["A"])
        model.state.apply(.questionAsked(QuestionAsked(sessionID: "synthetic", prompt: original, timestamp: .now)))
        model.answerQuestion(for: "synthetic", answer: QuestionPromptResponse(answer: "A"), requestID: original.id)
        model.answerQuestion(for: "synthetic", answer: QuestionPromptResponse(answer: "A"), requestID: original.id)
        #expect(model.state.session(id: "synthetic")?.questionPrompt?.id == original.id)
        #expect(model.state.session(id: "synthetic")?.phase == .waitingForAnswer)
        for _ in 0..<100 {
            if model.respondingDSHRequestIDs.isEmpty { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(await calls.questionIDs == [original.id])
        #expect(model.state.session(id: "synthetic")?.questionPrompt?.id == original.id)
        let current = QuestionPrompt(title: "New question", options: ["B"])
        model.state.apply(.questionAsked(QuestionAsked(sessionID: "synthetic", prompt: current, timestamp: .now)))
        model.answerQuestion(for: "synthetic", answer: QuestionPromptResponse(answer: "A"), requestID: original.id)
        await Task.yield()
        #expect(await calls.questionIDs == [original.id])
        #expect(model.respondingDSHRequestIDs.isEmpty)
        model.answerQuestion(for: "synthetic", answer: QuestionPromptResponse(answer: "B"), requestID: current.id)
        for _ in 0..<100 {
            if model.respondingDSHRequestIDs.isEmpty { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(await calls.questionIDs == [original.id, current.id])
        #expect(model.state.session(id: "synthetic")?.questionPrompt?.id == current.id)
        let permission = PermissionRequest(title: "Synthetic action", summary: "Test only", affectedPath: "")
        model.state.apply(.permissionRequested(PermissionRequested(sessionID: "synthetic", request: permission, timestamp: .now)))
        model.approvePermission(for: "synthetic", action: .allowOnce, requestID: UUID())
        #expect(model.respondingDSHRequestIDs.isEmpty)
        model.approveFocusedPermission(true)
        for _ in 0..<100 {
            if model.respondingDSHRequestIDs.isEmpty { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(await calls.permissionIDs == [permission.id])
        #expect(await calls.approved == [true])
        #expect(model.state.session(id: "synthetic")?.phase == .waitingForApproval)
        #expect(model.state.session(id: "synthetic")?.permissionRequest?.id == permission.id)
    }
}

private enum SimulatedConnectionError: Error { case unavailable }
private actor InteractionCalls {
    var questionIDs: [UUID] = []
    var permissionIDs: [UUID] = []
    var approved: [Bool] = []
    func recordQuestion(_ session: String, _ id: UUID) { questionIDs.append(id) }
    func recordPermission(_ session: String, _ id: UUID, _ allowed: Bool) {
        permissionIDs.append(id)
        approved.append(allowed)
    }
}
