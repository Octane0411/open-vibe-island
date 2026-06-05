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

    private static let autoCycleOrder: [UnifiedBars.Mode] = [.idle, .running, .waiting]
    private static let autoCycleInterval: TimeInterval = 2.0

    private var lang: LanguageManager { model.lang }
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
                if model.menuBarStatusItemEnabled {
                    MenuBarNotApplicableNote(lang: lang)
                }
                displayProfilePart
                    .disabled(model.menuBarStatusItemEnabled)
                    .opacity(model.menuBarStatusItemEnabled ? 0.45 : 1)
                notchPersonalizationPart
                    .disabled(model.menuBarStatusItemEnabled)
                    .opacity(model.menuBarStatusItemEnabled ? 0.45 : 1)
                sessionListPersonalizationPart
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .background(Color(red: 0.055, green: 0.055, blue: 0.06))
        .navigationTitle(lang.t("settings.tab.appearance"))
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
        sectionHeader(title: lang.t("settings.appearance.sessionPreview"), note: nil)

        SettingsPreviewStage(contentTopPadding: 20, contentBottomPadding: 28) {
            SessionListPanelPreview(
                sections: previewSessionSections,
                showsSections: editingPreferences.sessionGroup != .none,
                indicator: editingPreferences.sessionStateIndicator,
                profile: editingProfile,
                lang: lang
            )
            .padding(.horizontal, 18)
        }
        .padding(.top, 8)
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
                    UsageDisplayPreview(option: option)
                }
            }
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
            StateIndicatorPreview(option: option)
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
                    SessionGroupPreview(option: option)
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
                    SessionSortPreview(option: option)
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
        guard previewLayout == .external,
              editingPreferences.centerLabel != .off else { return nil }
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

    private var previewSessionSections: [AppearanceSessionPreviewSection] {
        let items = sortedPreviewSessionItems

        switch editingPreferences.sessionGroup {
        case .none:
            return [
                AppearanceSessionPreviewSection(
                    id: "all",
                    title: lang.t("settings.appearance.sessionGroup.none"),
                    items: items
                )
            ]
        case .state:
            let groups: [(String, String, (AppearanceSessionPreviewItem) -> Bool)] = [
                ("approval", lang.t("island.section.needsApproval"), { $0.phase == .approval }),
                ("answer", lang.t("island.section.needsAnswer"), { $0.phase == .answer }),
                ("running", lang.t("island.section.inProgress"), { $0.phase == .running }),
                ("done", lang.t("island.section.justDone"), { $0.phase == .done }),
                ("idle", lang.t("island.section.idle"), { $0.phase == .idle }),
            ]
            return groups.compactMap { id, title, include in
                let groupItems = items.filter(include)
                guard !groupItems.isEmpty else { return nil }
                return AppearanceSessionPreviewSection(id: id, title: title, items: groupItems)
            }
        case .agent:
            let groups = ["Codex", "Claude", "Cursor", "Gemini"]
            return groups.compactMap { agent in
                let groupItems = items.filter { $0.agent == agent }
                guard !groupItems.isEmpty else { return nil }
                return AppearanceSessionPreviewSection(id: agent, title: agent, items: groupItems)
            }
        case .project:
            let groups = ["open-island", "website", "docs"]
            return groups.compactMap { project in
                let groupItems = items.filter { $0.project == project }
                guard !groupItems.isEmpty else { return nil }
                return AppearanceSessionPreviewSection(id: project, title: project, items: groupItems)
            }
        }
    }

    private var sortedPreviewSessionItems: [AppearanceSessionPreviewItem] {
        switch editingPreferences.sessionSort {
        case .attention:
            return previewSessionItems.sorted { lhs, rhs in
                if lhs.attentionRank == rhs.attentionRank {
                    return lhs.updatedRank < rhs.updatedRank
                }
                return lhs.attentionRank < rhs.attentionRank
            }
        case .lastUpdate:
            return previewSessionItems.sorted { $0.updatedRank < $1.updatedRank }
        }
    }

    private var previewSessionItems: [AppearanceSessionPreviewItem] {
        [
            .init(
                id: "approval",
                title: "Codex · open-island",
                detail: lang.t("settings.appearance.preview.approveShellCommand"),
                agent: "Codex",
                agentShort: "codex",
                agentColor: Color(hex: AgentTool.codex.brandColorHex) ?? Color(red: 0.55, green: 0.72, blue: 1.0),
                project: "open-island",
                branch: "v8-design",
                prompt: lang.t("settings.appearance.preview.promptImplementPlan"),
                terminal: "Ghostty",
                age: "now",
                phase: .approval,
                attentionRank: 0,
                updatedRank: 2
            ),
            .init(
                id: "answer",
                title: "Claude · open-island",
                detail: lang.t("settings.appearance.preview.waitingForAnswer"),
                agent: "Claude",
                agentShort: "claude",
                agentColor: Color(hex: AgentTool.claudeCode.brandColorHex) ?? Color(red: 0.9, green: 0.55, blue: 0.34),
                project: "open-island",
                branch: "main",
                prompt: lang.t("settings.appearance.preview.promptChooseNotificationCopy"),
                terminal: "Ghostty",
                age: "1m",
                phase: .answer,
                attentionRank: 1,
                updatedRank: 3
            ),
            .init(
                id: "running",
                title: "Cursor · website",
                detail: lang.t("settings.appearance.preview.editingSessionListPreview"),
                agent: "Cursor",
                agentShort: "cursor",
                agentColor: Color(hex: AgentTool.cursor.brandColorHex) ?? Color(red: 0.62, green: 0.66, blue: 1.0),
                project: "website",
                branch: "main",
                prompt: lang.t("settings.appearance.preview.promptTightenSettingsUI"),
                terminal: "Cursor",
                age: "2m",
                phase: .running,
                attentionRank: 2,
                updatedRank: 0
            ),
            .init(
                id: "done",
                title: "Gemini · docs",
                detail: lang.t("settings.appearance.preview.replyAvailable"),
                agent: "Gemini",
                agentShort: "gemini",
                agentColor: Color(hex: AgentTool.geminiCLI.brandColorHex) ?? Color(red: 0.45, green: 0.78, blue: 1.0),
                project: "docs",
                branch: "main",
                prompt: lang.t("settings.appearance.preview.promptSummarizeDesignBundle"),
                terminal: "WezTerm",
                age: title(for: editingPreferences.completedStaleThreshold),
                phase: .done,
                attentionRank: 3,
                updatedRank: 1
            ),
            .init(
                id: "idle",
                title: "Codex · open-island",
                detail: lang.t("settings.appearance.preview.completedEarlier"),
                agent: "Codex",
                agentShort: "codex",
                agentColor: Color(hex: AgentTool.codex.brandColorHex) ?? Color(red: 0.55, green: 0.72, blue: 1.0),
                project: "open-island",
                branch: nil,
                prompt: nil,
                terminal: "Ghostty",
                age: lang.t("island.sessionOverview.idle"),
                phase: .idle,
                attentionRank: 4,
                updatedRank: 4
            ),
        ]
    }
}

