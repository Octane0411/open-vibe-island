import Foundation
import OpenIslandCore

/// Maps visible selection state back to exact native question IDs without
/// parsing display prose or comma-separated labels.
enum NativeQuestionAnswerBuilder {
    static func response(
        questions: [QuestionPromptItem],
        selections: [String: Set<String>],
        freeformTexts: [String: String]
    ) -> QuestionPromptResponse? {
        guard !questions.isEmpty,
              questions.allSatisfy({ $0.nativeID?.isEmpty == false }),
              Set(questions.map(\.responseKey)).count == questions.count else { return nil }
        var exact: [String: StructuredQuestionAnswer] = [:]
        var previews: [String: String] = [:]
        for question in questions {
            let key = question.responseKey
            let selected = selections[key] ?? []
            guard selected.isSubset(of: Set(question.options.map(\.label))) else { return nil }
            var labels: [String] = []
            var custom: String?
            if question.options.isEmpty {
                custom = nonempty(freeformTexts[key])
            } else {
                guard question.multiSelect || selected.count <= 1 else { return nil }
                for option in question.options where selected.contains(option.label) {
                    if option.allowsFreeform {
                        guard custom == nil, let text = nonempty(freeformTexts["\(key)|\(option.label)"]) else { return nil }
                        custom = text
                    } else {
                        labels.append(option.label)
                    }
                }
            }
            guard !labels.isEmpty || custom != nil else { return nil }
            exact[key] = StructuredQuestionAnswer(selectedOptions: labels, customText: custom)
            previews[key] = (labels + (custom.map { [$0] } ?? [])).joined(separator: ", ")
        }
        return QuestionPromptResponse(
            rawAnswer: questions.count == 1 ? previews[questions[0].responseKey] : nil,
            answers: previews,
            structuredAnswers: exact
        )
    }

    private static func nonempty(_ value: String?) -> String? {
        guard let text = value?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
        return text
    }
}
