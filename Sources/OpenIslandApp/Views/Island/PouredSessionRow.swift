import AppKit
import SwiftUI
@preconcurrency import MarkdownUI
import OpenIslandCore

/// Poured Island's session row (AB-302 · AB-303).
///
/// The glass re-skin of `IslandSessionRow` for **every** row state — collapsed,
/// running, done, idle/stale (AB-302) and the actionable approval / question /
/// completion interiors (AB-303) — across the `.list` and `.notification`
/// presentations. Status is expressed as luminous glow rather than a chip: a
/// running row carries a breathing green dot (static under Reduce Motion), a
/// done row settles to a quiet check, and an idle row recedes into the
/// material; hover lifts the row with a lighter glass tint in `.list` only.
///
/// **Actionable rows are now fully Poured (AB-303).** A permission request
/// radiates a pulsing warm-amber glow above the glass — the loudest surface in
/// the panel — with a filled Allow and a quiet Deny; the question and completion
/// bodies reuse the shared, token-driven `StructuredQuestionPromptView` /
/// completion card, which already read cleanly on the frosted surface. The
/// behaviours that are contract-level — approve / answer / reply callbacks, the
/// ⌘Y / ⌘⇧Y / ⌘N keyboard wiring (driven globally from `OverlayPanelController`),
/// the 1–9 / Enter question shortcuts, and the grouped VoiceOver summary — are
/// preserved verbatim; only the surfaces change.
struct PouredSessionRow: View {
    let session: AgentSession
    var stateIndicator: IslandSessionStateIndicator = .animatedDot
    var completedStaleThreshold: TimeInterval = AgentSession.staleCompletedDisplayThreshold
    var isActionable: Bool = false
    var useDrawingGroup: Bool = true
    var isInteractive: Bool = true
    /// Hover highlight, owned by the enclosing `SessionRowContainer` (AB-297).
    let isHighlighted: Bool
    var presentation: IslandSessionRowPresentation = .list
    var sideInset: CGFloat = 16
    var lang: LanguageManager = .shared
    let actions: RowActions
    /// Lets the visible question card register its option-selection state with
    /// `OverlayPanelController`'s keyboard shortcut handler (AB-227).
    var keyboardCoordinator: OverlayUICoordinator?
    /// Shared 15fps clock for the breathing status dot (AB-228) and the amber
    /// approval glow (AB-303). Passed through to the leaf views that animate;
    /// rows that don't animate never touch it.
    var pulseClock: PulseClock?

    var body: some View {
        PouredRowContent(
            session: session,
            stateIndicator: stateIndicator,
            completedStaleThreshold: completedStaleThreshold,
            isActionable: isActionable,
            isInteractive: isInteractive,
            isHighlighted: isHighlighted,
            presentation: presentation,
            sideInset: sideInset,
            lang: lang,
            actions: actions,
            keyboardCoordinator: keyboardCoordinator,
            pulseClock: pulseClock
        )
    }
}

/// The glass body for every Poured row. Renders the shared summary / auxiliary
/// chrome (verbatim from Classic so the two rows stay interchangeable inside one
/// list) plus, for actionable rows, the Poured approval / question / completion
/// interiors.
private struct PouredRowContent: View {
    let session: AgentSession
    let stateIndicator: IslandSessionStateIndicator
    let completedStaleThreshold: TimeInterval
    let isActionable: Bool
    let isInteractive: Bool
    let isHighlighted: Bool
    let presentation: IslandSessionRowPresentation
    let sideInset: CGFloat
    let lang: LanguageManager
    let actions: RowActions
    let keyboardCoordinator: OverlayUICoordinator?
    let pulseClock: PulseClock?

    @State private var detailOverride: Bool?
    @State private var replyText: String = ""

    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    private var increasesContrast: Bool { colorSchemeContrast == .increased }

    @Environment(\.islandTokens) private var tokens

    /// AB-333: Reduce Transparency flattens the question gold wash to opaque
    /// `surfaceInk` (so text keeps contrast without the translucent amber tint),
    /// mirroring the approval hero's own `reduceTransparency` branch.
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    /// AB-332: list-level duplicate-workspace disambiguators (AB-323), injected
    /// by `IslandPanelView`. Empty (the default) means "no collisions" and the
    /// title line renders the workspace name alone.
    @Environment(\.islandSessionDisambiguators) private var sessionDisambiguators

    /// Each row owns its own age refresh (AB-228) so a tick invalidates only
    /// this row, not its siblings or the list header.
    private static let ageRefreshInterval: TimeInterval = 30

    var body: some View {
        TimelineView(.periodic(from: .now, by: Self.ageRefreshInterval)) { context in
            rowBody(referenceDate: context.date)
        }
    }

    private func rowBody(referenceDate: Date) -> some View {
        let rawPresence = session.islandPresence(at: referenceDate)
        let isStaleCompleted = session.isStaleCompletedForIsland(
            at: referenceDate,
            threshold: completedStaleThreshold
        )
        let defaultShowsDetail = !isStaleCompleted && (rawPresence != .inactive || isActionable)
        let showsDetail = detailOverride ?? defaultShowsDetail
        let presence: IslandSessionPresence = isStaleCompleted
            ? .inactive
            : ((showsDetail && rawPresence == .inactive) ? .active : rawPresence)

        return VStack(alignment: .leading, spacing: 0) {
            rowSummary(presence: presence, showsDetail: showsDetail, referenceDate: referenceDate)

            if showsDetail {
                // §4G nested lists always ride at the top of the detail — a
                // fan-out is worth seeing whether the row is an actionable hero
                // or a quiet running session.
                subagentsAndTasksNests(presence: presence)

                if shouldShowEmbeddedDetailBody {
                    // Actionable interiors (approval / question / completion)
                    // are AB-333's to restyle — Poured renders them verbatim
                    // here, with the transcript kept as a footnote beneath.
                    embeddedDetailBody
                        .padding(.leading, detailLeadingInset)
                        .padding(.trailing, sideInset)
                        .padding(.bottom, 13)
                    // A completed row carries its transcript inside the §4H action
                    // rail, so the shared footnote would double it up — only the
                    // approval / question heroes keep the transcript as a footnote.
                    if session.phase != .completed {
                        transcriptFootnote
                    }
                } else {
                    // §4D: the quiet session-detail — metadata grid, last
                    // assistant message as rich prose, jump-primary + transcript
                    // + attachment chip.
                    sessionDetailBody(presence: presence, referenceDate: referenceDate)
                }
            }
        }
        .background(rowFillColor(for: presence))
        .overlay(alignment: .top) {
            Rectangle()
                .fill(.white.opacity(tokens.colors.hairline(increaseContrast: increasesContrast)))
                .frame(height: 1)
        }
        .overlay(alignment: .leading) {
            if showsLeadingStatusBar {
                RoundedRectangle(cornerRadius: 999, style: .continuous)
                    .fill(statusTint(for: presence))
                    // Poured's leading bar reads as poured light: a soft glow
                    // bleeds off the bar into the glass rather than a hard chip.
                    .shadow(color: statusTint(for: presence).opacity(presence == .inactive ? 0 : 0.5), radius: 4)
                    .frame(width: 3)
                    .padding(.vertical, showsDetail ? 10 : 8)
                    .padding(.leading, 14)
            }
        }
        // Idle / stale rows recede into the material — the same threshold
        // behaviour as Classic, expressed a touch deeper to read as "sunk into
        // the glass".
        .opacity(isStaleCompleted ? 0.62 : 1)
        .contentShape(Rectangle())
        .animation(.easeInOut(duration: 0.15), value: isHighlighted)
        .animation(.easeInOut(duration: 0.2), value: session.phase)
        .animation(.easeInOut(duration: 0.2), value: session.outcome)
        .animation(.easeInOut(duration: 0.2), value: presence)
        .onTapGesture(perform: handlePrimaryTap)
        .onChange(of: isInteractive) { _, interactive in
            if !interactive {
                detailOverride = nil
            }
        }
    }

    // MARK: - Summary

    private func rowSummary(presence: IslandSessionPresence, showsDetail: Bool, referenceDate: Date) -> some View {
        HStack(alignment: .top, spacing: 10) {
            if showsLeadingStatusIndicator {
                statusIndicator(for: presence)
                    .frame(width: 20, alignment: .top)
            }

            VStack(alignment: .leading, spacing: 3) {
                titleLine(presence: presence)

                if showsDetail {
                    activityLine(presence: presence)
                }
            }

            Spacer(minLength: 10)

            HStack(spacing: IslandSessionRowMetrics.badgeSpacing) {
                // AB-332: the capsule agent badge is gone from the collapsed row —
                // identity is now the 2pt brand tick before the workspace name
                // ("identity stays a whisper", SPEC §1.5). The agent's full name
                // reappears only as the dot+label chip in the expanded metadata
                // grid (`agentIdentityChip`).
                if let modelBadge = session.displayModelName {
                    sideBadge(modelBadge)
                }
                if let permissionChip = permissionModeBadgeKind {
                    permissionModeChip(permissionChip)
                }
                // AB-332 · SPEC §4G: when the detail is collapsed, the nested
                // subagent / task work rolls up to two quiet chips
                // (`3 subagents` · `⏲ 2/5 tasks`) — the only counts the row
                // invents are these real ones. Expanded, the full nests replace
                // them below (`subagentsAndTasksNests`).
                if !showsDetail {
                    if let subagentCount = collapsedSubagentCount {
                        sideBadge(lang.t("poured.subagents.count", subagentCount))
                    }
                    if let taskRollup = collapsedTaskRollup {
                        sideBadge("⏲ " + lang.t("poured.tasks.chip", taskRollup.done, taskRollup.total))
                    }
                }
                if session.isRemote {
                    sideBadge("SSH")
                }
                if let terminalBadge = session.spotlightTerminalBadge {
                    sideBadge(terminalBadge)
                }
                Text(ageBadgeText(at: referenceDate))
                    // AB-332: §2 `age` role — SF Pro 11/500 `.monospacedDigit()`
                    // at tertiary. The mono chrome is retired; only the digits
                    // stay tabular so ages line up column-to-column.
                    .font(PouredType.Role.age.font)
                    .foregroundStyle(summaryAgeColor(for: presence))
                    .frame(minWidth: IslandSessionRowMetrics.ageColumnWidth, alignment: .trailing)
                detailToggleButton(isOpen: showsDetail)
                if let dismiss = actions.dismiss {
                    // AB-332: hover-reveal — hidden at rest, fades in on the row's
                    // `isHighlighted` (which never becomes true in `.notification`,
                    // where `actions.dismiss` is nil anyway). The row's grouped
                    // VoiceOver summary already exposes dismiss as a named rotor
                    // action, so it stays reachable while visually hidden.
                    DismissButton(action: dismiss, lang: lang)
                        .opacity(isHighlighted ? PouredRowMotion.Dismiss.revealedOpacity : PouredRowMotion.Dismiss.hiddenOpacity)
                        .accessibilityHidden(true)
                }
            }
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
        }
        .padding(.leading, rowLeadingInset)
        .padding(.trailing, sideInset)
        .padding(.top, 11)
        .padding(.bottom, showsDetail ? 8 : 11)
        // AB-302: identical grouped VoiceOver summary to Classic — one stop for
        // the whole row, with the toggle and dismiss recreated as named rotor
        // actions so both stay reachable without splitting the row.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityRowSummaryText(referenceDate: referenceDate))
        .accessibilityAddTraits(isInteractive ? .isButton : [])
        .accessibilityAction {
            guard isInteractive else { return }
            actions.jump()
        }
        .accessibilityAction(named: Text(lang.t(showsDetail ? "a11y.session.collapseDetail" : "a11y.session.expandDetail"))) {
            toggleDetail(currentlyOpen: showsDetail)
        }
        .modifier(PouredOptionalNamedAccessibilityAction(name: actions.dismiss != nil ? lang.t("a11y.session.dismiss") : nil, action: { actions.dismiss?() }))
    }