// MARK: - Small preview ornaments

private struct AppearanceSessionPreviewSection: Identifiable {
    let id: String
    let title: String
    let items: [AppearanceSessionPreviewItem]
}

private struct AppearanceSessionPreviewItem: Identifiable {
    enum Phase {
        case approval
        case answer
        case running
        case done
        case idle
    }

    let id: String
    let title: String
    let detail: String
    let agent: String
    let agentShort: String
    let agentColor: Color
    let project: String
    let branch: String?
    let prompt: String?
    let terminal: String
    let age: String
    let phase: Phase
    let attentionRank: Int
    let updatedRank: Int
}

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

private struct SessionListPanelPreview: View {
    let sections: [AppearanceSessionPreviewSection]
    let showsSections: Bool
    let indicator: IslandSessionStateIndicator
    let profile: IslandAppearanceDisplayProfile
    let lang: LanguageManager

    private var items: [AppearanceSessionPreviewItem] {
        sections.flatMap(\.items)
    }

    private var waitingCount: Int {
        items.filter { $0.phase == .approval || $0.phase == .answer }.count
    }

    private var runningCount: Int {
        items.filter { $0.phase == .running }.count
    }

    private var doneCount: Int {
        items.filter { $0.phase == .done }.count
    }

    private var idleCount: Int {
        items.filter { $0.phase == .idle }.count
    }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            panel(width: preferredPanelWidth)
            panel(width: 500)
            panel(width: 460)
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private var preferredPanelWidth: CGFloat {
        profile == .notch ? 540 : 520
    }

