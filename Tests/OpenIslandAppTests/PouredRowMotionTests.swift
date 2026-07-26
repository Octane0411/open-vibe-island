import Testing
import OpenIslandCore
@testable import OpenIslandApp

/// AB-332 (Poured 2.0 session rows, stage 1): pins the row's motion constants
/// and its two pure presentation decisions — the narrated-activity tone split
/// and the disambiguator suffix styling input — so any drift in the row list
/// state (`SPEC-poured-island` §3.3 / §4C · mockup §C) fails the build.
struct PouredRowMotionTests {

    // MARK: - Entrance constants (mockup `rowin`)

    @Test
    func entranceConstantsMatchSpec() {
        // Mockup `rowin`: opacity 0 → 1, translateY(10px) → 0, scale(.98) → 1.
        #expect(PouredRowMotion.Entrance.riseOffset == 10)
        #expect(PouredRowMotion.Entrance.initialScale == 0.98)
        #expect(PouredRowMotion.Entrance.initialOpacity == 0)
    }

    @Test
    func entranceSettleSpringMatchesTheMorph() {
        // The row settles with the Poured morph spring (SPEC §1c: response 0.5 /
        // damping 0.84) — a liquid, overshoot-free settle, not the bouncy pop.
        #expect(PouredRowMotion.Entrance.springResponse == 0.5)
        #expect(PouredRowMotion.Entrance.springDamping == 0.84)
    }

    // MARK: - Dismiss / identity-tick geometry

    @Test
    func dismissRevealsFullyOnHover() {
        #expect(PouredRowMotion.Dismiss.hiddenOpacity == 0)
        #expect(PouredRowMotion.Dismiss.revealedOpacity == 1)
    }

    @Test
    func identityTickIsTwoByThirteen() {
        // SPEC §1b: a 2×13 tick, radius 1, in the agent brand colour.
        #expect(PouredRowMotion.IdentityTick.width == 2)
        #expect(PouredRowMotion.IdentityTick.height == 13)
        #expect(PouredRowMotion.IdentityTick.cornerRadius == 1)
    }

    // MARK: - Narrated activity tone split (mockup `.act` / `.act .live`)

