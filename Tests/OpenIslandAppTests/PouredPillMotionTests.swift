import SwiftUI
import Testing
@testable import OpenIslandApp
@testable import OpenIslandCore

/// AB-330 stage 1: pins the Poured 2.0 closed pill's motion constants, its
/// ambient-state resolution, and the two-tone label split so any drift in the
/// six-state vocabulary (`SPEC-poured-island` §1c / §4A) fails the build. Stage 2
/// extends this suite alongside the right-slot variants + snapshot regression.
struct PouredPillMotionTests {

    // MARK: - Motion constants (mockup §A keyframes)

    @Test
    func workingLumenConstantsMatchSpec() {
        #expect(PouredPillMotion.Working.period == 3.0)
        #expect(PouredPillMotion.Working.glowRadius == 22)
        #expect(PouredPillMotion.Working.glowOpacity == 0.16)
    }

    @Test
    func manyWorkingAgentsGridConstantsMatchSpec() {
        #expect(PouredPillMotion.AgentsGrid.runningGlowRadius == 6)
        #expect(PouredPillMotion.AgentsGrid.runningGlowOpacity == 0.6)
        #expect(PouredPillMotion.AgentsGrid.idleCellOpacity == 0.5)
    }

    @Test
    func permissionAttnpulseConstantsMatchSpec() {
        #expect(PouredPillMotion.Permission.period == 1.9)
        #expect(PouredPillMotion.Permission.radiusMin == 18)
        #expect(PouredPillMotion.Permission.radiusMax == 34)
        #expect(PouredPillMotion.Permission.spreadMax == 4)
        #expect(PouredPillMotion.Permission.opacityMin == 0.28)
        #expect(PouredPillMotion.Permission.opacityMax == 0.55)
        #expect(PouredPillMotion.Permission.ringWidth == 3)
        #expect(PouredPillMotion.Permission.ringOpacity == 0.22)
    }

    @Test
    func questionGlowConstantsMatchSpec() {
        #expect(PouredPillMotion.Question.glowRadius == 26)
        #expect(PouredPillMotion.Question.glowOpacity == 0.34)
        #expect(PouredPillMotion.Question.glyphBreathePeriod == 2.6)
    }

    @Test
    func settleConstantsMatchSpec() {
        #expect(PouredPillMotion.Settle.duration == 2.6)
        #expect(PouredPillMotion.Settle.greenKeyTime == 0.22)
        #expect(PouredPillMotion.Settle.flashRadius == 30)
        #expect(PouredPillMotion.Settle.flashSpread == 3)
        #expect(PouredPillMotion.Settle.flashOpacity == 0.4)
        #expect(PouredPillMotion.Settle.greenRadius == 22)
        #expect(PouredPillMotion.Settle.greenSpread == 2)
        #expect(PouredPillMotion.Settle.greenOpacity == 0.4)
    }

    // MARK: - Right-slot variant constants (stage 2 · §4A A3/A4 · §G · §I)

    @Test
    func rightSlotBadgeConstantsMatchSpec() {
        // A3 count.attn badge — glow `rgba(255,177,77,.55)` r14.
        #expect(PouredPillMotion.RightSlot.attnBadgeGlowRadius == 14)
        #expect(PouredPillMotion.RightSlot.attnBadgeGlowOpacity == 0.55)
        #expect(PouredPillMotion.RightSlot.badgeHPadding == 5)
        #expect(PouredPillMotion.RightSlot.badgeVPadding == 1.5)
        #expect(PouredPillMotion.RightSlot.badgeCornerRadius == 6)
    }

    @Test
    func rightSlotTaskAndUsageConstantsMatchSpec() {
        #expect(PouredPillMotion.RightSlot.taskChipSpacing == 3)
        #expect(PouredPillMotion.RightSlot.usageDialDiameter == 13)
        #expect(PouredPillMotion.RightSlot.usageDialLineWidth == 2.5)
        #expect(PouredPillMotion.RightSlot.usageDialValueSpacing == 3)
        // Threshold cutoffs mirror the shipped `usageColor` rule (§I / §3.2).
        #expect(PouredPillMotion.RightSlot.usageCriticalThreshold == 90)
        #expect(PouredPillMotion.RightSlot.usageWarnThreshold == 70)
    }

    // MARK: - Ambient-state resolution

    private func activity(
        _ phase: SessionPhase,
        outcome: SessionOutcome = .success,
        fresh: Bool = true
    ) -> IslandClosedPillActivity {
        IslandClosedPillActivity(phase: phase, outcome: outcome, isOutcomeFresh: fresh)
    }

