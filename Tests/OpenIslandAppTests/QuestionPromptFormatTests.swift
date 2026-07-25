import Foundation
import Testing
@testable import OpenIslandApp
import OpenIslandCore

/// AB-325 stage 1 — the pure `QuestionPromptFormat` presentation logic for the
/// shared `StructuredQuestionPromptView` interior: marker shape, "Other"-last
/// display ordering with digit remapping, the single-question keyboard hint, the
/// multi-select running submit label, and the `Question N of M` progress readout.
///
/// The suite is `.serialized` and snapshots `appLanguage` because the localized
/// assertions pin a `LanguageManager` to a concrete language (whose `didSet`
/// writes `UserDefaults.standard`), mirroring `AnnualThemeTests`.
@Suite(.serialized)
final class QuestionPromptFormatTests {
    private let savedLanguage: String?

    init() {
        savedLanguage = UserDefaults.standard.string(forKey: "appLanguage")
    }

    deinit {
        if let savedLanguage {
            UserDefaults.standard.set(savedLanguage, forKey: "appLanguage")
        } else {
            UserDefaults.standard.removeObject(forKey: "appLanguage")
        }
    }

    private func manager(_ language: LanguageManager.AppLanguage) -> LanguageManager {
        let manager = LanguageManager()
        manager.language = language
        return manager
    }

    // MARK: - Marker shape

    @Test
    func multiSelectMarkerIsSquareWithTicketRadius() {
        #expect(QuestionPromptFormat.markerShape(multiSelect: true) == .square(cornerRadius: 4))
        #expect(QuestionPromptFormat.multiSelectMarkerCornerRadius == 4)
    }

    @Test
    func singleSelectMarkerIsCircle() {
        #expect(QuestionPromptFormat.markerShape(multiSelect: false) == .circle)
    }

    // MARK: - Option ordering ("Other" pinned last)

    @Test
    func freeformOtherAuthoredMidListMovesLastAndRemapsDigits() {
        // "Other" authored in the MIDDLE (authored index 1) must render last, and
        // digit N must still select the option the user sees numbered N.
        let options = [
            QuestionOption(label: "A"),
            QuestionOption(label: "Other", allowsFreeform: true),
            QuestionOption(label: "B"),
            QuestionOption(label: "C"),
        ]

        let ordered = QuestionPromptFormat.orderedOptions(options)

        #expect(ordered.map(\.option.label) == ["A", "B", "C", "Other"])
        // Display-index → original-option mapping survives the reorder.
        #expect(ordered.map(\.originalIndex) == [0, 2, 3, 1])
        // Digit 2 (display index 1) selects "B", not the authored-2nd "Other".
        #expect(ordered[1].option.label == "B")
        #expect(ordered[1].originalIndex == 2)
    }

    @Test
    func freeformAlreadyLastIsStable() {
        let options = [
            QuestionOption(label: "A"),
            QuestionOption(label: "B"),
            QuestionOption(label: "Other", allowsFreeform: true),
        ]

        let ordered = QuestionPromptFormat.orderedOptions(options)

        #expect(ordered.map(\.option.label) == ["A", "B", "Other"])
        #expect(ordered.map(\.originalIndex) == [0, 1, 2])
    }

    @Test
    func noFreeformPreservesAuthoredOrder() {
        let options = [
            QuestionOption(label: "A"),
            QuestionOption(label: "B"),
            QuestionOption(label: "C"),
        ]

        let ordered = QuestionPromptFormat.orderedOptions(options)

        #expect(ordered.map(\.option.label) == ["A", "B", "C"])
        #expect(ordered.map(\.originalIndex) == [0, 1, 2])
    }

