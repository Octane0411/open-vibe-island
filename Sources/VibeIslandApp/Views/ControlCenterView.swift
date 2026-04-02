import SwiftUI
import VibeIslandCore

struct ControlCenterView: View {
    var model: AppModel

    var body: some View {
        HStack(spacing: 24) {
            sessionColumn
            detailColumn
        }
        .padding(24)
        .frame(width: 980, height: 640)
        .background(backgroundGradient)
    }

    private var sessionColumn: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Vibe Island OSS")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                Text("Native macOS scaffold for monitoring, approvals, and jump-back flows.")
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 12) {
                summaryCard(title: "Running", value: model.state.runningCount, tint: .mint)
                summaryCard(title: "Attention", value: model.state.attentionCount, tint: .orange)
                summaryCard(title: "Completed", value: model.state.completedCount, tint: .blue)
            }

            HStack(spacing: 12) {
                Button(model.isOverlayVisible ? "Hide Island" : "Show Island") {
                    model.toggleOverlay()
                }
                .buttonStyle(.borderedProminent)

                Button("Load Demo Sessions") {
                    model.resetDemo()
                }
                .buttonStyle(.bordered)
            }

            acceptanceCard
            setupCard

            VStack(alignment: .leading, spacing: 12) {
                Text("Sessions")
                    .font(.headline)
                List {
                    ForEach(model.sessions) { session in
                        Button {
                            model.select(sessionID: session.id)
                        } label: {
                            SessionRowView(
                                session: session,
                                isSelected: session.id == model.focusedSession?.id
                            )
                        }
                        .buttonStyle(.plain)
                        .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .background(Color.clear)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: 360, maxHeight: .infinity, alignment: .topLeading)
    }

    private var setupCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Codex Attach")
                        .font(.headline)
                    Text(model.codexHookStatusTitle)
                        .font(.subheadline.weight(.medium))
                    Text(model.codexHookStatusSummary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 12)
                Circle()
                    .fill(model.codexHooksInstalled ? Color.mint : Color.orange)
                    .frame(width: 10, height: 10)
            }

            if let hooksBinaryURL = model.hooksBinaryURL {
                Text(hooksBinaryURL.path)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .lineLimit(2)
            } else {
                Text("No local `VibeIslandHooks` executable was found. Build the package first.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 10) {
                Button("Refresh") {
                    model.refreshCodexHookStatus()
                }
                .buttonStyle(.bordered)
                .disabled(model.isCodexSetupBusy)

                Button("Install") {
                    model.installCodexHooks()
                }
                .buttonStyle(.borderedProminent)
                .disabled(model.isCodexSetupBusy || model.hooksBinaryURL == nil)

                Button("Uninstall") {
                    model.uninstallCodexHooks()
                }
                .buttonStyle(.bordered)
                .disabled(model.isCodexSetupBusy || !model.codexHooksInstalled)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(.white.opacity(0.08))
        )
    }

    private var acceptanceCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("v0.1 Acceptance")
                        .font(.headline)
                    Text(model.acceptanceStatusTitle)
                        .font(.subheadline.weight(.medium))
                    Text(model.acceptanceStatusSummary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 12)

                Text("\(model.acceptanceCompletedCount)/\(model.acceptanceSteps.count)")
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(.ultraThinMaterial, in: Capsule())
            }

            VStack(alignment: .leading, spacing: 10) {
                ForEach(model.acceptanceSteps) { step in
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: step.isComplete ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(step.isComplete ? Color.mint : Color.secondary)
                            .padding(.top, 2)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(step.title)
                                .font(.subheadline.weight(.medium))
                            Text(step.detail)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            HStack(spacing: 10) {
                Button("Refresh") {
                    model.refreshCodexHookStatus()
                }
                .buttonStyle(.bordered)

                Button("Load Demo Acceptance") {
                    model.startAcceptanceDemo()
                }
                .buttonStyle(.borderedProminent)

                Button("Open Overlay") {
                    if !model.isOverlayVisible {
                        model.toggleOverlay()
                    }
                }
                .buttonStyle(.bordered)
                .disabled(model.isOverlayVisible)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(.white.opacity(0.08))
        )
    }

    private var detailColumn: some View {
        VStack(alignment: .leading, spacing: 18) {
            if let session = model.focusedSession {
                Text(session.tool.displayName)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(session.title)
                    .font(.system(size: 30, weight: .semibold, design: .rounded))
                Text(session.spotlightPrimaryText)
                    .font(.title3)
                    .foregroundStyle(.primary)

                if let secondaryText = session.spotlightSecondaryText {
                    Text(secondaryText)
                        .font(.body)
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 12) {
                    detailPill(title: session.spotlightStatusLabel)
                    if let currentTool = session.spotlightCurrentToolLabel {
                        detailPill(title: currentTool)
                    }
                    if let terminalLabel = session.spotlightTerminalLabel {
                        detailPill(title: terminalLabel)
                    }
                    if session.spotlightTrackingLabel != nil {
                        detailPill(title: "rollout live")
                    }
                    Text(session.updatedAt, style: .relative)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if session.tool == .codex, session.codexMetadata != nil {
                    actionCard(title: "Live Codex State", subtitle: "Enriched from local rollout tracking") {
                        VStack(alignment: .leading, spacing: 10) {
                            if let assistantMessage = session.codexMetadata?.lastAssistantMessage {
                                metadataRow(title: "Assistant", value: assistantMessage)
                            }

                            if let currentTool = session.codexMetadata?.currentTool {
                                metadataRow(title: "Current tool", value: currentTool)
                            }

                            if let transcriptPath = session.codexMetadata?.transcriptPath {
                                metadataRow(title: "Transcript", value: transcriptPath)
                            }
                        }
                    }
                }

                if let request = session.permissionRequest {
                    actionCard(title: request.title, subtitle: request.affectedPath) {
                        Text(request.summary)
                            .foregroundStyle(.secondary)

                        HStack(spacing: 12) {
                            Button(request.secondaryActionTitle) {
                                model.approveFocusedPermission(false)
                            }
                            .buttonStyle(.bordered)

                            Button(request.primaryActionTitle) {
                                model.approveFocusedPermission(true)
                            }
                            .buttonStyle(.borderedProminent)
                        }
                    }
                } else if let prompt = session.questionPrompt {
                    actionCard(title: "Question", subtitle: "Reply from the island") {
                        Text(prompt.title)
                            .foregroundStyle(.secondary)

                        HStack(spacing: 12) {
                            ForEach(prompt.options, id: \.self) { option in
                                Button(option) {
                                    model.answerFocusedQuestion(option)
                                }
                                .buttonStyle(.bordered)
                            }
                        }
                    }
                } else {
                    actionCard(title: "Jump Back", subtitle: "Best-effort terminal focus") {
                        Text("The island will activate the detected terminal and, when possible, reopen the session workspace there.")
                            .foregroundStyle(.secondary)

                        Button("Jump to Session") {
                            model.jumpToFocusedSession()
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
            } else {
                Text("No session selected")
                    .font(.title2)
            }

            Spacer(minLength: 0)

            VStack(alignment: .leading, spacing: 8) {
                Text("Last action")
                    .font(.headline)
                Text(model.lastActionMessage)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .strokeBorder(.white.opacity(0.08))
        )
    }

    private func summaryCard(title: String, value: Int, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text("\(value)")
                .font(.system(size: 26, weight: .semibold, design: .rounded))
            Capsule()
                .fill(tint.gradient)
                .frame(width: 42, height: 6)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(.white.opacity(0.08))
        )
    }

    private func detailPill(title: String) -> some View {
        Text(title)
            .font(.caption.weight(.medium))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.ultraThinMaterial, in: Capsule())
    }

    private func actionCard<Content: View>(
        title: String,
        subtitle: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title)
                .font(.headline)
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
            content()
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(.white.opacity(0.08))
        )
    }

    private func metadataRow(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.subheadline)
                .textSelection(.enabled)
        }
    }

    private var backgroundGradient: some View {
        LinearGradient(
            colors: [
                Color(red: 0.08, green: 0.10, blue: 0.16),
                Color(red: 0.07, green: 0.16, blue: 0.19),
                Color(red: 0.14, green: 0.12, blue: 0.10),
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
    }
}

private struct SessionRowView: View {
    let session: AgentSession
    let isSelected: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Circle()
                .fill(statusColor)
                .frame(width: 10, height: 10)
                .padding(.top, 6)

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(session.title)
                        .font(.headline)
                    Spacer(minLength: 12)
                    HStack(spacing: 6) {
                        if session.isDemoSession {
                            Text("DEMO")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(.orange)
                        }

                        Text(session.tool.shortName)
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.secondary)
                    }
                }

                Text(session.spotlightPrimaryText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)

                HStack {
                    Text(session.spotlightStatusLabel)
                    if let currentTool = session.spotlightCurrentToolLabel {
                        Text("·")
                        Text(currentTool)
                    }
                    Text("·")
                    Text(session.updatedAt, style: .relative)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(isSelected ? Color.white.opacity(0.12) : Color.white.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(isSelected ? .white.opacity(0.18) : .white.opacity(0.06))
        )
    }

    private var statusColor: Color {
        switch session.phase {
        case .running:
            .mint
        case .waitingForApproval:
            .orange
        case .waitingForAnswer:
            .yellow
        case .completed:
            .blue
        }
    }
}
