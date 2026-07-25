import SwiftUI
import OpenIslandCore

/// Annual's session-list chrome (AB-316): the sessions summary as a **large light
/// hero numeral** (the total) over **small-caps state labels with counts**
/// (waiting / running / done / idle, each shown only when non-zero), the section
/// headers for all four grouping modes as **hairline-ruled small-caps lines**, the
/// scrollable list of rows, and a **quiet footer**.
///
/// The counting and grouping logic is identical to `IslandSessionListScaffold` —
/// the summary's waiting / running / done / idle tallies and the per-section
/// title / count are computed the same way — so only the surface treatment
/// differs: hierarchy is carried by the type scale (the oversized numeral), case
/// (small-caps eyebrows) and the 1px / 2px hairline rules rather than by glass,
/// wash or pills. Accent discipline holds: the summary's hero numeral and the
/// calm state counts draw in warm paper, and the accent appears only on genuine
/// attention — a non-zero waiting count, an approval / answer section header.
/// Every small-caps label routes its casing and tracking through `AnnualText`,
/// which neutralizes both for CJK so 中文 renders naturally.
///
/// Rows are built through the active theme's `sessionRow` factory (the shared
/// scaffold's exact path), so the Annual list reuses Classic's flat row until
/// AB-317 typesets the editorial rows.
struct AnnualSessionListScaffold: View {
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

    // MARK: - Sessions summary (hero numeral + small-caps state counts)

    private func sessionPanelHeader(referenceDate: Date) -> some View {
        let states = stateCounts(referenceDate: referenceDate)

        return HStack(alignment: .center, spacing: 18) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("\(sessions.count)")
                    .font(AnnualTypography.numeral)
                    .foregroundStyle(tokens.colors.paper.opacity(tokens.colors.text(0.92, increaseContrast: increasesContrast)))
                Text(AnnualText.lower(lang.t("island.sessionList.title"), lang: lang))
                    .font(AnnualTypography.smallCapsLabel)
                    .tracking(AnnualText.tracking(1.2, lang: lang))
                    .foregroundStyle(tokens.colors.paper.opacity(tokens.colors.text(tokens.colors.secondaryTextOpacity, increaseContrast: increasesContrast)))
            }

            ViewThatFits(in: .horizontal) {
                stateCountRow(states, spacing: 14)
                stateCountRow(states, spacing: 9)
            }