    // MARK: - Title line (identity tick + workspace + disambiguator)

    /// The mockup's `.title-line` (SPEC §C): a 2pt brand-coloured identity tick,
    /// the workspace name at the `workspaceTitle` role, and — only when a
    /// duplicate workspace name in the list demands it — the T05 branch/recency
    /// disambiguator as a mono span at tertiary. The workspace name yields
    /// (tail-truncates) before the disambiguator, which pins its intrinsic width,
    /// so a long name never squeezes the branch out of view.
    private func titleLine(presence: IslandSessionPresence) -> some View {
        HStack(spacing: 8) {
            identityTick(presence: presence)

            Text(session.spotlightDisplayName)
                .font(PouredType.Role.workspaceTitle.font)
                .tracking(PouredType.Role.workspaceTitle.spec.trackingPoints)
                .foregroundStyle(titleColor(for: presence))
                .lineLimit(1)
                .truncationMode(.tail)

            if let disambiguator = disambiguatorSuffix {
                Text(disambiguator)
                    .font(PouredType.Role.branchDisambiguator.font)
                    .foregroundStyle(tokens.colors.paper.opacity(contrastText(tokens.colors.tertiaryTextOpacity)))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .fixedSize(horizontal: true, vertical: false)
            }
        }
    }

    /// The 2×13 brand-colour tick that replaces the capsule agent badge in the
    /// collapsed row. Radius 1, brand hue from `AgentSession.brandColorHex`; it
    /// dims with the row when a stale/inactive row recedes into the glass.
    private func identityTick(presence: IslandSessionPresence) -> some View {
        RoundedRectangle(cornerRadius: PouredRowMotion.IdentityTick.cornerRadius, style: .continuous)
            .fill(Color(hex: session.tool.brandColorHex) ?? tokens.colors.paper)
            .frame(
                width: PouredRowMotion.IdentityTick.width,
                height: PouredRowMotion.IdentityTick.height
            )
            .opacity(presence == .inactive ? 0.7 : 1)
            .accessibilityHidden(true)
    }

    // MARK: - Activity line (T03 narration · mockup `.act`)

    /// The mockup's `.act` line (SPEC §C / §4C): the narrated activity, split so
    /// the verb reads at secondary opacity and the object (file / command / host)
    /// at primary. A running session narrates verb+object via the T03 layer
    /// (`AgentSession.narratedActivity`); every other row speaks a human summary
    /// (permission/question text, last message, outcome) wholly at secondary —
    /// never a raw tool id or a `$ …` command echo.
    @ViewBuilder
    private func activityLine(presence: IslandSessionPresence) -> some View {
        let segments = activitySegments
        if !segments.isEmpty {
            composedActivityText(segments)
                .font(PouredType.Role.activityLine.font)
                .lineLimit(1)
                .truncationMode(.tail)
        }
    }

    /// Tone-split runs for the `.act` line. Running rows narrate verb+object;
    /// the rest fall back to the human activity summary (never the `$` echo,
    /// which lived only in the retired running command block).
    private var activitySegments: [PouredRowActivityTone.Segment] {
        if let narrated = session.narratedActivity {
            return PouredRowActivityTone.segments(
                verb: narrated.localizedVerb(lang),
                object: narrated.object,
                fallback: nil
            )
        }
        return PouredRowActivityTone.segments(
            verb: nil,
            object: nil,
            fallback: session.spotlightActivityLineText ?? expandedActivityLineText
        )
    }

    private func composedActivityText(_ segments: [PouredRowActivityTone.Segment]) -> Text {
        let primary = tokens.colors.paper.opacity(contrastText(0.96))
        let secondary = tokens.colors.paper.opacity(contrastText(tokens.colors.secondaryTextOpacity))
        return segments.reduce(Text(verbatim: "")) { accumulated, segment in
            accumulated + Text(verbatim: segment.text)
                .foregroundStyle(segment.isPrimary ? primary : secondary)
        }
    }

    /// The bare branch / recency disambiguator for this row, or `nil` when its
    /// workspace name is unique among the visible sessions. Rendered as its own
    /// mono span (no parentheses) — see `PouredRowDisambiguation`.
    private var disambiguatorSuffix: String? {
        PouredRowDisambiguation.suffix(sessionDisambiguators[session.id])
    }

    // MARK: - Subagents & tasks nests (§4G · mockup §G)

    /// The expanded §4G nests: a subagent sub-list with live `M:SS` timers and
    /// the Claude todo list with real done/doing/pending state — each wrapped in
    /// a quiet "nest" slab (mockup `.nest`, an inset-hairline card) so the
    /// fan-out reads as one grouped surface rather than loose rows.
    @ViewBuilder
    private func subagentsAndTasksNests(presence: IslandSessionPresence) -> some View {
        if let subagents = session.claudeMetadata?.activeSubagents, !subagents.isEmpty {
            subagentNest(subagents)
                .padding(.leading, detailLeadingInset)
                .padding(.trailing, sideInset)
                .padding(.bottom, 10)
        }

        if let tasks = session.claudeMetadata?.activeTasks, !tasks.isEmpty {
            taskNest(tasks)
                .padding(.leading, detailLeadingInset)
                .padding(.trailing, sideInset)
                .padding(.bottom, 10)
        }
    }

