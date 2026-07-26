import SwiftUI
import OpenIslandCore

/// Poured Island's closed-pill slot (AB-300 · AB-330).
///
/// The closed state is the "black stem" the panel pours out of, so the pill
/// keeps a dark `surfaceInk` body — hierarchy is carried by light, not chrome —
/// lit by a specular top edge for the glass hint. Layout (glyph, centre label,
/// notch-lane label, right slot) and the fluid-width math are shared verbatim
/// with `V6ClosedPill` so the pill's outer dimensions — and therefore the
/// closed↔opened morph frame in `IslandPanelView` — stay identical across
/// themes; only the fill treatment and the agents-grid tiles differ.
///
/// AB-330 gives it the six ambient states of `SPEC-poured-island` §4A / mockup
/// §A. The frame stays byte-identical (the `V6ClosedPill.*OuterWidth` statics
/// are untouched); the state is expressed entirely inside the reserved slots:
///
/// - **A1 idle** — still 3-bar glyph at `paper@0.5`; no glow, no breathing.
/// - **A2 working** (and **A2′ many**) — the body breathes the cool `lumen`
///   glow; the glyph waves; the label is the narrated activity, verb dimmed and
///   object primary (two-tone). A2′ additionally lights the agents grid.
/// - **A3 permission** — the loudest state: an amber `attnpulse` bleeds outside
///   the silhouette; the left indicator is the approval dot with its warm ring.
/// - **A4 question** — a static gold halo + gold-tinted breathing glyph, kept
///   distinct from A3 by hue *and* shape (never colour alone).
/// - **A5 just completed** — a one-shot cool-white→green `settle`, then quiet.
/// - **A6 outcomes** — interrupted (`stop` glyph, warning amber) / failed
///   (`✕` glyph, red) rest with a coloured indicator and **no glow**.
///
/// The spotlight session's phase/outcome — which `UnifiedBars.Mode` alone can't
/// carry — arrives through `\.islandClosedPillActivity`; the pure
/// `PouredPillAmbientState.resolve(...)` folds it into the frame. Every
/// animation follows the shipped `PouredPulsingStatusDot` rule: never acquire a
/// clock under Reduce Motion — hold the peak (loudest) frame statically instead.
struct PouredClosedPill: View {
    var mode: UnifiedBars.Mode
    var label: String?
    var rightSlot: IslandRightSlotContent?
    var layout: V6ClosedLayout
    var height: CGFloat = 32
    var physicalNotchWidth: CGFloat = 0
    var minWidth: CGFloat = 70
    var showsGlyph: Bool = true

    @Environment(\.islandTokens) private var tokens
    @Environment(\.islandClosedPillActivity) private var activity
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    private static let glyphSize: CGFloat = 24
    private static let innerGap: CGFloat = 6
    private static let notchLaneLabelGap: CGFloat = 6

    private var pad: CGFloat { height / 2 }

    private var ambient: PouredPillAmbientState {
        PouredPillAmbientState.resolve(activity: activity, mode: mode, rightSlot: rightSlot)
    }

    var body: some View {
        switch layout {
        case .external: externalBody
        case .macbook:  macbookBody
        }
    }

    // MARK: Background

