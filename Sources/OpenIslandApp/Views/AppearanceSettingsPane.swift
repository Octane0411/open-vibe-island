import SwiftUI
import OpenIslandCore

/// v6 Personalization tab.
///
/// Two concerns, one preview:
/// - **Right slot** — what shows on the right of the closed island.
/// - **Center label** — what shows in the middle on external displays.
///
/// Everything else (idle behavior, per-tool agent colors, spinner, custom
/// avatars) was cut in the v6 redesign round.
struct AppearanceSettingsPane: View {
    var model: AppModel
    @State private var previewMode: UnifiedBars.Mode = .idle
    @State private var previewAutoCycle: Bool = true
    /// AB-326: which conformance scenario the session-list preview renders.
    @State private var previewScenario: AppearancePreviewScenario = .list

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    private static let autoCycleOrder: [UnifiedBars.Mode] = [.idle, .running, .waiting]
    private static let autoCycleInterval: TimeInterval = 2.0

    private var lang: LanguageManager { model.lang }

    /// AB-305: the previews render through the model's active theme's real slot
    /// components, so switching themes (Lab switch today, picker in AB-306)
    /// re-skins every preview with no per-theme preview code.
    private var theme: any IslandTheme { model.islandTheme }
    private var tokens: IslandThemeTokens { theme.tokens }
    private var editingProfile: IslandAppearanceDisplayProfile { model.appearanceSettingsProfile }
    private var editingPreferences: IslandAppearancePreferences {
        model.appearancePreferences(for: editingProfile)
    }
    private var previewLayout: V6ClosedLayout {
        editingProfile == .notch ? .macbook : .external
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 32) {
                themePart
                displayProfilePart
                notchPersonalizationPart
                sessionListPersonalizationPart
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .background(Color(red: 0.055, green: 0.055, blue: 0.06))
        .navigationTitle(lang.t("settings.tab.appearance"))
        // AB-305: inject the active theme + its tokens so every real slot
        // component in the previews (closed pill, session list, rows, usage
        // chips) resolves its look through the current selection, exactly as
        // the overlay does at its own root.
        .environment(\.islandTheme, theme)
        .environment(\.islandTokens, tokens)
    }

    // MARK: - Theme (AB-306)

    /// The real theme picker. One card per registered theme, each rendered
    /// through THAT theme's own slot views (closed pill + a short session-row
    /// snippet fed the shared fixtures) so the card previews the identity it
    /// selects. Theme is a GLOBAL choice — one product identity shared by the
    /// notch and top-bar profiles — so it sits above the per-profile display
    /// controls rather than inside them.
    private var themePart: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader(
                title: lang.t("settings.appearance.theme.title"),
                note: lang.t("settings.appearance.theme.note")
            )