    private func subagentNest(_ subagents: [ClaudeSubagentInfo]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "arrow.triangle.branch")
                    .font(.system(size: 9, weight: .semibold))
                    .accessibilityHidden(true)
                Text(pouredUppercased(lang.t("poured.subagents.count", subagents.count)))
                    .font(PouredType.Role.nestHeader.font)
                    .tracking(PouredType.Role.nestHeader.spec.trackingPoints)
            }
            .foregroundStyle(tokens.colors.paper.opacity(contrastText(tokens.colors.tertiaryTextOpacity)))
            .padding(.horizontal, 9)
            .padding(.top, 7)
            .padding(.bottom, 4)

            ForEach(Array(subagents.enumerated()), id: \.element.agentID) { index, sub in
                if index > 0 {
                    Rectangle()
                        .fill(.white.opacity(tokens.colors.hairline(increaseContrast: increasesContrast)))
                        .frame(height: 1)
                }
                subagentRow(sub)
            }
        }
        .background(nestBackground)
    }

    private func subagentRow(_ sub: ClaudeSubagentInfo) -> some View {
        let isRunning = sub.summary == nil
        return HStack(spacing: 10) {
            Circle()
                .fill(isRunning ? tokens.colors.statusRunning : tokens.colors.statusCompleted)
                .frame(width: 6, height: 6)
                .accessibilityLabel(lang.t(isRunning ? "a11y.subagent.running" : "subagents.completed"))

            VStack(alignment: .leading, spacing: 1) {
                Text(sub.agentType ?? sub.agentID)
                    .font(PouredType.Role.subagentType.font)
                    .foregroundStyle(tokens.colors.paper.opacity(contrastText(0.96)))
                    .lineLimit(1)
                if let desc = sub.taskDescription?.trimmedForRow, !desc.isEmpty {
                    Text(desc)
                        .font(PouredType.Role.subagentTask.font)
                        .foregroundStyle(tokens.colors.paper.opacity(contrastText(tokens.colors.secondaryTextOpacity)))
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }

            Spacer(minLength: 6)

            subagentTiming(sub, isRunning: isRunning)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 8)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func subagentTiming(_ sub: ClaudeSubagentInfo, isRunning: Bool) -> some View {
        let elapsedColor = tokens.colors.paper.opacity(contrastText(tokens.colors.tertiaryTextOpacity))
        if isRunning, let started = sub.startedAt {
            TimelineView(.periodic(from: .now, by: 1)) { timeline in
                Text(PouredSubagentTiming.clockLabel(
                    seconds: Int(timeline.date.timeIntervalSince(started))
                ))
                .font(PouredType.Role.subagentElapsed.font)
                .foregroundStyle(elapsedColor)
            }
        } else if !isRunning {
            Text(lang.t("subagents.completed"))
                .font(PouredType.Role.subagentElapsed.font)
                .foregroundStyle(elapsedColor)
        }
    }

    private func taskNest(_ tasks: [ClaudeTaskInfo]) -> some View {
        let rollup = PouredTaskRollup(statuses: tasks.map(\.status))
        return VStack(alignment: .leading, spacing: 0) {
            Text(pouredUppercased(lang.t("poured.tasks.header", rollup.done, rollup.total)))
                .font(PouredType.Role.nestHeader.font)
                .tracking(PouredType.Role.nestHeader.spec.trackingPoints)
                .foregroundStyle(tokens.colors.paper.opacity(contrastText(tokens.colors.tertiaryTextOpacity)))
                .padding(.horizontal, 9)
                .padding(.top, 7)
                .padding(.bottom, 4)

            VStack(alignment: .leading, spacing: 3) {
                ForEach(tasks) { task in
                    taskRow(task)
                }
            }
            .padding(.horizontal, 9)
            .padding(.bottom, 8)
        }
        .background(nestBackground)
    }

    private func taskRow(_ task: ClaudeTaskInfo) -> some View {
        HStack(spacing: 8) {
            taskStatusIcon(task.status)
                .frame(width: 14, height: 14)

            Text(task.title)
                .font(PouredType.Role.todo.font)
                .foregroundStyle(taskTitleColor(task.status))
                .strikethrough(task.status == .completed)
                .lineLimit(1)
                .truncationMode(.tail)

            if task.status == .inProgress {
                Spacer(minLength: 6)
                Text(lang.t("poured.tasks.doing"))
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(tokens.colors.statusRunning)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func taskTitleColor(_ status: ClaudeTaskInfo.Status) -> Color {
        switch status {
        case .completed:
            tokens.colors.paper.opacity(contrastText(tokens.colors.tertiaryTextOpacity))
        case .inProgress:
            tokens.colors.paper.opacity(contrastText(0.96))
        case .pending:
            tokens.colors.paper.opacity(contrastText(tokens.colors.secondaryTextOpacity))
        }
    }

    private var nestBackground: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(Color.white.opacity(0.025))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(.white.opacity(0.05), lineWidth: 1)
            )
    }

    /// Collapsed-row rollup counts (mockup §G′): only present when there is real
    /// nested work to summarise, so a plain row invents nothing.
    private var collapsedSubagentCount: Int? {
        guard let subagents = session.claudeMetadata?.activeSubagents, !subagents.isEmpty else {
            return nil
        }
        return subagents.count
    }

    private var collapsedTaskRollup: PouredTaskRollup? {
        guard let tasks = session.claudeMetadata?.activeTasks, !tasks.isEmpty else {
            return nil
        }
        return PouredTaskRollup(statuses: tasks.map(\.status))
    }

    // MARK: - Session detail body (§4D · mockup §D)

    /// The quiet expanded detail for a non-actionable row: the metadata cell
    /// grid, the last assistant message as rich prose, and the action rail
    /// (jump-primary + transcript ghost + pane-attachment chip). Actionable rows
    /// route to `embeddedDetailBody` (AB-333) instead and never reach here.
    @ViewBuilder
    private func sessionDetailBody(presence: IslandSessionPresence, referenceDate: Date) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            metadataGrid(presence: presence, referenceDate: referenceDate)

            if let message = lastAssistantMessageForDetail {
                assistantMessageCard(message)
                    .padding(.top, 10)
            }

            detailActionRail
                .padding(.top, 12)
        }
        .padding(.leading, detailLeadingInset)
        .padding(.trailing, sideInset)
        .padding(.bottom, 13)
    }

    // MARK: - Metadata grid (§4D · mockup `.meta-grid`)

    /// The mockup's calm cell grid. Each cell is a key (10pt uppercase tertiary,
    /// lifted to the Poured floor) over a 12.5 value. Absent fields render
    /// **nothing** — no `—` dashes (BRIEF §1.3): Model appears only with a
    /// resolved model name, Permission / Branch only for Claude, Live only while
    /// running, Directory only with a working directory.
    private func metadataGrid(presence: IslandSessionPresence, referenceDate: Date) -> some View {
        PouredFlowLayout(spacing: 8) {
            metadataCell(key: lang.t("poured.detail.meta.agent")) {
                agentIdentityChip
            }

            if let model = session.displayModelName {
                metadataTextCell(key: lang.t("poured.detail.meta.model"), value: model)
            }

            if let permission = permissionModeValueText {
                metadataTextCell(key: lang.t("poured.detail.meta.permission"), value: permission)
            }

            if let branch = SessionDisambiguation.branch(for: session) {
                metadataTextCell(
                    key: lang.t("poured.detail.meta.branch"),
                    value: SessionDisambiguation.displayBranch(branch),
                    mono: true
                )
            }

            if session.phase == .running {
                metadataTextCell(
                    key: lang.t("poured.detail.meta.live"),
                    value: session.elapsedRunningLabel(at: referenceDate),
                    tabular: true
                )
            }

            if let directory = directoryDisplayText {
                metadataTextCell(
                    key: lang.t("poured.detail.meta.directory"),
                    value: directory,
                    mono: true
                )
            }
        }
        .padding(.top, 11)
    }

    private func metadataTextCell(key: String, value: String, mono: Bool = false, tabular: Bool = false) -> some View {
        let baseFont = mono ? PouredType.Role.metadataValueMono.font : PouredType.Role.metadataValue.font
        return metadataCell(key: key) {
            Text(value)
                .font(tabular ? baseFont.monospacedDigit() : baseFont)
                .foregroundStyle(metadataValueColor)
                .lineLimit(1)
                .truncationMode(mono ? .middle : .tail)
        }
    }

    private func metadataCell<Content: View>(key: String, @ViewBuilder value: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(pouredUppercased(key))
                .font(PouredType.Role.metadataKey.font)
                .tracking(PouredType.Role.metadataKey.spec.trackingPoints)
                .foregroundStyle(metadataKeyColor)
            value()
        }
        .modifier(MetadataCellChrome())
    }

    /// The dot+label agent chip that resurfaces the agent's full identity in the
    /// grid — the whisper of §7 becomes a plain statement once the row is open.
    private var agentIdentityChip: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(Color(hex: session.tool.brandColorHex) ?? tokens.colors.paper)
                .frame(width: 7, height: 7)
            Text(session.tool.displayName)
                .font(PouredType.Role.metadataValue.font)
                .foregroundStyle(metadataValueColor)
                .lineLimit(1)
        }
    }

    private var metadataKeyColor: Color {
        tokens.colors.paper.opacity(contrastText(tokens.colors.tertiaryTextOpacity))
    }

    private var metadataValueColor: Color {
        tokens.colors.paper.opacity(contrastText(0.96))
    }

    /// Claude-only permission mode, surfaced verbatim (`acceptEdits`, `plan`,
    /// `bypassPermissions`). The implicit `.default` mode carries no information,
    /// so it renders nothing rather than a noisy "default" cell.
    private var permissionModeValueText: String? {
        guard session.tool == .claudeCode,
              let mode = session.claudeMetadata?.permissionMode,
              mode != .default else {
            return nil
        }
        return mode.rawValue
    }

    /// Home-abbreviated, middle-truncated working directory (mockup
    /// `~/…/open-vibe-island`). `nil` when the session carries no directory.
    private var directoryDisplayText: String? {
        guard let raw = session.jumpTarget?.workingDirectory?.trimmedForRow, !raw.isEmpty else {
            return nil
        }
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        var abbreviated = raw
        if raw == home {
            abbreviated = "~"
        } else if raw.hasPrefix(home + "/") {
            abbreviated = "~" + raw.dropFirst(home.count)
        }
        return ActivityNarrator.middleTruncated(abbreviated, maxLength: 34)
    }

    // MARK: - Last assistant message (§4D · mockup `.assistant`)

    /// The last assistant message rendered as rich prose (Markdown + the
    /// `.completionCard` theme so inline `code` reads mono ~11pt and emphasis
    /// resolves on glass) — never the raw single-line dump the shipped detail
    /// echoed. Capped in an `AutoHeightScrollView` so a long message can't run
    /// the row off the panel.
    private func assistantMessageCard(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(pouredUppercased(lang.t("poured.detail.lastMessage", session.tool.displayName)))
                .font(PouredType.Role.assistantLabel.font)
                .tracking(PouredType.Role.assistantLabel.spec.trackingPoints)
                .foregroundStyle(tokens.colors.paper.opacity(contrastText(tokens.colors.tertiaryTextOpacity)))

            AutoHeightScrollView(maxHeight: 150) {
                Markdown(message)
                    .markdownTheme(.completionCard(tokens.colors))
                    .markdownImageProvider(.noNetwork)
                    .markdownInlineImageProvider(.noNetwork)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(0.025))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(.white.opacity(0.045), lineWidth: 1)
                )
        )
    }

    private var lastAssistantMessageForDetail: String? {
        guard let text = session.lastAssistantMessageText?.trimmedForRow, !text.isEmpty else {
            return nil
        }
        return text
    }

    // MARK: - Detail action rail (§4D · mockup `.actions`)

    /// Jump-to-terminal as the primary CTA (a blue gradient button, mockup §D),
    /// the transcript as a ghost affordance, and the pane-attachment chip pushed
    /// to the trailing edge.
    private var detailActionRail: some View {
        HStack(spacing: 10) {
            Button(action: handlePrimaryTap) {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.up.forward")
                        .font(.system(size: 11.5, weight: .bold))
                        .accessibilityHidden(true)
                    Text(lang.t("poured.detail.jump"))
                        .font(PouredType.Role.jumpChip.font)
                        .lineLimit(1)
                }
            }
            .buttonStyle(PouredJumpButtonStyle())
            .accessibilityLabel(lang.t("poured.detail.jump"))

            if let transcriptPath = trimmedTranscriptPath {
                TranscriptAffordance(
                    path: transcriptPath,
                    workspace: session.spotlightWorkspaceName,
                    lang: lang
                )
            }

            Spacer(minLength: 8)

            attachmentChip
        }
    }

    /// `Pane attached` (green dot) / `Pane stale` / `Detached` from
    /// `attachmentState` — AB-332 is the first surface to render this field.
    private var attachmentChip: some View {
        let chip = PouredAttachmentChip(session.attachmentState)
        let label = lang.t(chip.localizationKey)
        return HStack(spacing: 5) {
            Circle()
                .fill(chip.isLive ? tokens.colors.statusCompleted : tokens.colors.paper.opacity(0.3))
                .frame(width: 7, height: 7)
            Text(label)
                .font(PouredType.Role.metaChip.font)
                .foregroundStyle(tokens.colors.paper.opacity(contrastText(tokens.colors.tertiaryTextOpacity)))
                .lineLimit(1)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(.white.opacity(0.05), in: Capsule())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(label)
    }

    /// The transcript kept as a footnote beneath an actionable hero (approval /
    /// question / completion), where it can't ride the §4D action rail.
    @ViewBuilder
    private var transcriptFootnote: some View {
        if let transcriptPath = trimmedTranscriptPath {
            TranscriptAffordance(
                path: transcriptPath,
                workspace: session.spotlightWorkspaceName,
                lang: lang
            )
            .padding(.leading, detailLeadingInset)
            .padding(.trailing, sideInset)
            .padding(.bottom, 10)
        }
    }

    private var trimmedTranscriptPath: String? {
        guard let path = session.trackingTranscriptPath?.trimmedForRow, !path.isEmpty else {
            return nil
        }
        return path
    }

    // MARK: - Embedded detail body (actionable interiors)

    /// Attention phases always earn the body; a completed row only when it's the
    /// actionable card with something to show. A **running** row no longer earns
    /// an embedded body — its activity is narrated in the `.act` line above, and
    /// the shipped boxed `$ command` echo (a raw preview the Poured direction
    /// explicitly bans) is retired with it (AB-332 · SPEC §C). The permission /
    /// question / completion interiors are stage 2's to restyle.
    private var shouldShowEmbeddedDetailBody: Bool {
        if session.phase.requiresAttention {
            return true
        }
        if session.phase == .completed {
            return isActionable && completionHasExpandedBody
        }
        return false
    }

    @ViewBuilder
    private var embeddedDetailBody: some View {
        switch session.phase {
        case .waitingForApproval:
            PouredApprovalCard(
                session: session,
                lang: lang,
                actions: actions,
                pulseClock: pulseClock,
                presentation: presentation
            )
        case .waitingForAnswer:
            questionActionBody
        case .completed:
            completionActionBody
        case .running:
            // Running rows narrate in `.act`; no boxed command echo (see above).
            EmptyView()
        }
    }

    // MARK: - Question action area

    /// The T07 shared interior (`StructuredQuestionPromptView`) wrapped in the
    /// Poured `.q-hero` gold chrome (`SPEC` §4F · mockup `.q-hero`): a gold-tinted
    /// vertical wash (`rgba(52,44,22,.4)→rgba(26,22,12,.5)`) under a 1pt inset
    /// `rgba(255,213,138,.24)` ring at radius 18. The interior's semantics are
    /// untouched — the gold header (`statusWaitingForAnswer` = `#ffd58a`) and the
    /// `1.5pt rgba(255,213,138,.5)` selection ring are already token-driven inside
    /// the shared view (AB-325), and the digit-select / Enter keyboard wiring keeps
    /// flowing through `keyboardCoordinator` exactly as before. Under Reduce
    /// Transparency the wash flattens to opaque `surfaceInk` so the amber tint can
    /// never erode the option text's contrast.
    private var questionActionBody: some View {
        StructuredQuestionPromptView(
            prompt: session.questionPrompt,
            lang: lang,
            keyboardCoordinator: keyboardCoordinator,
            onAnswer: { actions.answer?($0) }
        )
        .padding(3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(questionHeroWash)
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(PouredQuestionColors.ring, lineWidth: 1)
        )
    }

    @ViewBuilder
    private var questionHeroWash: some View {
        let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)
        if reduceTransparency || increasesContrast {
            shape.fill(tokens.colors.surfaceInk)
        } else {
            shape.fill(
                LinearGradient(
                    colors: [PouredQuestionColors.washTop, PouredQuestionColors.washBottom],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
        }
    }

    // MARK: - Completion action area

    /// The completion card, rebuilt to `SPEC` §4H (mockup §H): a tinted-pill
    /// outcome badge with tabular duration + `finished … ago`, the result as rich
    /// prose (the shared `.completionCard` Markdown path — `<strong>` + inline
    /// `code`), the reply input where supported, and a calm action rail (Jump
    /// primary, Transcript / Dismiss ghosts). The badge now renders for **every**
    /// outcome — `Success` too — so a clean completion is as legible as a failed
    /// one; the markdown / link / code colours still resolve from
    /// `.completionCard(tokens.colors)` and the reply stays wired to
    /// `actions.reply` exactly as Classic.
    private var completionActionBody: some View {
        VStack(alignment: .leading, spacing: 0) {
            completionOutcomeHeader

            if !completionMessageText.trimmedForRow.isEmpty {
                AutoHeightScrollView(maxHeight: 160) {
                    Markdown(completionMessageText)
                        .markdownTheme(.completionCard(tokens.colors))
                        .markdownImageProvider(.noNetwork)
                        .markdownInlineImageProvider(.noNetwork)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                        .padding(.horizontal, 14)
                        .padding(.top, 2)
                        .padding(.bottom, 9)
                }
            }

            if actions.reply != nil {
                Rectangle()
                    .fill(.white.opacity(0.05))
                    .frame(height: 1)

                completionReplyInput
            }

            Rectangle()
                .fill(.white.opacity(0.05))
                .frame(height: 1)

            completionActionRail
        }
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(.white.opacity(0.09))
        )
    }

    private var completionHasExpandedBody: Bool {
        // Every completed actionable row now earns the expanded card — the
        // outcome badge + action rail are always worth showing, and a non-success
        // outcome must never be indistinguishable from a plain "Completed" row.
        true
    }

    private var completionDoneOpacity: Double {
        presentation == .notification ? 0.82 : 0.96
    }

    /// §4H header: the outcome badge beside its tabular duration / finished-ago
    /// meta line.
    private var completionOutcomeHeader: some View {
        HStack(alignment: .center, spacing: 10) {
            PouredOutcomeBadge(
                glyphName: completionOutcomeGlyphName,
                label: completionOutcomeLabel,
                tint: completionOutcomeTint.opacity(completionDoneOpacity),
                fill: completionOutcomeFill
            )
            completionMetaLine
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.top, 11)
        .padding(.bottom, 9)
    }

    /// Tabular `43m duration · finished 12m ago` (`SPEC` §4H). Duration is derived
    /// from `firstSeenAt → updatedAt` (the run's own length, frozen at completion,
    /// so it never drifts with wall-clock time) and is shown only when the run
    /// actually lasted a minute or more; finished-ago reuses the row's age
    /// vocabulary.
    @ViewBuilder
    private var completionMetaLine: some View {
        let finishedAgo = lang.t("poured.completion.finishedAgo", session.spotlightAgeBadge)
        HStack(spacing: 7) {
            if let duration = completionDurationText {
                Text(lang.t("poured.completion.duration", duration))
                Text("·").foregroundStyle(tokens.colors.paper.opacity(0.28))
            }
            Text(finishedAgo)
        }
        .font(PouredType.Role.metaChip.font)
        .monospacedDigit()
        .foregroundStyle(tokens.colors.paper.opacity(contrastText(tokens.colors.tertiaryTextOpacity)))
        .lineLimit(1)
    }

    /// Run length (`43m`), or `nil` for a sub-minute run where a duration chip
    /// would read as noise.
    private var completionDurationText: String? {
        let seconds = session.updatedAt.timeIntervalSince(session.firstSeenAt)
        guard seconds >= 60 else { return nil }
        return session.elapsedRunningLabel(at: session.updatedAt)
    }

    /// §4H action rail: Jump primary + Transcript / Dismiss ghosts. The transcript
    /// rides here (not the shared footnote) for completed rows, so it isn't shown
    /// twice.
    private var completionActionRail: some View {
        HStack(spacing: 10) {
            Button(action: handlePrimaryTap) {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.up.forward")
                        .font(.system(size: 11.5, weight: .bold))
                        .accessibilityHidden(true)
                    Text(lang.t("poured.detail.jump"))
                        .font(PouredType.Role.jumpChip.font)
                        .lineLimit(1)
                }
            }
            .buttonStyle(PouredJumpButtonStyle())
            .accessibilityLabel(lang.t("poured.detail.jump"))

            if let transcriptPath = trimmedTranscriptPath {
                TranscriptAffordance(
                    path: transcriptPath,
                    workspace: session.spotlightWorkspaceName,
                    lang: lang
                )
            }

            Spacer(minLength: 8)

            if let dismiss = actions.dismiss {
                Button(action: dismiss) {
                    Text(lang.t("poured.completion.dismiss"))
                        .font(.system(size: 12, weight: .medium))
                        .lineLimit(1)
                }
                .buttonStyle(PouredGhostButtonStyle(role: .quiet))
                .accessibilityLabel(lang.t("a11y.session.dismiss"))
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
    }

    private var completionOutcomeGlyphName: String {
        switch session.outcome {
        case .success: "checkmark"
        case .interrupted: "stop.fill"
        case .failed: "xmark"
        }
    }

    private var completionOutcomeTint: Color {
        tokens.colors.statusTint(for: .completed, outcome: session.outcome)
    }

    /// The tinted-pill background under the outcome badge (`.outcome.ok/.intr/.fail`).
    private var completionOutcomeFill: Color {
        switch session.outcome {
        case .success: PouredCompletionColors.successFill
        case .interrupted: PouredCompletionColors.interruptedFill
        case .failed: PouredCompletionColors.failedFill
        }
    }

    private var completionOutcomeLabel: String {
        switch session.outcome {
        case .success:
            lang.t("poured.completion.success")
        case .interrupted:
            lang.t("completion.interrupted")
        case .failed:
            lang.t("completion.failed")
        }
    }

    @ViewBuilder
    private var completionReplyInput: some View {
        HStack(spacing: 8) {
            ReplyTextField(
                placeholder: lang.t("completion.replyPlaceholder", session.completionReplyRecipientName),
                text: $replyText,
                onSubmit: { submitReply() }
            )
            .frame(height: 32)

            Button {
                submitReply()
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 24))
                    .foregroundColor(replyText.trimmingCharacters(in: .whitespaces).isEmpty
                        ? .white.opacity(0.2) : .white.opacity(0.9))
            }
            .buttonStyle(.plain)
            .disabled(replyText.trimmingCharacters(in: .whitespaces).isEmpty)
            .accessibilityLabel(lang.t("a11y.completion.sendReply"))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private func submitReply() {
        let text = replyText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        replyText = ""
        actions.reply?(text)
    }

    private var completionMessageText: String {
        if let text = session.completionAssistantMessageText?.trimmedForRow, !text.isEmpty {
            return text
        }
        let summary = session.summary.trimmedForRow
        return summary == SessionPhase.completed.displayName ? "" : summary
    }

    // MARK: - Status indicator (all four preferences)

    @ViewBuilder
    private func statusIndicator(for presence: IslandSessionPresence) -> some View {
        let tint = statusTint(for: presence)
        switch stateIndicator {
        case .animatedDot:
            animatedIndicator(tint: tint, presence: presence)
        case .bar:
            RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                .fill(tint)
                .frame(width: 4, height: isActionable ? 34 : 28)
                .shadow(color: tint.opacity(presence == .inactive ? 0 : 0.5), radius: 4)
                .padding(.top, 2)
        case .glyph:
            Image(systemName: statusGlyphName)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(tint)
                .shadow(color: tint.opacity(presence == .inactive ? 0 : 0.45), radius: 4)
                .frame(width: 14, height: 20)
                .padding(.top, 1)
        case .tint:
            Circle()
                .fill(tint.opacity(presence == .inactive ? 0.54 : 0.92))
                .frame(width: 8, height: 8)
                .padding(.top, 6)
        }
    }

    /// The default indicator carries Poured's design language most directly:
    /// a running (or actionable-waiting) row breathes a glowing dot, a
    /// done-success row settles to a quiet check, and an idle row recedes to a
    /// dim, glow-less dot.
    @ViewBuilder
    private func animatedIndicator(tint: Color, presence: IslandSessionPresence) -> some View {
        if session.phase == .completed, session.outcome == .success, presence != .inactive {
            Image(systemName: "checkmark")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(tint)
                .shadow(color: tint.opacity(0.4), radius: 3)
                .frame(width: 14, height: 24, alignment: .top)
                .padding(.top, 3)
        } else if let pulseClock, stateIndicator.pulses(presence: presence, isActionable: isActionable) {
            PouredPulsingStatusDot(pulseClock: pulseClock, tint: tint, presence: presence)
                .frame(width: 12, height: 24, alignment: .top)
        } else {
            pouredStatusDotView(tint: tint, presence: presence, pulse: 0)
                .frame(width: 12, height: 24, alignment: .top)
        }
    }

    // MARK: - Badges (display rules AB-282…286, verbatim from Classic)

    private func sideBadge(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 10.5, weight: .medium, design: .monospaced))
            .foregroundStyle(tokens.colors.paper.opacity(presentation == .notification ? 0.52 : 0.72))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(.white.opacity(presentation == .notification ? 0.05 : 0.07), in: Capsule())
    }

    private enum PermissionModeBadgeKind {
        case plan
        case bypass
    }

    private var permissionModeBadgeKind: PermissionModeBadgeKind? {
        switch session.claudeMetadata?.permissionMode {
        case .plan:
            .plan
        case .bypassPermissions:
            .bypass
        default:
            nil
        }
    }

    @ViewBuilder
    private func permissionModeChip(_ kind: PermissionModeBadgeKind) -> some View {
        switch kind {
        case .plan:
            sideBadge(lang.t("badge.planMode"))
        case .bypass:
            Text(lang.t("badge.bypassPermissions"))
                .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                .foregroundStyle(tokens.colors.statusWarning.opacity(0.94))
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(tokens.colors.statusWarning.opacity(0.16), in: Capsule())
                .overlay(Capsule().stroke(tokens.colors.statusWarning.opacity(0.4), lineWidth: 1))
        }
    }

    private func ageBadgeText(at referenceDate: Date) -> String {
        if session.phase == .running {
            return session.elapsedRunningLabel(at: referenceDate)
        }
        return session.spotlightAgeBadge
    }

    // MARK: - Trailing controls

    private func detailToggleButton(isOpen: Bool) -> some View {
        Button {
            toggleDetail(currentlyOpen: isOpen)
        } label: {
            Image(systemName: "chevron.down")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(isOpen || isHighlighted ? .white.opacity(0.68) : .white.opacity(0.42))
                .frame(
                    width: IslandSessionRowMetrics.detailToggleColumnWidth,
                    height: IslandSessionRowMetrics.trailingControlHeight
                )
                .background(
                    Circle()
                        .fill(.white.opacity(detailToggleFillOpacity(isOpen: isOpen)))
                )
                .rotationEffect(.degrees(isOpen ? 180 : 0))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(lang.t(isOpen ? "a11y.session.collapseDetail" : "a11y.session.expandDetail"))
    }

    private func toggleDetail(currentlyOpen: Bool) {
        guard isInteractive else { return }
        withAnimation(.easeInOut(duration: 0.2)) {
            detailOverride = !currentlyOpen
        }
    }

    private func detailToggleFillOpacity(isOpen: Bool) -> Double {
        if isHighlighted {
            return isOpen ? 0.09 : 0.07
        }
        return isOpen ? 0.055 : 0.025
    }

    private func handlePrimaryTap() {
        guard isInteractive else { return }
        actions.jump()
    }

    // MARK: - Accessibility (identical wording to Classic)

    private func accessibilityRowSummaryText(referenceDate: Date) -> String {
        lang.t(
            "a11y.session.summary",
            session.tool.displayName,
            session.spotlightWorkspaceName,
            accessibilityPhaseText,
            accessibilityElapsedText(at: referenceDate)
        )
    }

    private var accessibilityPhaseText: String {
        switch session.phase {
        case .running:
            lang.t("a11y.phase.running")
        case .waitingForApproval:
            lang.t("a11y.phase.waitingForApproval")
        case .waitingForAnswer:
            lang.t("a11y.phase.waitingForAnswer")
        case .completed:
            switch session.outcome {
            case .success: lang.t("a11y.phase.completed")
            case .interrupted: lang.t("a11y.phase.interrupted")
            case .failed: lang.t("a11y.phase.failed")
            }
        }
    }

    private func accessibilityElapsedText(at referenceDate: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale(identifier: lang.language.resolvedCode)
        formatter.unitsStyle = .full
        let reference = session.phase == .running ? session.firstSeenAt : session.islandActivityDate
        return formatter.localizedString(for: reference, relativeTo: referenceDate)
    }

    // MARK: - Text / tint helpers

    /// Activity line for a manually expanded inactive row (bypasses the
    /// time-based filter) — the row's last assistant message, or a terse
    /// "Ready"/"Completed" fallback. The T03 `.act` line uses this when
    /// `spotlightActivityLineText` has aged out but the row is force-expanded.
    private var expandedActivityLineText: String? {
        guard detailOverride == true else { return nil }
        let trimmed = session.lastAssistantMessageText?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let assistantMessage = trimmed, !assistantMessage.isEmpty {
            return assistantMessage
        }
        return session.jumpTarget != nil ? "Ready" : "Completed"
    }

    private var showsLeadingStatusIndicator: Bool {
        presentation == .list && stateIndicator != .tint && stateIndicator != .bar
    }

    private var showsLeadingStatusBar: Bool {
        presentation == .list && stateIndicator == .bar
    }

    private var rowLeadingInset: CGFloat {
        if presentation == .notification {
            return sideInset
        }
        return stateIndicator == .bar ? max(28, sideInset) : sideInset
    }

    private var detailLeadingInset: CGFloat {
        if presentation == .notification {
            return sideInset
        }
        switch stateIndicator {
        case .bar:
            return max(28, sideInset)
        case .tint:
            return sideInset
        case .animatedDot, .glyph:
            return sideInset + 30
        }
    }

    private func titleColor(for presence: IslandSessionPresence) -> Color {
        if stateIndicator == .tint && presence != .inactive {
            return statusTint(for: presence)
        }
        return presence == .inactive
            ? tokens.colors.paper.opacity(0.78)
            : tokens.colors.paper
    }

    /// AB-332: age reads at tertiary on every row (mockup `.age{color:var(--t3)}`)
    /// — the shipped presence-dependent secondary/tertiary split is retired so
    /// the right rail stays quiet and consistent.
    private func summaryAgeColor(for presence: IslandSessionPresence) -> Color {
        tokens.colors.paper.opacity(contrastText(tokens.colors.tertiaryTextOpacity))
    }

    private func contrastText(_ base: Double) -> Double {
        tokens.colors.text(base, increaseContrast: increasesContrast)
    }

    private func statusTint(for presence: IslandSessionPresence) -> Color {
        tokens.colors.statusTint(for: session.phase, presence: presence, outcome: session.outcome)
    }

    private var statusGlyphName: String {
        switch session.phase {
        case .waitingForApproval:
            "exclamationmark.triangle.fill"
        case .waitingForAnswer:
            "questionmark.circle.fill"
        case .running:
            "circle.dashed"
        case .completed:
            switch session.outcome {
            case .success: "checkmark.circle.fill"
            case .interrupted: "stop.circle.fill"
            case .failed: "xmark.circle.fill"
            }
        }
    }

    /// Poured's hover is a lighter glass tint that lifts the row (list only).
    /// `.notification` never highlights (`SessionRowContainer` never sets it
    /// there, and this guards it a second time).
    private func rowFillColor(for presence: IslandSessionPresence) -> Color {
        if presentation == .notification {
            return .clear
        }

        let base = isHighlighted ? Color.white.opacity(isActionable ? 0.07 : 0.06) : Color.clear
        guard stateIndicator == .tint else { return base }

        let tintOpacity: Double
        if isHighlighted {
            tintOpacity = isActionable ? 0.15 : 0.13
        } else {
            tintOpacity = presence == .inactive ? 0.035 : 0.08
        }
        return statusTint(for: presence).opacity(tintOpacity)
    }

    // MARK: - Small formatters

    /// Uppercases a role's copy for the consuming view (metadata keys, nest
    /// headers, assistant-message label) — the `isUppercase` treatment travels
    /// with the role in `PouredType`, applied here since a `Font` can't carry
    /// case. A no-op for CJK strings.
    private func pouredUppercased(_ text: String) -> String {
        text.uppercased()
    }

    /// §4G todo glyphs — icon+text, never colour alone (a11y): done reads as a
    /// green check (#6FB982) with the title struck through, doing as the running
    /// bars in the run tint, pending as a hollow circle at tertiary.
    @ViewBuilder
    private func taskStatusIcon(_ status: ClaudeTaskInfo.Status) -> some View {
        switch status {
        case .completed:
            Image(systemName: "checkmark")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(tokens.colors.statusCompleted)
                .accessibilityLabel(lang.t("a11y.task.completed"))
        case .inProgress:
            if let pulseClock {
                PouredPulsingStatusDot(pulseClock: pulseClock, tint: tokens.colors.statusRunning, presence: .active)
                    .frame(width: 8, height: 8)
                    .accessibilityLabel(lang.t("a11y.task.inProgress"))
            } else {
                Circle()
                    .fill(tokens.colors.statusRunning)
                    .frame(width: 7, height: 7)
                    .accessibilityLabel(lang.t("a11y.task.inProgress"))
            }
        case .pending:
            Circle()
                .strokeBorder(tokens.colors.paper.opacity(contrastText(tokens.colors.tertiaryTextOpacity)), lineWidth: 1.4)
                .frame(width: 11, height: 11)
                .accessibilityLabel(lang.t("a11y.task.pending"))
        }
    }
}