    /// Dark stem body plus the specular top edge — the "glass treatment" on a
    /// deliberately dark surface. Under Reduce Transparency the specular is
    /// dropped and only the flat ink remains, keeping every glyph/label legible.
    private var glassBackground: some View {
        ZStack {
            V6ClosedPillShape()
                .fill(tokens.colors.surfaceInk)

            if !reduceTransparency, let specular = tokens.material.specularTopEdge {
                LinearGradient(
                    stops: [
                        .init(color: specular.color.opacity(specular.opacity * 0.7), location: 0),
                        .init(color: .clear, location: 1),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: min(specular.sheenHeight, height * 0.55))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .clipShape(V6ClosedPillShape())
                .allowsHitTesting(false)
            }
        }
    }

    // MARK: Left indicator (glyph / dot / outcome mark)

    /// The left wing's status indicator, always drawn inside the reserved
    /// `glyphSize` box so the pill width is unchanged whatever the state. When
    /// `showsGlyph` is false the morph owns the traveling glyph (AB-243), so the
    /// slot is a transparent placeholder exactly as before.
    @ViewBuilder
    private var leadingIndicator: some View {
        if showsGlyph {
            indicatorContent
                .frame(width: Self.glyphSize, height: Self.glyphSize)
        } else {
            Color.clear
                .frame(width: Self.glyphSize, height: Self.glyphSize)
        }
    }

    @ViewBuilder
    private var indicatorContent: some View {
        switch ambient {
        case .idle:
            UnifiedBars(mode: .idle, size: Self.glyphSize,
                        tint: tokens.colors.paper.opacity(tokens.colors.tertiaryTextOpacity))
        case .working:
            UnifiedBars(mode: .running, size: Self.glyphSize, tint: tokens.colors.statusRunning)
        case .question:
            UnifiedBars(mode: .waiting, size: Self.glyphSize, tint: tokens.colors.statusWaitingForAnswer)
        case .permission:
            PouredPillRingedDot(
                fill: tokens.colors.statusWaitingForApproval,
                ring: PouredPalette.attention.opacity(PouredPillMotion.Permission.ringOpacity),
                ringWidth: PouredPillMotion.Permission.ringWidth
            )
        case .completed(let outcome):
            PouredPillOutcomeMark(outcome: outcome)
                .foregroundStyle(outcomeTint(outcome))
        }
    }

    private func outcomeTint(_ outcome: SessionOutcome) -> Color {
        switch outcome {
        case .success:     tokens.colors.statusCompleted
        case .interrupted: tokens.colors.statusWarning
        case .failed:      tokens.colors.statusFailed
        }
    }

    // MARK: Label

    @ViewBuilder
    private func centerLabel(_ text: String) -> some View {
        PouredClosedPillLabel(
            text: text,
            ambient: ambient,
            // Cap at the width the fluid-layout math already reserved for this
            // label (`V6CenterLabelView.intrinsicWidth`), so the two-tone leaf
            // can never render wider than the pill sized itself for.
            maxWidth: V6CenterLabelView.intrinsicWidth(of: text)
        )
    }

    @ViewBuilder
    private func notchLaneLabel(_ text: String) -> some View {
        PouredClosedPillLabel(
            text: text,
            ambient: ambient,
            maxWidth: V6ClosedPill.notchLaneLabelMaxWidth
        )
    }

    @ViewBuilder
    private var rightSlotView: some View {
        if let rightSlot {
            PouredRightSlotView(content: rightSlot)
                .transition(.opacity.combined(with: .move(edge: .trailing)))
        }
    }

    // MARK: External (fluid)

    private var externalBody: some View {
        let width = V6ClosedPill.externalOuterWidth(
            label: label,
            rightSlot: rightSlot,
            minWidth: minWidth,
            height: height
        )

        return ZStack {
            glassBackground

            HStack(spacing: 0) {
                leadingIndicator

                if let label {
                    centerLabel(label)
                        .padding(.leading, Self.innerGap)
                        .transition(.opacity.combined(with: .move(edge: .leading)))
                }

                Spacer(minLength: Self.innerGap)

                rightSlotView
            }
            .padding(.horizontal, pad)
        }
        .frame(width: width, height: height)
        // AB-330 stage 2: the ambient glow no longer rides here. It moved to the
        // `PouredClosedGlow` seam layer `IslandPanelView` renders OUTSIDE the
        // morph's content `.clipShape`, so A2/A3/A4/A5 glows actually bleed past
        // the silhouette instead of being truncated at it (stage-1 deviation).
        .animation(pillLayoutAnimation, value: pillLayoutKey)
    }

    // MARK: MacBook (notch-lane label opt-in)

    private var macbookBody: some View {
        let outer = V6ClosedPill.macbookOuterWidth(
            label: label,
            physicalNotchWidth: physicalNotchWidth,
            height: height
        )

        return ZStack {
            glassBackground

            HStack(spacing: 0) {
                leadingIndicator

                if let label {
                    notchLaneLabel(label)
                        .padding(.leading, Self.notchLaneLabelGap)
                        .transition(.opacity.combined(with: .move(edge: .leading)))
                }

                Spacer(minLength: 0)

                rightSlotView
            }
            .padding(.horizontal, pad)
        }
        .frame(width: outer, height: height)
        // AB-330 stage 2: glow moved to the `PouredClosedGlow` seam layer — see
        // `externalBody`.
        .animation(pillLayoutAnimation, value: pillLayoutKey)
    }

    // MARK: Layout transition

    private var pillLayoutAnimation: Animation {
        .timingCurve(0.4, 0, 0.2, 1, duration: 0.45)
    }

    private var pillLayoutKey: AnyHashable {
        AnyHashable([
            AnyHashable(label ?? ""),
            AnyHashable(rightSlot.map(PouredRightSlotKey.init) ?? .none),
            AnyHashable(mode),
        ])
    }
}

private enum PouredRightSlotKey: Hashable {
    case none
    case count(Int)
    case agents(Int)
    case attention(Int, IslandAttentionKind)
    case tasks(Int, Int, Int)
    case usage(Int, String, String)