            VStack(spacing: 12) {
                ForEach(ThemeRegistry.all, id: \.id) { theme in
                    themeCard(theme)
                }
            }
        }
    }

    private func themeCard(_ cardTheme: any IslandTheme) -> some View {
        let selected = model.islandThemeID == cardTheme.id
        let name = cardTheme.name(lang)
        // AC: VoiceOver reads "<theme name>, <selected/not selected>".
        let a11yLabel = "\(name), \(selected ? lang.t("settings.appearance.theme.selected") : lang.t("settings.appearance.theme.notSelected"))"

        return Button {
            // Applies to the live overlay immediately (AppModel.islandTheme is
            // derived from this) and persists to `appearance.island.v8.theme`
            // via the property's didSet.
            model.islandThemeID = cardTheme.id
        } label: {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 10) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(name)
                            .font(.system(size: 13.5, weight: .semibold))
                            .foregroundStyle(V6Palette.paper.opacity(0.94))
                        Text(cardTheme.descriptor(lang))
                            .font(.system(size: 11.5, weight: .medium))
                            .foregroundStyle(V6Palette.paper.opacity(0.5))
                            .lineLimit(2)
                    }

                    Spacer(minLength: 8)

                    if selected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(V6Palette.paper.opacity(0.92))
                    }
                }

                ThemeMiniPreview(
                    theme: cardTheme,
                    sessions: themePreviewSnippet,
                    stateIndicator: editingPreferences.sessionStateIndicator,
                    completedStaleThreshold: editingPreferences.completedStaleThreshold.seconds,
                    lang: lang
                )
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.white.opacity(selected ? 0.075 : 0.025))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(
                        selected ? V6Palette.paper.opacity(0.86) : Color.white.opacity(0.08),
                        lineWidth: selected ? 1.5 : 1
                    )
            )
        }
        .buttonStyle(.plain)
        // Collapse the preview's inner rows/pill so VoiceOver reads only the
        // card's name + selection state; the button stays keyboard-focusable
        // and Return/Space-activatable like the pane's other cards.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(a11yLabel)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }

    /// A short, shared-fixture snippet (three compact rows — running, recently
    /// completed, stale) for each theme card's mini-preview. Drawn from the same
    /// `previewSessions` fixtures the big session-list preview uses.
    private var themePreviewSnippet: [AgentSession] {
        Array(previewSessions.suffix(3))
    }

    // MARK: - Display profile

    private var displayProfilePart: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader(
                title: lang.t("settings.appearance.profile.title"),
                note: lang.t("settings.appearance.profile.note")
            )

            HStack(spacing: 12) {
                displayProfileCard(
                    .topBar,
                    icon: "display",
                    title: lang.t("settings.appearance.profile.external.title"),
                    note: lang.t("settings.appearance.profile.external.note")
                )
                displayProfileCard(
                    .notch,
                    icon: "laptopcomputer",
                    title: lang.t("settings.appearance.profile.macbook.title"),
                    note: lang.t("settings.appearance.profile.macbook.note")
                )
            }
        }
    }

    private func displayProfileCard(
        _ profile: IslandAppearanceDisplayProfile,
        icon: String,
        title: String,
        note: String
    ) -> some View {
        let selected = editingProfile == profile
        return Button {
            model.appearanceSettingsProfile = profile
        } label: {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(selected ? V6Palette.paper : V6Palette.paper.opacity(0.55))
                    .frame(width: 34, height: 34)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color.white.opacity(selected ? 0.11 : 0.05))
                    )

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(V6Palette.paper.opacity(0.94))
                    Text(note)
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(V6Palette.paper.opacity(0.42))
                        .lineLimit(2)
                }

                Spacer(minLength: 8)

                if selected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(V6Palette.paper.opacity(0.9))
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.white.opacity(selected ? 0.075 : 0.025))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(selected ? V6Palette.paper.opacity(0.86) : Color.white.opacity(0.08), lineWidth: selected ? 1.5 : 1)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Notch part

    private var notchPersonalizationPart: some View {
        VStack(alignment: .leading, spacing: 18) {
            partHeader(title: lang.t("settings.appearance.notchPart.title"))
            previewSection
            rightSlotSection
            centerLabelSection
        }
    }

    // MARK: - Session list part

    private var sessionListPersonalizationPart: some View {
        VStack(alignment: .leading, spacing: 18) {
            partHeader(title: lang.t("settings.appearance.sessionListPart.title"))
            sessionListPreviewSection
            usageDisplaySection
            stateIndicatorSection
            sessionGroupSection
            sessionSortSection
            staleThresholdSection
        }
    }

    // MARK: - Notch preview

    @ViewBuilder
    private var previewSection: some View {
        sectionHeader(title: lang.t("settings.appearance.preview"), note: nil)

        SettingsPreviewStage(contentTopPadding: 16, contentBottomPadding: 18) {
            VStack(spacing: 14) {
                previewStage
                previewControls
            }
            .padding(.horizontal, 18)
        }
    }

    private var previewStage: some View {
        let physicalNotchW: CGFloat = 180
        let pillHeight: CGFloat = 32

        return ZStack(alignment: .top) {
            if previewLayout == .macbook {
                // Physical hardware notch mock — pinned to the TOP of the
                // frame, same as the real physical cutout would sit at the
                // top of the display.
                V6ClosedPillShape()
                    .fill(Color.black)
                    .frame(width: physicalNotchW, height: pillHeight)
            }

            TimelineView(.periodic(from: .now, by: 0.25)) { context in
                IslandPreviewPill(
                    mode: previewMode,
                    label: previewLabel,
                    rightSlot: previewRightContent,
                    layout: previewLayout,
                    physicalNotchWidth: physicalNotchW,
                    now: context.date
                )
            }
        }
        .frame(height: pillHeight)
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private var previewControls: some View {
        HStack(spacing: 10) {
            // Auto-cycle toggle (default on — drives the state chips).
            monoChip(
                title: previewAutoCycle
                    ? lang.t("settings.appearance.state.auto.on")
                    : lang.t("settings.appearance.state.auto.off"),
                selected: previewAutoCycle
            ) {
                previewAutoCycle.toggle()
            }

            // Manual state chips — selecting one turns off auto-cycle.
            ForEach([UnifiedBars.Mode.idle, .running, .waiting], id: \.self) { mode in
                monoChip(title: title(for: mode), selected: !previewAutoCycle && previewMode == mode) {
                    previewAutoCycle = false
                    previewMode = mode
                }
            }

            Spacer(minLength: 0)
        }
        .task(id: previewAutoCycle) {
            await runAutoCycle()
        }
    }

    // MARK: - Session list preview

    @ViewBuilder
    private var sessionListPreviewSection: some View {
        sectionHeader(
            title: lang.t("settings.appearance.sessionPreview"),
            note: lang.t("settings.appearance.previewScenario.note")
        )

        scenarioPicker

        // AB-326: horizontal + bottom margins are the previewed theme's opened
        // shadow-inset tokens, so a large glow (e.g. Poured's 34pt bloom) is
        // reserved room inside the stage instead of being clipped.
        SettingsPreviewStage(
            contentTopPadding: 20,
            contentBottomPadding: tokens.metrics.openedShadowBottomInset
        ) {
            AppearanceSessionListPreview(
                profile: editingProfile,
                sessions: scenarioSessions,
                sections: scenarioSections,
                group: editingPreferences.sessionGroup,
                stateIndicator: editingPreferences.sessionStateIndicator,
                completedStaleThreshold: editingPreferences.completedStaleThreshold.seconds,
                actionableSessionID: scenarioContent.actionableSessionID,
                usageProviders: scenarioContent.usageProviders,
                installedAgentNames: model.installedAgentDisplayNames,
                lang: lang
            )
            .padding(.horizontal, tokens.metrics.openedShadowHorizontalInset)
        }
        .padding(.top, 8)
    }

    /// Menu picker driving the session-list preview scenario. A `.menu` `Picker`
    /// scales cleanly to the full scenario set (a chip strip would overflow) and
    /// matches the native pickers the rest of Settings uses.
    private var scenarioPicker: some View {
        HStack(spacing: 10) {
            Text(lang.t("settings.appearance.previewScenario.title").uppercased())
                .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                .tracking(1.0)
                .foregroundStyle(V6Palette.paper.opacity(0.55))

            Picker(lang.t("settings.appearance.previewScenario.title"), selection: $previewScenario) {
                ForEach(AppearancePreviewScenario.allCases) { scenario in
                    Text(title(for: scenario)).tag(scenario)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .fixedSize()
            .tint(V6Palette.paper.opacity(0.85))

            Spacer(minLength: 0)
        }
    }

    private func runAutoCycle() async {
        guard previewAutoCycle else { return }

        while !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(Int(Self.autoCycleInterval * 1_000)))
            guard !Task.isCancelled, previewAutoCycle else { return }

            let order = Self.autoCycleOrder
            let current = order.firstIndex(of: previewMode) ?? 0
            let next = order[(current + 1) % order.count]
            withAnimation(.timingCurve(0.4, 0, 0.2, 1, duration: 0.45)) {
                previewMode = next
            }
        }
    }

    // MARK: - 01 · Right slot

    @ViewBuilder
    private var rightSlotSection: some View {
        sectionHeader(
            title: lang.t("settings.appearance.rightSlot.title"),
            note: lang.t("settings.appearance.rightSlot.note")
        )

        HStack(spacing: 12) {
            rightSlotCard(.count,  icon: { CountBadgePreview(count: 3) },
                          title: lang.t("settings.appearance.rightSlot.count"))
            rightSlotCard(.agents, icon: { AgentsMiniGridPreview() },
                          title: lang.t("settings.appearance.rightSlot.agents"))
            rightSlotCard(.none,   icon: { Text("—")
                                      .font(.system(size: 14, weight: .semibold, design: .monospaced))
                                      .foregroundStyle(V6Palette.paper.opacity(0.5)) },
                          title: lang.t("settings.appearance.rightSlot.none"))
        }
    }

    private func rightSlotCard<Content: View>(
        _ option: IslandRightSlot,
        @ViewBuilder icon: () -> Content,
        title: String
    ) -> some View {
        let selected = editingPreferences.rightSlot == option
        return Button {
            model.updateAppearancePreferences(for: editingProfile) { $0.rightSlot = option }
        } label: {
            VStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.white.opacity(0.04))
                    icon()
                }
                .frame(height: 56)

                Text(title)
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.85))
            }
            .padding(12)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.white.opacity(selected ? 0.07 : 0.02))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(
                        selected ? V6Palette.paper.opacity(0.9) : Color.white.opacity(0.08),
                        lineWidth: selected ? 1.5 : 1
                    )
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - 02 · Center label

    @ViewBuilder
    private var centerLabelSection: some View {
        sectionHeader(
            title: lang.t("settings.appearance.centerLabel.title"),
            note: lang.t("settings.appearance.centerLabel.note")
        )

        HStack(spacing: 12) {
            centerLabelCard(.agentAction, sample: "Claude · editing")
            centerLabelCard(.sessionName,  sample: "open-island")
            centerLabelCard(.off,          sample: "—")
        }
    }

    private func centerLabelCard(_ option: IslandCenterLabel, sample: String) -> some View {
        let selected = editingPreferences.centerLabel == option
        let title: String = switch option {
        case .agentAction: lang.t("settings.appearance.centerLabel.agentAction")
        case .sessionName: lang.t("settings.appearance.centerLabel.sessionName")
        case .off:         lang.t("settings.appearance.centerLabel.off")
        }
        return Button {
            model.updateAppearancePreferences(for: editingProfile) { $0.centerLabel = option }
        } label: {
            VStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.white.opacity(0.04))
                    Text(sample)
                        .font(.system(size: 11.5, weight: .medium, design: .monospaced))
                        .foregroundStyle(V6Palette.paper.opacity(option == .off ? 0.4 : 0.9))
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .padding(.horizontal, 12)
                }
                .frame(height: 56)

                Text(title)
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.85))
            }
            .padding(12)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.white.opacity(selected ? 0.07 : 0.02))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(
                        selected ? V6Palette.paper.opacity(0.9) : Color.white.opacity(0.08),
                        lineWidth: selected ? 1.5 : 1
                    )
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - 02 · Usage

    @ViewBuilder
    private var usageDisplaySection: some View {
        sectionHeader(
            title: lang.t("settings.appearance.usageDisplay.title"),
            note: lang.t("settings.appearance.usageDisplay.note")
        )

        HStack(spacing: 12) {
            ForEach(IslandUsageDisplay.allCases) { option in
                optionCard(
                    selected: editingPreferences.usageDisplay == option,
                    title: title(for: option)
                ) {
                    model.updateAppearancePreferences(for: editingProfile) { $0.usageDisplay = option }
                } icon: {
                    usageDisplayIcon(option)
                }
            }
        }
    }

    /// AB-305: `.compact` renders the real `IslandUsageSummary` chips (the same
    /// component the opened header uses) with sample providers; `.hidden` shows
    /// the collapsed dash. No bespoke chip re-implementation.
    @ViewBuilder
    private func usageDisplayIcon(_ option: IslandUsageDisplay) -> some View {
        switch option {
        case .compact:
            IslandUsageSummary(providers: Self.previewUsageProviders)
                .frame(maxWidth: 104)
        case .hidden:
            Text("—")
                .font(.system(size: 14, weight: .semibold, design: .monospaced))
                .foregroundStyle(V6Palette.paper.opacity(0.5))
        }
    }

    // MARK: - 03 · Session state

    @ViewBuilder
    private var stateIndicatorSection: some View {
        sectionHeader(
            title: lang.t("settings.appearance.stateIndicator.title"),
            note: lang.t("settings.appearance.stateIndicator.note")
        )

        HStack(spacing: 12) {
            stateIndicatorCard(.animatedDot)
            stateIndicatorCard(.bar)
            stateIndicatorCard(.glyph)
            stateIndicatorCard(.tint)
        }
    }

    private func stateIndicatorCard(_ option: IslandSessionStateIndicator) -> some View {
        optionCard(
            selected: editingPreferences.sessionStateIndicator == option,
            title: title(for: option)
        ) {
            model.updateAppearancePreferences(for: editingProfile) { $0.sessionStateIndicator = option }
        } icon: {
            // AB-305: a real themed row carrying this indicator — the exact
            // styling the list uses — rather than a hand-drawn dot/bar mockup.
            AppearanceRowThumbnail(
                sessions: previewIndicatorRows,
                stateIndicator: option,
                completedStaleThreshold: editingPreferences.completedStaleThreshold.seconds,
                lang: lang
            )
        }
    }

    // MARK: - 04 · Session grouping

    @ViewBuilder
    private var sessionGroupSection: some View {
        sectionHeader(
            title: lang.t("settings.appearance.sessionGroup.title"),
            note: lang.t("settings.appearance.sessionGroup.note")
        )

        HStack(spacing: 12) {
            ForEach(IslandSessionGroup.allCases) { option in
                optionCard(
                    selected: editingPreferences.sessionGroup == option,
                    title: title(for: option)
                ) {
                    model.updateAppearancePreferences(for: editingProfile) { $0.sessionGroup = option }
                } icon: {
                    // AB-305: real rows drawn from the leading rows of the
                    // sections this grouping produces, so each option's
                    // thumbnail reflects how it actually buckets the fixtures.
                    AppearanceRowThumbnail(
                        sessions: previewGroupRows(for: option),
                        stateIndicator: editingPreferences.sessionStateIndicator,
                        completedStaleThreshold: editingPreferences.completedStaleThreshold.seconds,
                        lang: lang
                    )
                }
            }
        }
    }

    // MARK: - 05 · Session sorting

    @ViewBuilder
    private var sessionSortSection: some View {
        sectionHeader(
            title: lang.t("settings.appearance.sessionSort.title"),
            note: lang.t("settings.appearance.sessionSort.note")
        )

        HStack(spacing: 12) {
            ForEach(IslandSessionSort.allCases) { option in
                optionCard(
                    selected: editingPreferences.sessionSort == option,
                    title: title(for: option)
                ) {
                    model.updateAppearancePreferences(for: editingProfile) { $0.sessionSort = option }
                } icon: {
                    // AB-305: real rows in the order this sort produces.
                    AppearanceRowThumbnail(
                        sessions: previewSortRows(for: option),
                        stateIndicator: editingPreferences.sessionStateIndicator,
                        completedStaleThreshold: editingPreferences.completedStaleThreshold.seconds,
                        lang: lang
                    )
                }
            }
        }
    }

    // MARK: - 06 · Done timeout

    @ViewBuilder
    private var staleThresholdSection: some View {
        sectionHeader(
            title: lang.t("settings.appearance.staleThreshold.title"),
            note: lang.t("settings.appearance.staleThreshold.note")
        )

        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 104), spacing: 12)],
            alignment: .leading,
            spacing: 12
        ) {
            ForEach(IslandCompletedStaleThreshold.allCases) { option in
                optionCard(
                    selected: editingPreferences.completedStaleThreshold == option,
                    title: title(for: option)
                ) {
                    model.updateAppearancePreferences(for: editingProfile) { $0.completedStaleThreshold = option }
                } icon: {
                    Text(title(for: option))
                        .font(.system(size: 13, weight: .semibold, design: .monospaced))
                        .foregroundStyle(V6Palette.paper.opacity(0.9))
                }
            }
        }
    }

    // MARK: - Helpers

    private func partHeader(title: String) -> some View {
        Text(title)
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(.white.opacity(0.92))
    }

    private func optionCard<Icon: View>(
        selected: Bool,
        title: String,
        action: @escaping () -> Void,
        @ViewBuilder icon: () -> Icon
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.white.opacity(0.04))
                    icon()
                }
                .frame(height: 56)

                Text(title)
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.85))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .padding(12)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.white.opacity(selected ? 0.07 : 0.02))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(
                        selected ? V6Palette.paper.opacity(0.9) : Color.white.opacity(0.08),
                        lineWidth: selected ? 1.5 : 1
                    )
            )
        }
        .buttonStyle(.plain)
    }

    private func sectionHeader(title: String, note: String?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title.uppercased())
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .tracking(1.2)
                .foregroundStyle(Color.white.opacity(0.55))
            if let note {
                Text(note)
                    .font(.system(size: 11.5))
                    .foregroundStyle(Color.white.opacity(0.38))
            }
        }
    }

    private func monoChip(title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .foregroundStyle(selected ? V6Palette.ink : V6Palette.paper.opacity(0.7))
                .background(
                    Capsule().fill(
                        selected ? V6Palette.paper : Color.white.opacity(0.06)
                    )
                )
        }
        .buttonStyle(.plain)
    }

    private func title(for mode: UnifiedBars.Mode) -> String {
        switch mode {
        case .idle:    lang.t("settings.appearance.state.idle")
        case .running: lang.t("settings.appearance.state.running")
        case .waiting: lang.t("settings.appearance.state.waiting")
        }
    }

    private func title(for option: IslandSessionStateIndicator) -> String {
        switch option {
        case .animatedDot: lang.t("settings.appearance.stateIndicator.animatedDot")
        case .bar:         lang.t("settings.appearance.stateIndicator.bar")
        case .glyph:       lang.t("settings.appearance.stateIndicator.glyph")
        case .tint:        lang.t("settings.appearance.stateIndicator.tint")
        }
    }

    private func title(for option: IslandUsageDisplay) -> String {
        switch option {
        case .hidden:  lang.t("settings.appearance.usageDisplay.hidden")
        case .compact: lang.t("settings.appearance.usageDisplay.compact")
        }
    }

    private func title(for option: IslandSessionGroup) -> String {
        switch option {
        case .none:    lang.t("settings.appearance.sessionGroup.none")
        case .state:   lang.t("settings.appearance.sessionGroup.state")
        case .agent:   lang.t("settings.appearance.sessionGroup.agent")
        case .project: lang.t("settings.appearance.sessionGroup.project")
        }
    }

    private func title(for option: IslandSessionSort) -> String {
        switch option {
        case .attention:  lang.t("settings.appearance.sessionSort.attention")
        case .lastUpdate: lang.t("settings.appearance.sessionSort.lastUpdate")
        }
    }

    private func title(for scenario: AppearancePreviewScenario) -> String {
        lang.t(scenario.labelKey)
    }

    private func title(for option: IslandCompletedStaleThreshold) -> String {
        switch option {
        case .twoMinutes:    lang.t("settings.appearance.staleThreshold.twoMinutes")
        case .fiveMinutes:   lang.t("settings.appearance.staleThreshold.fiveMinutes")
        case .tenMinutes:    lang.t("settings.appearance.staleThreshold.tenMinutes")
        case .twentyMinutes: lang.t("settings.appearance.staleThreshold.twentyMinutes")
        case .never:         lang.t("settings.appearance.staleThreshold.never")
        }
    }

    private var previewAgentCells: [AgentGridCell] {
        // Three Claude sessions, with one waiting when the preview mode is
        // `waiting` so the breathing tile is visible in the live preview.
        let claude = Color(hex: AgentTool.claudeCode.brandColorHex) ?? .white
        let waitingIdx = previewMode == .waiting ? 1 : -1
        return (0..<3).map { idx in
            if idx == waitingIdx {
                return .session(color: claude, state: .waiting)
            }
            return .session(color: claude, state: .running)
        }
    }

    private var previewLabel: String? {
        // AB-241: the text lane now renders on both profiles (centered on
        // external, notch-adjacent on MacBook) — the preview mirrors
        // `AppModel.islandClosedLabel()`'s per-profile gating exactly.
        guard editingPreferences.centerLabel != .off else { return nil }
        switch (previewMode, editingPreferences.centerLabel) {
        case (.idle, _):               return nil
        case (.waiting, _):            return lang.t("settings.appearance.preview.permissionNeeded")
        case (.running, .agentAction): return lang.t("settings.appearance.preview.agentEditing")
        case (.running, .sessionName): return "open-island"
        case (.running, .off):         return nil
        }
    }

    private var previewRightContent: IslandRightSlotContent? {
        switch editingPreferences.rightSlot {
        case .none: return nil
        case .count: return .count(3)
        case .agents:
            return .agents(previewAgentCells)
        }
    }

    // MARK: - Preview fixtures (AB-305)

    /// The fixture `AgentSession`s every session-list-flavoured preview is fed.
    /// Covers one running, one needs-approval, one needs-answer, one recently
    /// completed (`done`) and one stale-completed (`idle`) session, spread
    /// across agents and projects so the agent/project groupings produce more
    /// than one section. Rebuilt against `Date.now` per read so the recent vs.
    /// stale completed rows stay on the correct side of the staleness cut.
    private var previewSessions: [AgentSession] {
        AppearancePreviewFixtures.sessions(now: .now, lang: lang)
    }

    /// The fixtures grouped + sorted through the same `IslandSessionSectioning`
    /// the live overlay uses — with the *editing* profile's preferences — so
    /// the preview can never diverge from how the real list buckets and orders.
    private var previewSections: [IslandSessionSection] {
        IslandSessionSectioning.sections(
            for: previewSessions,
            group: editingPreferences.sessionGroup,
            sort: editingPreferences.sessionSort,
            completedStaleThreshold: editingPreferences.completedStaleThreshold.seconds
        )
    }

    /// AB-326: the selected scenario's resolved preview content (sessions,
    /// actionable hero id, optional header meters). Rebuilt against `Date.now`
    /// per read for the same recent-vs-stale reason as `previewSessions`.
    private var scenarioContent: AppearancePreviewScenarioContent {
        AppearancePreviewFixtures.scenarioContent(previewScenario, now: .now, lang: lang)
    }

    /// The scenario's fixture sessions the session-list preview lists.
    private var scenarioSessions: [AgentSession] {
        scenarioContent.sessions
    }

    /// The scenario's sessions grouped + sorted through the same
    /// `IslandSessionSectioning` the live overlay uses, with the editing
    /// profile's preferences — so a scenario preview buckets exactly as the
    /// real list would.
    private var scenarioSections: [IslandSessionSection] {
        IslandSessionSectioning.sections(
            for: scenarioSessions,
            group: editingPreferences.sessionGroup,
            sort: editingPreferences.sessionSort,
            completedStaleThreshold: editingPreferences.completedStaleThreshold.seconds
        )
    }

    /// A single running fixture — the row the state-indicator thumbnails carry.
    private var previewIndicatorRows: [AgentSession] {
        Array(previewSessions.filter { $0.phase == .running }.prefix(1))
    }

    /// Leading rows of the first two sections a grouping produces, so each
    /// group option's thumbnail reflects the buckets it actually forms.
    private func previewGroupRows(for option: IslandSessionGroup) -> [AgentSession] {
        IslandSessionSectioning.sections(
            for: previewSessions,
            group: option,
            sort: editingPreferences.sessionSort,
            completedStaleThreshold: editingPreferences.completedStaleThreshold.seconds
        )
        .prefix(2)
        .compactMap(\.sessions.first)
    }

    /// The first two fixtures in the order a sort produces.
    private func previewSortRows(for option: IslandSessionSort) -> [AgentSession] {
        Array(
            IslandSessionSectioning.sortedSessions(previewSessions, sort: option).prefix(2)
        )
    }

    private static let previewUsageProviders: [UsageProviderPresentation] = [
        UsageProviderPresentation(
            id: "claude",
            title: "Claude",
            windows: [UsageWindowPresentation(id: "claude-5h", label: "5h", usedPercentage: 42, resetsAt: nil)]
        ),
        UsageProviderPresentation(
            id: "codex",
            title: "Codex",
            windows: [UsageWindowPresentation(id: "codex-7d", label: "7d", usedPercentage: 13, resetsAt: nil)]
        ),
    ]
}

