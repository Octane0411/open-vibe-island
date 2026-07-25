import SwiftUI
import OpenIslandCore

/// Flight Deck's install-hooks hint (AB-312): the persistent "install hooks"
/// prompt shown while no agent hooks are installed, framed in the avionics idiom
/// — a squared hairline panel led by a caution-amber warning glyph and an
/// uppercase "SETUP" tag, with a hover lift instead of glass. The tap still
/// routes to Settings → Setup via the same `onTap` closure, and the copy is
/// unchanged. Being a flat panel there is no transparency to reduce; the hover
/// lift settles without easing under Reduce Motion, and the "SETUP" tag's casing
/// and tracking neutralize for CJK.
struct FlightDeckInstallHooksHint: View {
    let lang: LanguageManager
    let onTap: () -> Void

    @State private var hovering = false

    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    private var increasesContrast: Bool { colorSchemeContrast == .increased }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.islandTokens) private var tokens

    private var fillOpacity: Double {
        hovering ? 0.08 : 0.03
    }

    private var strokeOpacity: Double {
        let base = tokens.colors.hairline(increaseContrast: increasesContrast)
        return hovering ? min(1, base + 0.14) : base
    }

    var body: some View {
        Button {
            onTap()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(tokens.colors.statusWarning)
                    .accessibilityHidden(true)
                Text(lang.t("island.hint.installHooks"))
                    .font(FlightDeckTypography.body)
                    .foregroundStyle(tokens.colors.paper.opacity(tokens.colors.text(0.88, increaseContrast: increasesContrast)))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 6)
                Text(FlightDeckText.caps(lang.t("island.flightDeck.hint.setup"), lang: lang))
                    .font(FlightDeckTypography.microLabel)
                    .tracking(FlightDeckText.tracking(1.2, lang: lang))
                    .foregroundStyle(tokens.colors.paper.opacity(hovering ? 0.7 : 0.5))
                    .accessibilityHidden(true)
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(tokens.colors.paper.opacity(hovering ? 0.6 : 0.4))
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(tokens.colors.paper.opacity(fillOpacity))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(tokens.colors.paper.opacity(strokeOpacity), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        // Hover lift settles without easing under Reduce Motion (AB-311 / AB-312).
        .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: hovering)
    }
}
