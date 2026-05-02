import SwiftUI
import OpenIslandCore

struct AppearanceSettingsPane: View {
    var model: AppModel
    @State private var previewPhase: SessionPhase = .running

    private var lang: LanguageManager { model.lang }
    private var isCustom: Bool { model.islandAppearanceMode == .custom }

    var body: some View {
        Form {
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
                DisclosureGroup(lang.t("settings.projectColors.title")) {
                    let keys = model.projectColorRegistry.knownKeys().sorted()
                    if keys.isEmpty {
                        Text(lang.t("settings.projectColors.empty"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(keys, id: \.self) { key in
                            projectColorRow(key)
                        }
                    }
                    HStack {
                        Button(lang.t("settings.projectColors.resetAll")) {
                            model.projectColorRegistry.resetAll()
                        }
                        Button(lang.t("settings.projectColors.removeUnused")) {
                            model.projectColorRegistry.pruneUnusedKeys(activePaths: model.activeWorkspaceKeys)
                        }
                    }
                    Text(lang.t("settings.projectColors.help"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section(lang.t("settings.companion.title")) {
                let petOptions: [(String, String)] = [
                    ("__none__", lang.t("settings.companion.pet.none")),
                    ("daily",    lang.t("settings.companion.pet.daily")),
                ] + CompanionPet.allCases.map { ($0.rawValue, lang.t("settings.companion.pet.\($0.rawValue)")) }

                Picker("", selection: Binding(
                    get: { model.companionPetSelection ?? "__none__" },
                    set: { newValue in
                        model.companionPetSelection = (newValue == "__none__") ? nil : newValue
                    }
                )) {
                    ForEach(petOptions, id: \.0) { value, label in
                        Text(label).tag(value)
                    }
                }
                .pickerStyle(.segmented)

                if let pet = model.resolvedCompanionPet {
                    VStack(spacing: 4) {
                        Text(lang.t("settings.companion.preview"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        companionLivePreview(pet: pet)
                            .frame(width: 64, height: 64)
                            .background(Color.black.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
                    }
                }
            }

            Section(lang.t("settings.ambient.title")) {
                Toggle(lang.t("settings.ambient.toggle"), isOn: Binding(
                    get: { model.ambientThemeEnabled },
                    set: { model.ambientThemeEnabled = $0 }
                ))

                HStack {
                    Text(lang.t("settings.ambient.subtle")).font(.caption).foregroundStyle(.secondary)
                    Slider(value: Binding(
                        get: { model.ambientThemeOpacity },
                        set: { model.ambientThemeOpacity = AmbientTheme.clampOpacity($0) }
                    ), in: AmbientTheme.minOpacity...AmbientTheme.maxOpacity)
                    Text(lang.t("settings.ambient.bold")).font(.caption).foregroundStyle(.secondary)
                }

                Text(lang.t("settings.ambient.help"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section(lang.t("settings.celebrations.title")) {
                Toggle(lang.t("settings.celebrations.toggle"), isOn: Binding(
                    get: { model.celebrationsEnabled },
                    set: { model.celebrationsEnabled = $0 }
                ))
                Text(lang.t("settings.celebrations.help"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
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

    @ViewBuilder
    private func companionLivePreview(pet: CompanionPet) -> some View {
        TimelineView(.animation) { timeline in
            let elapsed = timeline.date.timeIntervalSinceReferenceDate
            let stateIndex = Int(elapsed / 2.0) % 4
            let state: CompanionState = [.idle, .working, .waiting, .celebrating][stateIndex]
            AnimatedCompanionPet(pet: pet, state: state)
                .scaleEffect(3)
        }
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

    // MARK: - Project colors

    private static let projectColorPresets: [ProjectColor] = [
        ProjectColor(red: 0.94, green: 0.40, blue: 0.40),  // red
        ProjectColor(red: 0.96, green: 0.62, blue: 0.32),  // orange
        ProjectColor(red: 0.95, green: 0.84, blue: 0.36),  // yellow
        ProjectColor(red: 0.55, green: 0.85, blue: 0.45),  // green
        ProjectColor(red: 0.40, green: 0.83, blue: 0.69),  // teal
        ProjectColor(red: 0.36, green: 0.74, blue: 0.94),  // sky
        ProjectColor(red: 0.45, green: 0.55, blue: 0.95),  // blue
        ProjectColor(red: 0.65, green: 0.46, blue: 0.95),  // purple
        ProjectColor(red: 0.92, green: 0.50, blue: 0.85),  // pink
        ProjectColor(red: 0.78, green: 0.78, blue: 0.78),  // light gray
        ProjectColor(red: 0.50, green: 0.50, blue: 0.50),  // mid gray
        ProjectColor(red: 0.30, green: 0.30, blue: 0.30),  // dark gray
    ]

    @ViewBuilder
    private func projectColorRow(_ key: String) -> some View {
        let current = model.projectColorRegistry.color(for: key)
        HStack(spacing: 10) {
            Circle()
                .fill(swiftUIColor(current))
                .frame(width: 14, height: 14)
            VStack(alignment: .leading, spacing: 2) {
                Text((key as NSString).lastPathComponent)
                    .font(.system(size: 12, weight: .medium))
                Text(key)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
            Menu {
                ForEach(Array(Self.projectColorPresets.enumerated()), id: \.offset) { _, preset in
                    Button {
                        model.projectColorRegistry.setColor(preset, for: key)
                    } label: {
                        HStack {
                            Circle().fill(swiftUIColor(preset)).frame(width: 12, height: 12)
                            Text(hexLabel(preset))
                        }
                    }
                }
            } label: {
                Image(systemName: "paintpalette")
                    .font(.system(size: 12))
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
    }

    private func swiftUIColor(_ c: ProjectColor) -> Color {
        Color(red: c.red, green: c.green, blue: c.blue)
    }

    private func hexLabel(_ c: ProjectColor) -> String {
        let r = Int((c.red * 255).rounded())
        let g = Int((c.green * 255).rounded())
        let b = Int((c.blue * 255).rounded())
        return String(format: "#%02X%02X%02X", r, g, b)
    }
}