// MARK: - Small preview ornaments

private struct SettingsPreviewStage<Content: View>: View {
    var contentTopPadding: CGFloat = 20
    var contentBottomPadding: CGFloat = 24
    let content: Content

    init(
        contentTopPadding: CGFloat = 20,
        contentBottomPadding: CGFloat = 24,
        @ViewBuilder content: () -> Content
    ) {
        self.contentTopPadding = contentTopPadding
        self.contentBottomPadding = contentBottomPadding
        self.content = content()
    }

    var body: some View {
        VStack(spacing: 0) {
            content
                .padding(.top, contentTopPadding)
                .padding(.bottom, contentBottomPadding)
        }
        .frame(maxWidth: .infinity)
        .background(SettingsPreviewWallpaper())
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(.white.opacity(0.08), lineWidth: 1)
        )
    }
}

private struct SettingsPreviewWallpaper: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 60.0 / 255.0, green: 35.0 / 255.0, blue: 68.0 / 255.0),
                    Color(red: 95.0 / 255.0, green: 46.0 / 255.0, blue: 88.0 / 255.0),
                    Color(red: 168.0 / 255.0, green: 81.0 / 255.0, blue: 122.0 / 255.0),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            LinearGradient(
                colors: [
                    Color.black.opacity(0.10),
                    Color.black.opacity(0.26),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }
}

