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
    @State private var previewMode: UnifiedBars.Mode = .running
    @State private var previewLayout: V6ClosedLayout = .external

    private var lang: LanguageManager { model.lang }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                previewSection
                rightSlotSection
                centerLabelSection
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .background(Color(red: 0.055, green: 0.055, blue: 0.06))
        .navigationTitle(lang.t("settings.tab.appearance"))
    }

    // MARK: - Preview

    @ViewBuilder
    private var previewSection: some View {
        sectionHeader(title: lang.t("settings.appearance.preview"), note: nil)

        VStack(spacing: 14) {
            previewStage
            previewControls
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(red: 0.1, green: 0.1, blue: 0.115))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.white.opacity(0.06), lineWidth: 1)
        )
    }

    private var previewStage: some View {
        let frameW: CGFloat = 420
        let frameH: CGFloat = 44
        let physicalNotchW: CGFloat = 180

        return ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.16, green: 0.16, blue: 0.19),
                    Color(red: 0.12, green: 0.12, blue: 0.14),
                ],
                startPoint: .top, endPoint: .bottom
            )

            if previewLayout == .macbook {
                // Physical hardware notch mock
                V6ClosedPillShape()
                    .fill(Color.black)
                    .frame(width: physicalNotchW, height: 32)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .frame(height: frameH, alignment: .top)
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
        .frame(width: frameW, height: frameH)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.white.opacity(0.05), lineWidth: 1)
        )
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private var previewControls: some View {
        HStack(spacing: 16) {
            // Layout toggle
            Picker("", selection: $previewLayout) {
                Text(lang.t("settings.appearance.preview.external")).tag(V6ClosedLayout.external)
                Text(lang.t("settings.appearance.preview.macbook")).tag(V6ClosedLayout.macbook)
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .frame(width: 220)

            Spacer()

            // State toggle
            ForEach([UnifiedBars.Mode.idle, .running, .waiting, .done], id: \.self) { mode in
                monoChip(title: title(for: mode), selected: previewMode == mode) {
                    previewMode = mode
                }
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
            rightSlotCard(.agents, icon: { AgentDotsPreview(colors: previewAgentColors) },
                          title: lang.t("settings.appearance.rightSlot.agents"))
            rightSlotCard(.time,   icon: { TimeLeftPreview(text: "2m") },
                          title: lang.t("settings.appearance.rightSlot.time"))
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
        let selected = model.islandRightSlot == option
        return Button {
            model.islandRightSlot = option
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
        let selected = model.islandCenterLabel == option
        let title: String = switch option {
        case .agentAction: lang.t("settings.appearance.centerLabel.agentAction")
        case .sessionName: lang.t("settings.appearance.centerLabel.sessionName")
        case .off:         lang.t("settings.appearance.centerLabel.off")
        }
        return Button {
            model.islandCenterLabel = option
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

    // MARK: - Helpers

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
        case .done:    lang.t("settings.appearance.state.done")
        }
    }

    private var previewAgentColors: [Color] {
        [AgentTool.claudeCode, .codex, .cursor]
            .map { Color(hex: $0.brandColorHex) ?? .white }
    }

    private var previewLabel: String? {
        guard previewLayout == .external,
              model.islandCenterLabel != .off else { return nil }
        switch (previewMode, model.islandCenterLabel) {
        case (.idle, _):           return nil
        case (.done, _):           return "Commit pushed"
        case (.waiting, _):        return "Permission needed"
        case (.running, .agentAction): return "Claude · editing"
        case (.running, .sessionName): return "open-island"
        case (.running, .off):         return nil
        }
    }

    private var previewRightContent: IslandRightSlotContent? {
        switch model.islandRightSlot {
        case .none: return nil
        case .count: return .count(3)
        case .agents:
            return .agents(previewAgentColors)
        case .time:
            return previewMode == .waiting ? .time("2m") : .time("1m 24s")
        }
    }
}

// MARK: - Small preview ornaments

private struct CountBadgePreview: View {
    let count: Int
    var body: some View {
        Text("×\(count)")
            .font(.system(size: 12, weight: .semibold, design: .monospaced))
            .foregroundStyle(V6Palette.paper)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(
                Capsule().fill(V6Palette.paper.opacity(0.14))
            )
            .overlay(
                Capsule().stroke(V6Palette.paper.opacity(0.35), lineWidth: 1)
            )
    }
}

private struct AgentDotsPreview: View {
    let colors: [Color]
    var body: some View {
        HStack(spacing: 4) {
            ForEach(Array(colors.enumerated()), id: \.offset) { _, color in
                Circle().fill(color).frame(width: 8, height: 8)
            }
        }
    }
}

private struct TimeLeftPreview: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.system(size: 11.5, weight: .medium, design: .monospaced))
            .foregroundStyle(V6Palette.paper.opacity(0.75))
    }
}
