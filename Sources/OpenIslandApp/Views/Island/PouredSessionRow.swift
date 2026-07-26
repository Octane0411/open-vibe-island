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
                    transcriptFootnote
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
            PouredApprovalCard(session: session, lang: lang, actions: actions, pulseClock: pulseClock)
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

    /// The structured question card is fully token-driven and already reads on
    /// glass, so Poured reuses it verbatim — that keeps the 1–9 / Enter keyboard
    /// wiring, multi-select toggles, freeform + quick-reply fields and submit
    /// behaviour identical to Classic (AB-303).
    private var questionActionBody: some View {
        StructuredQuestionPromptView(
            prompt: session.questionPrompt,
            lang: lang,
            keyboardCoordinator: keyboardCoordinator,
            onAnswer: { actions.answer?($0) }
        )
    }

    // MARK: - Completion action area

    /// The completion card, restyled for glass: the markdown body resolves its
    /// text / link / code colours from `.completionCard(tokens.colors)` (already
    /// token-driven, so links and code read on the frosted surface), scrolls
    /// within the same 160pt cap, and the reply input / send stay wired to
    /// `actions.reply` exactly as Classic.
    private var completionActionBody: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !completionMessageText.trimmedForRow.isEmpty {
                if session.outcome != .success {
                    completionOutcomeBanner
                }

                AutoHeightScrollView(maxHeight: 160) {
                    Markdown(completionMessageText)
                        .markdownTheme(.completionCard(tokens.colors))
                        .markdownImageProvider(.noNetwork)
                        .markdownInlineImageProvider(.noNetwork)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                }
            } else {
                completionEmptyState
            }

            if actions.reply != nil {
                Rectangle()
                    .fill(.white.opacity(0.05))
                    .frame(height: 1)

                completionReplyInput
            }
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
        // A non-success outcome always earns the expanded card — even with no
        // message body — so an interrupted/failed completion isn't silently
        // indistinguishable from a plain "Completed" row.
        session.outcome != .success
            || !completionMessageText.trimmedForRow.isEmpty
            || actions.reply != nil
    }

    private var completionDoneOpacity: Double {
        presentation == .notification ? 0.82 : 0.96
    }

    private var completionOutcomeBanner: some View {
        HStack(spacing: 6) {
            Image(systemName: completionOutcomeGlyphName)
                .font(.system(size: 10.5, weight: .bold))
                .accessibilityHidden(true)
            Text(completionOutcomeLabel)
                .font(.system(size: 11, weight: .bold))
            Spacer(minLength: 0)
        }
        .foregroundStyle(completionOutcomeTint.opacity(completionDoneOpacity))
        .padding(.horizontal, 14)
        .padding(.top, 10)
        .padding(.bottom, 4)
    }

    /// Only ever rendered from `completionOutcomeBanner`, which is gated on
    /// `session.outcome != .success` — "stop" is just the glyph for the
    /// remaining `.interrupted` case.
    private var completionOutcomeGlyphName: String {
        session.outcome == .failed ? "xmark.circle.fill" : "stop.circle.fill"
    }

    private var completionOutcomeTint: Color {
        tokens.colors.statusTint(for: .completed, outcome: session.outcome)
    }

    private var completionOutcomeLabel: String {
        switch session.outcome {
        case .success:
            lang.t("completion.done")
        case .interrupted:
            lang.t("completion.interrupted")
        case .failed:
            lang.t("completion.failed")
        }
    }

    private var completionEmptyState: some View {
        HStack {
            Text(completionOutcomeLabel)
                .font(.system(size: 11.5, weight: .bold))
                .foregroundStyle(completionOutcomeTint.opacity(completionDoneOpacity))

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
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

    @Environment(\.islandTokens) private var tokens
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    private var increasesContrast: Bool { colorSchemeContrast == .increased }

    /// The hero glow is warm amber (`statusWarning`) so the permission card
    /// reads as the loudest, warmest surface next to the cool running/done/idle
    /// rows.
    private var amber: Color { tokens.colors.statusWarning }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(lang.t("approval.toolPermissionRequested"))
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(tokens.colors.paper.opacity(contrastText(0.9)))

            VStack(alignment: .leading, spacing: 8) {
                Text(commandPreviewText)
                    .font(.system(size: 11.5, weight: .semibold, design: .monospaced))
                    .foregroundStyle(tokens.colors.paper.opacity(contrastText(0.82)))
                    .fixedSize(horizontal: false, vertical: true)

                if let path = affectedPath {
                    Text(path)
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(tokens.colors.paper.opacity(contrastText(0.5)))
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.white.opacity(0.06))
            )

            // AB-235: only for Edit/Write requests whose `tool_input` carried
            // enough to compute a diff; the shared renderer's token-driven +/−
            // colours already read on glass, within its 500-line / 180pt caps.
            if let diffResult = permissionDiffResult {
                PermissionDiffPreview(result: diffResult, lang: lang)
            }

            if session.permissionRequest?.requiresTerminalApproval == true {
                terminalApprovalCTA
            } else {
                HStack(spacing: 8) {
                    Button(session.permissionRequest?.secondaryActionTitle ?? lang.t("approval.deny")) { actions.approve?(.deny) }
                        .buttonStyle(IslandActionButtonStyle(kind: .secondary, expands: true))
                        .accessibilityLabel(session.permissionRequest?.secondaryActionTitle ?? lang.t("a11y.approval.deny"))
                    Button(session.permissionRequest?.primaryActionTitle ?? lang.t("approval.allowOnce")) { actions.approve?(.allowOnce) }
                        .buttonStyle(IslandActionButtonStyle(kind: .warning, expands: true))
                        .accessibilityLabel(session.permissionRequest?.primaryActionTitle ?? lang.t("a11y.approval.allowOnce"))
                }

                alwaysAllowOptions
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardFill)
        .overlay(
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .strokeBorder(amber.opacity(reduceTransparency ? 0.75 : 0.5), lineWidth: 1)
        )
        .modifier(PouredAmberGlow(tint: amber, pulseClock: pulseClock))
        // The buttons carry their own labels/actions; group the surrounding
        // copy so VoiceOver reads the card, then reaches Allow / Deny.
        .accessibilityElement(children: .contain)
    }

    /// A warm amber wash over the frosted slab. Under Reduce Transparency the
    /// wash sits on an opaque ink base so the card never relies on the glass
    /// showing through to stay legible (AB-303).
    @ViewBuilder
    private var cardFill: some View {
        let shape = RoundedRectangle(cornerRadius: 13, style: .continuous)
        ZStack {
            if reduceTransparency {
                shape.fill(tokens.colors.surfaceInk)
                shape.fill(amber.opacity(0.22))
            } else {
                shape.fill(amber.opacity(0.1))
            }
        }
    }

    /// AB-235: scoped always-allow options (one button per suggested update) or
    /// the generic session-scoped "Always allow <tool>" fallback. Choosing one
    /// fires `RowActions.approve(.allowWithUpdates(...))` with exactly that
    /// update — the same call ⌘⇧Y drives.
    @ViewBuilder
    private var alwaysAllowOptions: some View {
        if let updates = session.permissionRequest?.suggestedUpdates, !updates.isEmpty {
            VStack(spacing: 6) {
                ForEach(Array(updates.enumerated()), id: \.offset) { _, update in
                    Button(update.displayLabel) {
                        actions.approve?(.allowWithUpdates([update]))
                    }
                    .buttonStyle(IslandActionButtonStyle(kind: .primary, expands: true))
                }
            }
        } else if let toolName = session.permissionRequest?.toolName {
            Button(lang.t("approval.alwaysAllow", toolName)) {
                let rule = ClaudePermissionRuleValue(toolName: toolName)
                let update = ClaudePermissionUpdate.addRules(
                    destination: .session,
                    rules: [rule],
                    behavior: .allow
                )
                actions.approve?(.allowWithUpdates([update]))
            }
            .buttonStyle(IslandActionButtonStyle(kind: .primary, expands: true))
        }
    }

    /// AB-235: shown instead of Deny/Allow when `requiresTerminalApproval` is
    /// set — the decision can't be round-tripped through the bridge, so the CTA
    /// jumps to wherever the request lives (terminal pane or `codex://` URL).
    private var terminalApprovalCTA: some View {
        Button {
            actions.jump()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "arrow.up.forward.app")
                    .font(.system(size: 11, weight: .semibold))
                    .accessibilityHidden(true)
                Text(lang.t("approval.respondInTerminal"))
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(IslandActionButtonStyle(kind: .primary, expands: true))
    }

    private var affectedPath: String? {
        guard let path = session.permissionRequest?.affectedPath.trimmingCharacters(in: .whitespacesAndNewlines),
              !path.isEmpty else {
            return nil
        }
        return path
    }

    private var commandPreviewText: String {
        let preview = session.currentCommandPreviewText?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let preview, !preview.isEmpty {
            return "$ \(preview)"
        }
        return (session.permissionRequest?.summary ?? session.summary)
            .trimmingCharacters(in: .whitespacesAndNewlines)
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

    private func contrastText(_ base: Double) -> Double {
        tokens.colors.text(base, increaseContrast: increasesContrast)
    }
}

/// Wraps the approval card in Poured's pulsing amber glow. Isolated as a
/// modifier so the 15fps `PulseClock` read invalidates only the glow (not the
/// buttons inside), and so Reduce Motion — or a missing clock — renders a
/// static-but-still-loud glow rather than a breathing one (AB-303).
private struct PouredAmberGlow: ViewModifier {
    let tint: Color
    let pulseClock: PulseClock?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var animates: Bool { !reduceMotion && pulseClock != nil }

    private var pulse: Double {
        animates ? (pulseClock?.phase ?? 0) : 0
    }

    func body(content: Content) -> some View {
        content
            .shadow(color: tint.opacity(0.34 + pulse * 0.26), radius: 10 + pulse * 8)
            .shadow(color: tint.opacity(0.18 + pulse * 0.16), radius: 20 + pulse * 10)
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
