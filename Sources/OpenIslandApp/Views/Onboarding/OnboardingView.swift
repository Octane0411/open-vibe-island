import SwiftUI

struct OnboardingView: View {
    var model: AppModel
    @State private var coordinator: OnboardingCoordinator

    init(model: AppModel) {
        self.model = model
        _coordinator = State(initialValue: OnboardingCoordinator(model: model))
    }

    var body: some View {
        VStack(spacing: 0) {
            OnboardingProgressDots(
                current: coordinator.step.rawValue,
                total: OnboardingCoordinator.Step.allCases.count
            )
            .padding(.top, 20)

            Group {
                switch coordinator.step {
                case .welcome:
                    OnboardingWelcomeScreen(
                        coordinator: coordinator,
                        lang: model.lang,
                        onSkip: { coordinator.skip() }
                    )
                case .agents:
                    OnboardingAgentsScreen(coordinator: coordinator, lang: model.lang)
                case .permissions:
                    OnboardingPermissionsScreen(coordinator: coordinator, lang: model.lang)
                case .completion:
                    OnboardingCompletionScreen(coordinator: coordinator, lang: model.lang)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 720, minHeight: 520)
    }
}
