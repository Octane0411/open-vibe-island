import SwiftUI
import OpenIslandCore

struct OnboardingAgentsScreen: View {
    var coordinator: OnboardingCoordinator
    var lang: LanguageManager

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(lang.t("onboarding.agents.title"))
                .font(.system(size: 22, weight: .bold))

            Text(lang.t("onboarding.agents.subtitle"))
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            ScrollView {
                VStack(spacing: 8) {
                    ForEach(OnboardingCoordinator.primaryAgents, id: \.self) { agent in
                        agentRow(agent)
                    }

                    DisclosureGroup(isExpanded: Binding(
                        get: { coordinator.moreAgentsExpanded },
                        set: { coordinator.moreAgentsExpanded = $0 }
                    )) {
                        VStack(spacing: 8) {
                            ForEach(OnboardingCoordinator.secondaryAgents, id: \.self) { agent in
                                agentRow(agent)
                            }
                        }
                        .padding(.top, 8)
                    } label: {
                        Text(lang.t("onboarding.agents.more"))
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                }
            }
            .frame(maxHeight: 320)

            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "info.circle")
                    .foregroundStyle(.secondary)
                Text(lang.t("onboarding.agents.footnote"))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)

            HStack {
                Button(lang.t("onboarding.back")) { coordinator.goBack() }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)

                Spacer()

                Button(lang.t("onboarding.continue")) {
                    coordinator.advance()
                }
                .keyboardShortcut(.defaultAction)
                .controlSize(.large)
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(40)
    }

    @ViewBuilder
    private func agentRow(_ agent: AgentIdentifier) -> some View {
        let selected = coordinator.isSelected(agent)
        HStack(spacing: 12) {
            Image(systemName: agentIcon(agent))
                .font(.system(size: 16))
                .foregroundStyle(.tint)
                .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(agentDisplayName(agent))
                    .font(.system(size: 13, weight: .semibold))
                Text(lang.t("onboarding.agents.desc.\(agent.rawValue)"))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Toggle("", isOn: Binding(
                get: { selected },
                set: { _ in coordinator.toggleSelection(agent) }
            ))
            .toggleStyle(.switch)
            .labelsHidden()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.secondary.opacity(0.08))
        )
    }

    private func agentDisplayName(_ agent: AgentIdentifier) -> String {
        switch agent {
        case .claudeCode: return "Claude Code"
        case .codex: return "Codex"
        case .cursor: return "Cursor"
        case .openCode: return "OpenCode"
        case .qoder: return "Qoder"
        case .qwenCode: return "Qwen Code"
        case .factory: return "Factory"
        case .codebuddy: return "CodeBuddy"
        case .gemini: return "Gemini CLI"
        case .claudeUsageBridge: return "Claude Usage Bridge"
        }
    }

    private func agentIcon(_ agent: AgentIdentifier) -> String {
        switch agent {
        case .claudeCode, .qoder, .qwenCode, .factory, .codebuddy: return "terminal"
        case .codex: return "chevron.left.slash.chevron.right"
        case .cursor: return "cursorarrow.rays"
        case .openCode: return "curlybraces"
        case .gemini: return "sparkles"
        case .claudeUsageBridge: return "chart.bar"
        }
    }
}
