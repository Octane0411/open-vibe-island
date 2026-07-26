import SwiftUI
import OpenIslandCore

/// Flight Deck's session-list chrome (AB-312): the sessions summary as a strip of
/// **annunciator tiles** (ATTN / RUN / DONE / IDLE, each lit when its count is
/// non-zero and dark at zero), a column-caption strip (SESSION / MODEL / APP /
/// TIME) over the list, the section headers for all four grouping modes, the
/// scrollable list of rows, and a **BRIDGE LINK** footer wired to the real
/// bridge-socket state.
///
/// The counting and grouping logic is identical to `IslandSessionListScaffold` —
/// the summary's total / waiting / running / done / idle tallies and the
/// per-section tint / title / count are computed the same way — so only the
/// surface treatment differs: hierarchy is carried by lit annunciator tiles,
/// uppercase letterspaced mono captions, square status lamps and load-bearing
/// hairline rules rather than by glass or wash. Every uppercase caption routes
/// its casing and tracking through `FlightDeckText`, which neutralizes both for
/// CJK so 中文 never letterspaces into illegibility.
///
/// Rows are built through the active theme's `sessionRow` factory (the shared
/// scaffold's exact path), so the Flight Deck list inherits the theme's
/// `FlightDeckSessionRow` (AB-313): every non-actionable row carries a status
/// lane on the SESSION / MODEL / APP / TIME column grid, registered directly
/// under this strip's captions. Actionable rows still route to Classic through
/// the row's thin seam until AB-314.
struct FlightDeckSessionListScaffold: View {
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

            columnCaptionStrip

            AutoHeightScrollView(maxHeight: Self.maxSessionListHeight) {
                TimelineView(.periodic(from: .now, by: 30)) { _ in
                    sessionRowsContent()
                }
            }