    init(_ content: IslandRightSlotContent) {
        switch content {
        case .count(let n):   self = .count(n)
        case .agents(let cs): self = .agents(cs.count)
        case .attentionCount(let count, let kind):
            self = .attention(count, kind)
        case .taskCounter(let completed, let total, let subagents):
            self = .tasks(completed, total, subagents)
        case .usage(let percent, let window, let provider):
            self = .usage(percent, window, provider)
        }
    }
}

// MARK: - Ambient glow

/// The glow-casting seam layer (AB-330 stage 2). Renders the closed-pill
/// silhouette filled with `surfaceInk` — hidden behind the real pill, which is
/// the same ink shape drawn on top — so only its `.shadow` bleeds out around the
/// edges. `IslandPanelView` places this *behind* the morph/legacy surface and
/// **outside** the shared content `.clipShape`, which is why the glow now bleeds
/// past the silhouette instead of being truncated at it (the honest stage-1
/// deviation). The window already reserves headroom for the bloom via Poured's
/// `closedShadowHorizontalInset 40` / `closedShadowBottomInset 44`
/// (`SPEC-poured-island` §3.1).
struct PouredClosedGlow: View {
    let ambient: PouredPillAmbientState
    let width: CGFloat
    let height: CGFloat

    @Environment(\.islandTokens) private var tokens

    var body: some View {
        V6ClosedPillShape()
            .fill(tokens.colors.surfaceInk)
            .frame(width: width, height: height)
            .modifier(PouredPillGlow(ambient: ambient))
            .allowsHitTesting(false)
    }
}

/// The six ambient states' body glow (`SPEC-poured-island` §4A · mockup §A
/// keyframes `lumen` / `attnpulse` / `settle`), applied to the glow-seam
/// silhouette (`PouredClosedGlow`) so it bleeds from the pill outline. Every
/// timing/radius/opacity comes from `PouredPillMotion`.
///
/// Motion follows the `PouredPulsingStatusDot` precedent: the breathing states
/// drive a single `@State` toggle via `repeatForever`, and the settle is a
/// one-shot `0 → 1` progress that never loops. Under Reduce Motion no animation
/// is ever started — the breathing states hold their **peak** (loudest) frame,
/// and the settle jumps straight to its quiet end (`SPEC` §K, ticket "static
/// frames at PEAK attention visibility").
private struct PouredPillGlow: ViewModifier {
    let ambient: PouredPillAmbientState

    @Environment(\.islandTokens) private var tokens
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Breathing phase for `lumen` (A2) and `attnpulse` (A3): `false` = trough,
    /// `true` = peak. Held at `true` (peak) under Reduce Motion.
    @State private var breathing = false
    /// Settle one-shot progress (A5): `0` = cool-white flash, `1` = quiet. Rests
    /// at `1` so a pill that never completes shows no settle glow.
    @State private var settleProgress: Double = 1

    func body(content: Content) -> some View {
        glow(content)
            .onAppear { syncMotion() }
            .onChange(of: ambient) { _, _ in syncMotion() }
    }

