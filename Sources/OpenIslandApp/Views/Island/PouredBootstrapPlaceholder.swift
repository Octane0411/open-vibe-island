import SwiftUI
import OpenIslandCore

/// Poured Island's cold-launch bootstrap placeholder (AB-301): the spinner and
/// "checking terminals" copy Classic shows while probing terminal ownership,
/// recessed into the same faint glass panel as the empty state so the two
/// pre-list states share one identity. Copy and spinner behavior are unchanged.
struct PouredBootstrapPlaceholder: View {
    let lang: LanguageManager

    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    private var increasesContrast: Bool { colorSchemeContrast == .increased }

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.islandTokens) private var tokens

    var body: some View {
        VStack(spacing: 12) {
            Spacer()
            ProgressView()
                .progressViewStyle(.circular)
                .tint(tokens.colors.paper.opacity(0.7))
                .scaleEffect(0.8)
            Text(lang.t("island.checkingTerminals"))
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(tokens.colors.paper.opacity(tokens.colors.text(tokens.colors.secondaryTextOpacity, increaseContrast: increasesContrast)))
            Text(lang.t("island.terminalOwnership"))
                .font(.system(size: 12))
                .foregroundStyle(tokens.colors.paper.opacity(tokens.colors.text(tokens.colors.tertiaryTextOpacity, increaseContrast: increasesContrast)))
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 22)
        .padding(.horizontal, 18)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.white.opacity(reduceTransparency ? 0.05 : 0.025))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(.white.opacity(tokens.colors.hairline(increaseContrast: increasesContrast)), lineWidth: 1)
                )
        )
    }
}