// MARK: - Poured approval hero card

/// The permission request rendered as Poured Island's hero: an amber-glow card
/// that radiates a pulsing warm glow above everything else on the glass (static
/// under Reduce Motion), a command preview in a mono block, an affected-path
/// line, an optional `PermissionDiffPreview`, and a prominent filled Allow next
/// to a quiet Deny — or the always-allow options / Codex terminal CTA.
///
/// Isolated in its own `View` so the amber glow's 15fps pulse (read off the
/// shared `PulseClock` via `PouredAmberGlow`) invalidates only the glow, and so
/// the approve / deny callbacks stay exactly the ones ⌘Y / ⌘⇧Y / ⌘N fire
/// against from `OverlayPanelController`.
private struct PouredApprovalCard: View {
    let session: AgentSession
    let lang: LanguageManager
    let actions: RowActions
    let pulseClock: PulseClock?
    var presentation: IslandSessionRowPresentation = .list

    @Environment(\.islandTokens) private var tokens
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    private var increasesContrast: Bool { colorSchemeContrast == .increased }

    /// E3: a Codex terminal-approval request can't round-trip through the bridge
    /// (the ⌘Y / ⌘⇧Y / ⌘N handler deliberately no-ops for it), so the hero drops
    /// every Approve/Deny affordance for a single honest "jump to approve" CTA and
    /// re-tints cool blue.
    private var requiresTerminalApproval: Bool {
        session.permissionRequest?.requiresTerminalApproval == true
    }