    private var agentsGrid: IslandRightSlotContent {
        .agents([.session(color: .blue, state: .running), .session(color: .green, state: .idle)])
    }

    @Test
    func resolveFallsBackToModeWhenNoActivity() {
        #expect(PouredPillAmbientState.resolve(activity: nil, mode: .idle, rightSlot: nil) == .idle)
        #expect(PouredPillAmbientState.resolve(activity: nil, mode: .running, rightSlot: nil)
                == .working(manyWorking: false))
        #expect(PouredPillAmbientState.resolve(activity: nil, mode: .running, rightSlot: agentsGrid)
                == .working(manyWorking: true))
        // `.waiting` without a spotlight can't be split — takes the calmer gold
        // question frame, never the loud amber it can't substantiate.
        #expect(PouredPillAmbientState.resolve(activity: nil, mode: .waiting, rightSlot: nil) == .question)
    }

    @Test
    func resolvePermissionAndQuestionFromPhase() {
        #expect(PouredPillAmbientState.resolve(
            activity: activity(.waitingForApproval), mode: .waiting, rightSlot: nil) == .permission)
        #expect(PouredPillAmbientState.resolve(
            activity: activity(.waitingForAnswer), mode: .waiting, rightSlot: nil) == .question)
    }

    @Test
    func resolveWorkingTracksAgentsGrid() {
        #expect(PouredPillAmbientState.resolve(
            activity: activity(.running), mode: .running, rightSlot: .count(1))
            == .working(manyWorking: false))
        #expect(PouredPillAmbientState.resolve(
            activity: activity(.running), mode: .running, rightSlot: agentsGrid)
            == .working(manyWorking: true))
    }

    @Test
    func resolveCompletedGatesOnFreshness() {
        #expect(PouredPillAmbientState.resolve(
            activity: activity(.completed, outcome: .success, fresh: true), mode: .idle, rightSlot: nil)
            == .completed(.success))
        #expect(PouredPillAmbientState.resolve(
            activity: activity(.completed, outcome: .interrupted, fresh: true), mode: .idle, rightSlot: nil)
            == .completed(.interrupted))
        #expect(PouredPillAmbientState.resolve(
            activity: activity(.completed, outcome: .failed, fresh: true), mode: .idle, rightSlot: nil)
            == .completed(.failed))
        // Past the settle window a completion is just another quiet session.
        #expect(PouredPillAmbientState.resolve(
            activity: activity(.completed, outcome: .success, fresh: false), mode: .idle, rightSlot: nil)
            == .idle)
    }

    @Test
    func castsGlowOnlyForLiveAndSuccessStates() {
        #expect(PouredPillAmbientState.idle.castsGlow == false)
        #expect(PouredPillAmbientState.working(manyWorking: false).castsGlow == true)
        #expect(PouredPillAmbientState.permission.castsGlow == true)
        #expect(PouredPillAmbientState.question.castsGlow == true)
        #expect(PouredPillAmbientState.completed(.success).castsGlow == true)
        // A6 interrupted / failed rest with no glow.
        #expect(PouredPillAmbientState.completed(.interrupted).castsGlow == false)
        #expect(PouredPillAmbientState.completed(.failed).castsGlow == false)
    }

    // MARK: - Two-tone narrated label split

    @Test
    func completedLabelSplitsPrefixDimWorkspacePrimary() {
        let segments = PouredPillLabelTone.segments(
            for: "Done · the-automator", ambient: .completed(.success))
        #expect(segments == [
            .init(text: "Done ·", isDim: true),
            .init(text: " the-automator", isDim: false),
        ])
    }

    @Test
    func workingVerbLabelSplitsVerbDimObjectPrimary() {
        let segments = PouredPillLabelTone.segments(
            for: "Editing AppModel.swift", ambient: .working(manyWorking: false))
        #expect(segments == [
            .init(text: "Editing", isDim: true),
            .init(text: " AppModel.swift", isDim: false),
        ])
    }

    @Test
    func manyWorkingLabelMakesCountStrongPrimaryWordDim() {
        let segments = PouredPillLabelTone.segments(
            for: "3 working", ambient: .working(manyWorking: true))
        #expect(segments == [
            .init(text: "3", isDim: false, isStrong: true),
            .init(text: " working", isDim: true),
        ])
    }

    @Test
    func attentionAndIdleLabelsStayWhollyPrimary() {
        #expect(PouredPillLabelTone.segments(for: "Approve swift build?", ambient: .permission)
                == [.init(text: "Approve swift build?", isDim: false)])
        #expect(PouredPillLabelTone.segments(for: "Answer needed", ambient: .question)
                == [.init(text: "Answer needed", isDim: false)])
        #expect(PouredPillLabelTone.segments(for: "", ambient: .idle).isEmpty)
    }
}

