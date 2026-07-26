import CoreGraphics
import Foundation
import OpenIslandCore

/// Motion + pure presentation vocabulary for the Poured 2.0 **session row**
/// list state (AB-332, `SPEC-poured-island` §3.3 / §4C · mockup §C).
///
/// A sibling of `PouredPillMotion`: the pill owns the closed-pill ambient
/// states, this owns the row. Like the pill table it is a pure, `Equatable`-
/// friendly vector of geometry / timing (colours come from the token layer at
/// the view site), so `PouredRowMotionTests` can pin every number and drift
/// fails the build instead of the eye.
///
/// The `PouredPulsingStatusDot` "never acquire the clock under Reduce Motion"
/// precedent governs the entrance: with motion a freshly-inserted row rises and
/// fades once into its settled frame; under Reduce Motion the row is *born*
/// settled — no offset, no fade, and crucially no clock is ever touched
/// (`SPEC` §K "gated under Reduce Motion", ticket "row appears with no entrance
/// animation — never acquire the clock").
enum PouredRowMotion {

    // MARK: Row entrance — `rowin` (mockup §K motion strip)

    /// The one-shot rise+fade a row plays when it is inserted into the list.
    ///
    /// Mockup keyframe `rowin`:
    /// `0% { opacity:0; transform: translateY(10px) scale(.98) }` settling to
    /// `opacity:1; translateY(0) scale(1)`. The demo loops for the motion
    /// strip; the real row plays it **once** on appear, spring-settled.
    enum Entrance {
        /// Starting vertical offset (mockup `translateY(10px)`), eased to `0`.
        static let riseOffset: CGFloat = 10
        /// Starting scale (mockup `scale(.98)`), eased to `1`.
        static let initialScale: CGFloat = 0.98
        /// Starting opacity (mockup `opacity:0`), eased to `1`.
        static let initialOpacity: Double = 0

        /// Settle spring — deliberately the Poured **morph** spring
        /// (`SPEC` §1c open = `spring(response:0.5, damping:0.84)`) so a row
        /// arriving reads with the same liquid, overshoot-free settle as the
        /// surface itself, rather than the bouncier new-event `pop`.
        static let springResponse: TimeInterval = 0.5
        static let springDamping: Double = 0.84
    }

    // MARK: Hover-reveal dismiss (mockup §C `.row:hover .dismiss`)

    /// The trailing dismiss glyph is hidden at rest and fades in on row hover
    /// (`SPEC` §D "Dismiss hover-reveal only (opacity 0→1 on row hover)"). The
    /// fade rides the row's existing `isHighlighted` animation; these are the
    /// endpoint opacities the view interpolates between.
    enum Dismiss {
        static let hiddenOpacity: Double = 0
        static let revealedOpacity: Double = 1
    }

    // MARK: Identity tick (mockup §C `.row .tick` · `SPEC` §1b "identity tick")

    /// The 2×13 brand-coloured tick that replaces the capsule agent badge in the
    /// collapsed row — "identity stays a whisper" (`SPEC` §1.5).
    enum IdentityTick {
        static let width: CGFloat = 2
        static let height: CGFloat = 13
        static let cornerRadius: CGFloat = 1
    }
}

// MARK: - Narrated activity tone split (mockup §C `.act` / `.act .live`)

/// Splits the row's narrated activity line into tone runs for the mockup's
/// `.act` treatment: the **verb** reads at secondary opacity and the **object**
/// (the file / command / host — the data half a human scans for) reads at
/// primary. A verb with no object is the whole line, so it takes primary. When
/// there is no narration to speak (a completed / interrupted / idle row, or a
/// running row with no active tool yet) the human fallback line renders wholly
/// secondary — exactly the mockup's `.act{color:var(--t2)}` for those rows.
///
/// Pure and view-free (it takes already-resolved, already-localized strings) so
/// `PouredRowMotionTests` can pin the split without standing up a view or a
/// `LanguageManager`. This is the row analogue of the pill's
/// `PouredPillLabelTone`, but it works off the structured `NarratedActivity`
/// verb/object directly instead of re-parsing a joined string.
enum PouredRowActivityTone {

    /// One tone run of the activity line.
    struct Segment: Equatable {
        var text: String
        /// `true` → primary ink (`t1`); `false` → secondary ink (`t2`).
        var isPrimary: Bool
    }