    /// The hero's accent: amber `PouredPalette.attention` for a normal request,
    /// Codex blue `#4aa3df` for the terminal-approval variant (`SPEC` §4E E1/E3).
    private var accent: Color {
        requiresTerminalApproval ? PouredApprovalColors.codexBlue : PouredPalette.attention
    }

    private var borderOpacity: Double {
        (reduceTransparency || increasesContrast) ? 0.7 : PouredPillMotion.Hero.borderOpacity
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            heroHead

            if let commandText {
                commandBlock(commandText)
            }

            if let effectText {
                Text(effectText)
                    .font(PouredType.Role.heroSubtitle.font)
                    .foregroundStyle(PouredApprovalColors.effectInk)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // AB-235 / E2: Edit/Write requests carry captured old/new text; the
            // Poured-side wrapper renders that diff with gutter line numbers and
            // Poured's del/add tints. The diff *engine* (`PermissionDiff`) is
            // reused verbatim — only the presentation is Poured-local.
            if let diffResult = permissionDiffResult {
                PouredPermissionDiff(result: diffResult, lang: lang)
            }

            if requiresTerminalApproval {
                codexNote
                terminalApprovalCTA
            } else {
                actionButtons
                alwaysAllowOptions
            }

            // E4: the shared `IslandNotificationCard` stays unchanged, so the
            // honest auto-collapse countdown is printed here, inside the hero, when
            // it renders in the notification presentation.
            if presentation == .notification {
                notificationCountdownFooter
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardFill)
        .overlay(
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .strokeBorder(accent.opacity(borderOpacity), lineWidth: PouredPillMotion.Hero.borderWidth)
        )
        .modifier(PouredAmberGlow(tint: accent, pulseClock: pulseClock))
        // The buttons carry their own labels/actions; group the surrounding
        // copy so VoiceOver reads the card, then reaches Allow / Deny.
        .accessibilityElement(children: .contain)
    }

    // MARK: Hero head

    /// The event "headline": an accent-tinted glyph chip beside the hero title,
    /// with the effect-tone subtitle when the request names one (`SPEC` §4E,
    /// mockup `.hero-head`).
    private var heroHead: some View {
        HStack(alignment: .center, spacing: 9) {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(accent.opacity(0.16))
                .frame(width: 24, height: 24)
                .overlay(
                    Image(systemName: requiresTerminalApproval ? "arrow.up.forward.app.fill" : "chevron.left.forwardslash.chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(accent)
                )
                .accessibilityHidden(true)

            Text(lang.t("approval.toolPermissionRequested"))
                .font(PouredType.Role.heroTitle.font)
                .tracking(PouredType.Role.heroTitle.spec.trackingPoints)
                .foregroundStyle(requiresTerminalApproval ? PouredApprovalColors.codexTitleInk : PouredApprovalColors.titleInk)

            Spacer(minLength: 0)
        }
    }

    // MARK: Command block (syntax spans — T10)

    /// The command awaiting approval, syntax-highlighted through the shipped
    /// `ShellCommandTokenizer` (T10 / AB-328): command `#f2f5fb`/600, subcommand
    /// `#8fd0ff`, flags `#6ea7ff`, strings `#7fd39a`, paths `#f2f5fb`@0.55; plain
    /// runs inherit the block's `#c9cedb` (`SPEC` §4E / mockup `.cmd`).
    private func commandBlock(_ command: String) -> some View {
        let highlighted = ShellCommandTokenizer.attributed(
            command,
            palette: PouredApprovalColors.syntaxPalette,
            weights: [.command: .semibold],
            baseFont: PouredType.Role.commandBlock.font
        )
        return (Text("$ ").foregroundStyle(accent.opacity(0.7)) + Text(highlighted))
            .font(PouredType.Role.commandBlock.font)
            .foregroundStyle(PouredApprovalColors.commandInk)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(reduceTransparency ? tokens.colors.surfaceInk : PouredApprovalColors.codeSurface)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(.white.opacity(0.06), lineWidth: 1)
                    )
            )
            .textSelection(.enabled)
    }

