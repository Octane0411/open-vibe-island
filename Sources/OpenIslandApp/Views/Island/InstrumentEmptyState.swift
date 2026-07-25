import SwiftUI
import OpenIslandCore

/// Instrument's empty state (AB-308): the same "No terminals" copy and the
/// "start an agent" / "recent sessions" second line the app shows, framed in the
/// instrument idiom — a squared `surfaceInk` panel outlined by a single hairline
/// rule, headed by an uppercase letterspaced "NO SIGNAL" caption so the empty
/// surface reads as a console at rest rather than a blank hole. The copy and the
/// `hasRecentSessions` branch are unchanged. Being a flat panel, there is no
/// transparency to reduce; the caption's casing and tracking neutralize for CJK.
struct InstrumentEmptyState: View {
    let lang: LanguageManager
    let hasRecentSessions: Bool

    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    private var increasesContrast: Bool { colorSchemeContrast == .increased }

    @Environment(\.islandTokens) private var tokens

    var body: some View {
        VStack(spacing: 10) {
            Spacer()
            Text(InstrumentText.caps(lang.t("island.instrument.state.noSignal"), lang: lang))
                .font(InstrumentTypography.microLabel)
                .tracking(InstrumentText.tracking(1.6, lang: lang))
                .foregroundStyle(tokens.colors.paper.opacity(tokens.colors.text(tokens.colors.tertiaryTextOpacity, increaseContrast: increasesContrast)))
            Text(lang.t("island.noTerminals"))
                .font(InstrumentTypography.body)
                .foregroundStyle(tokens.colors.paper.opacity(tokens.colors.text(tokens.colors.secondaryTextOpacity, increaseContrast: increasesContrast)))
            Text(hasRecentSessions
                ? lang.t("island.recentSessions")
                : lang.t("island.startAgent"))
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