private struct CountBadgePreview: View {
    let count: Int
    var body: some View {
        Text("×\(count)")
            .font(.system(size: 12, weight: .semibold, design: .monospaced))
            .foregroundStyle(V6Palette.paper.opacity(0.72))
    }
}

private struct AgentsMiniGridPreview: View {
    var body: some View {
        let claude = Color(hex: AgentTool.claudeCode.brandColorHex) ?? .white
        HStack(spacing: 2) {
            ForEach(0..<3, id: \.self) { _ in
                RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                    .fill(claude)
                    .frame(width: 8, height: 8)
            }
        }
    }
}


// MARK: - Real-component previews (AB-305)

/// The session-list preview, rendered through the active theme's real
/// `sessionList` slot inside the real opened-surface chrome (shape, vibrancy
/// base, shadow, hairline stroke) — the same components the overlay composes.
/// Fixture `AgentSession`s and pre-grouped sections are passed in; nothing here
/// re-implements a row, section header, or overview.
private struct AppearanceSessionListPreview: View {
    let profile: IslandAppearanceDisplayProfile
    let sessions: [AgentSession]
    let sections: [IslandSessionSection]
    let group: IslandSessionGroup
    let stateIndicator: IslandSessionStateIndicator
    let completedStaleThreshold: TimeInterval
    /// AB-326: the scenario's hero session. Non-`nil` promotes that row's
    /// `isActionable` path so its permission / question / completion *card*
    /// expands inside the list (a plain-list preview leaves this `nil`).
    let actionableSessionID: String?
    /// AB-326: when set (the `meters` scenario), the previewed theme's real
    /// opened header is drawn above the list, fed these fixture providers, so
    /// the usage meters render per theme. `nil` keeps the headerless list.
    let usageProviders: [UsageProviderPresentation]?
    /// AB-331: agents whose hooks are installed, forwarded to the theme's empty
    /// state so the Poured `empty` scenario shows its "Hooks installed for …"
    /// reassurance pill (hidden when none are installed).
    let installedAgentNames: [String]
    let lang: LanguageManager

