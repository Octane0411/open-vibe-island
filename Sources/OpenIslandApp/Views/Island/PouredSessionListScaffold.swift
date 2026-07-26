import SwiftUI
import OpenIslandCore

/// Poured Island's session-list chrome (AB-301): the sessions-summary strip, the
/// section headers for all four grouping modes, the scrollable list of rows, and
/// the footer hairline.
///
/// The counting and grouping logic is identical to `IslandSessionListScaffold` —
/// the summary's total / waiting / running / done / idle tallies and the
/// per-section tint / title / count are computed the same way — so only the
/// surface treatment differs: the summary sits inside a quiet glass capsule and
/// the section headers wear a faint frosted wash so hierarchy is carried by
/// light rather than chrome, matching the rest of the poured slab.
///
/// Rows are built through the active theme's `sessionRow` factory (poured
/// returns the glass `PouredSessionRow` since AB-302), exactly as the shared
/// scaffold does.
struct PouredSessionListScaffold: View {
    /// Cap for the scrollable region — kept in sync with the shared scaffold so
    /// the opened surface's height math is identical across themes.
    private static let maxSessionListHeight: CGFloat = 560

    let sessions: [AgentSession]
    let sections: [IslandSessionSection]
    let group: IslandSessionGroup
    let stateIndicator: IslandSessionStateIndicator
    let completedStaleThreshold: TimeInterval
    let sideInset: CGFloat
    let isInteractive: Bool
    let actionableSessionID: String?
    let lang: LanguageManager
    let keyboardCoordinator: OverlayUICoordinator?
    let pulseClock: PulseClock?
    let makeActions: (AgentSession) -> RowActions

    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    private var increasesContrast: Bool { colorSchemeContrast == .increased }

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.islandTokens) private var tokens
    @Environment(\.islandTheme) private var theme

    var body: some View {
        VStack(spacing: 0) {
            TimelineView(.periodic(from: .now, by: 30)) { context in
                sessionPanelHeader(referenceDate: context.date)
            }

            AutoHeightScrollView(maxHeight: Self.maxSessionListHeight) {
                TimelineView(.periodic(from: .now, by: 30)) { _ in
                    sessionRowsContent()
                }
            }

            TimelineView(.periodic(from: .now, by: 30)) { context in
                sessionPanelFooter(referenceDate: context.date)
            }
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private func sessionRowsContent() -> some View {
        ForEach(sections) { section in
            VStack(alignment: .leading, spacing: 0) {
                if group != .none {
                    sessionSectionHeader(section)
                }

                ForEach(section.sessions) { session in
                    SessionRowContainer(isInteractive: isInteractive) { isHighlighted in
                        theme.sessionRow(
                            session: session,
                            stateIndicator: stateIndicator,
                            completedStaleThreshold: completedStaleThreshold,
                            isActionable: session.phase.requiresAttention || session.id == actionableSessionID,
                            useDrawingGroup: isInteractive,
                            isInteractive: isInteractive,
                            isHighlighted: isHighlighted,
                            presentation: .list,
                            sideInset: sideInset,
                            lang: lang,
                            actions: makeActions(session),
                            keyboardCoordinator: keyboardCoordinator,
                            pulseClock: pulseClock
                        )
                    }
                }
            }
        }
    }

    private func sessionPanelHeader(referenceDate: Date) -> some View {
        let overview = sessionOverviewItems(referenceDate: referenceDate)

        return HStack(spacing: 8) {
            Text(lang.t("island.sessionList.title").uppercased())
                // §2 `listOverviewTitle` role: SF Pro 10.5/650, tracking 0.16em
                // uppercase — the mono chrome is retired (Font can't carry
                // tracking, so it is applied here from the pinned spec).
                .font(PouredType.Role.listOverviewTitle.font)
                .tracking(PouredType.Role.listOverviewTitle.spec.trackingPoints)
                .foregroundStyle(tokens.colors.paper.opacity(0.6))

            ViewThatFits(in: .horizontal) {
                sessionOverviewView(overview, compact: false)
                sessionOverviewView(overview, compact: true)
            }

            Spacer(minLength: 0)
        }
        .padding(.leading, sideInset)
        .padding(.trailing, sideInset)
        .frame(height: 36)
        .accessibilityElement(children: .combine)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(.white.opacity(tokens.colors.hairline(increaseContrast: increasesContrast)))
                .frame(height: 1)
        }
    }

    /// The list footer (§C · mockup `.p-foot`): a leading `Grouped by <mode>`
    /// caption (only while grouping is on) and a trailing `All quiet elsewhere ·
    /// N idle` readout with a tabular count, over the retained top hairline.
    /// Together they close the list with the same "quiet confidence" the empty
    /// state carries.
    private func sessionPanelFooter(referenceDate: Date) -> some View {
        HStack(spacing: 8) {
            if let groupedByText {
                Text(groupedByText)
                    .font(.system(size: 11))
                    .foregroundStyle(tokens.colors.paper.opacity(tokens.colors.text(tokens.colors.tertiaryTextOpacity, increaseContrast: increasesContrast)))
            }

            Spacer(minLength: 0)

            Text(lang.t("island.poured.footer.idle", idleSessionCount(referenceDate: referenceDate)))
                .font(.system(size: 11).monospacedDigit())
                .foregroundStyle(tokens.colors.paper.opacity(tokens.colors.text(tokens.colors.secondaryTextOpacity, increaseContrast: increasesContrast)))
        }
        .lineLimit(1)
        .padding(.leading, sideInset)
        .padding(.trailing, sideInset)
        .padding(.vertical, 9)
        .accessibilityElement(children: .combine)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(.white.opacity(tokens.colors.hairline(increaseContrast: increasesContrast)))
                .frame(height: 1)
        }
    }

    /// The leading footer caption naming the active grouping, or `nil` when the
    /// list is ungrouped (nothing to say). Each mode is a whole localized phrase
    /// so it reads naturally in every language (CJK does not case-fold a word
    /// inserted mid-sentence).
    private var groupedByText: String? {
        switch group {
        case .none:    return nil
        case .state:   return lang.t("island.poured.footer.groupedByState")
        case .agent:   return lang.t("island.poured.footer.groupedByAgent")
        case .project: return lang.t("island.poured.footer.groupedByProject")
        }
    }

    /// Idle sessions at `referenceDate` — the same stale/inactive bucket the
    /// summary strip counts, surfaced in the footer's trailing readout.
    private func idleSessionCount(referenceDate: Date) -> Int {
        sessions.filter {
            isIdleSessionOverviewItem($0, referenceDate: referenceDate, threshold: completedStaleThreshold)
        }.count
    }

    private func sessionOverviewItems(referenceDate: Date) -> [PouredSessionOverviewItem] {
        guard !sessions.isEmpty else { return [] }

        let threshold = completedStaleThreshold
        let waiting = sessions.filter(\.phase.requiresAttention).count
        let running = sessions.filter { $0.phase == .running }.count
        let done = sessions.filter {
            $0.phase == .completed
                && !isIdleSessionOverviewItem($0, referenceDate: referenceDate, threshold: threshold)
        }.count
        let idle = sessions.filter {
            isIdleSessionOverviewItem($0, referenceDate: referenceDate, threshold: threshold)
        }.count

        return [
            PouredSessionOverviewItem(id: "total", title: lang.t("island.sessionOverview.total"), compactTitle: "", count: sessions.count, tint: nil),
            PouredSessionOverviewItem(id: "waiting", title: lang.t("island.sessionOverview.waiting"), compactTitle: lang.t("island.sessionOverview.waitingCompact"), count: waiting, tint: tokens.colors.statusWaitingAggregate),
            PouredSessionOverviewItem(id: "running", title: lang.t("island.sessionOverview.running"), compactTitle: lang.t("island.sessionOverview.runningCompact"), count: running, tint: tokens.colors.statusRunning),
            PouredSessionOverviewItem(id: "done", title: lang.t("island.sessionOverview.done"), compactTitle: lang.t("island.sessionOverview.done"), count: done, tint: tokens.colors.statusCompleted),
            PouredSessionOverviewItem(id: "idle", title: lang.t("island.sessionOverview.idle"), compactTitle: lang.t("island.sessionOverview.idle"), count: idle, tint: tokens.colors.statusIdle),
        ].filter { $0.id == "total" || $0.count > 0 }
    }

    private func isIdleSessionOverviewItem(
        _ session: AgentSession,
        referenceDate: Date,
        threshold: TimeInterval
    ) -> Bool {
        guard session.phase == .completed else { return false }
        return session.isStaleCompletedForIsland(at: referenceDate, threshold: threshold)
            || session.islandPresence(at: referenceDate) == .inactive
    }

    private func sessionOverviewView(_ items: [PouredSessionOverviewItem], compact: Bool) -> some View {
        HStack(spacing: compact ? 7 : 9) {
            ForEach(items) { item in
                sessionOverviewMetric(item, compact: compact)
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 3)
        .background(.white.opacity(reduceTransparency ? 0.1 : 0.05), in: Capsule())
        .lineLimit(1)
        .fixedSize(horizontal: true, vertical: false)
        .accessibilityElement(children: .combine)
    }

    private func sessionOverviewMetric(_ item: PouredSessionOverviewItem, compact: Bool) -> some View {
        let label = sessionOverviewMetricLabel(item, compact: compact)

        // §2 splits the bucket into a bold tabular number (`summaryNumber`
        // 12/700) and a proportional word (`summaryLabel` 11/400); the tinted
        // dot carries the status colour, so the mono chrome is retired.
        return HStack(spacing: 4) {
            if let tint = item.tint {
                Circle()
                    .fill(tint)
                    .frame(width: 5.5, height: 5.5)
                    .accessibilityHidden(true)
            }

            HStack(spacing: 3) {
                Text("\(item.count)")
                    .font(PouredType.Role.summaryNumber.font)
                    .foregroundStyle(tokens.colors.paper.opacity(tokens.colors.text(0.9, increaseContrast: increasesContrast)))

                if !label.isEmpty {
                    Text(label)
                        .font(PouredType.Role.summaryLabel.font)
                        .foregroundStyle(tokens.colors.paper.opacity(tokens.colors.text(tokens.colors.secondaryTextOpacity, increaseContrast: increasesContrast)))
                }
            }
        }
    }

    /// The bucket's word (without the count) for the current density: the
    /// `total` bucket drops its word entirely in the compact strip, leaving just
    /// the number.
    private func sessionOverviewMetricLabel(_ item: PouredSessionOverviewItem, compact: Bool) -> String {
        if item.id == "total" {
            return compact ? "" : item.title
        }
        return compact ? item.compactTitle : item.title
    }

    private func sessionSectionHeader(_ section: IslandSessionSection) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(sectionTint(for: section))
                .frame(width: 7, height: 7)
                .accessibilityHidden(true)
            Text(sessionSectionTitle(for: section).uppercased())
                // §2 `sectionHeader` role: SF Pro 10.5/650, tracking 0.09em
                // uppercase — mono retired, tracking from the pinned spec.
                .font(PouredType.Role.sectionHeader.font)
                .tracking(PouredType.Role.sectionHeader.spec.trackingPoints)
                .foregroundStyle(sectionLabelColor(for: section))
            Text("\(section.sessions.count)")
                // Drop mono, keep the digits tabular so counts line up column-wise.
                .font(.system(size: 10.5, weight: .medium).monospacedDigit())
                .foregroundStyle(tokens.colors.paper.opacity(tokens.colors.text(tokens.colors.tertiaryTextOpacity, increaseContrast: increasesContrast)))
            Spacer(minLength: 0)
        }
        .padding(.leading, sideInset)
        .padding(.trailing, sideInset)
        .padding(.top, 10)
        .padding(.bottom, 7)
        .background(sectionHeaderWash)
        .accessibilityElement(children: .combine)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(.white.opacity(tokens.colors.hairline(increaseContrast: increasesContrast)))
                .frame(height: 1)
        }
    }

    /// A top-lit wash so the section header reads as a lip in the glass rather
    /// than a painted bar. Flattens to a single low-opacity fill under Reduce
    /// Transparency.
    ///
    /// Re-tuned (AB-331) against the T11 body gradient (§1d — lighter top,
    /// darker toward the bottom): the old `0.05 → 0.012` linear never reached
    /// zero, so a uniform milky film sat over the darkening body and read as
    /// *mud*. This concentrates the light in a brighter top edge (`0.075`) and
    /// falls all the way to `0` by the header's baseline, so the lower band
    /// returns to the pure body gradient and the bright top edge reads as a
    /// raised lip catching light.
    @ViewBuilder
    private var sectionHeaderWash: some View {
        if reduceTransparency {
            Color.white.opacity(0.05)
        } else {
            LinearGradient(
                stops: [
                    .init(color: .white.opacity(0.075), location: 0.0),
                    .init(color: .white.opacity(0.02), location: 0.5),
                    .init(color: .white.opacity(0.0), location: 1.0),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }

    private func sectionTint(for section: IslandSessionSection) -> Color {
        guard let first = section.sessions.first else { return tokens.colors.statusIdle }
        if section.id == "state-idle" { return tokens.colors.statusIdle }
        return tokens.colors.statusTint(for: first.phase, outcome: first.outcome)
    }

    private func sessionSectionTitle(for section: IslandSessionSection) -> String {
        if section.title.hasPrefix("island.") {
            return lang.t(section.title)
        }
        return section.title
    }

    private func sectionLabelColor(for section: IslandSessionSection) -> Color {
        switch section.id {
        case "state-approval":
            return tokens.colors.statusWaitingForApproval.opacity(0.86)
        case "state-answer":
            return tokens.colors.statusWaitingForAnswer.opacity(0.86)
        default:
            return tokens.colors.paper.opacity(0.72)
        }
    }
}

private struct PouredSessionOverviewItem: Identifiable {
    let id: String
    let title: String
    let compactTitle: String
    let count: Int
    let tint: Color?
}
