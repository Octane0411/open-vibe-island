import SwiftUI
import OpenIslandCore

/// Poured Island's empty state (AB-301 · AB-331, `SPEC-poured-island` §3.6/§4J).
///
/// The same "No terminals" copy and the "start an agent" / "recent sessions"
/// second line Classic shows, but recessed into the glass — a faint frosted
/// panel behind the text so the empty surface reads as part of the poured slab
/// rather than a blank hole. The copy and the `hasRecentSessions` branch are
/// unchanged.
///
/// Poured 2.0 adds the two §4J touches that turn silence into "quiet confidence,
/// not a hole": a slow-breathing monitor glyph above the copy (the only motion
/// in an otherwise still frame — held mid-glow under Reduce Motion), and a
/// `✓ Hooks installed for …` reassurance pill that lists the agents whose hooks
/// are wired so the user reads the quiet as "nothing to do", not "is this
/// broken?". The pill is hidden entirely when no agents are installed.
struct PouredEmptyState: View {
    let lang: LanguageManager
    let hasRecentSessions: Bool
    /// Human display names of agents whose managed hooks are installed
    /// (`AppModel.installedAgentDisplayNames`). Empty ⇒ no reassurance pill.
    var installedAgentNames: [String] = []

    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    private var increasesContrast: Bool { colorSchemeContrast == .increased }

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.islandTokens) private var tokens

    var body: some View {
        VStack(spacing: 12) {
            Spacer()

            PouredEmptyMonitorGlyph()

            Text(lang.t("island.noTerminals"))
                .font(PouredType.Role.emptyTitle.font)
                .foregroundStyle(tokens.colors.paper.opacity(tokens.colors.text(0.96, increaseContrast: increasesContrast)))

            Text(hasRecentSessions
                ? lang.t("island.recentSessions")
                : lang.t("island.startAgent"))
                .font(PouredType.Role.emptySubtitle.font)
                .multilineTextAlignment(.center)
                .foregroundStyle(tokens.colors.paper.opacity(tokens.colors.text(tokens.colors.secondaryTextOpacity, increaseContrast: increasesContrast)))

            if !installedAgentNames.isEmpty {
                hooksInstalledPill
                    .padding(.top, 2)
            }

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

    /// The §4J reassurance pill: `✓ Hooks installed for Claude, Codex, Gemini`.
    /// Deliberately quiet — tertiary ink on a faint white capsule, no accent, no
    /// glow (a reassurance, not an attention state; color = state discipline).
    private var hooksInstalledPill: some View {
        HStack(spacing: 7) {
            Image(systemName: "checkmark")
                .font(.system(size: 9, weight: .bold))
                .accessibilityHidden(true)
            Text(lang.t("island.poured.empty.hooksInstalled", joinedInstalledNames))
                .font(.system(size: 11, weight: .regular))
        }
        .foregroundStyle(tokens.colors.paper.opacity(tokens.colors.text(tokens.colors.tertiaryTextOpacity, increaseContrast: increasesContrast)))
        .padding(.horizontal, 11)
        .padding(.vertical, 5)
        .background(.white.opacity(reduceTransparency ? 0.06 : 0.03), in: Capsule())
        .accessibilityElement(children: .combine)
    }

    /// The installed agent names joined for the sentence, using each locale's
    /// natural list separator (`, ` for Latin, the ideographic `、` for CJK) so
    /// the join reads correctly in every language.
    private var joinedInstalledNames: String {
        installedAgentNames.joined(separator: lang.usesCJKScript ? "、" : ", ")
    }
}

/// The §4J monitor glyph: a small hollow ring with four cardinal ticks (the
/// mockup's radial "watching" mark) inside a recessed disc, wrapped in a slow
/// `lumen` 3s cool-blue breathing glow — the single moment of life in the empty
/// frame. Under Reduce Motion the glow holds at its mid point (no animation),
/// exactly as `PouredWaitingTile` does, so the mark still reads as "monitoring"
/// without moving.
private struct PouredEmptyMonitorGlyph: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.islandTokens) private var tokens

    @State private var breathe = false

    private var glyphColor: Color { tokens.colors.paper.opacity(0.66) }

    var body: some View {
        let active = reduceMotion ? true : breathe
        ZStack {
            Circle()
                .stroke(glyphColor, lineWidth: 1.6)
                .frame(width: 8, height: 8)

            ForEach(0..<4, id: \.self) { index in
                Capsule()
                    .fill(glyphColor)
                    .frame(width: 1.6, height: 4)
                    .offset(y: -11)
                    .rotationEffect(.degrees(Double(index) * 90))
            }
        }
        .frame(width: 34, height: 34)
        .background(Circle().fill(.white.opacity(0.03)))
        // `lumen`: the cool-blue running tint bloom, breathing 0 → r22 (CSS) so
        // the disc reads as a live sensor. Held mid-glow under Reduce Motion.
        .shadow(
            color: tokens.colors.statusRunning.opacity(active ? 0.16 : 0),
            radius: active ? 11 : 0
        )
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 3).repeatForever(autoreverses: true)) {
                breathe = true
            }
        }
        .accessibilityHidden(true)
    }
}
