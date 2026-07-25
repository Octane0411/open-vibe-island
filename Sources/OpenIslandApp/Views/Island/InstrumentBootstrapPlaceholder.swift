import SwiftUI
import OpenIslandCore

/// Instrument's cold-launch bootstrap placeholder (AB-308): the spinner and
/// "checking terminals" copy the app shows while probing terminal ownership,
/// framed in the same squared hairline panel as the empty state so the two
/// pre-list states share one instrument identity, headed by an uppercase
/// "PROBING" caption. Copy and spinner behavior are unchanged; the caption's
/// casing and tracking neutralize for CJK.
struct InstrumentBootstrapPlaceholder: View {
    let lang: LanguageManager

    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    private var increasesContrast: Bool { colorSchemeContrast == .increased }

    @Environment(\.islandTokens) private var tokens

    var body: some View {
        VStack(spacing: 10) {
            Spacer()
            Text(InstrumentText.caps(lang.t("island.instrument.state.probing"), lang: lang))
                .font(InstrumentTypography.microLabel)
                .tracking(InstrumentText.tracking(1.6, lang: lang))
                .foregroundStyle(tokens.colors.paper.opacity(tokens.colors.text(tokens.colors.tertiaryTextOpacity, increaseContrast: increasesContrast)))
            ProgressView()
                .progressViewStyle(.circular)
                .tint(tokens.colors.paper.opacity(0.7))
                .scaleEffect(0.8)
            Text(lang.t("island.checkingTerminals"))
                .font(InstrumentTypography.body)
                .foregroundStyle(tokens.colors.paper.opacity(tokens.colors.text(tokens.colors.secondaryTextOpacity, increaseContrast: increasesContrast)))
            Text(lang.t("island.terminalOwnership"))
                .font(.system(size: InstrumentTypography.microLabelSize, weight: .regular, design: .monospaced))
                .multilineTextAlignment(.center)
                .foregroundStyle(tokens.colors.paper.opacity(tokens.colors.text(tokens.colors.tertiaryTextOpacity, increaseContrast: increasesContrast)))
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 22)
        .padding(.horizontal, 18)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(tokens.colors.paper.opacity(increasesContrast ? 0.03 : 0.012))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(tokens.colors.paper.opacity(tokens.colors.hairline(increaseContrast: increasesContrast)), lineWidth: 1)
                )
        )
    }
}