            sessionPanelFooter
        }
        .padding(.vertical, 2)
        // AB-335: the opened panel body renders the FD `panel` tone (#0E1113),
        // a distinct step *lighter* than the `surfaceInk` cockpit ground the
        // shared `OpenedSurfaceBackground` fills beneath it — so the list reads
        // as a lit panel seated over the darker ground. The closed pill / ground
        // keep `surfaceInk`.
        .frame(maxWidth: .infinity)
        .background(FlightDeckSurfaces.panel)
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

    // MARK: - Annunciator summary tiles

    private func sessionPanelHeader(referenceDate: Date) -> some View {
        let tiles = annunciatorTiles(referenceDate: referenceDate)

        return HStack(spacing: 10) {
            Text(FlightDeckText.caps(lang.t("island.sessionList.title"), lang: lang))
                .font(FlightDeckTypography.microLabel)
                .tracking(FlightDeckText.tracking(1.6, lang: lang))
                .foregroundStyle(tokens.colors.paper.opacity(tokens.colors.text(0.62, increaseContrast: increasesContrast)))

            ViewThatFits(in: .horizontal) {
                annunciatorRow(tiles, compact: false)
                annunciatorRow(tiles, compact: true)
            }

            Spacer(minLength: 0)
        }
        .padding(.leading, sideInset)
        .padding(.trailing, sideInset)
        .frame(height: 40)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(annunciatorAccessibilityLabel(tiles))
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(tokens.colors.paper.opacity(tokens.colors.hairline(increaseContrast: increasesContrast)))
                .frame(height: 1)
        }
    }

    private func annunciatorRow(_ tiles: [FlightDeckAnnunciatorTile], compact: Bool) -> some View {
        HStack(spacing: compact ? 5 : 7) {
            ForEach(tiles) { tile in
                FlightDeckAnnunciatorTileView(tile: tile, compact: compact, lang: lang)
            }
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    /// The four fixed annunciator tiles. Unlike the shared / Instrument summary,
    /// which filters out zero-count states, the Flight Deck panel always renders
    /// all four — an unlit annunciator is as much a readout as a lit one — so ATTN
    /// / RUN / DONE / IDLE stay in fixed positions and simply light or go dark
    /// with their count.
    private func annunciatorTiles(referenceDate: Date) -> [FlightDeckAnnunciatorTile] {
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
            FlightDeckAnnunciatorTile(id: "attn", label: lang.t("island.flightDeck.annunciator.attn"), count: waiting, tint: tokens.colors.statusWaitingAggregate),
            FlightDeckAnnunciatorTile(id: "run", label: lang.t("island.flightDeck.annunciator.run"), count: running, tint: tokens.colors.statusRunning),
            FlightDeckAnnunciatorTile(id: "done", label: lang.t("island.flightDeck.annunciator.done"), count: done, tint: tokens.colors.statusCompleted),
            FlightDeckAnnunciatorTile(id: "idle", label: lang.t("island.flightDeck.annunciator.idle"), count: idle, tint: tokens.colors.statusIdle),
        ]
    }

    private func annunciatorAccessibilityLabel(_ tiles: [FlightDeckAnnunciatorTile]) -> String {
        let parts = tiles.map { "\($0.count) \($0.label)" }
        return "\(lang.t("island.sessionList.title")) \(parts.joined(separator: ", "))"
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

    // MARK: - Column-caption strip

    /// The SESSION / MODEL / APP / TIME column captions over the list. As of
    /// AB-313 the captions and the rows share one geometry: the SESSION caption
    /// flexes over the flexing headline, and the MODEL / APP / TIME captions sit
    /// at the exact `FlightDeckSessionRowGrid` lane widths (with the chevron and
    /// dismiss control lanes reserved as clear trailing space) so each caption
    /// lands directly over its cell across every row.
    private var columnCaptionStrip: some View {
        HStack(spacing: 8) {
            columnCaption(lang.t("island.flightDeck.column.session"))
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: FlightDeckSessionRowGrid.columnGap) {
                columnCaption(lang.t("island.flightDeck.column.model"))
                    .frame(width: FlightDeckSessionRowGrid.modelColumnWidth, alignment: .leading)
                columnCaption(lang.t("island.flightDeck.column.app"))
                    .frame(width: FlightDeckSessionRowGrid.appColumnWidth, alignment: .leading)
                columnCaption(lang.t("island.flightDeck.column.time"))
                    .frame(width: FlightDeckSessionRowGrid.timeColumnWidth, alignment: .trailing)
                // Reserve the chevron + dismiss control lanes so the TIME caption
                // registers over the row's TIME cell, which sits left of them.
                Color.clear.frame(width: FlightDeckSessionRowGrid.detailToggleColumnWidth, height: 1)
                Color.clear.frame(width: FlightDeckSessionRowGrid.dismissColumnWidth, height: 1)
            }
            .fixedSize(horizontal: true, vertical: false)
        }
        .padding(.leading, sideInset)
        .padding(.trailing, sideInset)
        .padding(.vertical, 6)
        .accessibilityHidden(true)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(tokens.colors.paper.opacity(tokens.colors.hairline(increaseContrast: increasesContrast)))
                .frame(height: 1)
        }
    }

    private func columnCaption(_ text: String) -> some View {
        Text(FlightDeckText.caps(text, lang: lang))
            .font(FlightDeckTypography.microLabel)
            .tracking(FlightDeckText.tracking(1.0, lang: lang))
            .foregroundStyle(tokens.colors.paper.opacity(tokens.colors.text(tokens.colors.tertiaryTextOpacity, increaseContrast: increasesContrast)))
            .lineLimit(1)
    }

    // MARK: - Section header

    private func sessionSectionHeader(_ section: IslandSessionSection) -> some View {
        HStack(spacing: 8) {
            Rectangle()
                .fill(sectionTint(for: section))
                .frame(width: 7, height: 7)
                .accessibilityHidden(true)
            Text(FlightDeckText.caps(sessionSectionTitle(for: section), lang: lang))
                .font(FlightDeckTypography.microLabel)
                .tracking(FlightDeckText.tracking(0.9, lang: lang))
                .foregroundStyle(sectionLabelColor(for: section))
            Text("\(section.sessions.count)")
                .font(.system(size: FlightDeckTypography.microLabelSize, weight: .medium, design: .monospaced))
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

    // MARK: - BRIDGE LINK footer

    /// The bridge-link readout, wired to the real socket state: a live square lamp
    /// and a BRIDGE LINK · LINK / NO LINK caption on the left (green nominal and
    /// blinking when the socket is up, warning red and static when it is down),
    /// the live session count on the right. The panel displays the truth of the
    /// connection, not a decorative string.
    private var sessionPanelFooter: some View {
        FlightDeckBridgeFooter(sessionCount: sessions.count, sideInset: sideInset, lang: lang)
    }
}

// MARK: - Annunciator tile

private struct FlightDeckAnnunciatorTile: Identifiable {
    let id: String
    let label: String
    let count: Int
    let tint: Color
    var isLit: Bool { count > 0 }
}

/// One annunciator tile: a square status lamp, the count, and an uppercase
/// caption, boxed in a hairline housing. Lit tiles light their lamp and raise
/// their text; dark tiles seat a dim lamp and drop their text into the ground —
/// an unlit annunciator is still a readout. A lit lamp is now self-lit phosphor
/// (AB-336): it bleeds a static halo outside its square via the shared
/// `phosphorGlow` primitive so the summary strip reads as a bank of self-lit
/// annunciators. The glow is static (a count readout, not a live lamp), so
/// there is nothing to animate and Reduce Motion is a no-op here.
private struct FlightDeckAnnunciatorTileView: View {
    let tile: FlightDeckAnnunciatorTile
    let compact: Bool
    let lang: LanguageManager

    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    private var increasesContrast: Bool { colorSchemeContrast == .increased }

    @Environment(\.islandTokens) private var tokens

    private var lampColor: Color {
        tile.isLit ? tile.tint : tokens.colors.statusIdle.opacity(0.5)
    }

    private var countColor: Color {
        tile.isLit
            ? tokens.colors.paper.opacity(tokens.colors.text(0.85, increaseContrast: increasesContrast))
            : tokens.colors.paper.opacity(tokens.colors.text(tile.count == 0 ? tokens.colors.tertiaryTextOpacity : tokens.colors.secondaryTextOpacity, increaseContrast: increasesContrast))
    }

    private var labelColor: Color {
        tokens.colors.paper.opacity(
            tokens.colors.text(
                tile.isLit ? tokens.colors.secondaryTextOpacity : tokens.colors.tertiaryTextOpacity,
                increaseContrast: increasesContrast
            )
        )
    }

    var body: some View {
        HStack(spacing: 5) {
            Rectangle()
                .fill(lampColor)
                .frame(width: 6, height: 6)
                // A lit annunciator bleeds a phosphor halo outside its square; a
                // dark one casts nothing (intensity 0).
                .phosphorGlow(
                    shape: Rectangle(),
                    tint: tile.tint,
                    radius: FlightDeckMotion.Breathe.glowRadiusMin,
                    intensity: tile.isLit ? 0.55 : 0
                )
                .accessibilityHidden(true)

            Text("\(tile.count)")
                .font(.system(size: FlightDeckTypography.countSize, weight: .bold, design: .monospaced))
                .foregroundStyle(countColor)

            Text(FlightDeckText.caps(tile.label, lang: lang))
                .font(FlightDeckTypography.microLabel)
                .tracking(FlightDeckText.tracking(0.8, lang: lang))
                .foregroundStyle(labelColor)
        }
        .padding(.horizontal, compact ? 5 : 7)
        .padding(.vertical, 4)
        // AB-335: annunciator tiles seat on the FD `tile` sub-panel tone
        // (#101519), one step above the panel body, framed by a tier-2 bezel
        // that brightens under Increase Contrast. Lit vs dark is carried by the
        // lamp and text, not a wash of the fill.
        .background(
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(FlightDeckSurfaces.tile)
                .overlay(
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .strokeBorder(
                            FlightDeckSurfaces.hairline(tier: 2, increaseContrast: increasesContrast),
                            lineWidth: 1
                        )
                )
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(tile.count) \(tile.label)")
    }
}

// MARK: - Bridge-link footer

/// The footer that reads the live bridge-socket state from the environment and
/// draws it as an avionics link light: a blinking green lamp and a LINK caption
/// when the socket is up, a static red lamp and NO LINK when it is down. The
/// blink is disabled under Reduce Motion (the lamp holds steady lit), and the
/// caption's casing / tracking neutralize for CJK.
private struct FlightDeckBridgeFooter: View {
    let sessionCount: Int
    let sideInset: CGFloat
    let lang: LanguageManager

    @Environment(\.islandBridgeIsLive) private var bridgeIsLive
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    private var increasesContrast: Bool { colorSchemeContrast == .increased }
    @Environment(\.islandTokens) private var tokens

    private var linkColor: Color {
        bridgeIsLive ? tokens.colors.statusRunning : tokens.colors.statusFailed
    }

    var body: some View {
        HStack(spacing: 7) {
            FlightDeckLinkLamp(color: linkColor, isLive: bridgeIsLive)

            Text(FlightDeckText.caps(lang.t("island.flightDeck.footer.bridgeLink"), lang: lang))
                .font(FlightDeckTypography.microLabel)
                .tracking(FlightDeckText.tracking(1.2, lang: lang))
                .foregroundStyle(tokens.colors.paper.opacity(tokens.colors.text(tokens.colors.secondaryTextOpacity, increaseContrast: increasesContrast)))

            Text(FlightDeckText.caps(
                lang.t(bridgeIsLive ? "island.flightDeck.footer.link" : "island.flightDeck.footer.noLink"),
                lang: lang
            ))
            .font(FlightDeckTypography.microLabel)
            .tracking(FlightDeckText.tracking(1.0, lang: lang))
            .foregroundStyle(linkColor)

            Spacer(minLength: 0)

            Text(FlightDeckText.caps(lang.t("island.flightDeck.footer.sessions", sessionCount), lang: lang))
                .font(FlightDeckTypography.microLabel)
                .tracking(FlightDeckText.tracking(0.8, lang: lang))
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

/// The footer's live link lamp: a self-lit status square that blinks while the
/// bridge is up, and holds a steady square when the link is down or under Reduce
/// Motion. A phosphor halo (AB-336, the shared primitive) bleeds outside the
/// square and tracks the blink so the link lamp reads as a lit annunciator, not a
/// flat swatch; a down link holds a steady dim halo.
private struct FlightDeckLinkLamp: View {
    let color: Color
    let isLive: Bool

    @State private var blink = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var lampOpacity: Double {
        isLive && !reduceMotion ? (blink ? 1 : 0.4) : (isLive ? 1 : 0.85)
    }

    /// The halo tracks the blink (bright at the lit peak, dim at the trough); a
    /// down link keeps a steady low halo.
    private var glowIntensity: Double {
        isLive && !reduceMotion ? (blink ? 0.6 : 0.25) : (isLive ? 0.55 : 0.35)
    }

    var body: some View {
        Rectangle()
            .fill(color)
            .frame(width: 6, height: 6)
            .opacity(lampOpacity)
            .phosphorGlow(
                shape: Rectangle(),
                tint: color,
                radius: FlightDeckMotion.Breathe.glowRadiusMin,
                intensity: glowIntensity
            )
            .onAppear {
                guard isLive, !reduceMotion else { return }
                withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                    blink = true
                }
            }
            .accessibilityHidden(true)
    }
}