    /// Tone-segments the activity line.
    ///
    /// - Parameters:
    ///   - verb: the narrated verb, already localized. `nil`/empty → no narration.
    ///   - object: the narrated object (file / command / host), never localized.
    ///   - fallback: the human activity line to speak when there is no narration.
    static func segments(verb: String?, object: String?, fallback: String?) -> [Segment] {
        if let verb = verb?.pouredTrimmed, !verb.isEmpty {
            if let object = object?.pouredTrimmed, !object.isEmpty {
                return [
                    Segment(text: verb, isPrimary: false),
                    Segment(text: " " + object, isPrimary: true),
                ]
            }
            return [Segment(text: verb, isPrimary: true)]
        }
        if let fallback = fallback?.pouredTrimmed, !fallback.isEmpty {
            return [Segment(text: fallback, isPrimary: false)]
        }
        return []
    }
}

// MARK: - Disambiguator suffix styling input (mockup §C `.disamb`)

/// The bare branch / recency phrase rendered after the workspace name in the
/// title line (`SPEC` §C "`feat/bridge-auth`, `main`, `12m ago`").
///
/// The mockup draws the disambiguator as its own mono span — **not** a
/// parenthesised suffix on the headline the way the old `spotlightHeadlineText`
/// did. This pure helper is the single formatting decision the row makes about
/// that span (trim, drop-if-empty, no parentheses), pinned so it can't silently
/// regain the `(…)` wrapper.
enum PouredRowDisambiguation {
    static func suffix(_ raw: String?) -> String? {
        guard let trimmed = raw?.pouredTrimmed, !trimmed.isEmpty else { return nil }
        return trimmed
    }
}

// MARK: - Subagent live timer (mockup §G `.sa-time` — `0:42`)

/// The `M:SS` clock the expanded subagent list ticks against `startedAt`
/// (mockup §G `.sa-time` renders `0:42` / `1:15` / `0:08`, not the shipped
/// row's `42s` / `1m 15s`). Pure and view-free so `PouredRowMotionTests` can
/// pin the padding without a `TimelineView`.
///
/// Minutes are **not** rolled into hours: a subagent that has run 83 minutes
/// reads `83:20`, an honest live count rather than a truncated `1:23:20` the
/// tabular column can't align. Negative intervals (a `startedAt` in the future
/// after a clock nudge) clamp to `0:00`.
enum PouredSubagentTiming {
    static func clockLabel(seconds: Int) -> String {
        let clamped = max(0, seconds)
        let minutes = clamped / 60
        let secs = clamped % 60
        return "\(minutes):" + String(format: "%02d", secs)
    }
}

// MARK: - Task rollup (mockup §G nest header + §G′ compressed chip)

/// The done / total split the todo list rolls up to — the nest header
/// `Tasks · 2 of 5 done` when expanded and the `2/5 tasks` chip when
/// compressed both read from this. Pure count arithmetic, pinned so the two
/// surfaces can never disagree about what "done" means (completed only, never
/// in-progress).
struct PouredTaskRollup: Equatable {
    var done: Int
    var total: Int

    init(done: Int, total: Int) {
        self.done = done
        self.total = total
    }

    init(statuses: [ClaudeTaskInfo.Status]) {
        self.total = statuses.count
        self.done = statuses.filter { $0 == .completed }.count
    }
}

// MARK: - Pane attachment chip (mockup §D `.chip` — first surfacing of the field)

/// The attachment chip in the expanded detail (mockup §D
/// `Pane attached` / `Pane stale` / `Detached`). AB-332 is the first surface
/// to render `SessionAttachmentState` anywhere, so the state→(copy-key, live)
/// mapping lives here as one pinnable decision rather than a `switch` buried in
/// the view. `isLive` drives the green status dot; only `.attached` is live.
enum PouredAttachmentChip {
    case attached
    case stale
    case detached

    init(_ state: SessionAttachmentState) {
        switch state {
        case .attached: self = .attached
        case .stale: self = .stale
        case .detached: self = .detached
        }
    }

    /// Localization key for the chip label — resolved ×3 (en / zh-Hans /
    /// zh-Hant) in `Localizable.strings`.
    var localizationKey: String {
        switch self {
        case .attached: "poured.detail.attachment.attached"
        case .stale: "poured.detail.attachment.stale"
        case .detached: "poured.detail.attachment.detached"
        }
    }

    /// Only an attached pane reads as live (green dot); stale/detached recede.
    var isLive: Bool { self == .attached }
}

private extension String {
    var pouredTrimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
