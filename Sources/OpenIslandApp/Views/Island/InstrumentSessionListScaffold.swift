import SwiftUI
import OpenIslandCore

/// Instrument's session-list chrome (AB-308): the sessions-summary strip as an
/// uppercase micro-label state-distribution, the section headers for all four
/// grouping modes, the scrollable list of rows, and a status-line footer wired to
/// the live session count.
///
/// The counting and grouping logic is identical to `IslandSessionListScaffold` —
/// the summary's total / waiting / running / done / idle tallies and the
/// per-section tint / title / count are computed the same way — so only the
/// surface treatment differs: hierarchy is carried by uppercase letterspaced mono
/// captions, square status ticks and load-bearing hairline rules rather than by
/// glass or wash. Every uppercase caption routes its casing and tracking through
/// `InstrumentText`, which neutralizes both for CJK so 中文 never letterspaces
/// into illegibility (AB-308 §5).
///
/// Rows are built through the active theme's `sessionRow` factory (the shared
/// scaffold's exact path), so the instrument list inherits whatever row the
/// theme supplies — Classic's flat row for the instrument shell until AB-309
/// restyles the rows themselves.
struct InstrumentSessionListScaffold: View {
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

            sessionPanelFooter
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

    // MARK: - Summary strip

    private func sessionPanelHeader(referenceDate: Date) -> some View {
        let overview = sessionOverviewItems(referenceDate: referenceDate)

        return HStack(spacing: 10) {
            Text(InstrumentText.caps(lang.t("island.sessionList.title"), lang: lang))
                .font(InstrumentTypography.microLabel)
                .tracking(InstrumentText.tracking(1.6, lang: lang))
                .foregroundStyle(tokens.colors.paper.opacity(tokens.colors.text(0.62, increaseContrast: increasesContrast)))

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
                .fill(tokens.colors.paper.opacity(tokens.colors.hairline(increaseContrast: increasesContrast)))
                .frame(height: 1)
        }
    }

    /// The state-distribution strip: total, then each non-empty state as a
    /// `[■] N LABEL` cell with a square status tick, uppercase mono caption and
    /// count.
    private func sessionOverviewView(_ items: [InstrumentSessionOverviewItem], compact: Bool) -> some View {
        HStack(spacing: compact ? 9 : 12) {
            ForEach(items) { item in
                sessionOverviewMetric(item, compact: compact)
            }
        }
        .lineLimit(1)
        .fixedSize(horizontal: true, vertical: false)
        .accessibilityElement(children: .combine)
    }

    private func sessionOverviewMetric(_ item: InstrumentSessionOverviewItem, compact: Bool) -> some View {
        HStack(spacing: 5) {
            if let tint = item.tint {
                Rectangle()
                    .fill(tint)
                    .frame(width: 6, height: 6)
                    .accessibilityHidden(true)
            }

            Text("\(item.count)")
                .font(.system(size: InstrumentTypography.countSize, weight: .bold, design: .monospaced))
                .foregroundStyle(tokens.colors.paper.opacity(tokens.colors.text(0.82, increaseContrast: increasesContrast)))

            Text(sessionOverviewMetricCaption(item, compact: compact))
                .font(InstrumentTypography.microLabel)
                .tracking(InstrumentText.tracking(0.8, lang: lang))
                .foregroundStyle(
                    tokens.colors.paper.opacity(
                        tokens.colors.text(
                            item.tint == nil ? tokens.colors.tertiaryTextOpacity : tokens.colors.secondaryTextOpacity,
                            increaseContrast: increasesContrast
                        )
                    )
                )
        }
    }

    private func sessionOverviewMetricCaption(_ item: InstrumentSessionOverviewItem, compact: Bool) -> String {
        InstrumentText.caps(compact ? item.compactTitle : item.title, lang: lang)
    }

