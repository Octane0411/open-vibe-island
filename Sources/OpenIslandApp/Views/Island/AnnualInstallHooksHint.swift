import SwiftUI
import OpenIslandCore

/// Annual's install-hooks hint (AB-316): the persistent "install hooks" prompt
/// shown while no agent hooks are installed, set typographically in the editorial
/// idiom — a caution glyph and the copy, closed by a small-caps "setup" tag and a
/// chevron, with **no box or pill**. A single hairline rule under the line seats
/// it as an editorial masthead entry rather than a chip, and a hover lifts the
/// text opacity. The tap still routes to Settings → Setup through the same `onTap`
/// closure, and the copy is unchanged. Being a flat page there is no transparency
/// to reduce; the hover lift settles without easing under Reduce Motion, and the
/// "setup" tag's casing / tracking neutralize for CJK. The caution glyph draws in
/// the warm-grey caution tone — not the accent — since an install hint is not a
/// session attention state.
struct AnnualInstallHooksHint: View {
    let lang: LanguageManager
    let onTap: () -> Void

    @State private var hovering = false

    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    private var increasesContrast: Bool { colorSchemeContrast == .increased }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.islandTokens) private var tokens

    var body: some View {
        Button {
            onTap()
        } label: {
            VStack(spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 11, weight: .regular))
                        .foregroundStyle(tokens.colors.statusWarning)
                        .accessibilityHidden(true)
                    Text(lang.t("island.hint.installHooks"))
                        .font(AnnualTypography.body)
                        .foregroundStyle(tokens.colors.paper.opacity(tokens.colors.text(hovering ? 0.92 : 0.8, increaseContrast: increasesContrast)))
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    Spacer(minLength: 6)
                    Text(AnnualText.lower(lang.t("island.annual.hint.setup"), lang: lang))
                        .font(AnnualTypography.smallCaps)
                        .tracking(AnnualText.tracking(1.0, lang: lang))
                        .foregroundStyle(tokens.colors.paper.opacity(tokens.colors.text(hovering ? 0.7 : 0.5, increaseContrast: increasesContrast)))
                        .accessibilityHidden(true)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .regular))
                        .foregroundStyle(tokens.colors.paper.opacity(hovering ? 0.6 : 0.4))
                        .accessibilityHidden(true)
                }
                Rectangle()
                    .fill(tokens.colors.paper.opacity(tokens.colors.hairline(increaseContrast: increasesContrast)))
                    .frame(height: AnnualHairline.hairline)
            }
            .padding(.horizontal, 2)
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        // Hover lift settles without easing under Reduce Motion (AB-316).
        .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: hovering)
    }
}
