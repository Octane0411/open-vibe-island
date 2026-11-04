import Foundation
import Testing
@testable import OpenIslandCore

struct StructuredQuestionContractTests {
    @Test
    func legacyQuestionAndAnswerPayloadsStillDecodeWithoutNativeFields() throws {
        let question = Data("{\"question\":\"Pick a database\",\"header\":\"Database\",\"options\":[],\"multiSelect\":false}".utf8)
        let decoded = try JSONDecoder().decode(QuestionPromptItem.self, from: question)
        #expect(decoded.nativeID == nil)
        #expect(decoded.detail == nil)
        #expect(decoded.responseKey == decoded.question)
        let answer = Data("{\"rawAnswer\":\"Postgres\",\"answers\":{},\"annotations\":{}}".utf8)
        let response = try JSONDecoder().decode(QuestionPromptResponse.self, from: answer)
        #expect(response.rawAnswer == "Postgres")
        #expect(response.structuredAnswers == nil)
    }

    @Test
    func nativeWireRoundTripRetainsDuplicateQuestionIdentitiesAndCommaLabels() throws {
        let questions = ["first", "second"].map {
            QuestionPromptItem(question: "Which option?", header: "Choose", options: [], nativeID: $0, detail: "## Plan\n\nKeep the full review.")
        }
        let prompt = QuestionPrompt(title: "Review", questions: questions)
        let decoded = try JSONDecoder().decode(QuestionPrompt.self, from: JSONEncoder().encode(prompt))
        #expect(decoded.questions.map(\.responseKey) == ["first", "second"])
        #expect(decoded.questions.allSatisfy { $0.detail == questions[0].detail })
        let answers = [
            "first": StructuredQuestionAnswer(selectedOptions: ["Read, then write", "Skip"], customText: "Add a migration"),
            "second": StructuredQuestionAnswer(customText: "Keep planning"),
        ]
        let response = QuestionPromptResponse(structuredAnswers: answers)
        let restored = try JSONDecoder().decode(QuestionPromptResponse.self, from: JSONEncoder().encode(response))
        #expect(restored.structuredAnswers == answers)
    }
}