    @ViewBuilder
    private func glow(_ content: Content) -> some View {
        switch ambient {
        case .idle:
            content
        case .working:
            content.shadow(
                color: tokens.colors.statusRunning.opacity(breathing ? PouredPillMotion.Working.glowOpacity : 0),
                radius: breathing ? PouredPillMotion.Working.glowRadius : 0
            )
        case .permission:
            let opacity = breathing ? PouredPillMotion.Permission.opacityMax : PouredPillMotion.Permission.opacityMin
            let radius = breathing ? PouredPillMotion.Permission.radiusMax : PouredPillMotion.Permission.radiusMin
            let spread = breathing ? PouredPillMotion.Permission.spreadMax : 0
            content
                .shadow(color: PouredPalette.attention.opacity(opacity), radius: radius)
                // Second, wider layer emulates the mockup's `spread` — no native
                // spread on SwiftUI shadows, so the extra bleed rides here.
                .shadow(color: PouredPalette.attention.opacity(opacity * 0.6), radius: radius + spread)
        case .question:
            content.shadow(
                color: tokens.colors.statusWaitingForAnswer.opacity(PouredPillMotion.Question.glowOpacity),
                radius: PouredPillMotion.Question.glowRadius
            )
        case .completed(.success):
            content
                .shadow(color: Color.white.opacity(settleWhiteOpacity), radius: PouredPillMotion.Settle.flashRadius)
                .shadow(color: tokens.colors.statusCompleted.opacity(settleGreenOpacity), radius: PouredPillMotion.Settle.greenRadius)
        case .completed:
            // A6 interrupted / failed rest with no glow — the coloured indicator
            // and outcome glyph carry the state.
            content
        }
    }

    // MARK: Settle interpolation (functions of `settleProgress`)

    /// Cool-white flash: full at `0`, gone by the green key-time.
    private var settleWhiteOpacity: Double {
        let key = PouredPillMotion.Settle.greenKeyTime
        let fade = max(0, 1 - settleProgress / key)
        return PouredPillMotion.Settle.flashOpacity * fade
    }

    /// Green bloom: rises to the key-time, then fades to nothing by `1`.
    private var settleGreenOpacity: Double {
        let key = PouredPillMotion.Settle.greenKeyTime
        let level: Double
        if settleProgress <= key {
            level = key > 0 ? settleProgress / key : 1
        } else {
            level = 1 - (settleProgress - key) / (1 - key)
        }
        return PouredPillMotion.Settle.greenOpacity * max(0, min(1, level))
    }

    // MARK: Motion lifecycle

    private func syncMotion() {
        switch ambient {
        case .working:
            startBreathing(period: PouredPillMotion.Working.period)
        case .permission:
            startBreathing(period: PouredPillMotion.Permission.period)
        case .completed(.success):
            playSettle()
        case .idle, .question, .completed:
            // Question's halo is static; idle / A6 cast nothing. Nothing to run.
            break
        }
    }

    private func startBreathing(period: TimeInterval) {
        guard !reduceMotion else {
            breathing = true // hold the peak, never acquire the clock
            return
        }
        breathing = false
        withAnimation(.easeInOut(duration: period).repeatForever(autoreverses: true)) {
            breathing = true
        }
    }

    private func playSettle() {
        guard !reduceMotion else {
            settleProgress = 1 // render the settled (quiet) frame immediately
            return
        }
        settleProgress = 0
        withAnimation(.easeOut(duration: PouredPillMotion.Settle.duration)) {
            settleProgress = 1
        }
    }
}

// MARK: - Indicator leaves

/// A filled status dot inside a soft translucent ring — the A3 approval marker
/// (`.dot.approve.ring`). The ring is drawn as a wider filled disc behind the
/// dot so its translucency reads like the mockup's `box-shadow` spread rather
/// than a hard stroke.
private struct PouredPillRingedDot: View {
    let fill: Color
    let ring: Color
    let ringWidth: CGFloat

    private let dotSize: CGFloat = 8

    var body: some View {
        ZStack {
            Circle()
                .fill(ring)
                .frame(width: dotSize + ringWidth * 2, height: dotSize + ringWidth * 2)
            Circle()
                .fill(fill)
                .frame(width: dotSize, height: dotSize)
        }
    }
}

/// The A6 outcome mark: a stop bar for interrupted, an ✕ for failed, and a
/// check for a (fresh) success — distinct in shape as well as hue so the state
/// never rides on colour alone. Tint is supplied by the caller.
private struct PouredPillOutcomeMark: View {
    let outcome: SessionOutcome

