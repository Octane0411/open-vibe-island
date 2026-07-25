import SwiftUI
import OpenIslandCore

/// Annual's cold-launch bootstrap placeholder (AB-316): the spinner and
/// "checking terminals" copy the app shows while probing terminal ownership, set
/// purely typographically like the empty state so the two pre-list states share
/// one editorial identity — a small-caps eyebrow over the body copy, with **no
/// box, bezel or pill**. Copy and spinner behavior are unchanged; the eyebrow's
/// casing / tracking neutralize for CJK.
struct AnnualBootstrapPlaceholder: View {
    let lang: LanguageManager

    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    private var increasesContrast: Bool { colorSchemeContrast == .increased }

    @Environment(\.islandTokens) private var tokens

    var body: some View {
        VStack(spacing: 8) {
            Spacer()
            Text(AnnualText.lower(lang.t("island.annual.state.loading"), lang: lang))
                .font(AnnualTypography.smallCaps)
                .tracking(AnnualText.tracking(1.6, lang: lang))
                .foregroundStyle(tokens.colors.paper.opacity(tokens.colors.text(tokens.colors.tertiaryTextOpacity, increaseContrast: increasesContrast)))
            ProgressView()
                .progressViewStyle(.circular)
                .tint(tokens.colors.paper.opacity(0.7))
                .scaleEffect(0.8)
            Text(lang.t("island.checkingTerminals"))
                .font(AnnualTypography.body)
                .foregroundStyle(tokens.colors.paper.opacity(tokens.colors.text(tokens.colors.secondaryTextOpacity, increaseContrast: increasesContrast)))
            Text(lang.t("island.terminalOwnership"))
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