            Spacer(minLength: 0)
        }
        .padding(.leading, sideInset)
        .padding(.trailing, sideInset)
        .padding(.vertical, 10)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(summaryAccessibilityLabel(states))
        // The load-bearing 2px emphasis rule separates the summary from the list.
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(tokens.colors.paper.opacity(tokens.colors.hairline(increaseContrast: increasesContrast)))
                .frame(height: AnnualHairline.rule)
        }
    }

    private func stateCountRow(_ states: [AnnualStateCount], spacing: CGFloat) -> some View {
        HStack(spacing: spacing) {
            ForEach(states) { state in
                HStack(spacing: 4) {
                    Text("\(state.count)")
                        .font(.system(size: AnnualTypography.countSize, weight: .regular, design: .monospaced))
                        .foregroundStyle(state.countColor(tokens: tokens, increaseContrast: increasesContrast))
                    Text(AnnualText.lower(state.label, lang: lang))
                        .font(AnnualTypography.smallCaps)
                        .tracking(AnnualText.tracking(0.6, lang: lang))
                        .foregroundStyle(tokens.colors.paper.opacity(tokens.colors.text(tokens.colors.secondaryTextOpacity, increaseContrast: increasesContrast)))
                }
            }
        }
        .lineLimit(1)
        .fixedSize(horizontal: true, vertical: false)
    }

    /// The waiting / running / done / idle tallies, computed exactly as the shared
    /// scaffold does, kept only where non-zero. Waiting is the one attention state
    /// and carries the accent; the rest are calm warm greys.
    private func stateCounts(referenceDate: Date) -> [AnnualStateCount] {
        guard !sessions.isEmpty else { return [] }

        let threshold = completedStaleThreshold
        let waiting = sessions.filter(\.phase.requiresAttention).count
        let running = sessions.filter { $0.phase == .running }.count
        let done = sessions.filter {
            $0.phase == .completed
                && !isIdleSession($0, referenceDate: referenceDate, threshold: threshold)
        }.count
        let idle = sessions.filter {
            isIdleSession($0, referenceDate: referenceDate, threshold: threshold)
        }.count

        return [
            AnnualStateCount(id: "waiting", label: lang.t("island.sessionOverview.waiting"), count: waiting, isAttention: true),
            AnnualStateCount(id: "running", label: lang.t("island.sessionOverview.running"), count: running, isAttention: false),
            AnnualStateCount(id: "done", label: lang.t("island.sessionOverview.done"), count: done, isAttention: false),
            AnnualStateCount(id: "idle", label: lang.t("island.sessionOverview.idle"), count: idle, isAttention: false),
        ].filter { $0.count > 0 }
    }

    private func summaryAccessibilityLabel(_ states: [AnnualStateCount]) -> String {
        let parts = states.map { "\($0.count) \($0.label)" }
        let prefix = "\(sessions.count) \(lang.t("island.sessionList.title"))"
        return parts.isEmpty ? prefix : "\(prefix), \(parts.joined(separator: ", "))"
    }

    private func isIdleSession(
        _ session: AgentSession,
        referenceDate: Date,
        threshold: TimeInterval
    ) -> Bool {
        guard session.phase == .completed else { return false }
        return session.isStaleCompletedForIsland(at: referenceDate, threshold: threshold)
            || session.islandPresence(at: referenceDate) == .inactive
    }

    // MARK: - Section header (hairline-ruled small-caps line)

    private func sessionSectionHeader(_ section: IslandSessionSection) -> some View {
        HStack(spacing: 8) {
            Text(AnnualText.lower(sessionSectionTitle(for: section), lang: lang))
                .font(AnnualTypography.smallCaps)
                .tracking(AnnualText.tracking(0.9, lang: lang))
                .foregroundStyle(sectionLabelColor(for: section))
            Text("\(section.sessions.count)")
                .font(.system(size: AnnualTypography.microLabelSize, weight: .regular, design: .monospaced))
                .foregroundStyle(tokens.colors.paper.opacity(tokens.colors.text(tokens.colors.tertiaryTextOpacity, increaseContrast: increasesContrast)))
            Spacer(minLength: 0)
        }
        .padding(.leading, sideInset)
        .padding(.trailing, sideInset)
        .padding(.top, 10)
        .padding(.bottom, 7)
        .accessibilityElement(children: .combine)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(tokens.colors.paper.opacity(tokens.colors.hairline(increaseContrast: increasesContrast)))
                .frame(height: AnnualHairline.hairline)
        }
    }

    private func sessionSectionTitle(for section: IslandSessionSection) -> String {
        if section.title.hasPrefix("island.") {
            return lang.t(section.title)
        }
        return section.title
    }

    /// Attention sections (a permission request, a pending question) spend the
    /// accent on their small-caps title; every calm section is warm paper — the
    /// accent-discipline guarantee at the section level.
    private func sectionLabelColor(for section: IslandSessionSection) -> Color {
        switch section.id {
        case "state-approval", "state-answer":
            return IslandColorTokens.annualAccent
        default:
            return tokens.colors.paper.opacity(tokens.colors.text(0.72, increaseContrast: increasesContrast))
        }
    }

    // MARK: - Quiet footer

    /// A quiet footer: a single hairline rule closing the list, no readout, no
    /// chrome — the editorial page ends on a rule, not a status bar.
    private var sessionPanelFooter: some View {
        Color.clear
            .frame(height: 10)
            .overlay(alignment: .top) {
                Rectangle()
                    .fill(tokens.colors.paper.opacity(tokens.colors.hairline(increaseContrast: increasesContrast)))
                    .frame(height: AnnualHairline.hairline)
            }
    }
}

// MARK: - State count model

private struct AnnualStateCount: Identifiable {
    let id: String
    let label: String
    let count: Int
    let isAttention: Bool

    func countColor(tokens: IslandThemeTokens, increaseContrast: Bool) -> Color {
        isAttention
            ? IslandColorTokens.annualAccent
            : tokens.colors.paper.opacity(tokens.colors.text(0.85, increaseContrast: increaseContrast))
    }
}
