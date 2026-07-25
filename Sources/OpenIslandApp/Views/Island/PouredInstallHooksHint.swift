import SwiftUI
import OpenIslandCore

/// Poured Island's install-hooks hint (AB-301): the persistent "install hooks"
/// prompt shown while no agent hooks are installed, restyled into the glass
/// identity — a frosted capsule with a specular lip and a hover lift instead of
/// Classic's accent-tinted card. The tap still routes to Settings → Setup via
/// the same `onTap` closure, and the copy is unchanged.
struct PouredInstallHooksHint: View {
    let lang: LanguageManager
    let onTap: () -> Void

    @State private var hovering = false

    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    private var increasesContrast: Bool { colorSchemeContrast == .increased }

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.islandTokens) private var tokens

    private var fillOpacity: Double {
        if reduceTransparency {
            return hovering ? 0.16 : 0.1
        }
        return hovering ? 0.11 : 0.06
    }

    var body: some View {
        Button {
            onTap()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(tokens.colors.paper.opacity(0.9))
                    .accessibilityHidden(true)
                Text(lang.t("island.hint.installHooks"))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(tokens.colors.paper.opacity(tokens.colors.text(0.88, increaseContrast: increasesContrast)))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(tokens.colors.paper.opacity(hovering ? 0.6 : 0.4))
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(.white.opacity(fillOpacity))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(.white.opacity(hovering ? 0.22 : 0.12), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        // Hover lift settles without easing under Reduce Motion (AB-304).
        .animation(reduceMotion ? nil : .easeOut(duration: 0.14), value: hovering)
    }
}
