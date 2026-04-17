import SwiftUI

struct OnboardingWelcomeScreen: View {
    var coordinator: OnboardingCoordinator
    var lang: LanguageManager
    var onSkip: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Spacer(minLength: 0)

            Image(systemName: "sparkles")
                .font(.system(size: 52, weight: .light))
                .foregroundStyle(.tint)
                .padding(.bottom, 4)

            Text(lang.t("onboarding.welcome.title"))
                .font(.system(size: 26, weight: .bold))

            Text(lang.t("onboarding.welcome.subtitle"))
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 500)

            VStack(alignment: .leading, spacing: 10) {
                bullet(lang.t("onboarding.welcome.bullet.agents"))
                bullet(lang.t("onboarding.welcome.bullet.permissions"))
                bullet(lang.t("onboarding.welcome.bullet.jump"))
            }
            .frame(maxWidth: 440, alignment: .leading)
            .padding(.top, 8)

            Spacer(minLength: 0)

            HStack {
                Button(lang.t("onboarding.welcome.skip")) { onSkip() }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)

                Spacer()

                Button(lang.t("onboarding.welcome.continue")) {
                    coordinator.advance()
                }
                .keyboardShortcut(.defaultAction)
                .controlSize(.large)
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(40)
    }

    private func bullet(_ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.tint)
                .font(.system(size: 14))
            Text(text)
                .font(.system(size: 13))
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