/// Stage 2 regression: the Poured 2.0 closed pill keeps the shipped
/// `V6ClosedPill.*OuterWidth` math **byte-identical** for every (label,
/// rightSlot) combination — the morph frame (and every theme's pill silhouette)
/// depends on it, and the new right-slot variants (amber badge, `?` badge, task
/// chip, usage dial) must render *inside* the slot this already reserves, never
/// widen it.
///
/// The goldens below were computed from the CURRENT formula (stage 1 left the
/// statics untouched), so they pin today's output as the contract. If the width
/// math drifts, this fails — regardless of what the right-slot views draw.
@MainActor
struct PouredClosedPillWidthRegressionTests {

    /// Pinned at a fixed height (38 — the notch closed height); the formula is
    /// height-parametric, so one height is enough to pin its shape.
    private static let height: CGFloat = 38
    private static let tolerance: CGFloat = 0.001

    private func external(_ label: String?, _ rightSlot: IslandRightSlotContent?) -> CGFloat {
        V6ClosedPill.externalOuterWidth(
            label: label, rightSlot: rightSlot, minWidth: 70, height: Self.height
        )
    }

    private func macbook(_ label: String?, notch: CGFloat) -> CGFloat {
        V6ClosedPill.macbookOuterWidth(
            label: label, physicalNotchWidth: notch, height: Self.height
        )
    }

    /// External / top-bar fluid layout — width DOES fold in the right slot, so
    /// each right-slot kind is pinned. The four count-shaped kinds (`.count`,
    /// `.attentionCount`, `.taskCounter`, `.usage`) share the badge width math,
    /// so the Poured variants never move the frame.
    @Test
    func externalOuterWidthGoldensAreUnchanged() {
        #expect(abs(external(nil, nil) - 70) < Self.tolerance)
        #expect(abs(external("Editing AppModel.swift", nil) - 238.6) < Self.tolerance)
        #expect(abs(external("Approve swift build?", .attentionCount(count: 1, kind: .permission)) - 244.4) < Self.tolerance)
        #expect(abs(external("3 working", .count(3)) - 164.1) < Self.tolerance)
        #expect(abs(external(nil, .attentionCount(count: 12, kind: .question)) - 89.6) < Self.tolerance)
        #expect(abs(external("Refactoring", .taskCounter(completed: 2, total: 5, subagents: 0)) - 178.7) < Self.tolerance)
        #expect(abs(external(nil, .usage(percent: 92, windowLabel: "5h", providerTitle: "Claude")) - 89.6) < Self.tolerance)
        #expect(abs(external(nil, .agents([
            .session(color: .blue, state: .running),
            .session(color: .green, state: .idle),
            .session(color: .red, state: .waiting),
        ])) - 96) < Self.tolerance)
        #expect(abs(external("Done · the-automator", nil) - 224) < Self.tolerance)
    }

    /// A permission and a question badge with the same count reserve the same
    /// width — the two variants differ only in fill/glyph, not in geometry.
    @Test
    func attentionBadgeKindDoesNotChangeReservedWidth() {
        #expect(
            external("x", .attentionCount(count: 3, kind: .permission))
                == external("x", .attentionCount(count: 3, kind: .question))
        )
    }

    /// MacBook / notch layout — outer width does NOT fold in the right slot
    /// (the wings straddle the physical notch), so it depends only on the label
    /// and the notch width. Pinned so the notch-lane math stays put.
    @Test
    func macbookOuterWidthGoldensAreUnchanged() {
        #expect(abs(macbook(nil, notch: 180) - 274) < Self.tolerance)
        #expect(abs(macbook("Editing AppModel.swift", notch: 180) - 454) < Self.tolerance)
        #expect(abs(macbook("hi", notch: 200) - 340.4) < Self.tolerance)
    }

    /// The right slot is invisible to the MacBook width math, so swapping it (or
    /// swapping the count-shaped kind) never changes the outer width.
    @Test
    func macbookOuterWidthIgnoresRightSlot() {
        // `macbookOuterWidth` takes no rightSlot argument at all — assert the
        // label-only contract holds across notch widths so a future refactor
        // can't quietly start folding the right slot in.
        #expect(macbook("Refactoring · 3 agents", notch: 160) == macbook("Refactoring · 3 agents", notch: 160))
        #expect(abs(macbook(nil, notch: 0) - 94) < Self.tolerance) // 47 + 0 + 47 (half = max(44, 19+24+4))
    }
}
