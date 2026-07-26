import Foundation
import OpenIslandCore

/// The Poured 2.0 closed pill's ambient state — one of the six frames in
/// `SPEC-poured-island` §4A / mockup §A (`A1…A6`).
///
/// `UnifiedBars.Mode` (`.idle` / `.running` / `.waiting`) is not enough to pick
/// a frame: `.idle` is shared by a truly-idle pill and a just-completed one, and
/// `.waiting` is shared by a permission and a question. `resolve` folds the
/// mode together with the spotlight's phase/outcome (threaded through
/// `\.islandClosedPillActivity`) and the right-slot shape into the exact frame,
/// as a pure function so `PouredPillMotionTests` can pin every mapping without
/// standing up an overlay or reading the wall clock.
enum PouredPillAmbientState: Equatable {
    /// A1 — still glyph, dim idle dot, no glow, no breathing.
    case idle
    /// A2 / A2′ — `lumen` breathing; running glyph. `manyWorking` is `true` when
    /// the right slot is the agents grid (A2′), which restyles the tiles; the
    /// body glow is identical either way.
    case working(manyWorking: Bool)
    /// A3 — the loudest state: amber `attnpulse` bleeding outside the silhouette.
    case permission
    /// A4 — static gold halo + breathing gold glyph, distinct from A3 by hue.
    case question
    /// A5 / A6 — a freshly completed spotlight: `.success` plays the one-shot
    /// settle (A5); `.interrupted` / `.failed` rest as a coloured dot + outcome
    /// glyph with no glow (A6).
    case completed(SessionOutcome)

    /// Picks the ambient frame from everything the pill knows.
    ///
    /// - Parameters:
    ///   - activity: the spotlight session's phase/outcome, or `nil` when there
    ///     is no spotlight (resolves to `.idle`).
    ///   - mode: the closed pill's `UnifiedBars` mode — the fallback signal when
    ///     no `activity` is threaded (e.g. a preview that sets only the mode).
    ///   - rightSlot: the resolved right-slot payload; an `.agents` grid promotes
    ///     a running state to `working(manyWorking: true)`.
    static func resolve(
        activity: IslandClosedPillActivity?,
        mode: UnifiedBars.Mode,
        rightSlot: IslandRightSlotContent?
    ) -> PouredPillAmbientState {
        guard let activity else {
            // No spotlight threaded: fall back to the glyph mode alone. `.waiting`
            // without an activity can't be split into permission/question, so it
            // takes the calmer question frame (gold, not the loud amber) — never
            // shout attention the pill can't substantiate.
            switch mode {
            case .running: return .working(manyWorking: isAgentsGrid(rightSlot))
            case .waiting: return .question
            case .idle:    return .idle
            }
        }

        switch activity.phase {
        case .waitingForApproval:
            return .permission
        case .waitingForAnswer:
            return .question
        case .running:
            return .working(manyWorking: isAgentsGrid(rightSlot))
        case .completed:
            // A just-completed spotlight only wears its verdict inside the settle
            // window; afterwards it is just another quiet session, so the pill
            // returns to idle rather than pinning a permanent badge (§A5).
            return activity.isOutcomeFresh ? .completed(activity.outcome) : .idle
        }
    }

    /// Whether the right slot is the multi-agent grid (A2′).
    private static func isAgentsGrid(_ rightSlot: IslandRightSlotContent?) -> Bool {
        if case .agents = rightSlot { return true }
        return false
    }

    /// Whether this state paints a glow that bleeds outside the pill silhouette.
    /// Idle and the A6 outcomes (interrupted / failed) deliberately cast none.
    var castsGlow: Bool {
        switch self {
        case .idle:
            return false
        case .working, .permission, .question:
            return true
        case .completed(let outcome):
            return outcome == .success
        }
    }
}

// MARK: - Narrated label two-tone split

/// Splits the closed pill's narrated label into tone segments so the verb /
/// prefix reads at secondary opacity and the object at primary — the mockup's
/// `.lab .dim` treatment (`SPEC-poured-island` §A2 "verb `dim`/`t2`, object
/// `t1`", §A2′ "count bold + `dim`", §A5/§A6 "`Done ·` dim, workspace primary").
///
/// The label arrives as one already-localized string from
/// `IslandClosedLabelResolver`, so the split is keyed off the resolved ambient
/// state (which produced that string) rather than re-parsing localized words —
/// a pure function `PouredPillMotionTests` pins against the resolver's own
/// output.
enum PouredPillLabelTone {

    /// One tone run of the label.
    struct Segment: Equatable {
        var text: String
        /// `true` → secondary opacity (`t2`); `false` → primary (`t1`).
        var isDim: Bool
        /// `true` → rendered a step heavier than the label's base weight — the
        /// A2′ count (`SPEC` §A2′ "count semibold").
        var isStrong: Bool

        init(text: String, isDim: Bool, isStrong: Bool = false) {
            self.text = text
            self.isDim = isDim
            self.isStrong = isStrong
        }
    }

    /// Tone-segments the label for `ambient`. A label that has no natural split
    /// (permission / question prompts, single words) renders wholly primary.
    static func segments(for text: String, ambient: PouredPillAmbientState) -> [Segment] {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return [] }

        switch ambient {
        case .completed:
            // "Done · the-automator" → "Done ·" dim, workspace primary.
            if let range = trimmed.range(of: " · ") {
                let prefix = String(trimmed[..<range.lowerBound]) + " ·"
                let object = String(trimmed[range.upperBound...])
                return [
                    Segment(text: prefix, isDim: true),
                    Segment(text: " " + object, isDim: false),
                ]
            }
            return [Segment(text: trimmed, isDim: false)]

        case .working:
            // "N working" — leading count is the object (primary, semibold), the
            // word is the qualifier (dim). Otherwise "Verb object…" — verb dim,
            // object primary.
            let parts = trimmed.split(separator: " ", maxSplits: 1).map(String.init)
            guard parts.count == 2 else {
                return [Segment(text: trimmed, isDim: false)]
            }
            if parts[0].allSatisfy(\.isNumber) {
                return [
                    Segment(text: parts[0], isDim: false, isStrong: true),
                    Segment(text: " " + parts[1], isDim: true),
                ]
            }
            return [
                Segment(text: parts[0], isDim: true),
                Segment(text: " " + parts[1], isDim: false),
            ]

        case .idle, .permission, .question:
            return [Segment(text: trimmed, isDim: false)]
        }
    }
}
