import SwiftUI
import OpenIslandCore

/// Flight Deck's empty state (AB-312): the same "No terminals" copy and the
/// "start an agent" / "recent sessions" second line the app shows, framed in the
/// avionics idiom — a squared `surfaceInk` panel outlined by a single hairline
/// bezel rule, headed by an uppercase letterspaced "NO SIGNAL" caption so the
/// empty surface reads as a cockpit panel at rest rather than a blank hole. The
/// copy and the `hasRecentSessions` branch are unchanged. Being a flat panel,
/// there is no transparency to reduce; the caption's casing and tracking
/// neutralize for CJK.
struct FlightDeckEmptyState: View {
    let lang: LanguageManager
    let hasRecentSessions: Bool

    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    private var increasesContrast: Bool { colorSchemeContrast == .increased }

    @Environment(\.islandTokens) private var tokens

    var body: some View {
        VStack(spacing: 10) {
            Spacer()
            Text(FlightDeckText.caps(lang.t("island.flightDeck.state.noSignal"), lang: lang))
                .font(FlightDeckTypography.microLabel)
                .tracking(FlightDeckText.tracking(1.6, lang: lang))
                .foregroundStyle(tokens.colors.paper.opacity(tokens.colors.text(tokens.colors.tertiaryTextOpacity, increaseContrast: increasesContrast)))
            Text(lang.t("island.noTerminals"))
                .font(FlightDeckTypography.body)
                .foregroundStyle(tokens.colors.paper.opacity(tokens.colors.text(tokens.colors.secondaryTextOpacity, increaseContrast: increasesContrast)))
            Text(hasRecentSessions
                ? lang.t("island.recentSessions")
                : lang.t("island.startAgent"))
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