    @Test
    func verbAndObjectSplitDimsVerbAndBrightensObject() {
        let segments = PouredRowActivityTone.segments(
            verb: "Editing",
            object: "AppModel.swift",
            fallback: nil
        )
        #expect(segments == [
            .init(text: "Editing", isPrimary: false),
            .init(text: " AppModel.swift", isPrimary: true),
        ])
    }

    @Test
    func verbWithoutObjectIsWhollyPrimary() {
        // A lone verb (e.g. "Planning") is the entire line, so it reads primary.
        let segments = PouredRowActivityTone.segments(verb: "Planning", object: nil, fallback: nil)
        #expect(segments == [.init(text: "Planning", isPrimary: true)])
    }

    @Test
    func blankObjectCollapsesToTheLoneVerb() {
        let segments = PouredRowActivityTone.segments(verb: "Reading", object: "   ", fallback: nil)
        #expect(segments == [.init(text: "Reading", isPrimary: true)])
    }

    @Test
    func fallbackLineIsWhollySecondary() {
        // No narration (a completed / interrupted / idle row): the human summary
        // renders wholly at secondary, matching the mockup's `.act{color:t2}`.
        let segments = PouredRowActivityTone.segments(
            verb: nil,
            object: nil,
            fallback: "Updated AGENTS.md and CLAUDE.md"
        )
        #expect(segments == [.init(text: "Updated AGENTS.md and CLAUDE.md", isPrimary: false)])
    }

    @Test
    func narrationWinsOverFallbackWhenBothPresent() {
        // The narrated verb/object is authoritative; a stray fallback is ignored.
        let segments = PouredRowActivityTone.segments(
            verb: "Running",
            object: "git status",
            fallback: "ignored"
        )
        #expect(segments == [
            .init(text: "Running", isPrimary: false),
            .init(text: " git status", isPrimary: true),
        ])
    }

    @Test
    func noNarrationAndNoFallbackYieldsNothing() {
        #expect(PouredRowActivityTone.segments(verb: nil, object: nil, fallback: nil).isEmpty)
        #expect(PouredRowActivityTone.segments(verb: "  ", object: "x", fallback: "   ").isEmpty)
    }

    // MARK: - Disambiguator suffix styling input (mockup `.disamb`)

    @Test
    func disambiguatorRendersBareWithNoParentheses() {
        // The mockup draws the branch/recency as its own mono span — never the
        // old `(feat/bridge-auth)` parenthesised headline suffix.
        #expect(PouredRowDisambiguation.suffix("feat/bridge-auth") == "feat/bridge-auth")
        #expect(PouredRowDisambiguation.suffix("  main · 3 subagents  ") == "main · 3 subagents")
        #expect(PouredRowDisambiguation.suffix("12m ago") == "12m ago")
    }

    @Test
    func disambiguatorDropsWhenAbsentOrBlank() {
        #expect(PouredRowDisambiguation.suffix(nil) == nil)
        #expect(PouredRowDisambiguation.suffix("") == nil)
        #expect(PouredRowDisambiguation.suffix("   ") == nil)
    }

    // MARK: - Subagent live timer (mockup §G `.sa-time` — `M:SS`)

    @Test
    func subagentClockZeroPadsSecondsUnderAMinute() {
        // Mockup renders `0:42`, `0:08` — not the shipped `42s` / `8s`.
        #expect(PouredSubagentTiming.clockLabel(seconds: 42) == "0:42")
        #expect(PouredSubagentTiming.clockLabel(seconds: 8) == "0:08")
        #expect(PouredSubagentTiming.clockLabel(seconds: 0) == "0:00")
    }

    @Test
    func subagentClockCountsMinutesWithoutHourRollover() {
        #expect(PouredSubagentTiming.clockLabel(seconds: 75) == "1:15")
        #expect(PouredSubagentTiming.clockLabel(seconds: 600) == "10:00")
        // 83m20s stays an honest live count, not a truncated 1:23:20.
        #expect(PouredSubagentTiming.clockLabel(seconds: 5000) == "83:20")
    }

    @Test
    func subagentClockClampsNegativeIntervals() {
        // A `startedAt` nudged into the future clamps to 0:00, never "-1:59".
        #expect(PouredSubagentTiming.clockLabel(seconds: -5) == "0:00")
    }

    // MARK: - Task rollup (mockup §G nest header + §G′ chip)

    @Test
    func taskRollupCountsCompletedOnly() {
        let rollup = PouredTaskRollup(statuses: [.completed, .completed, .inProgress, .pending, .pending])
        // "2 of 5 done" — in-progress is not done.
        #expect(rollup.done == 2)
        #expect(rollup.total == 5)
    }

    @Test
    func taskRollupOnEmptyIsZeroOfZero() {
        let rollup = PouredTaskRollup(statuses: [])
        #expect(rollup.done == 0)
        #expect(rollup.total == 0)
    }

    // MARK: - Pane attachment chip (mockup §D — first surfacing of the field)

    @Test
    func attachmentChipMapsStateToCopyAndLiveness() {
        #expect(PouredAttachmentChip(.attached) == .attached)
        #expect(PouredAttachmentChip(.attached).localizationKey == "poured.detail.attachment.attached")
        #expect(PouredAttachmentChip(.attached).isLive)

        #expect(PouredAttachmentChip(.stale) == .stale)
        #expect(PouredAttachmentChip(.stale).localizationKey == "poured.detail.attachment.stale")
        #expect(!PouredAttachmentChip(.stale).isLive)

        #expect(PouredAttachmentChip(.detached) == .detached)
        #expect(PouredAttachmentChip(.detached).localizationKey == "poured.detail.attachment.detached")
        #expect(!PouredAttachmentChip(.detached).isLive)
    }
}