    @Test
    func multipleFreeformOptionsKeepRelativeOrderAtEnd() {
        let options = [
            QuestionOption(label: "Other1", allowsFreeform: true),
            QuestionOption(label: "A"),
            QuestionOption(label: "Other2", allowsFreeform: true),
        ]

        let ordered = QuestionPromptFormat.orderedOptions(options)

        #expect(ordered.map(\.option.label) == ["A", "Other1", "Other2"])
        #expect(ordered.map(\.originalIndex) == [1, 0, 2])
    }

    @Test
    func emptyOptionsReturnEmpty() {
        #expect(QuestionPromptFormat.orderedOptions([]).isEmpty)
    }

    // MARK: - Keyboard hint caption

    @Test
    func hintForSingleQuestionRendersCappedRange() {
        let en = manager(.en)
        #expect(
            QuestionPromptFormat.keyboardHint(optionCount: 3, questionCount: 1, lang: en)
                == "1–3 select · Enter submits · Esc closes"
        )
    }

    @Test
    func hintForSingleOptionRendersJustOne() {
        let en = manager(.en)
        #expect(
            QuestionPromptFormat.keyboardHint(optionCount: 1, questionCount: 1, lang: en)
                == "1 select · Enter submits · Esc closes"
        )
    }

    @Test
    func hintCapsDigitRangeAtNine() {
        let en = manager(.en)
        // Only 1…9 are keyboard-selectable, so 12 options still reads "1–9".
        #expect(
            QuestionPromptFormat.keyboardHint(optionCount: 12, questionCount: 1, lang: en)
                == "1–9 select · Enter submits · Esc closes"
        )
    }

    @Test
    func hintIsNilForMultiQuestionPrompt() {
        let en = manager(.en)
        #expect(QuestionPromptFormat.keyboardHint(optionCount: 3, questionCount: 2, lang: en) == nil)
    }

    @Test
    func hintIsNilWhenNoOptions() {
        let en = manager(.en)
        #expect(QuestionPromptFormat.keyboardHint(optionCount: 0, questionCount: 1, lang: en) == nil)
    }

    // MARK: - Multi-select submit label (running count)

    @Test
    func multiSelectSubmitLabelReflectsCount() {
        let en = manager(.en)
        #expect(QuestionPromptFormat.multiSelectSubmitLabel(selectedCount: 0, lang: en) == "Submit — 0 selected")
        #expect(QuestionPromptFormat.multiSelectSubmitLabel(selectedCount: 1, lang: en) == "Submit — 1 selected")
        #expect(QuestionPromptFormat.multiSelectSubmitLabel(selectedCount: 3, lang: en) == "Submit — 3 selected")
    }

    // MARK: - Progress readout

    @Test
    func progressIsNilForSingleQuestion() {
        let en = manager(.en)
        #expect(QuestionPromptFormat.progressReadout(questionIndex: 0, questionCount: 1, lang: en) == nil)
    }

    @Test
    func progressRendersOneBasedForMultiQuestion() {
        let en = manager(.en)
        #expect(
            QuestionPromptFormat.progressReadout(questionIndex: 0, questionCount: 2, lang: en)
                == "Question 1 of 2"
        )
        #expect(
            QuestionPromptFormat.progressReadout(questionIndex: 1, questionCount: 3, lang: en)
                == "Question 2 of 3"
        )
    }

    // MARK: - Localization coverage (every new key resolves in all 3 languages)

    /// Every AB-325 string resolves to a real translation — not the bare key — in
    /// English and both Chinese scripts (the `AnnualThemeTests` pattern).
    @Test
    func allNewKeysLocalizeInEveryLanguage() {
        let keys = [
            "question.progress",
            "question.hint.keyboard.single",
            "question.hint.keyboard.range",
            "question.submit.multiSelect",
        ]

        for language in [LanguageManager.AppLanguage.en, .zhHans, .zhHant] {
            let manager = manager(language)
            for key in keys {
                let resolved = manager.t(key)
                #expect(resolved != key, "\(key) is unlocalized in \(language)")
                #expect(!resolved.isEmpty)
            }
        }
    }
}
