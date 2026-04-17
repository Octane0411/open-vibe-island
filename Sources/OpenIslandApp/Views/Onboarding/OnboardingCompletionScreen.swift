import SwiftUI

struct OnboardingCompletionScreen: View {
    var coordinator: OnboardingCoordinator
    var lang: LanguageManager

    var body: some View {
        VStack(spacing: 22) {
            Spacer(minLength: 0)

            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 48, weight: .light))
                .foregroundStyle(.green)

            Text(lang.t("onboarding.completion.title"))
                .font(.system(size: 24, weight: .bold))

            Text(lang.t("onboarding.completion.subtitle"))
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 500)

            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.secondary.opacity(0.08))
                    .frame(width: 320, height: 96)

                VStack(spacing: 6) {
                    Image(systemName: "chevron.up")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(.tint)
                    Text(lang.t("onboarding.completion.hint"))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.top, 4)

            Text(lang.t("onboarding.completion.revisit"))
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 440)

            Spacer(minLength: 0)

            HStack {
                Button(lang.t("onboarding.back")) { coordinator.goBack() }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)

                Spacer()

                Button(lang.t("onboarding.completion.start")) {
                    coordinator.complete()
                }
                .keyboardShortcut(.defaultAction)
                .controlSize(.large)
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(40)
    }
}
