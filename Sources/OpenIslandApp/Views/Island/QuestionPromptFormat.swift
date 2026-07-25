import CoreGraphics
import Foundation
import OpenIslandCore

/// Pure presentation logic for the shared `StructuredQuestionPromptView`
/// interior (AB-325 stage 1).
///
/// The question prompt *structure* is a non-restructurable contract shared by
/// every theme (numbered options, multi-select, freeform "Other", submit). The
/// 2.0 redesign layers *semantic* affordances on top of that structure — a
/// progress readout, square-vs-round selection markers, a running submit count,
/// "Other" pinned last with digit remapping, and a keyboard-hint caption. All of
/// those decisions are pure functions of the model plus the active language, so
/// they live here where they can be unit-tested without a running view. Stage 2
/// adopts them inside the view without adapters.
///
/// Nothing here reads global state: the language manager is injected (defaulting
/// to `.shared` for view call sites) so tests can pin each localized string.
enum QuestionPromptFormat {

    // MARK: - Selection marker shape

    /// The selection-marker geometry for a question's options.
    ///
    /// State is never conveyed by color alone (BRIEF accessibility invariant):
    /// multi-select and single-select carry visibly different marker *shapes*,
    /// and each stamps a ✓ / filled tick when selected.
    enum MarkerShape: Equatable, Sendable {
        /// Multi-select: a rounded-rect (square) marker, checked with a ✓ when
        /// selected. Carries the corner radius so the view renders it directly.
        case square(cornerRadius: CGFloat)
        /// Single-select: a circular marker, filled with a tick when selected.
        case circle
    }

    /// Corner radius for the multi-select square marker (~4pt per the ticket).
    static let multiSelectMarkerCornerRadius: CGFloat = 4

    /// The marker shape for a question, decided purely by its `multiSelect` flag.
    static func markerShape(multiSelect: Bool) -> MarkerShape {
        multiSelect
            ? .square(cornerRadius: multiSelectMarkerCornerRadius)
            : .circle
    }

    // MARK: - Option display ordering ("Other" pinned last)

    /// A question option in *display* position, carrying its authored index so
    /// the view (and the keyboard digit handlers) can map a visible position
    /// back to the original option.
    struct DisplayOption: Equatable, Identifiable, Sendable {
        /// The underlying authored option.
        let option: QuestionOption
        /// The option's index in the question's authored `options` array. This
        /// is the display-index → original-option mapping: digit N (1-based)
        /// selects `orderedOptions[N - 1]`, whose `originalIndex` recovers the
        /// authored slot regardless of how the author ordered "Other".
        let originalIndex: Int

        var id: UUID { option.id }
    }

    /// The options re-ordered for display: freeform ("Other") options are pinned
    /// last, regardless of where the author placed them, while every option's
    /// relative order is otherwise preserved (a stable partition).
    ///
    /// So digit N always selects the option the user *sees* numbered N, even when
    /// "Other" was authored in the middle of the list. `originalIndex` on each
    /// returned `DisplayOption` is the mapping back to the authored option.
    static func orderedOptions(_ options: [QuestionOption]) -> [DisplayOption] {
        let indexed = options.enumerated().map { offset, option in
            DisplayOption(option: option, originalIndex: offset)
        }
        // Stable partition: non-freeform first (authored order preserved),
        // freeform ("Other") appended last (authored order preserved).
        let pinnedLast = indexed.filter { $0.option.allowsFreeform }
        let leading = indexed.filter { !$0.option.allowsFreeform }
        return leading + pinnedLast
    }

    // MARK: - Keyboard hint caption

    /// The largest option digit the overlay keyboard monitor maps (1…9); options
    /// beyond the ninth are mouse-only, so the hint never advertises them.
    static let maxKeyboardDigit = 9

    /// The keyboard-hint caption, e.g. `1–3 select · Enter submits · Esc closes`.
    ///
    /// Rendered only for *single*-question prompts — those are the only prompts
    /// whose digits/Enter are registered with `OverlayUICoordinator`; a
    /// multi-question prompt is mouse-driven and returns `nil` (no caption).
    ///
    /// The digit range's upper bound is the option count, capped at
    /// `maxKeyboardDigit` (only 1…9 are keyboard-selectable). A single option
    /// renders just `1` rather than a range; a question with no options returns
    /// `nil` (there is nothing to number).
    static func keyboardHint(
        optionCount: Int,
        questionCount: Int,
        lang: LanguageManager = .shared
    ) -> String? {
        guard questionCount == 1, optionCount > 0 else {
            return nil
        }

        let highest = min(optionCount, maxKeyboardDigit)
        if highest <= 1 {
            return lang.t("question.hint.keyboard.single")
        }
        return lang.t("question.hint.keyboard.range", highest)
    }

    // MARK: - Submit label (multi-select running count)

    /// The submit-button label for a multi-select question, carrying the running
    /// selection count, e.g. `Submit — 2 selected`.
    ///
    /// Single-select prompts keep their existing submit-label semantics (send
    /// reply / send answer / submit) and don't call this.
    static func multiSelectSubmitLabel(
        selectedCount: Int,
        lang: LanguageManager = .shared
    ) -> String {
        lang.t("question.submit.multiSelect", selectedCount)
    }

    // MARK: - Progress readout

    /// The `Question N of M` progress readout, or `nil` when there is a single
    /// question (M ≤ 1) and progress would be noise.
    ///
    /// `questionIndex` is 0-based (matching `Array.enumerated()`); the readout
    /// renders it 1-based.
    static func progressReadout(
        questionIndex: Int,
        questionCount: Int,
        lang: LanguageManager = .shared
    ) -> String? {
        guard questionCount > 1 else {
            return nil
        }
        return lang.t("question.progress", questionIndex + 1, questionCount)
    }
}