    // MARK: Buttons + keycaps

    /// `Allow once ⌘Y` (amber gradient) beside `Deny ⌘N`. The keycap glyphs are
    /// sourced from `PouredApprovalShortcut`, which mirrors the real
    /// `OverlayPanelController` handler (⌘Y / ⌘N), never the mockup's ⏎/⎋.
    private var actionButtons: some View {
        HStack(spacing: 8) {
            Button {
                actions.approve?(.allowOnce)
            } label: {
                PouredApprovalButtonLabel(
                    title: session.permissionRequest?.primaryActionTitle ?? lang.t("approval.allowOnce"),
                    shortcut: .allowOnce,
                    kind: .allow
                )
            }
            .buttonStyle(.plain)
            .accessibilityLabel(session.permissionRequest?.primaryActionTitle ?? lang.t("a11y.approval.allowOnce"))

            Button {
                actions.approve?(.deny)
            } label: {
                PouredApprovalButtonLabel(
                    title: session.permissionRequest?.secondaryActionTitle ?? lang.t("approval.deny"),
                    shortcut: .deny,
                    kind: .deny
                )
            }
            .buttonStyle(.plain)
            .accessibilityLabel(session.permissionRequest?.secondaryActionTitle ?? lang.t("a11y.approval.deny"))
        }
    }

    // MARK: Scoped always-allow rows

    /// AB-235 / E1: scoped always-allow options rendered from the request's real
    /// `suggestedUpdates` (their human `displayLabel`s), or the generic
    /// session-scoped fallback. The FIRST row carries the `⌘⇧Y` key-hint the
    /// always-allow shortcut fires. Each choice sends exactly its update — the
    /// same call `⌘⇧Y` drives.
    @ViewBuilder
    private var alwaysAllowOptions: some View {
        if let updates = session.permissionRequest?.suggestedUpdates, !updates.isEmpty {
            VStack(spacing: 1) {
                ForEach(Array(updates.enumerated()), id: \.offset) { index, update in
                    PouredScopeRow(label: update.displayLabel, showsKeycap: index == 0) {
                        actions.approve?(.allowWithUpdates([update]))
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(.white.opacity(0.05), lineWidth: 1)
            )
        } else if let toolName = session.permissionRequest?.toolName {
            VStack(spacing: 1) {
                PouredScopeRow(label: lang.t("approval.alwaysAllow", toolName), showsKeycap: true) {
                    let rule = ClaudePermissionRuleValue(toolName: toolName)
                    let update = ClaudePermissionUpdate.addRules(
                        destination: .session,
                        rules: [rule],
                        behavior: .allow
                    )
                    actions.approve?(.allowWithUpdates([update]))
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(.white.opacity(0.05), lineWidth: 1)
            )
        }
    }

    // MARK: Codex (E3)

    /// E3: the blue "approves in-app" note that makes the terminal-approval
    /// variant honest about where the decision actually happens.
    private var codexNote: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "arrow.up.forward.app")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(PouredApprovalColors.codexBlue)
                .accessibilityHidden(true)
            Text(lang.t("approval.codexApprovesInApp"))
                .font(PouredType.Role.optionDesc.font)
                .foregroundStyle(PouredApprovalColors.codexNoteInk)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(PouredApprovalColors.codexBlue.opacity(0.1))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(PouredApprovalColors.codexBlue.opacity(0.25), lineWidth: 1)
                )
        )
    }

    /// E3: the single honest CTA when `requiresTerminalApproval` is set. No
    /// keycap — the ⌘Y / ⌘⇧Y / ⌘N handler intentionally no-ops for terminal
    /// approval, so printing one would be a fake affordance.
    private var terminalApprovalCTA: some View {
        Button {
            actions.jump()
        } label: {
            HStack(spacing: 7) {
                Image(systemName: "arrow.up.forward")
                    .font(.system(size: 12, weight: .bold))
                    .accessibilityHidden(true)
                Text(terminalApprovalCTATitle)
                    .font(.system(size: 13, weight: .semibold))
            }
            .foregroundStyle(PouredApprovalColors.codexButtonInk)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [PouredApprovalColors.codexButtonTop, PouredApprovalColors.codexBlue],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
            )
        }
        .buttonStyle(.plain)
    }

    private var terminalApprovalCTATitle: String {
        session.tool == .codex ? lang.t("approval.jumpToCodex") : lang.t("approval.respondInTerminal")
    }

    // MARK: Notification footer (E4)

    /// E4: the honest auto-collapse countdown printed under the hero in the
    /// notification presentation. The value is read from the coordinator's real
    /// delay (10s), not the mockup's stale "8s".
    private var notificationCountdownFooter: some View {
        Text(lang.t("approval.autoCollapseCountdown", Int(OverlayUICoordinator.notificationSurfaceAutoCollapseDelay)))
            .font(PouredType.Role.heroSubtitle.font)
            .foregroundStyle(tokens.colors.paper.opacity(tokens.colors.text(tokens.colors.tertiaryTextOpacity, increaseContrast: increasesContrast)))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 2)
    }

    // MARK: Fill

    /// The accent wash over the frosted slab. Under Reduce Transparency the wash
    /// sits on an opaque ink base so the card never relies on the glass showing
    /// through to stay legible (AB-303).
    @ViewBuilder
    private var cardFill: some View {
        let shape = RoundedRectangle(cornerRadius: 15, style: .continuous)
        ZStack {
            if reduceTransparency {
                shape.fill(tokens.colors.surfaceInk)
                shape.fill(accent.opacity(0.22))
            } else {
                shape.fill(
                    LinearGradient(
                        colors: [accent.opacity(0.16), accent.opacity(0.08)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
            }
        }
    }

    // MARK: Content

    private var commandText: String? {
        let preview = session.currentCommandPreviewText?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let preview, !preview.isEmpty else { return nil }
        return preview
    }

    /// The plain-English effect line. Prefers the request summary; suppressed
    /// when it is empty or merely echoes the command already shown above.
    private var effectText: String? {
        let summary = (session.permissionRequest?.summary ?? session.summary)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !summary.isEmpty, summary != commandText else { return nil }
        return summary
    }

    /// Computes the diff lazily from the request's captured old/new text
    /// (AB-235). `nil` when there's nothing to diff or old/new are identical.
    private var permissionDiffResult: PermissionDiffResult? {
        guard let source = session.permissionRequest?.fileDiffSource else {
            return nil
        }
        let result = PermissionDiff.compute(oldText: source.oldText, newText: source.newText)
        return result.isEmpty ? nil : result
    }
}

/// The three approval decisions the Poured hero exposes, each paired with the
/// **real** registered `OverlayPanelController` shortcut it fires. The glyph
/// strings printed on the keycaps must stay in lock-step with that handler
/// (`⌘Y` / `⌘⇧Y` / `⌘N`), never the mockup's ⏎/⎋.
private enum PouredApprovalShortcut {
    case allowOnce
    case alwaysAllow
    case deny

    /// The key-hint glyphs printed on the keycap, in order.
    var glyphs: [String] {
        switch self {
        case .allowOnce: ["⌘", "Y"]
        case .alwaysAllow: ["⌘", "⇧", "Y"]
        case .deny: ["⌘", "N"]
        }
    }
}

/// The Poured keycap chip (`SPEC` §2 `.kc kbd` role, 10pt/600) — first keycap
/// rendering in Poured. Two visual variants: a light chip for dark buttons /
/// scope rows, an ink chip for the amber primary (so it reads on the light
/// gradient), per the mockup `.kc kbd` / `.btn.primary .kc kbd`.
private struct PouredKeycapRow: View {
    let shortcut: PouredApprovalShortcut
    var onAmber: Bool = false

    var body: some View {
        HStack(spacing: 2) {
            ForEach(Array(shortcut.glyphs.enumerated()), id: \.offset) { _, glyph in
                Text(glyph)
                    .font(PouredType.Role.keycap.font)
                    .foregroundStyle(onAmber ? PouredApprovalColors.keycapInkOnAmber : PouredApprovalColors.keycapInk)
                    .frame(minWidth: 15, minHeight: 16)
                    .padding(.horizontal, 3)
                    .background(
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(onAmber ? PouredApprovalColors.keycapFillOnAmber : PouredApprovalColors.keycapFill)
                            .overlay(
                                RoundedRectangle(cornerRadius: 4, style: .continuous)
                                    .strokeBorder(onAmber ? PouredApprovalColors.keycapStrokeOnAmber : PouredApprovalColors.keycapStroke, lineWidth: 1)
                            )
                    )
            }
        }
        .accessibilityHidden(true)
    }
}

/// The Allow / Deny button label: title + keycap, filled per its kind. Amber
/// gradient for `.allow` (`#ffce8a→#ffb14d`, ink `#3a2405`), red-wash for
/// `.deny` (`rgba(219,82,82,.14)`, text `#f0a8a8`) — `SPEC` §4E.
private struct PouredApprovalButtonLabel: View {
    enum Kind { case allow, deny }

    let title: String
    let shortcut: PouredApprovalShortcut
    let kind: Kind

    var body: some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(1)
            PouredKeycapRow(shortcut: shortcut, onAmber: kind == .allow)
        }
        .foregroundStyle(kind == .allow ? PouredApprovalColors.allowInk : PouredApprovalColors.denyInk)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(buttonBackground)
    }

    @ViewBuilder
    private var buttonBackground: some View {
        let shape = RoundedRectangle(cornerRadius: 11, style: .continuous)
        switch kind {
        case .allow:
            shape.fill(
                LinearGradient(
                    colors: [PouredApprovalColors.allowTop, PouredApprovalColors.allowBottom],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
        case .deny:
            shape.fill(PouredApprovalColors.denyFill)
        }
    }
}

/// One scoped always-allow row (mockup `.scope`): a lock glyph, the real human
/// `displayLabel`, and — on the first row — the `⌘⇧Y` key-hint.
private struct PouredScopeRow: View {
    let label: String
    let showsKeycap: Bool
    let action: () -> Void

    @Environment(\.islandTokens) private var tokens
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    private var increasesContrast: Bool { colorSchemeContrast == .increased }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(tokens.colors.paper.opacity(tokens.colors.text(tokens.colors.tertiaryTextOpacity, increaseContrast: increasesContrast)))
                    .accessibilityHidden(true)
                Text(label)
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(tokens.colors.paper.opacity(tokens.colors.text(tokens.colors.secondaryTextOpacity, increaseContrast: increasesContrast)))
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 6)
                if showsKeycap {
                    PouredKeycapRow(shortcut: .alwaysAllow)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 11)
            .padding(.vertical, 9)
            .background(Color.white.opacity(0.02))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// E2 (Poured-side): the captured Edit/Write diff rendered with gutter line
/// numbers and Poured's del/add tints. Consumes `PermissionDiffResult` straight
/// off the shared `PermissionDiff` engine — it does not fork the engine, and it
/// leaves the shared `PermissionDiffPreview` untouched (`SPEC` §4E E2).
private struct PouredPermissionDiff: View {
    let result: PermissionDiffResult
    let lang: LanguageManager

    @Environment(\.islandTokens) private var tokens
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    private static let maxRenderedLines = 500
    private static let maxHeight: CGFloat = 180

    private var renderedLines: [PermissionDiffLine] {
        Array(result.lines.prefix(Self.maxRenderedLines))
    }

    private var hiddenLineCount: Int {
        result.lines.count - renderedLines.count
    }

    /// The rendered lines paired with a running gutter number. Removed lines
    /// number against the old file, added/unchanged against the new — the
    /// familiar unified-diff gutter (`SPEC` §4E E2 "gutter line numbers").
    private var numberedLines: [(index: Int, line: PermissionDiffLine, gutter: Int)] {
        var out: [(index: Int, line: PermissionDiffLine, gutter: Int)] = []
        var oldNo = 1
        var newNo = 1
        for (index, line) in renderedLines.enumerated() {
            let gutter: Int
            switch line.kind {
            case .removed:
                gutter = oldNo
                oldNo += 1
            case .added:
                gutter = newNo
                newNo += 1
            case .unchanged:
                gutter = newNo
                oldNo += 1
                newNo += 1
            }
            out.append((index, line, gutter))
        }
        return out
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            AutoHeightScrollView(maxHeight: Self.maxHeight) {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(numberedLines, id: \.index) { entry in
                        row(entry.line, gutter: entry.gutter)
                    }

                    if hiddenLineCount > 0 {
                        Text(lang.t("approval.diffMoreLines", hiddenLineCount))
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(PouredApprovalColors.diffContextInk)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 3)
                    }
                }
                .padding(.vertical, 3)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(reduceTransparency ? tokens.colors.surfaceInk : PouredApprovalColors.codeSurface)
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(.white.opacity(0.06), lineWidth: 1)
                )
        )
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: "doc.text")
                .font(.system(size: 10, weight: .semibold))
                .accessibilityHidden(true)
            Text(lang.t("approval.diffUpdated"))
            Text("+\(result.addedCount)")
                .foregroundStyle(PouredApprovalColors.diffAddInk)
            Text("\u{2212}\(result.removedCount)")
                .foregroundStyle(PouredApprovalColors.diffDelInk)
        }
        .font(.system(size: 10.5, weight: .semibold))
        .foregroundStyle(tokens.colors.paper.opacity(0.6))
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.03))
    }

    private func row(_ line: PermissionDiffLine, gutter: Int) -> some View {
        HStack(alignment: .top, spacing: 0) {
            Text("\(gutter)")
                .frame(width: 26, alignment: .trailing)
                .padding(.trailing, 10)
                .foregroundStyle(gutterColor(line.kind))
            Text(markerPrefix(line.kind) + (line.text.isEmpty ? " " : line.text))
                .foregroundStyle(textColor(line.kind))
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(PouredType.Role.diff.font)
        .padding(.leading, 8)
        .padding(.trailing, 10)
        .padding(.vertical, 1)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(rowBackground(line.kind))
    }

    private func markerPrefix(_ kind: PermissionDiffLine.Kind) -> String {
        switch kind {
        case .added: "+ "
        case .removed: "\u{2212} "
        case .unchanged: "  "
        }
    }

    private func gutterColor(_ kind: PermissionDiffLine.Kind) -> Color {
        switch kind {
        case .added: PouredApprovalColors.diffAddGutter
        case .removed: PouredApprovalColors.diffDelGutter
        case .unchanged: PouredApprovalColors.diffContextGutter
        }
    }

    private func textColor(_ kind: PermissionDiffLine.Kind) -> Color {
        switch kind {
        case .added: PouredApprovalColors.diffAddInk
        case .removed: PouredApprovalColors.diffDelInk
        case .unchanged: PouredApprovalColors.diffContextInk
        }
    }

    private func rowBackground(_ kind: PermissionDiffLine.Kind) -> Color {
        switch kind {
        case .added: PouredApprovalColors.diffAddFill
        case .removed: PouredApprovalColors.diffDelFill
        case .unchanged: .clear
        }
    }
}

