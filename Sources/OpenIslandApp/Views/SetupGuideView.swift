import SwiftUI

struct SetupGuideView: View {
    var model: AppModel
    @Environment(\.dismiss) private var dismiss

    private var lang: LanguageManager { model.lang }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(spacing: 12) {
                OpenIslandBrandMark(size: 64, style: .duotone)
                Text(lang.t("setup.title"))
                    .font(.title2.bold())
                Text(lang.t("setup.subtitle"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.top, 32)
            .padding(.bottom, 24)

            Divider()

            // Hook rows
            VStack(spacing: 0) {
                hookRow(
                    name: "Claude Code",
                    installed: model.claudeHooksInstalled,
                    busy: model.isClaudeHookSetupBusy,
                    binaryMissing: model.hooksBinaryURL == nil,
                    installAction: { model.installClaudeHooks() }
                )

                Divider().padding(.horizontal, 20)

                hookRow(
                    name: "Codex",
                    installed: model.codexHooksInstalled,
                    busy: model.isCodexSetupBusy,
                    binaryMissing: model.hooksBinaryURL == nil,
                    installAction: { model.installCodexHooks() }
                )
            }
            .padding(.vertical, 16)

            if model.hooksBinaryURL == nil {
                binaryMissingHint
                    .padding(.horizontal, 20)
                    .padding(.bottom, 8)
            }

            Spacer()

            Divider()

            // Footer buttons
            HStack {
                Button(lang.t("setup.skip")) {
                    model.dismissSetupGuide()
                    dismiss()
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)

                Spacer()

                if allHooksInstalled {
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
        .frame(width: 420, height: 400)
        .preferredColorScheme(.dark)
    }

    // MARK: - Subviews

    private func hookRow(
        name: String,
        installed: Bool,
        busy: Bool,
        binaryMissing: Bool,
        installAction: @escaping () -> Void
    ) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(.body.weight(.medium))
                Text(installed
                     ? lang.t("setup.hookReady")
                     : lang.t("setup.hookMissing"))
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
                .disabled(binaryMissing)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    @ViewBuilder
    private var binaryMissingHint: some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.yellow)
                .font(.caption)
            Text(lang.t("setup.binaryMissing"))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Helpers

    private var allHooksInstalled: Bool {
        model.claudeHooksInstalled && model.codexHooksInstalled
    }

    private var anyBusy: Bool {
        model.isClaudeHookSetupBusy || model.isCodexSetupBusy
    }

    private func installAllMissing() {
        if !model.claudeHooksInstalled {
            model.installClaudeHooks()
        }
        if !model.codexHooksInstalled {
            model.installCodexHooks()
        }
    }
}
