import OpenIslandCore
import SwiftUI

struct MenuBarContentView: View {
    var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(model.lang.t("app.name.oss"))
                .font(.headline)
            Text(model.lang.t("menu.status", model.liveSessionCount, model.liveAttentionCount))
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Divider()

            Button(model.lang.t("menu.settings")) {
                model.showSettings()
            }

            #if DEBUG
            Button(model.lang.t("menu.openDebug")) {
                model.showControlCenter()
            }
            #endif

            Text(model.acceptanceStatusTitle)
                .font(.subheadline.weight(.semibold))
            Text(model.acceptanceStatusSummary)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Divider()

            Button(model.isOverlayVisible ? model.lang.t("menu.hideOverlay") : model.lang.t("menu.showOverlay")) {
                model.toggleOverlay()
            }

            Divider()

            Text(model.codexHookStatusTitle)
                .font(.subheadline.weight(.semibold))
            Text(model.codexHookStatusSummary)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Button(model.lang.t("menu.refreshCodexHooks")) {
                model.refreshCodexHookStatus()
            }

            if model.codexHooksInstalled {
                Button(model.lang.t("menu.uninstallCodexHooks")) {
                    model.uninstallCodexHooks()
                }
            } else {
                Button(model.lang.t("menu.installCodexHooks")) {
                    model.installCodexHooks()
                }
                .disabled(model.hooksBinaryURL == nil)
            }

            Divider()

            Text(model.claudeHookStatusTitle)
                .font(.subheadline.weight(.semibold))
            Text(model.claudeHookStatusSummary)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Button(model.lang.t("menu.refreshClaudeHooks")) {
                model.refreshClaudeHookStatus()
            }

            if model.claudeHooksInstalled {
                Button(model.lang.t("menu.uninstallClaudeHooks")) {
                    model.uninstallClaudeHooks()
                }
            } else {
                Button(model.lang.t("menu.installClaudeHooks")) {
                    model.installClaudeHooks()
                }
                .disabled(model.hooksBinaryURL == nil)
            }

            if let session = model.focusedSession {
                Divider()
                Text(session.displayName)
                    .font(.subheadline.weight(.semibold))
                Text(session.spotlightPrimaryText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if let currentTool = session.spotlightCurrentToolLabel {
                    Text(model.lang.t("menu.liveTool", currentTool))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                if let trackingLabel = session.spotlightTrackingLabel {
                    Text(model.lang.t("menu.tracking", trackingLabel))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(16)
        .frame(width: 280)
    }
}