/// The Poured permission hero's literal colour palette (`SPEC` §4E / mockup
/// `01-poured-island.html`). Theme-local like `PouredPalette` — these are exact
/// hero hexes, not status tokens, so they live beside the view rather than on the
/// token layer.
private enum PouredApprovalColors {
    // Hero head / effect line
    static let titleInk = Color(red: 0xFF/255, green: 0xE6/255, blue: 0xC2/255)             // #ffe6c2
    static let codexTitleInk = Color(red: 0xCF/255, green: 0xE8/255, blue: 0xFB/255)        // #cfe8fb
    static let effectInk = Color(red: 0xFF/255, green: 0xD6/255, blue: 0xA0/255).opacity(0.75) // rgba(255,214,160,.75)

    // Command block
    static let commandInk = Color(red: 0xC9/255, green: 0xCE/255, blue: 0xDB/255)           // #c9cedb (plain runs)
    static let codeSurface = Color(red: 0x06/255, green: 0x08/255, blue: 0x0D/255).opacity(0.6) // rgba(6,8,13,.6)
    static let syntaxPalette: [ShellCommandTokenizer.Kind: Color] = [
        .command: Color(red: 0xF2/255, green: 0xF5/255, blue: 0xFB/255),                    // #f2f5fb
        .subcommand: Color(red: 0x8F/255, green: 0xD0/255, blue: 0xFF/255),                 // #8fd0ff
        .flag: Color(red: 0x6E/255, green: 0xA7/255, blue: 0xFF/255),                       // #6ea7ff
        .string: Color(red: 0x7F/255, green: 0xD3/255, blue: 0x9A/255),                     // #7fd39a
        .path: Color(red: 0xF2/255, green: 0xF5/255, blue: 0xFB/255).opacity(0.55),         // rgba(242,245,251,.55)
    ]

    // Buttons
    static let allowTop = Color(red: 0xFF/255, green: 0xCE/255, blue: 0x8A/255)             // #ffce8a
    static let allowBottom = Color(red: 0xFF/255, green: 0xB1/255, blue: 0x4D/255)          // #ffb14d
    static let allowInk = Color(red: 0x3A/255, green: 0x24/255, blue: 0x05/255)             // #3a2405
    static let denyFill = Color(red: 0xDB/255, green: 0x52/255, blue: 0x52/255).opacity(0.14) // rgba(219,82,82,.14)
    static let denyInk = Color(red: 0xF0/255, green: 0xA8/255, blue: 0xA8/255)              // #f0a8a8

    // Keycaps
    static let keycapFill = Color.black.opacity(0.28)
    static let keycapStroke = Color.white.opacity(0.14)
    static let keycapInk = Color.white.opacity(0.75)
    static let keycapFillOnAmber = Color(red: 0x3A/255, green: 0x24/255, blue: 0x05/255).opacity(0.25) // rgba(58,36,5,.25)
    static let keycapStrokeOnAmber = Color(red: 0x3A/255, green: 0x24/255, blue: 0x05/255).opacity(0.3)
    static let keycapInkOnAmber = Color(red: 0x5A/255, green: 0x3A/255, blue: 0x0C/255)     // #5a3a0c

    // Codex (E3)
    static let codexBlue = Color(red: 0x4A/255, green: 0xA3/255, blue: 0xDF/255)            // #4aa3df
    static let codexButtonTop = Color(red: 0x8F/255, green: 0xCC/255, blue: 0xF0/255)       // #8fccf0
    static let codexButtonInk = Color(red: 0x06/255, green: 0x21/255, blue: 0x33/255)       // #062133
    static let codexNoteInk = Color(red: 0xBF/255, green: 0xE0/255, blue: 0xF6/255)         // #bfe0f6

    // Diff (E2)
    static let diffDelFill = Color(red: 0xDB/255, green: 0x52/255, blue: 0x52/255).opacity(0.13) // rgba(219,82,82,.13)
    static let diffDelInk = Color(red: 0xF0/255, green: 0xB3/255, blue: 0xB3/255)           // #f0b3b3
    static let diffDelGutter = Color(red: 0xDB/255, green: 0x52/255, blue: 0x52/255).opacity(0.6)
    static let diffAddFill = Color(red: 0x6F/255, green: 0xB9/255, blue: 0x82/255).opacity(0.14) // rgba(111,185,130,.14)
    static let diffAddInk = Color(red: 0xA8/255, green: 0xE0/255, blue: 0xBB/255)           // #a8e0bb
    static let diffAddGutter = Color(red: 0x6F/255, green: 0xB9/255, blue: 0x82/255).opacity(0.7)
    static let diffContextInk = Color(red: 0xF2/255, green: 0xF5/255, blue: 0xFB/255).opacity(0.55)
    static let diffContextGutter = Color(red: 0xF2/255, green: 0xF5/255, blue: 0xFB/255).opacity(0.3)
}

/// The question hero (`.q-hero`) gold chrome (`SPEC` §4F · mockup `.q-hero`).
/// The header chip fill and selection ring live inside the shared
/// `StructuredQuestionPromptView` (token-driven, `statusWaitingForAnswer`), so
/// this table only carries the outer wash + ring the Poured wrapper adds.
private enum PouredQuestionColors {
    /// `.q-hero` gradient top — `rgba(52,44,22,.4)`.
    static let washTop = Color(red: 0x34/255, green: 0x2C/255, blue: 0x16/255).opacity(0.4)
    /// `.q-hero` gradient bottom — `rgba(26,22,12,.5)`.
    static let washBottom = Color(red: 0x1A/255, green: 0x16/255, blue: 0x0C/255).opacity(0.5)
    /// `.q-hero` inset ring — `rgba(255,213,138,.24)` (the `#ffd58a` gold at .24).
    static let ring = Color(red: 0xFF/255, green: 0xD5/255, blue: 0x8A/255).opacity(0.24)
}

/// The completion outcome badge (`.outcome`) fills (`SPEC` §4H · mockup
/// `.outcome.ok/.intr/.fail`). Text tints come from the shared status tokens
/// (`statusCompleted` / `statusWarning` / `statusFailed`); only the tinted pill
/// backgrounds are Poured-local here.
private enum PouredCompletionColors {
    /// `.outcome.ok` background — `rgba(111,185,130,.14)`.
    static let successFill = Color(red: 0x6F/255, green: 0xB9/255, blue: 0x82/255).opacity(0.14)
    /// `.outcome.intr` background — `rgba(217,140,38,.16)`.
    static let interruptedFill = Color(red: 0xD9/255, green: 0x8C/255, blue: 0x26/255).opacity(0.16)
    /// `.outcome.fail` background — `rgba(219,82,82,.16)`.
    static let failedFill = Color(red: 0xDB/255, green: 0x52/255, blue: 0x52/255).opacity(0.16)
}

