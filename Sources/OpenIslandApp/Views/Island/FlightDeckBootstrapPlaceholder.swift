import SwiftUI
import OpenIslandCore

/// Flight Deck's cold-launch bootstrap placeholder (AB-312): the spinner and
/// "checking terminals" copy the app shows while probing terminal ownership,
/// framed in the same squared hairline panel as the empty state so the two
/// pre-list states share one avionics identity, headed by an uppercase "STANDBY"
/// caption. Copy and spinner behavior are unchanged; the caption's casing and
/// tracking neutralize for CJK.
struct FlightDeckBootstrapPlaceholder: View {
    let lang: LanguageManager

    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    private var increasesContrast: Bool { colorSchemeContrast == .increased }

    @Environment(\.islandTokens) private var tokens

    var body: some View {
        VStack(spacing: 10) {
            Spacer()
            Text(FlightDeckText.caps(lang.t("island.flightDeck.state.standby"), lang: lang))
                .font(FlightDeckTypography.microLabel)
                .tracking(FlightDeckText.tracking(1.6, lang: lang))
                .foregroundStyle(tokens.colors.paper.opacity(tokens.colors.text(tokens.colors.tertiaryTextOpacity, increaseContrast: increasesContrast)))
            ProgressView()
                .progressViewStyle(.circular)
                .tint(tokens.colors.paper.opacity(0.7))
                .scaleEffect(0.8)
            Text(lang.t("island.checkingTerminals"))
                .font(FlightDeckTypography.body)
                .foregroundStyle(tokens.colors.paper.opacity(tokens.colors.text(tokens.colors.secondaryTextOpacity, increaseContrast: increasesContrast)))
            Text(lang.t("island.terminalOwnership"))
                .font(.system(size: FlightDeckTypography.microLabelSize, weight: .regular, design: .monospaced))
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