    private func panel(width: CGFloat) -> some View {
        ZStack(alignment: .top) {
            surfaceShape
                .fill(V6Palette.ink)
                .shadow(color: .black.opacity(0.36), radius: 22, y: 12)

            VStack(spacing: 0) {
                panelHead
                listBody
                panelFoot
            }
            .clipShape(surfaceShape)
        }
        .frame(width: width)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var surfaceShape: OpenedIslandSurfaceShape {
        OpenedIslandSurfaceShape(topProfile: profile == .notch ? .notch : .topBar)
    }

    private var sideInset: CGFloat {
        profile == .notch ? 46 : 16
    }

    private var panelHead: some View {
        HStack(spacing: 8) {
            UnifiedBars(mode: .waiting, size: 22)
                .frame(width: 24, height: 24)

            Text(lang.t("island.sessionList.title").uppercased())
                .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                .tracking(1.4)
                .foregroundStyle(V6Palette.paper.opacity(0.55))

            ViewThatFits(in: .horizontal) {
                previewSessionOverview(compact: false)
                previewSessionOverview(compact: true)
            }

            Spacer(minLength: 0)

            previewHeaderButton(systemName: "gearshape.fill")
        }
        .padding(.leading, sideInset)
        .padding(.trailing, sideInset)
        .frame(height: 42)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(.white.opacity(0.05))
                .frame(height: 1)
        }
    }

    private func previewHeaderButton(systemName: String) -> some View {
        Image(systemName: systemName)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(.white.opacity(0.62))
            .frame(width: 22, height: 22)
            .background(.white.opacity(0.08), in: Circle())
    }

    private func previewSessionOverview(compact: Bool) -> some View {
        HStack(spacing: compact ? 7 : 9) {
            previewSessionOverviewMetric(
                count: items.count,
                title: lang.t("island.sessionOverview.total"),
                compactTitle: "",
                tint: nil,
                compact: compact
            )
            if waitingCount > 0 {
                previewSessionOverviewMetric(
                    count: waitingCount,
                    title: lang.t("island.sessionOverview.waiting"),
                    compactTitle: lang.t("island.sessionOverview.waitingCompact"),
                    tint: IslandDesignPalette.Status.waitingAggregate,
                    compact: compact
                )
            }
            if runningCount > 0 {
                previewSessionOverviewMetric(
                    count: runningCount,
                    title: lang.t("island.sessionOverview.running"),
                    compactTitle: lang.t("island.sessionOverview.runningCompact"),
                    tint: IslandDesignPalette.Status.running,
                    compact: compact
                )
            }
            if doneCount > 0 {
                previewSessionOverviewMetric(
                    count: doneCount,
                    title: lang.t("island.sessionOverview.done"),
                    compactTitle: lang.t("island.sessionOverview.done"),
                    tint: IslandDesignPalette.Status.completed,
                    compact: compact
                )
            }
            if idleCount > 0 {
                previewSessionOverviewMetric(
                    count: idleCount,
                    title: lang.t("island.sessionOverview.idle"),
                    compactTitle: lang.t("island.sessionOverview.idle"),
                    tint: IslandDesignPalette.Status.idle,
                    compact: compact
                )
            }
        }
        .lineLimit(1)
        .fixedSize(horizontal: true, vertical: false)
    }

    private func previewSessionOverviewMetric(
        count: Int,
        title: String,
        compactTitle: String,
        tint: Color?,
        compact: Bool
    ) -> some View {
        HStack(spacing: 4) {
            if let tint {
                Circle()
                    .fill(tint)
                    .frame(width: 5.5, height: 5.5)
            }

            let label = title == "total"
                ? (compact ? "\(count)" : "\(count) \(title)")
                : "\(count) \(compact ? compactTitle : title)"

            Text(label)
                .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                .foregroundStyle(tint == nil ? V6Palette.paper.opacity(0.34) : V6Palette.paper.opacity(0.48))
        }
    }

