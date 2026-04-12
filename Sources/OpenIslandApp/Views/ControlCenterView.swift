import SwiftUI
import OpenIslandCore

struct ControlCenterView: View {
    var model: AppModel

    @State private var selectedScenario: IslandDebugScenario = .approvalCard
    @State private var previewModel = AppModel()
    @State private var previewSnapshot = IslandDebugScenario.approvalCard.snapshot()

    private var lang: LanguageManager { model.lang }

    var body: some View {
        HStack(spacing: 28) {
            controlColumn
            previewColumn
        }
        .padding(28)
        .frame(width: 1280, height: 820)
        .background(debugBackground)
        .preferredColorScheme(model.preferredColorScheme.swiftUIScheme)
        .onAppear {
            refreshPreview(for: selectedScenario)
        }
        .onChange(of: selectedScenario) { _, newValue in
            refreshPreview(for: newValue)
        }
    }

    private var controlColumn: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 10) {
                    Text(lang.t("debug.title"))
                        .font(.system(size: 30, weight: .bold))
                        .foregroundStyle(.white)

                    Text(lang.t("debug.description"))
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.white.opacity(0.68))
                        .fixedSize(horizontal: false, vertical: true)
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text(lang.t("debug.scenarios"))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.58))

                    ForEach(IslandDebugScenario.allCases) { scenario in
                        scenarioButton(for: scenario)
                    }
                }

                usageDebugCard(
                    title: "Claude Hooks",
                    statusTitle: model.claudeHookStatusTitle,
                    statusSummary: model.claudeHookStatusSummary,
                    isActive: model.claudeHooksInstalled || model.claudeHookStatus?.hasClaudeIslandHooks == true,
                    accentColor: model.claudeHooksInstalled ? .mint : (model.claudeHookStatus?.hasClaudeIslandHooks == true ? .orange : .blue)
                ) {
                    if let status = model.claudeHookStatus {
                        metadataRow(title: "settings", value: status.settingsURL.path)
                        metadataRow(title: "manifest", value: status.manifestURL.path)
                        if status.hasClaudeIslandHooks {
                            metadataRow(title: "notice", value: "claude-island hooks still present")
                        }
                    }
                    if let report = model.claudeHealthReport, !report.issues.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(Array(report.issues.enumerated()), id: \.offset) { _, issue in
                                HStack(alignment: .top, spacing: 4) {
                                    Image(systemName: controlCenterIssueIcon(issue))
                                        .font(.system(size: 8))
                                        .foregroundStyle(controlCenterIssueColor(issue))
                                    Text(issue.description)
                                        .font(.system(size: 10, weight: .medium))
                                        .foregroundStyle(.white.opacity(issue.severity == .info ? 0.4 : 0.6))
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }
                    }
                } actions: {
                    HStack(spacing: 10) {
                        Button(lang.t("debug.refresh")) {
                            model.refreshClaudeHookStatus()
                            model.runHealthChecks()
                        }
                        .buttonStyle(DebugActionButtonStyle(kind: .secondary))

                        if let report = model.claudeHealthReport, !report.repairableIssues.isEmpty {
                            Button("Repair") {
                                model.repairHooks()
                            }
                            .buttonStyle(DebugActionButtonStyle(kind: .primary))
                        } else {
                            Button(model.claudeHooksInstalled ? lang.t("debug.removeHooks") : lang.t("debug.installHooks")) {
                                if model.claudeHooksInstalled {
                                    model.uninstallClaudeHooks()
                                } else {
                                    model.installClaudeHooks()
                                }
                            }
                            .buttonStyle(DebugActionButtonStyle(kind: .primary))
                            .disabled(model.isClaudeHookSetupBusy || model.hooksBinaryURL == nil)
                        }
                    }
                }

                ccForkHookCard(title: "Qoder Hooks", installed: model.qoderHooksInstalled, status: model.qoderHookStatus, isBusy: model.isQoderHookSetupBusy, install: model.installQoderHooks, uninstall: model.uninstallQoderHooks)

                ccForkHookCard(title: "Qwen Code Hooks", installed: model.qwenCodeHooksInstalled, status: model.qwenCodeHookStatus, isBusy: model.isQwenCodeHookSetupBusy, install: model.installQwenCodeHooks, uninstall: model.uninstallQwenCodeHooks)

                ccForkHookCard(title: "Factory Hooks", installed: model.factoryHooksInstalled, status: model.factoryHookStatus, isBusy: model.isFactoryHookSetupBusy, install: model.installFactoryHooks, uninstall: model.uninstallFactoryHooks)

                ccForkHookCard(title: "CodeBuddy Hooks", installed: model.codebuddyHooksInstalled, status: model.codebuddyHookStatus, isBusy: model.isCodebuddyHookSetupBusy, install: model.installCodebuddyHooks, uninstall: model.uninstallCodebuddyHooks)

                geminiHookCard

                usageDebugCard(
                    title: "Claude Usage",
                    statusTitle: model.claudeUsageStatusTitle,
                    statusSummary: model.claudeUsageStatusSummary,
                    isActive: model.claudeUsageInstalled || model.claudeStatusLineStatus?.hasConflictingStatusLine == true,
                    accentColor: model.claudeUsageInstalled ? .mint : (model.claudeStatusLineStatus?.hasConflictingStatusLine == true ? .orange : .blue)
                ) {
                    if let summary = model.claudeUsageSummaryText {
                        metadataRow(title: "usage", value: summary)
                    }

                    if let status = model.claudeStatusLineStatus {
                        metadataRow(title: "settings", value: status.settingsURL.path)
                        metadataRow(title: "script", value: status.scriptURL.path)
                        metadataRow(title: "cache", value: status.cacheURL.path)
                    }
                } actions: {
                    HStack(spacing: 10) {
                        Button(lang.t("debug.refresh")) {
                            model.refreshClaudeUsageState()
                        }
                        .buttonStyle(DebugActionButtonStyle(kind: .secondary))

                        Button(model.claudeUsageInstalled ? lang.t("debug.removeBridge") : lang.t("debug.installBridge")) {
                            if model.claudeUsageInstalled {
                                model.uninstallClaudeUsageBridge()
                            } else {
                                model.installClaudeUsageBridge()
                            }
                        }
                        .buttonStyle(DebugActionButtonStyle(kind: .primary))
                        .disabled(model.isClaudeUsageSetupBusy || model.claudeStatusLineStatus?.hasConflictingStatusLine == true)
                    }
                }

                if model.showCodexUsage {
                    usageDebugCard(
                        title: "Codex Usage",
                        statusTitle: model.codexUsageStatusTitle,
                        statusSummary: model.codexUsageStatusSummary,
                        isActive: model.codexUsageSnapshot?.isEmpty == false,
                        accentColor: model.codexUsageSnapshot?.isEmpty == false ? .mint : .blue
                    ) {
                        if let summary = model.codexUsageSummaryText {
                            metadataRow(title: "usage", value: summary)
                        }

                        if let snapshot = model.codexUsageSnapshot {
                            metadataRow(title: "latest rollout", value: snapshot.sourceFilePath)

                            if let planType = snapshot.planType {
                                metadataRow(title: "plan", value: planType)
                            }

                            if let capturedAt = snapshot.capturedAt {
                                metadataRow(
                                    title: "captured",
                                    value: capturedAt.formatted(date: .abbreviated, time: .standard)
                                )
                            }
                        }
                    } actions: {
                        HStack(spacing: 10) {
                            Button(lang.t("debug.refresh")) {
                                model.refreshCodexUsageState()
                            }
                            .buttonStyle(DebugActionButtonStyle(kind: .secondary))
                        }
                    }
                }

                actionCard
                transcriptCard
                liveOverlayCard

                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .scrollIndicators(.visible)
        .frame(width: 360, alignment: .topLeading)
    }

    private func scenarioButton(for scenario: IslandDebugScenario) -> some View {
        HStack(alignment: .top, spacing: 0) {
            Button {
                selectedScenario = scenario
            } label: {
                HStack(alignment: .top, spacing: 12) {
                    Circle()
                        .fill(selectedScenario == scenario ? .white.opacity(0.88) : .white.opacity(0.22))
                        .frame(width: 8, height: 8)
                        .padding(.top, 6)

                    VStack(alignment: .leading, spacing: 5) {
                        Text(scenario.title)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.white)

                        Text(scenario.summary)
                            .font(.system(size: 11.5, weight: .medium))
                            .foregroundStyle(.white.opacity(0.5))
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: 0)
                }
            }
            .buttonStyle(.plain)

            Button {
                let snapshot = scenario.snapshot()
                model.loadDebugSnapshot(snapshot, presentOverlay: true, autoCollapseNotificationCards: false)
            } label: {
                Image(systemName: "play.fill")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.6))
                    .frame(width: 28, height: 28)
                    .background(Circle().fill(.white.opacity(0.08)))
            }
            .buttonStyle(.plain)
            .padding(.top, 2)
            .help("Trigger on island")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(selectedScenario == scenario ? Color.white.opacity(0.08) : Color.white.opacity(0.03))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(selectedScenario == scenario ? .white.opacity(0.18) : .white.opacity(0.05))
        )
    }

    private var geminiHookCard: some View {
        usageDebugCard(
            title: "Gemini Hooks",
            statusTitle: model.geminiHookStatusTitle,
            statusSummary: model.geminiHookStatusSummary,
            isActive: model.geminiHooksInstalled,
            accentColor: model.geminiHooksInstalled ? .mint : .blue
        ) {
            EmptyView()
        } actions: {
            HStack(spacing: 10) {
                Button(lang.t("debug.refresh")) {
                    model.refreshGeminiHookStatus()
                }
                .buttonStyle(DebugActionButtonStyle(kind: .secondary))

                Button(model.geminiHooksInstalled ? lang.t("debug.removeHooks") : lang.t("debug.installHooks")) {
                    if model.geminiHooksInstalled {
                        model.uninstallGeminiHooks()
                    } else {
                        model.installGeminiHooks()
                    }
                }
                .buttonStyle(DebugActionButtonStyle(kind: .primary))
                .disabled(model.isGeminiHookSetupBusy || model.hooksBinaryURL == nil)
            }
        }
    }

    private var actionCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(lang.t("debug.actions"))
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white.opacity(0.58))

            Text(lang.t("debug.actionsDescription"))
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(.white.opacity(0.5))
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 10) {
                Button(lang.t("debug.mirrorToIsland")) {
                    model.loadDebugSnapshot(previewSnapshot, presentOverlay: true, autoCollapseNotificationCards: false)
                }
                .buttonStyle(DebugActionButtonStyle(kind: .primary))

                Button(lang.t("debug.closeIsland")) {
                    model.notchClose()
                }
                .buttonStyle(DebugActionButtonStyle(kind: .secondary))
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(debugCardBackground)
    }

    private var transcriptCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(lang.t("debug.currentMock"))
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white.opacity(0.58))

            Text(previewSnapshot.title)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)

            Text(previewSnapshot.summary)
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(.white.opacity(0.52))
                .fixedSize(horizontal: false, vertical: true)

            if let session = activePreviewSession {
                debugLine("Line 1", session.spotlightHeadlineText)
                debugLine("Line 2", session.spotlightPromptLineText ?? "None")
                debugLine("Line 3", session.spotlightActivityLineText ?? session.summary)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(debugCardBackground)
    }

    private var liveOverlayCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(lang.t("debug.liveOverlay"))
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white.opacity(0.58))

            debugMetricRow(label: lang.t("debug.visible"), value: model.isOverlayVisible ? lang.t("debug.yes") : lang.t("debug.no"))
            debugMetricRow(label: lang.t("debug.surface"), value: liveSurfaceTitle)
            debugMetricRow(label: lang.t("debug.sessions"), value: "\(model.sessions.count)")
            debugMetricRow(label: lang.t("debug.message"), value: model.lastActionMessage)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(debugCardBackground)
    }

    private var previewColumn: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                VStack(alignment: .leading, spacing: 6) {
                    Text(lang.t("debug.inlinePreview"))
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.white)
                    Text(lang.t("debug.previewDescription"))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white.opacity(0.48))
                }

                Spacer(minLength: 0)
            }

            ZStack(alignment: .top) {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.07, green: 0.07, blue: 0.08),
                                Color(red: 0.03, green: 0.03, blue: 0.04),
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 28, style: .continuous)
                            .strokeBorder(.white.opacity(0.06))
                    )

                VStack(spacing: 0) {
                    IslandPanelView(model: previewModel)
                        .frame(width: 860, height: previewSnapshot.previewHeight, alignment: .top)
                        .allowsHitTesting(false)

                    Spacer(minLength: 0)
                }
                .padding(.top, 24)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var activePreviewSession: AgentSession? {
        previewModel.activeIslandCardSession ?? previewModel.surfacedSessions.first
    }

    private var debugCardBackground: some View {
        RoundedRectangle(cornerRadius: 22, style: .continuous)
            .fill(Color.white.opacity(0.04))
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(.white.opacity(0.06))
            )
    }

    private var debugBackground: some View {
        LinearGradient(
            colors: [
                Color.black,
                Color(red: 0.03, green: 0.03, blue: 0.04),
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var liveSurfaceTitle: String {
        switch model.islandSurface {
        case .sessionList(actionableSessionID: nil):
            lang.t("debug.sessionList")
        case .sessionList(actionableSessionID: .some):
            lang.t("debug.sessionListActionable")
        }
    }

    private func refreshPreview(for scenario: IslandDebugScenario) {
        let snapshot = scenario.snapshot()
        previewSnapshot = snapshot
        previewModel.loadDebugSnapshot(snapshot)
    }

    private func ccForkHookCard(
        title: String,
        installed: Bool,
        status: ClaudeHookInstallationStatus?,
        isBusy: Bool,
        install: @escaping () -> Void,
        uninstall: @escaping () -> Void
    ) -> some View {
        usageDebugCard(
            title: title,
            statusTitle: installed ? "\(title) installed" : "\(title) not installed",
            statusSummary: {
                guard status != nil else {
                    return "Reading settings.json."
                }
                if installed {
                    return "managed hooks present"
                }
                if model.hooksBinaryURL == nil {
                    return "Build OpenIslandHooks before installing."
                }
                return "no managed hooks"
            }(),
            isActive: installed,
            accentColor: installed ? .mint : .blue
        ) {
            if let status {
                metadataRow(title: "settings", value: status.settingsURL.path)
            }
        } actions: {
            HStack(spacing: 10) {
                Button(lang.t("debug.refresh")) {
                    model.refreshCCForkHookStatuses()
                }
                .buttonStyle(DebugActionButtonStyle(kind: .secondary))

                Button(installed ? lang.t("debug.removeHooks") : lang.t("debug.installHooks")) {
                    if installed {
                        uninstall()
                    } else {
                        install()
                    }
                }
                .buttonStyle(DebugActionButtonStyle(kind: .primary))
                .disabled(isBusy || model.hooksBinaryURL == nil)
            }
        }
    }

    private func usageDebugCard<Content: View, Actions: View>(
        title: String,
        statusTitle: String,
        statusSummary: String,
        isActive: Bool,
        accentColor: Color,
        @ViewBuilder content: () -> Content,
        @ViewBuilder actions: () -> Actions
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(title)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.58))

                    Text(statusTitle)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)

                    Text(statusSummary)
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(.white.opacity(0.5))
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)

                Circle()
                    .fill(isActive ? accentColor : accentColor.opacity(0.7))
                    .frame(width: 10, height: 10)
                    .padding(.top, 4)
            }

            content()
            actions()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(debugCardBackground)
    }

    private func debugMetricRow(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.white.opacity(0.4))
            Text(value)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(0.72))
                .lineLimit(2)
        }
    }

    private func debugLine(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.white.opacity(0.38))
            Text(value)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(0.75))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func metadataRow(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.white.opacity(0.38))

            Text(value)
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(.white.opacity(0.72))
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func controlCenterIssueIcon(_ issue: HookHealthReport.Issue) -> String {
        switch issue.severity {
        case .info: "info.circle.fill"
        case .error: issue.isAutoRepairable ? "wrench.fill" : "exclamationmark.triangle.fill"
        }
    }

    private func controlCenterIssueColor(_ issue: HookHealthReport.Issue) -> Color {
        switch issue.severity {
        case .info: .blue
        case .error: issue.isAutoRepairable ? .orange : .red
        }
    }
}

private struct DebugActionButtonStyle: ButtonStyle {
    enum Kind {
        case primary
        case secondary
    }

    let kind: Kind

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(kind == .primary ? Color.black : .white.opacity(0.78))
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(background(configuration: configuration), in: Capsule())
    }

    private func background(configuration: Configuration) -> Color {
        switch kind {
        case .primary:
            return Color.white.opacity(configuration.isPressed ? 0.72 : 0.9)
        case .secondary:
            return Color.white.opacity(configuration.isPressed ? 0.08 : 0.12)
        }
    }
}
