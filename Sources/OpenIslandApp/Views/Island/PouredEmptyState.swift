import SwiftUI
import OpenIslandCore

/// Poured Island's empty state (AB-301): the same "No terminals" copy and the
/// "start an agent" / "recent sessions" second line Classic shows, but recessed
/// into the glass — a faint frosted panel behind the text so the empty surface
/// reads as part of the poured slab rather than a blank hole. The copy and the
/// `hasRecentSessions` branch are unchanged.
struct PouredEmptyState: View {
    let lang: LanguageManager
    let hasRecentSessions: Bool

    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    private var increasesContrast: Bool { colorSchemeContrast == .increased }

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.islandTokens) private var tokens

    var body: some View {
        VStack(spacing: 12) {
            Spacer()
            Text(lang.t("island.noTerminals"))
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(tokens.colors.paper.opacity(tokens.colors.text(tokens.colors.secondaryTextOpacity, increaseContrast: increasesContrast)))
            Text(hasRecentSessions
                ? lang.t("island.recentSessions")
                : lang.t("island.startAgent"))
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