    private var listBody: some View {
        VStack(spacing: 0) {
            ForEach(sections) { section in
                if showsSections {
                    sectionHeader(section)
                }

                ForEach(section.items) { item in
                    SessionListLivePreviewRow(
                        item: item,
                        indicator: indicator,
                        sideInset: sideInset,
                        lang: lang
                    )
                }
            }
        }
    }

    private func sectionHeader(_ section: AppearanceSessionPreviewSection) -> some View {
        HStack(spacing: 8) {
            sectionDot(for: section)
            Text(section.title.uppercased())
                .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                .tracking(0.4)
                .foregroundStyle(V6Palette.paper.opacity(0.7))
            Text("\(section.items.count)")
                .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                .foregroundStyle(V6Palette.paper.opacity(0.4))
            Spacer(minLength: 0)
        }
        .padding(.leading, sideInset)
        .padding(.trailing, sideInset)
        .padding(.top, 9)
        .padding(.bottom, 6)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(.white.opacity(0.05))
                .frame(height: 1)
        }
    }

    @ViewBuilder
    private func sectionDot(for section: AppearanceSessionPreviewSection) -> some View {
        Circle()
            .fill(section.items.first?.phase.tint ?? V6Palette.paper.opacity(0.35))
            .frame(width: 7, height: 7)
    }

    private var panelFoot: some View {
        Color.clear
            .frame(height: 10)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(.white.opacity(0.05))
                .frame(height: 1)
        }
    }
}