    var body: some View {
        switch outcome {
        case .success:
            Image(systemName: "checkmark")
                .font(.system(size: 12, weight: .bold))
        case .interrupted:
            Image(systemName: "stop.fill")
                .font(.system(size: 11, weight: .semibold))
        case .failed:
            Image(systemName: "xmark")
                .font(.system(size: 12, weight: .bold))
        }
    }
}

// MARK: - Two-tone narrated label

/// The closed pill's narrated activity, split into primary / dim tone runs by
/// `PouredPillLabelTone` (verb dim + object primary, count semibold). Renders at
/// the Poured `activityLine` role but is capped at `maxWidth` — the width the
/// fluid-layout math already reserved — so it never renders wider than the pill
/// sized itself for (the `V6ClosedPill.*OuterWidth` statics are untouched).
private struct PouredClosedPillLabel: View {
    let text: String
    let ambient: PouredPillAmbientState
    let maxWidth: CGFloat

    @Environment(\.islandTokens) private var tokens

    private var primary: Color { tokens.colors.paper.opacity(0.96) }
    private var dim: Color { tokens.colors.paper.opacity(tokens.colors.secondaryTextOpacity) }

    private var composed: Text {
        let segments = PouredPillLabelTone.segments(for: text, ambient: ambient)
        return segments.reduce(Text(verbatim: "")) { accumulated, segment in
            var piece = Text(verbatim: segment.text)
            if segment.isStrong { piece = piece.fontWeight(.semibold) }
            return accumulated + piece.foregroundStyle(segment.isDim ? dim : primary)
        }
    }

    var body: some View {
        let styled = composed
            .font(PouredType.Role.activityLine.font)
            .tracking(PouredType.Role.activityLine.spec.trackingPoints)
            .lineLimit(1)
            .truncationMode(.tail)

        // Grow to the text when it fits inside the reserved width, otherwise
        // pin to the cap and tail-truncate — mirrors `V6NotchLaneLabelView`, so
        // a long activity string is bounded instead of pushing the pill wider.
        ViewThatFits(in: .horizontal) {
            styled.fixedSize(horizontal: true, vertical: false)
            styled.frame(width: maxWidth, alignment: .leading)
        }
        .frame(maxWidth: maxWidth, alignment: .leading)
    }
}

// MARK: - Right slot

/// Poured Island's closed-pill right slot. AB-330 stage 2 gives each AB-322
/// content kind its own Poured rendering (`SPEC-poured-island` §4A A3/A4 · §G ·
/// §I) instead of the shipped degrade-to-`×N` fallback: an amber attention
/// badge, a gold `?` question badge, a `⏲ 2/5` task chip, and a worst-window
/// usage dial. `.count` keeps the neutral `×N` badge; `.agents` keeps the glass
/// grid. Every variant reuses `IslandRightSlotContent.fallbackBadgeAccessibilityLabel`
/// so the VoiceOver summary is unchanged. The pill's outer width math
/// (`V6ClosedPill.*OuterWidth`) is untouched — these variants render inside the
/// slot the fluid layout already reserved.
struct PouredRightSlotView: View {
    let content: IslandRightSlotContent
    var lang: LanguageManager = .shared
    @Environment(\.islandTokens) private var tokens

    var body: some View {
        switch content {
        case .count:
            countBadge
        case .attentionCount(let count, let kind):
            PouredAttentionBadge(count: count, kind: kind)
                .accessibilityLabel(content.fallbackBadgeAccessibilityLabel(lang))
        case .taskCounter(let completed, let total, let subagents):
            PouredTaskCounterChip(completed: completed, total: total, subagents: subagents)
                .accessibilityLabel(content.fallbackBadgeAccessibilityLabel(lang))
        case .usage(let percent, _, _):
            PouredUsageDialChip(percent: percent)
                .accessibilityLabel(content.fallbackBadgeAccessibilityLabel(lang))
        case .agents(let cells):
            PouredAgentsGridBody(cells: cells)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(V6RightSlotView.agentsGridAccessibilitySummary(for: cells, lang: lang))
        }
    }

