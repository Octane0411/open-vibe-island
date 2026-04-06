import SwiftUI

struct SetupGuideView: View {
    var model: AppModel
    @Environment(\.dismiss) private var dismiss

    private var lang: LanguageManager { model.lang }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(spacing: 0) {
                    // Section: Hooks Binary
                    sectionHeader(lang.t("setup.section.binary"))
                    binaryRow
                    Divider().padding(.horizontal, 20)

                    // Section: CLI Hooks
                    sectionHeader(lang.t("setup.section.hooks"))
                    setupRow(
                        icon: "terminal",
                        name: "Claude Code",
                        subtitle: hookSubtitle(installed: model.claudeHooksInstalled),
                        installed: model.claudeHooksInstalled,
                        busy: model.isClaudeHookSetupBusy,
                        canInstall: model.hooksBinaryURL != nil,
                        installAction: { model.installClaudeHooks() }
                    )
                    Divider().padding(.horizontal, 20)
                    setupRow(
                        icon: "terminal",
                        name: "Codex",
                        subtitle: hookSubtitle(installed: model.codexHooksInstalled),
                        installed: model.codexHooksInstalled,
                        busy: model.isCodexSetupBusy,
                        canInstall: model.hooksBinaryURL != nil,
                        installAction: { model.installCodexHooks() }
                    )
                    Divider().padding(.horizontal, 20)

                    // Section: Usage Bridge (optional)
                    sectionHeader(lang.t("setup.section.usage"))
                    setupRow(
                        icon: "chart.bar",
                        name: lang.t("setup.usageBridge"),
                        subtitle: model.claudeUsageInstalled
                            ? lang.t("setup.usageBridgeReady")
                            : lang.t("setup.usageBridgeDesc"),
                        installed: model.claudeUsageInstalled,
                        busy: model.isClaudeUsageSetupBusy,
                        canInstall: true,
                        installAction: { model.installClaudeUsageBridge() },
                        optional: true
                    )
                    Divider().padding(.horizontal, 20)

                    // Section: Permissions info
                    sectionHeader(lang.t("setup.section.permissions"))
                    permissionsInfoRow
                }
                .padding(.bottom, 8)
            }

            Divider()
            footer
        }
        .frame(width: 460, height: 520)
        .preferredColorScheme(.dark)
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 10) {
            OpenIslandBrandMark(size: 56, style: .duotone)
            Text(lang.t("setup.title"))
                .font(.title2.bold())
            Text(lang.t("setup.subtitle"))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .padding(.top, 28)
        .padding(.bottom, 20)
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            Button(lang.t("setup.skip")) {
                model.dismissSetupGuide()
                dismiss()
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)

            Spacer()

            if allRequiredReady {
                Button(lang.t("setup.done")) {
                    model.dismissSetupGuide()
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            } else {
                Button(lang.t("setup.installAll")) {
                    installAllMissing()
                }
                .buttonStyle(.borderedProminent)
                .disabled(model.hooksBinaryURL == nil || anyBusy)
            }
        }
        .padding(20)
    }

    // MARK: - Section header

    private func sectionHeader(_ title: String) -> some View {
        HStack {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.top, 14)
        .padding(.bottom, 6)
    }

    // MARK: - Binary row

    private var binaryRow: some View {
        HStack {
            Image(systemName: "hammer")
                .font(.body)
                .foregroundStyle(.secondary)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text("OpenIslandHooks")
                    .font(.body.weight(.medium))
                Text(model.hooksBinaryURL != nil
                     ? lang.t("setup.binaryReady")
                     : lang.t("setup.binaryMissing"))
                    .font(.caption)
                    .foregroundStyle(model.hooksBinaryURL != nil ? .green : .orange)
            }
            Spacer()
            if model.hooksBinaryURL != nil {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.title3)
            } else {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.yellow)
                    .font(.title3)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
    }

    // MARK: - Generic setup row

    private func setupRow(
        icon: String,
        name: String,
        subtitle: String,
        installed: Bool,
        busy: Bool,
        canInstall: Bool,
        installAction: @escaping () -> Void,
        optional: Bool = false
    ) -> some View {
        HStack {
            Image(systemName: icon)
                .font(.body)
                .foregroundStyle(.secondary)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(name)
                        .font(.body.weight(.medium))
                    if optional {
                        Text(lang.t("setup.optional"))
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(.quaternary, in: RoundedRectangle(cornerRadius: 3))
                    }
                }
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(installed ? .green : .secondary)
            }
            Spacer()
            if installed {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.title3)
            } else if busy {
                ProgressView()
                    .controlSize(.small)
            } else {
                Button(lang.t("settings.general.install")) {
                    installAction()
                }
                .disabled(!canInstall)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
    }

    // MARK: - Permissions info row

    private var permissionsInfoRow: some View {
        HStack(alignment: .top) {
            Image(systemName: "lock.shield")
                .font(.body)
                .foregroundStyle(.secondary)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(lang.t("setup.permissionsTitle"))
                    .font(.body.weight(.medium))
                Text(lang.t("setup.permissionsDesc"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "info.circle")
                .foregroundStyle(.secondary)
                .font(.title3)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
    }

    // MARK: - Helpers

    private func hookSubtitle(installed: Bool) -> String {
        installed ? lang.t("setup.hookReady") : lang.t("setup.hookMissing")
    }

    private var allRequiredReady: Bool {
        model.claudeHooksInstalled && model.codexHooksInstalled
    }

    private var anyBusy: Bool {
        model.isClaudeHookSetupBusy || model.isCodexSetupBusy || model.isClaudeUsageSetupBusy
    }

    private func installAllMissing() {
        if !model.claudeHooksInstalled {
            model.installClaudeHooks()
        }
        if !model.codexHooksInstalled {
            model.installCodexHooks()
        }
        if !model.claudeUsageInstalled {
            model.installClaudeUsageBridge()
        }
    }
}