    private func sessionOverviewItems(referenceDate: Date) -> [InstrumentSessionOverviewItem] {
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
            InstrumentSessionOverviewItem(id: "total", title: lang.t("island.sessionOverview.total"), compactTitle: lang.t("island.sessionOverview.total"), count: sessions.count, tint: nil),
            InstrumentSessionOverviewItem(id: "waiting", title: lang.t("island.sessionOverview.waiting"), compactTitle: lang.t("island.sessionOverview.waitingCompact"), count: waiting, tint: tokens.colors.statusWaitingAggregate),
            InstrumentSessionOverviewItem(id: "running", title: lang.t("island.sessionOverview.running"), compactTitle: lang.t("island.sessionOverview.runningCompact"), count: running, tint: tokens.colors.statusRunning),
            InstrumentSessionOverviewItem(id: "done", title: lang.t("island.sessionOverview.done"), compactTitle: lang.t("island.sessionOverview.done"), count: done, tint: tokens.colors.statusCompleted),
            InstrumentSessionOverviewItem(id: "idle", title: lang.t("island.sessionOverview.idle"), compactTitle: lang.t("island.sessionOverview.idle"), count: idle, tint: tokens.colors.statusIdle),
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

    // MARK: - Section header

    private func sessionSectionHeader(_ section: IslandSessionSection) -> some View {
        HStack(spacing: 8) {
            Rectangle()
                .fill(sectionTint(for: section))
                .frame(width: 7, height: 7)
                .accessibilityHidden(true)
            Text(InstrumentText.caps(sessionSectionTitle(for: section), lang: lang))
                .font(InstrumentTypography.microLabel)
                .tracking(InstrumentText.tracking(0.9, lang: lang))
                .foregroundStyle(sectionLabelColor(for: section))
            Text("\(section.sessions.count)")
                .font(.system(size: InstrumentTypography.microLabelSize, weight: .medium, design: .monospaced))
                .foregroundStyle(tokens.colors.paper.opacity(tokens.colors.text(tokens.colors.tertiaryTextOpacity, increaseContrast: increasesContrast)))
            Spacer(minLength: 0)
        }
        .padding(.leading, sideInset)
        .padding(.trailing, sideInset)
        .padding(.top, 10)
        .padding(.bottom, 7)
        .background(tokens.colors.paper.opacity(increasesContrast ? 0.03 : 0.012))
        .accessibilityElement(children: .combine)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(tokens.colors.paper.opacity(tokens.colors.hairline(increaseContrast: increasesContrast)))
                .frame(height: 1)
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
            return tokens.colors.statusWaitingForApproval.opacity(0.9)
        case "state-answer":
            return tokens.colors.statusWaitingForAnswer.opacity(0.9)
        default:
            return tokens.colors.paper.opacity(tokens.colors.text(0.72, increaseContrast: increasesContrast))
        }
    }

    // MARK: - Status-line footer

    /// A bridge/status line in the instrument idiom, wired to real state: a live
    /// square tick and a MONITORING / STANDBY readout on the left, the live
    /// session count on the right. STANDBY (dim) when the list is empty, else the
    /// green MONITORING with the running count reflected in the tick.
    private var sessionPanelFooter: some View {
        let isMonitoring = !sessions.isEmpty
        let statusColor = isMonitoring ? tokens.colors.statusRunning : tokens.colors.statusIdle

        return HStack(spacing: 7) {
            InstrumentStatusTick(color: statusColor, isLive: isMonitoring)

            Text(InstrumentText.caps(
                lang.t(isMonitoring ? "island.instrument.footer.monitoring" : "island.instrument.footer.standby"),
                lang: lang
            ))
            .font(InstrumentTypography.microLabel)
            .tracking(InstrumentText.tracking(1.2, lang: lang))
            .foregroundStyle(tokens.colors.paper.opacity(tokens.colors.text(tokens.colors.secondaryTextOpacity, increaseContrast: increasesContrast)))

            Spacer(minLength: 0)

            Text(InstrumentText.caps(lang.t("island.instrument.footer.sessions", sessions.count), lang: lang))
                .font(InstrumentTypography.microLabel)
                .tracking(InstrumentText.tracking(0.8, lang: lang))
                .foregroundStyle(tokens.colors.paper.opacity(tokens.colors.text(tokens.colors.tertiaryTextOpacity, increaseContrast: increasesContrast)))
        }
        .padding(.leading, sideInset)
        .padding(.trailing, sideInset)
        .frame(height: 26)
        .accessibilityElement(children: .combine)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(tokens.colors.paper.opacity(tokens.colors.hairline(increaseContrast: increasesContrast)))
                .frame(height: 1)
        }
    }
}

/// The footer's live square tick: a flat status square that blinks while
/// monitoring, and holds a steady square when idle or under Reduce Motion.
private struct InstrumentStatusTick: View {
    let color: Color
    let isLive: Bool

    @State private var blink = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Rectangle()
            .fill(color)
            .frame(width: 6, height: 6)
            .opacity(isLive && !reduceMotion ? (blink ? 1 : 0.4) : (isLive ? 1 : 0.7))
            .onAppear {
                guard isLive, !reduceMotion else { return }
                withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                    blink = true
                }
            }
            .accessibilityHidden(true)
    }
}

private struct InstrumentSessionOverviewItem: Identifiable {
    let id: String
    let title: String
    let compactTitle: String
    let count: Int
    let tint: Color?
}