    private var countBadge: some View {
        Text("×\(content.fallbackBadgeCount ?? 0)")
            .font(.system(size: 11, weight: .semibold, design: .monospaced))
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .foregroundStyle(tokens.colors.paper.opacity(0.72))
            .accessibilityLabel(content.fallbackBadgeAccessibilityLabel(lang))
    }
}

// MARK: - Right-slot variant leaves

/// A3/A4 attention badge — the loud `count.attn` amber capsule (permission) or
/// the calmer gold `?` capsule (question). The two are distinct by **hue and
/// shape/glyph**, never colour alone: permission shows the blocked-session
/// count on the bright `attention` fill with its own r14 glow; question shows a
/// `?` on the softer `statusWaitingForAnswer` gold with no extra badge glow
/// (`SPEC-poured-island` §4A A3/A4).
private struct PouredAttentionBadge: View {
    let count: Int
    let kind: IslandAttentionKind

    @Environment(\.islandTokens) private var tokens

    private var fill: Color {
        switch kind {
        case .permission: PouredPalette.attention
        case .question:   tokens.colors.statusWaitingForAnswer
        }
    }

    private var ink: Color {
        switch kind {
        case .permission: PouredPalette.attentionBadgeInk
        case .question:   PouredPalette.questionBadgeInk
        }
    }

    /// The permission badge is the "you are the blocker" state, so it carries
    /// the r14 amber glow; the question badge stays quiet (gold fill only).
    private var glowRadius: CGFloat {
        kind == .permission ? PouredPillMotion.RightSlot.attnBadgeGlowRadius : 0
    }

    private var label: String {
        switch kind {
        case .permission: "\(count)"
        case .question:   "?"
        }
    }

    var body: some View {
        Text(label)
            .font(PouredType.Role.summaryNumber.font)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .foregroundStyle(ink)
            .padding(.horizontal, PouredPillMotion.RightSlot.badgeHPadding)
            .padding(.vertical, PouredPillMotion.RightSlot.badgeVPadding)
            .background(
                RoundedRectangle(cornerRadius: PouredPillMotion.RightSlot.badgeCornerRadius, style: .continuous)
                    .fill(fill)
            )
            .shadow(
                color: PouredPalette.attention.opacity(glowRadius > 0 ? PouredPillMotion.RightSlot.attnBadgeGlowOpacity : 0),
                radius: glowRadius
            )
    }
}

/// G task-counter chip — `⏲ 2/5` (or a bare `⏲ ×3` when the spotlight has
/// subagents but no todo list). Tabular digits so a ticking counter doesn't
/// jitter; drawn in the neutral paper tone since a running task list is
/// progress, not attention (`SPEC-poured-island` §G "pill: right slot `⏲ 2/5`").
private struct PouredTaskCounterChip: View {
    let completed: Int
    let total: Int
    let subagents: Int

    @Environment(\.islandTokens) private var tokens

    var body: some View {
        HStack(spacing: PouredPillMotion.RightSlot.taskChipSpacing) {
            Image(systemName: "timer")
                .font(.system(size: 9, weight: .semibold))
            Text(fraction)
                .font(PouredType.Role.age.font)
        }
        .lineLimit(1)
        .fixedSize(horizontal: true, vertical: false)
        .foregroundStyle(tokens.colors.paper.opacity(0.82))
    }

    /// A todo list is the headline (`2/5`); a pure subagent fan-out with no todos
    /// falls back to the agent count (`×3`) rather than a frozen `0/0`.
    private var fraction: String {
        total > 0 ? "\(completed)/\(total)" : "×\(subagents)"
    }
}

/// I usage dial — a small conic ring + tabular `92%`, tinted by threshold
/// (`≥90` critical red, `≥70` warn gold, else green). The pill only surfaces the
/// worst window once it is critical (`IslandRightSlotResolver.usageAlertThreshold
/// == 90`), so in practice this is always the red crit dial; the tint is still
/// computed from the value so a fixture at any percent reads truthfully
/// (`SPEC-poured-island` §I "pill compression: small red dial + `92%`").
private struct PouredUsageDialChip: View {
    let percent: Int

    @Environment(\.islandTokens) private var tokens

    private var tint: Color {
        if percent >= PouredPillMotion.RightSlot.usageCriticalThreshold {
            tokens.colors.statusFailed
        } else if percent >= PouredPillMotion.RightSlot.usageWarnThreshold {
            tokens.colors.statusWaitingForAnswer
        } else {
            tokens.colors.statusCompleted
        }
    }

    private var fraction: Double { min(1, max(0, Double(percent) / 100)) }

