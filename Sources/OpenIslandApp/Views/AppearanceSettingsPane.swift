import SwiftUI
import OpenIslandCore

struct AppearanceSettingsPane: View {
    var model: AppModel
    @State private var previewPhase: SessionPhase = .running

    private var lang: LanguageManager { model.lang }
    private var isCustom: Bool { model.islandAppearanceMode == .custom }

    var body: some View {
        Form {
            Section(lang.t("settings.appearance.colorScheme")) {
                Picker(lang.t("settings.appearance.colorScheme"), selection: Binding(
                    get: { model.preferredColorScheme },
                    set: { model.preferredColorScheme = $0 }
                )) {
                    Text(lang.t("settings.appearance.colorScheme.system")).tag(AppModel.AppColorScheme.system)
                    Text(lang.t("settings.appearance.colorScheme.light")).tag(AppModel.AppColorScheme.light)
                    Text(lang.t("settings.appearance.colorScheme.dark")).tag(AppModel.AppColorScheme.dark)
                }
                .pickerStyle(.segmented)
            }

            Section(lang.t("settings.appearance.mode")) {
                Picker(lang.t("settings.appearance.mode"), selection: Binding(
                    get: { model.islandAppearanceMode },
                    set: { model.islandAppearanceMode = $0 }
                )) {
                    Text(lang.t("settings.appearance.mode.default")).tag(IslandAppearanceMode.default)
                    Text(lang.t("settings.appearance.mode.custom")).tag(IslandAppearanceMode.custom)
                }
                .pickerStyle(.segmented)

                if !isCustom {
                    Text(lang.t("settings.appearance.mode.defaultDesc"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section(lang.t("settings.appearance.style")) {
                if isCustom {
                    Picker(lang.t("settings.appearance.closedStyle"), selection: Binding(
                        get: { model.islandClosedDisplayStyle },
                        set: { model.islandClosedDisplayStyle = $0 }
                    )) {
                        Text(lang.t("settings.appearance.style.minimal")).tag(IslandClosedDisplayStyle.minimal)
                        Text(lang.t("settings.appearance.style.detailed")).tag(IslandClosedDisplayStyle.detailed)
                    }
                    .pickerStyle(.segmented)
                }

                Toggle(lang.t("settings.appearance.hideIdleToEdge"), isOn: Binding(
                    get: { model.hideIdleIslandToEdge },
                    set: { model.hideIdleIslandToEdge = $0 }
                ))

                Text(lang.t("settings.appearance.hideIdleToEdge.help"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if isCustom {
                Section(lang.t("settings.appearance.preview")) {
                    notchPreviewCard
                        .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                        .listRowBackground(Color.clear)
                }

                Section(lang.t("settings.appearance.pixelShape")) {
                    HStack(spacing: 12) {
                        ForEach(IslandPixelShapeStyle.allCases) { style in
                            pixelShapeCard(style)
                        }
                    }

                    if model.islandPixelShapeStyle == .custom {
                        HStack(spacing: 12) {
                            Button(lang.t("settings.appearance.avatar.upload")) {
                                model.importCustomAvatar()
                            }
                            if model.customAvatarImage != nil {
                                Button(lang.t("settings.appearance.avatar.remove")) {
                                    model.removeCustomAvatar()
                                }
                                .foregroundStyle(.red)
                            }
                        }

                        Text(lang.t("settings.appearance.avatar.help"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Section(lang.t("settings.appearance.statusColors")) {
                    ForEach(SessionPhase.allCases, id: \.self) { phase in
                        statusColorRow(phase)
                    }
                }
            }

            Section {
                Text(lang.t("settings.appearance.communityNote"))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .multilineTextAlignment(.center)
            }
        }
        .formStyle(.grouped)
        .navigationTitle(lang.t("settings.tab.appearance"))
    }

    // MARK: - Preview card

    private var notchPreviewCard: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(white: 0.12))

            VStack(spacing: 14) {
                previewIslandBar
                previewPhaseSelector
            }
            .padding(16)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 140)
    }

    private var previewIslandBar: some View {
        if shouldPreviewIdleEdgeOnly {
            return AnyView(previewIdleEdge)
        }

        let tint = model.statusColor(for: previewPhase)
        let isDetailed = model.islandClosedDisplayStyle == .detailed

        return AnyView(HStack(spacing: 8) {
            IslandPixelGlyph(
                tint: tint,
                style: model.islandPixelShapeStyle,
                isAnimating: previewPhase != .completed,
                customAvatarImage: model.customAvatarImage
            )

            if previewPhase.requiresAttention {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 10.5, weight: .bold))
                    .foregroundStyle(tint)
            }

            if isDetailed {
                Text(phaseTitle(previewPhase))
                    .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.92))
                    .lineLimit(1)
            }

            Spacer()

            Text("2")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(tint)

            if isDetailed {
                Text(lang.t("settings.appearance.preview.sessions"))
                    .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.72))
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
        .background(Color.black, in: RoundedRectangle(cornerRadius: 18, style: .continuous)))
    }

    private var shouldPreviewIdleEdgeOnly: Bool {
        model.hideIdleIslandToEdge && previewPhase == .running
    }

    private var previewIdleEdge: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            Capsule()
                .fill(Color.black)
                .frame(height: 4)
                .overlay {
                    Capsule()
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                }
        }
        .frame(maxWidth: .infinity)
    }

    private var previewPhaseSelector: some View {
        HStack(spacing: 8) {
            ForEach(SessionPhase.allCases, id: \.self) { phase in
                Button {
                    previewPhase = phase
                } label: {
                    Text(phaseTitle(phase))
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(previewPhase == phase ? .white : .white.opacity(0.5))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(
                            Capsule().fill(
                                previewPhase == phase
                                    ? model.statusColor(for: phase).opacity(0.35)
                                    : Color.white.opacity(0.06)
                            )
                        )
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Status color row

    private func statusColorRow(_ phase: SessionPhase) -> some View {
        HStack(spacing: 12) {
            Circle()
                .fill(model.statusColor(for: phase))
                .frame(width: 10, height: 10)

            Text(phaseTitle(phase))

            Spacer()

            Text(model.statusColorHexes[phase] ?? "#6E9FFF")
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(.secondary)

            ColorPicker(
                "",
                selection: Binding(
                    get: { model.statusColor(for: phase) },
                    set: { model.setStatusColor($0, for: phase) }
                ),
                supportsOpacity: false
            )
            .labelsHidden()
        }
    }

    // MARK: - Pixel shape card

    private func pixelShapeCard(_ style: IslandPixelShapeStyle) -> some View {
        let selected = model.islandPixelShapeStyle == style
        return Button {
            if style == .custom && model.customAvatarImage == nil {
                model.importCustomAvatar()
            } else {
                model.islandPixelShapeStyle = style
            }
        } label: {
            VStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.white.opacity(0.05))
                    .frame(height: 48)
                    .overlay {
                        if style == .custom {
                            if let avatar = model.customAvatarImage {
                                Image(nsImage: avatar)
                                    .resizable()
                                    .interpolation(.high)
                                    .scaledToFill()
                                    .frame(width: 28, height: 28)
                                    .clipShape(Circle())
                            } else {
                                Image(systemName: "person.crop.circle.badge.plus")
                                    .font(.system(size: 20))
                                    .foregroundStyle(.secondary)
                            }
                        } else {
                            IslandPixelGlyph(
                                tint: model.statusColor(for: previewPhase),
                                style: style,
                                isAnimating: previewPhase != .completed,
                                width: 30,
                                height: 18
                            )
                        }
                    }

                Text(pixelShapeTitle(style))
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.primary)
            }
            .padding(10)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.white.opacity(selected ? 0.06 : 0.02))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(
                        selected ? Color.accentColor : Color.white.opacity(0.08),
                        lineWidth: selected ? 2 : 1
                    )
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Helpers

    private func phaseTitle(_ phase: SessionPhase) -> String {
        switch phase {
        case .running:            lang.t("settings.appearance.status.running")
        case .waitingForApproval: lang.t("settings.appearance.status.approval")
        case .waitingForAnswer:   lang.t("settings.appearance.status.answer")
        case .completed:          lang.t("settings.appearance.status.completed")
        }
    }

    private func pixelShapeTitle(_ style: IslandPixelShapeStyle) -> String {
        switch style {
        case .bars:   lang.t("settings.appearance.pixelShape.bars")
        case .steps:  lang.t("settings.appearance.pixelShape.steps")
        case .blocks: lang.t("settings.appearance.pixelShape.blocks")
        case .custom: lang.t("settings.appearance.pixelShape.custom")
        }
    }
}
