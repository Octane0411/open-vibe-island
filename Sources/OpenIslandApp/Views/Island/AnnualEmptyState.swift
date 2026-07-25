import SwiftUI
import OpenIslandCore

/// Annual's empty state (AB-316): the same "No terminals" copy and the
/// "start an agent" / "recent sessions" second line the app shows, set purely
/// typographically in the editorial idiom — a small-caps eyebrow over the body
/// copy and a quiet tertiary line, with **no box, bezel or pill**; hierarchy is
/// carried by the type scale, weight and case alone. The copy and the
/// `hasRecentSessions` branch are unchanged, and the eyebrow's casing / tracking
/// neutralize for CJK.
struct AnnualEmptyState: View {
    let lang: LanguageManager
    let hasRecentSessions: Bool

    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    private var increasesContrast: Bool { colorSchemeContrast == .increased }

    @Environment(\.islandTokens) private var tokens

    var body: some View {
        VStack(spacing: 8) {
            Spacer()
            Text(AnnualText.lower(lang.t("island.annual.state.empty"), lang: lang))
                .font(AnnualTypography.smallCaps)
                .tracking(AnnualText.tracking(1.6, lang: lang))
                .foregroundStyle(tokens.colors.paper.opacity(tokens.colors.text(tokens.colors.tertiaryTextOpacity, increaseContrast: increasesContrast)))
            Text(lang.t("island.noTerminals"))
                .font(AnnualTypography.body)
                .foregroundStyle(tokens.colors.paper.opacity(tokens.colors.text(tokens.colors.secondaryTextOpacity, increaseContrast: increasesContrast)))
            Text(hasRecentSessions
                ? lang.t("island.recentSessions")
                : lang.t("island.startAgent"))
                .font(.system(size: AnnualTypography.microLabelSize, weight: .regular, design: .monospaced))
                .multilineTextAlignment(.center)
                .foregroundStyle(tokens.colors.paper.opacity(tokens.colors.text(tokens.colors.tertiaryTextOpacity, increaseContrast: increasesContrast)))
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 22)
        .padding(.horizontal, 18)
    }
}