private struct SessionListLivePreviewRow: View {
    let item: AppearanceSessionPreviewItem
    let indicator: IslandSessionStateIndicator
    let sideInset: CGFloat
    let lang: LanguageManager

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 10) {
                if indicator != .tint {
                    indicatorView
                }

                VStack(alignment: .leading, spacing: 3) {
                    titleLine

                    if let prompt = item.prompt {
                        Text(prompt)
                            .font(.system(size: 11.5, weight: .medium))
                            .foregroundStyle(V6Palette.paper.opacity(item.phase == .idle ? 0.34 : 0.52))
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 10)

                HStack(spacing: 6) {
                    agentChip
                    sideBadge(item.terminal)
                    Text(item.age)
                        .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                        .foregroundStyle(V6Palette.paper.opacity(item.phase == .idle ? 0.32 : 0.45))
                        .frame(minWidth: 30, alignment: .trailing)

                    Image(systemName: item.phase == .idle ? "chevron.right" : "chevron.down")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(V6Palette.paper.opacity(item.phase == .idle ? 0.42 : 0.68))
                        .frame(width: 28, height: 28)
                        .background(
                            Circle()
                                .fill(.white.opacity(item.phase == .idle ? 0.02 : 0.045))
                        )
                }
            }
            .padding(.horizontal, rowLeadingPadding)
            .padding(.vertical, 11)
            .background(rowFill)

            if item.phase != .idle {
                detailPreview
            }
        }
        .overlay(alignment: .top) {
            Rectangle()
                .fill(.white.opacity(0.04))
                .frame(height: 1)
        }
        .overlay(alignment: .leading) {
            if indicator == .bar {
                RoundedRectangle(cornerRadius: 999, style: .continuous)
                    .fill(tint)
                    .frame(width: 3)
                    .padding(.vertical, 8)
                    .padding(.leading, 14)
            }
        }
        .opacity(item.phase == .idle ? 0.74 : 1)
    }

    private var titleLine: some View {
        HStack(spacing: 0) {
            Text(item.project)
                .fontWeight(.semibold)
                .foregroundStyle(projectColor)
            if let branch = item.branch {
                Text(" (\(branch))")
                    .foregroundStyle(V6Palette.paper.opacity(0.55))
            }
            Text(" · ")
                .foregroundStyle(V6Palette.paper.opacity(0.22))
            Text(item.detail)
                .foregroundStyle(V6Palette.paper.opacity(0.7))
        }
        .font(.system(size: 13, weight: .medium))
        .lineLimit(1)
    }

    private var agentChip: some View {
        Text(item.agentShort)
            .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
            .foregroundStyle(item.agentColor)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(item.agentColor.opacity(0.13), in: Capsule())
            .overlay(Capsule().stroke(item.agentColor.opacity(0.35), lineWidth: 1))
    }

    private func sideBadge(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10.5, weight: .medium, design: .monospaced))
            .foregroundStyle(V6Palette.paper.opacity(0.7))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(.white.opacity(0.06), in: Capsule())
    }

    private var detailPreview: some View {
        VStack(alignment: .leading, spacing: 7) {
            switch item.phase {
            case .approval:
                Text(lang.t("approval.toolPermissionRequested"))
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(V6Palette.paper.opacity(0.86))
                Text(lang.t("settings.appearance.preview.permissionBody"))
                    .font(.system(size: 11.5, weight: .semibold, design: .monospaced))
                    .foregroundStyle(V6Palette.paper.opacity(0.78))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            case .answer:
                Text(lang.t("settings.appearance.preview.pickOrTypeAnswer"))
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(V6Palette.paper.opacity(0.82))
            case .running:
                Text(item.detail)
                    .font(.system(size: 11.5, weight: .semibold, design: .monospaced))
                    .foregroundStyle(V6Palette.paper.opacity(0.78))
            case .done:
                Text(lang.t("settings.appearance.preview.replyAvailable"))
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(V6Palette.paper.opacity(0.82))
            case .idle:
                EmptyView()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.leading, detailLeadingPadding)
        .padding(.trailing, sideInset)
        .padding(.bottom, 12)
        .background(.white.opacity(0.015))
    }

    @ViewBuilder
    private var indicatorView: some View {
        switch indicator {
        case .animatedDot:
            Circle()
                .fill(tint)
                .frame(width: 9, height: 9)
                .shadow(color: tint.opacity(item.phase == .idle ? 0 : 0.44), radius: 5)
                .frame(width: 20, height: 20)
        case .bar:
            EmptyView()
        case .glyph:
            glyphView
                .frame(width: 20, height: 20)
        case .tint:
            EmptyView()
        }
    }

    private var rowFill: Color {
        guard indicator == .tint else { return Color.clear }
        return tint.opacity(item.phase == .idle ? 0.015 : 0.045)
    }

    @ViewBuilder
    private var glyphView: some View {
        switch item.phase {
        case .idle:
            Circle()
                .fill(V6Palette.paper.opacity(0.3))
                .frame(width: 4, height: 4)
        case .running:
            UnifiedBars(mode: .running, size: 16, tint: tint)
        case .approval, .answer:
            UnifiedBars(mode: .waiting, size: 16, tint: tint)
        case .done:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(tint)
        }
    }

    private var projectColor: Color {
        indicator == .tint && item.phase != .idle ? tint : V6Palette.paper.opacity(item.phase == .idle ? 0.72 : 0.92)
    }

    private var tint: Color {
        item.phase.tint
    }

    private var rowLeadingPadding: CGFloat {
        switch indicator {
        case .bar: max(28, sideInset)
        case .tint: sideInset
        case .animatedDot, .glyph: sideInset
        }
    }

    private var detailLeadingPadding: CGFloat {
        switch indicator {
        case .bar: max(28, sideInset)
        case .tint: sideInset
        case .animatedDot, .glyph: sideInset + 30
        }
    }
}