    @Environment(\.islandTheme) private var theme
    @Environment(\.islandTokens) private var tokens
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    private var sideInset: CGFloat { profile == .notch ? 46 : 16 }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            panel(width: profile == .notch ? 540 : 520)
            panel(width: 500)
            panel(width: 460)
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private func panel(width: CGFloat) -> some View {
        let shape = OpenedIslandSurfaceShape(
            topProfile: profile == .notch ? .notch : .topBar,
            topCornerRadius: tokens.metrics.openedTopRadius,
            bottomCornerRadius: tokens.metrics.openedBottomRadius,
            filletRadius: tokens.metrics.filletRadius
        )
        let shadow = tokens.metrics.surfaceShadow

        return ZStack(alignment: .top) {
            OpenedSurfaceBackground(reduceTransparency: reduceTransparency || !theme.usesVibrancy)
                .clipShape(shape)
                .shadow(color: shadow.resolvedColor, radius: shadow.radius, y: shadow.yOffset)

            VStack(spacing: 0) {
                if let usageProviders {
                    // The real per-theme header slot. Non-notch-aware layout +
                    // inert control closures keep the preview simple; the top
                    // pad clears the physical notch stem on the notch profile.
                    theme.openedHeader(
                        providers: usageProviders,
                        usesNotchAwareLayout: false,
                        targetScreen: nil,
                        isSoundMuted: false,
                        lang: lang,
                        onToggleMute: {},
                        onShowSettings: {},
                        onQuit: {}
                    )
                    .padding(.top, profile == .notch ? 34 : 10)
                    .padding(.bottom, 4)

                    // AB-331: the theme's §I full-meter surface, hosted here (the
                    // `meters` scenario is the app's analog of the mockup's
                    // standalone §I frame). Only Poured returns a card; every
                    // other theme's seam is `nil`, keeping the headerless list.
                    if let meterCard = theme.usageMeterCard(providers: usageProviders, lang: lang) {
                        meterCard
                            .padding(.horizontal, sideInset)
                            .padding(.bottom, 8)
                    }
                }

                if sessions.isEmpty {
                    // Mirror the overlay: an empty session set routes to the
                    // theme's empty scaffold, not an empty list. Also exercises
                    // the AB-326 `workspaceCount` + AB-331 installed-agents seams.
                    theme.emptyState(
                        lang: lang,
                        hasRecentSessions: false,
                        workspaceCount: 0,
                        installedAgentNames: installedAgentNames
                    )
                        .frame(minHeight: 120)
                        .padding(.vertical, 12)
                } else {
                    theme.sessionList(
                        sessions: sessions,
                        sections: sections,
                        group: group,
                        stateIndicator: stateIndicator,
                        completedStaleThreshold: completedStaleThreshold,
                        sideInset: sideInset,
                        isInteractive: true,
                        actionableSessionID: actionableSessionID,
                        lang: lang,
                        keyboardCoordinator: nil,
                        pulseClock: nil,
                        makeActions: { _ in RowActions(jump: {}) }
                    )
                }
            }
            .clipShape(shape)
            .overlay {
                shape.stroke(Color.white.opacity(0.07), lineWidth: 1)
            }
        }
        .frame(width: width)
        .fixedSize(horizontal: false, vertical: true)
    }
}