    var body: some View {
        HStack(spacing: PouredPillMotion.RightSlot.usageDialValueSpacing) {
            ZStack {
                Circle()
                    .stroke(tokens.colors.paper.opacity(0.14),
                            lineWidth: PouredPillMotion.RightSlot.usageDialLineWidth)
                Circle()
                    .trim(from: 0, to: fraction)
                    .stroke(tint,
                            style: StrokeStyle(lineWidth: PouredPillMotion.RightSlot.usageDialLineWidth, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            .frame(width: PouredPillMotion.RightSlot.usageDialDiameter,
                   height: PouredPillMotion.RightSlot.usageDialDiameter)

            Text("\(percent)%")
                .font(PouredType.Role.age.font)
                .foregroundStyle(tint)
        }
        .lineLimit(1)
        .fixedSize(horizontal: true, vertical: false)
    }
}

/// Glass restyle of the closed-island agents grid. The matrix shape (rows,
/// cell size, gap) comes from the active theme's grid strategy — Poured shares
/// Classic's, so the layout is pinned by the same `AgentsGridLayoutTests` — and
/// only the per-tile rendering changes for the frosted surface.
private struct PouredAgentsGridBody: View {
    let cells: [AgentGridCell]

    @Environment(\.islandTheme) private var theme

    var body: some View {
        let geometry = theme.agentsGridGeometry
        let rowSizes = geometry.balancedRows(cells.count)
        let geom = geometry.cellGeometry(rowSizes.count)
        let rows = V6RightSlotView.splitIntoRows(cells, rowSizes: rowSizes)

        VStack(spacing: geom.gap) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: geom.gap) {
                    ForEach(Array(row.enumerated()), id: \.offset) { _, cell in
                        PouredAgentsTileView(cell: cell, size: geom.cell, radius: geom.radius)
                    }
                }
            }
        }
        .fixedSize()
    }
}

/// One agents-grid tile (A2′). Liveness is carried by status colour, not agent
/// brand: a running cell lights `statusRunning` with a soft halo, an idle cell
/// dims to `paper@0.5`, and a waiting cell breathes the attention amber
/// (`SPEC-poured-island` §A2′ · mockup `.agrid i.on / i.idle / i.wait`). The
/// overflow cell keeps its neutral "+N" chip.
private struct PouredAgentsTileView: View {
    let cell: AgentGridCell
    let size: CGFloat
    let radius: CGFloat
    @Environment(\.islandTokens) private var tokens

    var body: some View {
        switch cell {
        case .session(_, let state):
            switch state {
            case .running:
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(tokens.colors.statusRunning)
                    .frame(width: size, height: size)
                    .shadow(
                        color: tokens.colors.statusRunning.opacity(PouredPillMotion.AgentsGrid.runningGlowOpacity),
                        radius: PouredPillMotion.AgentsGrid.runningGlowRadius
                    )
            case .idle:
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(tokens.colors.paper.opacity(PouredPillMotion.AgentsGrid.idleCellOpacity))
                    .frame(width: size, height: size)
            case .waiting:
                PouredWaitingTile(color: PouredPalette.attention, size: size, radius: radius)
            }
        case .overflow(let n):
            ZStack {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(tokens.colors.paper.opacity(0.14))
                Text("+\(n)")
                    .font(.system(size: max(5, size * 0.55), weight: .bold, design: .monospaced))
                    .foregroundStyle(tokens.colors.paper)
            }
            .frame(width: size, height: size)
        }
    }
}

/// A waiting agent's tile: a breathing glow that pulses the halo radius and
/// opacity with motion enabled, and holds a fixed mid-glow under Reduce Motion
/// so the tile still reads as distinct from idle/running without animating.
private struct PouredWaitingTile: View {
    let color: Color
    let size: CGFloat
    let radius: CGFloat
    @State private var pulse = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let active = reduceMotion ? true : pulse
        RoundedRectangle(cornerRadius: radius, style: .continuous)
            .fill(color)
            .frame(width: size, height: size)
            .shadow(color: color.opacity(active ? 0.85 : 0.3), radius: active ? 4 : 1.5)
            .opacity(reduceMotion ? 0.85 : (pulse ? 1.0 : 0.55))
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true)) {
                    pulse = true
                }
            }
    }
}