private extension AppearanceSessionPreviewItem.Phase {
    var tint: Color {
        switch self {
        case .approval:
            IslandDesignPalette.Status.waitingForApproval
        case .answer:
            IslandDesignPalette.Status.waitingForAnswer
        case .running:
            IslandDesignPalette.Status.running
        case .done:
            IslandDesignPalette.Status.completed
        case .idle:
            IslandDesignPalette.Status.idle
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

private struct StateIndicatorPreview: View {
    let option: IslandSessionStateIndicator

    var body: some View {
        HStack(spacing: 8) {
            indicator
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(V6Palette.paper.opacity(option == .tint ? 0.55 : 0.22))
                .frame(width: 58, height: 6)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(option == .tint ? Color(hex: AgentTool.codex.brandColorHex)?.opacity(0.22) ?? Color.white.opacity(0.08) : Color.clear)
        )
    }

    @ViewBuilder
    private var indicator: some View {
        let color = Color(hex: AgentTool.codex.brandColorHex) ?? V6Palette.paper
        switch option {
        case .animatedDot:
            Circle()
                .fill(color)
                .frame(width: 10, height: 10)
                .shadow(color: color.opacity(0.55), radius: 5)
        case .bar:
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(color)
                .frame(width: 4, height: 28)
        case .glyph:
            Image(systemName: "sparkle")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(color)
        case .tint:
            Circle()
                .fill(V6Palette.paper.opacity(0.72))
                .frame(width: 10, height: 10)
        }
    }
}

private struct UsageDisplayPreview: View {
    let option: IslandUsageDisplay

    var body: some View {
        HStack(spacing: 6) {
            if option == .compact {
                usageChip("Cl", window: "5h", value: 42, color: Color(hex: AgentTool.claudeCode.brandColorHex) ?? .orange)
                usageChip("Cx", window: "7d", value: 13, color: Color(hex: AgentTool.codex.brandColorHex) ?? .blue)
            } else {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(V6Palette.paper.opacity(0.18))
                    .frame(width: 72, height: 5)
            }
        }
        .frame(width: 104, alignment: .center)
    }

    private func usageChip(_ title: String, window: String, value: Int, color: Color) -> some View {
        HStack(spacing: 4) {
            Text(title)
                .font(.system(size: 9.5, weight: .semibold))
                .foregroundStyle(V6Palette.paper.opacity(0.66))
            Text(window)
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .foregroundStyle(V6Palette.paper.opacity(0.42))
            Text("\(value)%")
                .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                .foregroundStyle(color)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(.white.opacity(0.055), in: Capsule())
    }
}

private struct SessionGroupPreview: View {
    let option: IslandSessionGroup

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            switch option {
            case .none:
                previewLine(width: 72, color: V6Palette.paper.opacity(0.42))
                previewLine(width: 54, color: V6Palette.paper.opacity(0.28))
                previewLine(width: 64, color: V6Palette.paper.opacity(0.22))
            case .state:
                groupBlock(width: 52)
                groupBlock(width: 70)
            case .agent:
                agentBlock(color: Color(hex: AgentTool.claudeCode.brandColorHex) ?? .white)
                agentBlock(color: Color(hex: AgentTool.codex.brandColorHex) ?? .white)
            case .project:
                groupBlock(width: 76)
                groupBlock(width: 46)
            }
        }
        .frame(width: 84, alignment: .leading)
    }

    private func previewLine(width: CGFloat, color: Color) -> some View {
        RoundedRectangle(cornerRadius: 2, style: .continuous)
            .fill(color)
            .frame(width: width, height: 5)
    }

    private func groupBlock(width: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            previewLine(width: width * 0.48, color: V6Palette.paper.opacity(0.48))
            previewLine(width: width, color: V6Palette.paper.opacity(0.22))
        }
    }

    private func agentBlock(color: Color) -> some View {
        HStack(spacing: 5) {
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
            previewLine(width: 54, color: V6Palette.paper.opacity(0.25))
        }
    }
}

private struct SessionSortPreview: View {
    let option: IslandSessionSort

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            ForEach(rows.indices, id: \.self) { index in
                HStack(spacing: 6) {
                    Text(rows[index].rank)
                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                        .foregroundStyle(V6Palette.paper.opacity(0.55))
                        .frame(width: 12, alignment: .leading)
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(rows[index].color)
                        .frame(width: rows[index].width, height: 5)
                }
            }
        }
        .frame(width: 82, alignment: .leading)
    }

    private var rows: [(rank: String, width: CGFloat, color: Color)] {
        switch option {
        case .attention:
            return [
                ("!", 62, Color(hex: AgentTool.claudeCode.brandColorHex) ?? .white),
                ("2", 48, V6Palette.paper.opacity(0.28)),
                ("3", 58, V6Palette.paper.opacity(0.2)),
            ]
        case .lastUpdate:
            return [
                ("1", 64, V6Palette.paper.opacity(0.38)),
                ("2", 56, V6Palette.paper.opacity(0.3)),
                ("3", 42, V6Palette.paper.opacity(0.22)),
            ]
        }
    }
}