/// Wraps the approval card in Poured's pulsing hero glow (`heropulse`, `SPEC`
/// §4E E1). Isolated as a modifier so the 15fps `PulseClock` read invalidates
/// only the glow (not the buttons inside), and so Reduce Motion — or a missing
/// clock — renders a static-but-still-loud glow (the wide ambient layer is
/// always present) rather than a breathing one. The tint is supplied by the
/// card (amber `attention`, or Codex blue), keeping this geometry-only.
private struct PouredAmberGlow: ViewModifier {
    let tint: Color
    let pulseClock: PulseClock?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var animates: Bool { !reduceMotion && pulseClock != nil }

    private var pulse: Double {
        animates ? (pulseClock?.phase ?? 0) : 0
    }

    func body(content: Content) -> some View {
        let hero = PouredPillMotion.Hero.self
        let ambientOpacity = hero.ambientOpacityMin + (hero.ambientOpacityMax - hero.ambientOpacityMin) * pulse
        content
            // Wide ambient "event" bloom (mockup 0 0 42px -6px), always present.
            .shadow(color: tint.opacity(ambientOpacity), radius: hero.ambientRadius)
            // Retuned breathing layers (r10+8·pulse / r20+10·pulse), retinted.
            .shadow(color: tint.opacity(hero.innerOpacityBase + pulse * hero.innerOpacityPulse),
                    radius: hero.innerRadiusBase + pulse * hero.innerRadiusPulse)
            .shadow(color: tint.opacity(hero.outerOpacityBase + pulse * hero.outerOpacityPulse),
                    radius: hero.outerRadiusBase + pulse * hero.outerRadiusPulse)
            .onAppear { if animates { pulseClock?.acquire() } }
            .onDisappear { if animates { pulseClock?.release() } }
    }
}

// MARK: - Row entrance

/// AB-332: the one-shot rise+fade a Poured row plays when it is **inserted** into
/// an already-mounted list (`PouredRowMotion.Entrance`, mockup `rowin`).
///
/// Expressed as a SwiftUI insertion `.transition` (applied per row by
/// `PouredSessionListScaffold`, driven by the scaffold's `entranceAnimation`
/// keyed to the row-id set) rather than an `onAppear` state machine. Two things
/// fall out for free: a container's **initial** appearance never plays insertion
/// transitions, so the whole list arrives at its settled frame under the panel's
/// own open-morph (and a first-render snapshot pins that settled frame); and the
/// scaffold gates the driving animation on Reduce Motion, so a reduced-motion
/// insert simply snaps in — no clock is ever touched.
enum PouredRowEntrance {
    /// Rise (`translateY`) + fade + top-anchored scale, from the mockup `rowin`
    /// keyframe. Removal is a plain fade so a dismissed row doesn't lurch.
    static var transition: AnyTransition {
        .asymmetric(
            insertion: .offset(y: PouredRowMotion.Entrance.riseOffset)
                .combined(with: .opacity)
                .combined(with: .scale(scale: PouredRowMotion.Entrance.initialScale, anchor: .top)),
            removal: .opacity
        )
    }

    /// The settle spring the scaffold drives the insertion with (nil under
    /// Reduce Motion → the insert snaps).
    static let animation: Animation = .spring(
        response: PouredRowMotion.Entrance.springResponse,
        dampingFraction: PouredRowMotion.Entrance.springDamping,
        blendDuration: 0
    )
}

// MARK: - Glow dot

/// Poured's status dot: a filled circle wrapped in a soft luminous glow so
/// status reads as light bleeding into the glass rather than a flat chip.
/// `pulse` (0…1, from the shared `PulseClock`) breathes both the scale and the
/// glow radius. A little softer/larger than Classic's dot to match the frosted
/// surface.
private func pouredStatusDotView(tint: Color, presence: IslandSessionPresence, pulse: Double) -> some View {
    Circle()
        .fill(tint)
        .frame(width: 9, height: 9)
        .scaleEffect(1 + (pulse * 0.2))
        .shadow(color: tint.opacity(presence == .inactive ? 0 : 0.42 + (pulse * 0.3)), radius: 5 + (pulse * 4))
        .shadow(color: tint.opacity(presence == .inactive ? 0 : 0.2 + (pulse * 0.16)), radius: 10 + (pulse * 5))
}

/// The breathing variant of `pouredStatusDotView`, isolated in its own `View`
/// so Observation's per-view tracking invalidates only this dot at 15fps
/// (AB-228), and so Reduce Motion never even acquires the shared clock — it
/// renders the settled (`pulse: 0`) dot instead (AB-244).
private struct PouredPulsingStatusDot: View {
    let pulseClock: PulseClock
    let tint: Color
    let presence: IslandSessionPresence

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if reduceMotion {
            pouredStatusDotView(tint: tint, presence: presence, pulse: 0)
        } else {
            pouredStatusDotView(tint: tint, presence: presence, pulse: pulseClock.phase)
                .onAppear { pulseClock.acquire() }
                .onDisappear { pulseClock.release() }
        }
    }
}

/// AB-302: attaches a named VoiceOver action only when `name` is non-nil —
/// the row's "Dismiss" rotor action, present only for dismissible rows. A
/// local copy of the same modifier Classic's row uses (that one is file-private
/// to `IslandPanelView`).
private struct PouredOptionalNamedAccessibilityAction: ViewModifier {
    let name: String?
    let action: () -> Void

    func body(content: Content) -> some View {
        if let name {
            content.accessibilityAction(named: Text(name), action)
        } else {
            content
        }
    }
}

private extension String {
    var trimmedForRow: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - Metadata cell chrome (mockup §D `.mcell`)

/// The quiet cell slab every metadata entry sits in — a faint fill with an
/// inset hairline and a floor width so the grid reads as an even lattice rather
/// than ragged pills. Isolated as a modifier so every cell (text, agent chip,
/// live timer) wears the identical frame.
private struct MetadataCellChrome: ViewModifier {
    func body(content: Content) -> some View {
        content
            .frame(minWidth: 84, alignment: .leading)
            .padding(.horizontal, 11)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(Color.white.opacity(0.025))
                    .overlay(
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .strokeBorder(.white.opacity(0.045), lineWidth: 1)
                    )
            )
    }
}

// MARK: - Jump primary CTA (mockup §D `.btn.primary`)

/// The blue-gradient primary button the §4D detail leads with. Poured-local so
/// the shared `IslandActionButtonStyle` (paper-filled) is left untouched; the
/// gradient + glow are lifted straight from the mockup's inline style.
private struct PouredJumpButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(Color(red: 0.04, green: 0.10, blue: 0.21))
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.56, green: 0.74, blue: 1.0),
                                Color(red: 0.43, green: 0.65, blue: 1.0),
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(.white.opacity(0.4), lineWidth: 1)
                            .blendMode(.overlay)
                    )
            )
            .shadow(
                color: reduceTransparency ? .clear : Color(red: 0.43, green: 0.65, blue: 1.0).opacity(0.5),
                radius: 10,
                y: 4
            )
            .opacity(configuration.isPressed ? 0.82 : 1)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
    }
}

// MARK: - Ghost secondary button (mockup §H `.btn.ghost`)

/// A calm ghost secondary (`SPEC` §4H · mockup `.btn.ghost`): a low-contrast
/// `rgba(242,245,251,.08)` fill that lifts to `.14` on hover, text at `t1`
/// (`.standard`) or `t3` (`.quiet`, e.g. Dismiss). Deliberately quiet so it never
/// competes with the amber/blue primaries.
private struct PouredGhostButtonStyle: ButtonStyle {
    enum Role { case standard, quiet }
    var role: Role = .standard

    func makeBody(configuration: Configuration) -> some View {
        // `@State` (hover) + `@Environment` (tokens / contrast) can only be read
        // from a real `View`, not the `ButtonStyle` struct — so the label is a
        // nested view.
        PouredGhostButtonLabel(role: role, configuration: configuration)
    }

    private struct PouredGhostButtonLabel: View {
        let role: Role
        let configuration: Configuration

        @Environment(\.islandTokens) private var tokens
        @Environment(\.colorSchemeContrast) private var colorSchemeContrast
        @State private var isHovering = false

        var body: some View {
            let increaseContrast = colorSchemeContrast == .increased
            let inkOpacity = role == .quiet
                ? tokens.colors.text(tokens.colors.tertiaryTextOpacity, increaseContrast: increaseContrast)
                : tokens.colors.text(0.96, increaseContrast: increaseContrast)
            configuration.label
                .foregroundStyle(tokens.colors.paper.opacity(inkOpacity))
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .fill(Color(red: 0xF2/255, green: 0xF5/255, blue: 0xFB/255)
                            .opacity(isHovering ? 0.14 : 0.08))
                )
                .opacity(configuration.isPressed ? 0.82 : 1)
                .onHover { isHovering = $0 }
        }
    }
}

// MARK: - Outcome badge (mockup §H `.outcome`)

/// The completion outcome pill (`SPEC` §4H · mockup `.outcome.ok/.intr/.fail`):
/// a glyph + label at the `outcomeBadge` role (10.5/650), the status tint on its
/// matching tinted-pill fill. State is glyph + colour, never colour alone.
private struct PouredOutcomeBadge: View {
    let glyphName: String
    let label: String
    let tint: Color
    let fill: Color

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: glyphName)
                .font(.system(size: 9, weight: .bold))
                .accessibilityHidden(true)
            Text(label)
                .font(PouredType.Role.outcomeBadge.font)
                .lineLimit(1)
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 9)
        .padding(.vertical, 3)
        .background(Capsule().fill(fill))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(label)
    }
}

// MARK: - Metadata flow layout (mockup §D `.meta-grid{flex-wrap:wrap}`)

/// A left-to-right wrapping row (`flex-wrap: wrap`) for the metadata cells: it
/// lays subviews at their ideal size, breaking to a new line when the next cell
/// would overrun the proposed width. Small and self-contained so the grid can
/// reflow at either panel width without a fixed column count.
private struct PouredFlowLayout: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        let rows = arrange(subviews: subviews, maxWidth: maxWidth)
        let width = rows.map(\.width).max() ?? 0
        let height = rows.reduce(0) { $0 + $1.height } + spacing * CGFloat(max(0, rows.count - 1))
        return CGSize(width: min(width, maxWidth), height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) {
        let rows = arrange(subviews: subviews, maxWidth: bounds.width)
        var y = bounds.minY
        for row in rows {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(
                    at: CGPoint(x: x, y: y),
                    anchor: .topLeading,
                    proposal: ProposedViewSize(size)
                )
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private struct Row {
        var indices: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func arrange(subviews: Subviews, maxWidth: CGFloat) -> [Row] {
        var rows: [Row] = []
        var current = Row()
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let addedWidth = current.indices.isEmpty ? size.width : current.width + spacing + size.width
            if !current.indices.isEmpty, addedWidth > maxWidth {
                rows.append(current)
                current = Row()
                current.indices = [index]
                current.width = size.width
                current.height = size.height
            } else {
                current.indices.append(index)
                current.width = addedWidth
                current.height = max(current.height, size.height)
            }
        }
        if !current.indices.isEmpty {
            rows.append(current)
        }
        return rows
    }
}