/// The per-theme-card mini-preview (AB-306). Renders a closed pill and a short
/// session-row snippet through the *card's* theme — it injects that theme (and
/// its tokens) into the environment, overriding the pane-level active theme, so
/// every card shows its own identity even though they share one fixture set and
/// the real slot components (`V6ClosedPill`, `theme.sessionRow`, the opened
/// surface chrome). Nothing here is theme-specific drawing code.
private struct ThemeMiniPreview: View {
    let theme: any IslandTheme
    let sessions: [AgentSession]
    let stateIndicator: IslandSessionStateIndicator
    let completedStaleThreshold: TimeInterval
    let lang: LanguageManager

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        SettingsPreviewStage(contentTopPadding: 16, contentBottomPadding: 18) {
            VStack(spacing: 14) {
                V6ClosedPill(
                    mode: .running,
                    label: nil,
                    rightSlot: .count(sessions.count),
                    layout: .external
                )
                .frame(maxWidth: .infinity, alignment: .center)

                rowsSnippet
            }
            .padding(.horizontal, 18)
        }
        // Override the pane's active-theme injection with this card's theme so
        // the pill's tokens and the rows' slot all resolve to this identity.
        .environment(\.islandTheme, theme)
        .environment(\.islandTokens, theme.tokens)
    }

    private var rowsSnippet: some View {
        let shape = OpenedIslandSurfaceShape(
            topProfile: .topBar,
            topCornerRadius: theme.tokens.metrics.openedTopRadius,
            bottomCornerRadius: theme.tokens.metrics.openedBottomRadius,
            filletRadius: theme.tokens.metrics.filletRadius
        )
        return ViewThatFits(in: .horizontal) {
            panel(shape: shape, width: 460)
            panel(shape: shape, width: 400)
            panel(shape: shape, width: 340)
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private func panel(shape: OpenedIslandSurfaceShape, width: CGFloat) -> some View {
        ZStack(alignment: .top) {
            OpenedSurfaceBackground(reduceTransparency: reduceTransparency || !theme.usesVibrancy)
                .clipShape(shape)

            VStack(spacing: 0) {
                ForEach(sessions) { session in
                    theme.sessionRow(
                        session: session,
                        stateIndicator: stateIndicator,
                        completedStaleThreshold: completedStaleThreshold,
                        isActionable: false,
                        useDrawingGroup: false,
                        isInteractive: false,
                        isHighlighted: false,
                        presentation: .list,
                        sideInset: 16,
                        lang: lang,
                        actions: RowActions(jump: {}),
                        keyboardCoordinator: nil,
                        pulseClock: nil
                    )
                }
            }
            .clipShape(shape)
            .overlay { shape.stroke(Color.white.opacity(0.07), lineWidth: 1) }
        }
        .frame(width: width)
        .fixedSize(horizontal: false, vertical: true)
    }
}

/// A tiny option-card thumbnail that draws one or two *real* themed session
/// rows (via the active theme's `sessionRow` slot), scaled to fit and clipped.
/// Used by the state-indicator / grouping / sorting selectors so their icons
/// are the genuine row styling rather than a hand-drawn mockup.
private struct AppearanceRowThumbnail: View {
    let sessions: [AgentSession]
    let stateIndicator: IslandSessionStateIndicator
    let completedStaleThreshold: TimeInterval
    let lang: LanguageManager
    var renderWidth: CGFloat = 340

    @Environment(\.islandTheme) private var theme

    var body: some View {
        GeometryReader { geo in
            let scale = geo.size.width > 0 ? min(1, geo.size.width / renderWidth) : 1
            VStack(spacing: 0) {
                ForEach(sessions) { session in
                    theme.sessionRow(
                        session: session,
                        stateIndicator: stateIndicator,
                        completedStaleThreshold: completedStaleThreshold,
                        isActionable: false,
                        useDrawingGroup: false,
                        isInteractive: false,
                        isHighlighted: false,
                        presentation: .list,
                        sideInset: 14,
                        lang: lang,
                        actions: RowActions(jump: {}),
                        keyboardCoordinator: nil,
                        pulseClock: nil
                    )
                }
            }
            .frame(width: renderWidth, alignment: .topLeading)
            .fixedSize(horizontal: false, vertical: true)
            .scaleEffect(scale, anchor: .topLeading)
        }
        .clipped()
    }
}

// Preview session fixtures live in `AppearancePreviewFixtures.swift` (AB-326)
// so `IslandDebugScenario` can reuse the exact same payloads.
