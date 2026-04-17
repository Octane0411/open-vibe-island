import SwiftUI

struct OnboardingPermissionsScreen: View {
    var coordinator: OnboardingCoordinator
    var lang: LanguageManager

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(lang.t("onboarding.permissions.title"))
                .font(.system(size: 22, weight: .bold))

            Text(lang.t("onboarding.permissions.subtitle"))
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(spacing: 10) {
                permissionRow(
                    icon: "bell",
                    title: lang.t("onboarding.permissions.notifications.title"),
                    subtitle: lang.t("onboarding.permissions.notifications.desc"),
                    badge: lang.t("onboarding.permissions.required"),
                    badgeTint: .orange,
                    status: coordinator.notificationStatus
                ) {
                    coordinator.requestNotificationPermission()
                }

                permissionRow(
                    icon: "accessibility",
                    title: lang.t("onboarding.permissions.accessibility.title"),
                    subtitle: lang.t("onboarding.permissions.accessibility.desc"),
                    badge: lang.t("onboarding.permissions.recommended"),
                    badgeTint: .blue,
                    status: coordinator.accessibilityStatus
                ) {
                    coordinator.openAccessibilitySettings()
                }

                permissionRow(
                    icon: "applescript",
                    title: lang.t("onboarding.permissions.automation.title"),
                    subtitle: lang.t("onboarding.permissions.automation.desc"),
                    badge: lang.t("onboarding.permissions.optional"),
                    badgeTint: .secondary,
                    status: coordinator.automationStatus
                ) {
                    coordinator.openAutomationSettings()
                }
            }

            Spacer(minLength: 0)

            HStack {
                Button(lang.t("onboarding.back")) { coordinator.goBack() }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)

                Spacer()

                Button(lang.t("onboarding.permissions.skip")) {
                    coordinator.advance()
                }
                .controlSize(.regular)

                Button(lang.t("onboarding.continue")) {
                    coordinator.advance()
                }
                .keyboardShortcut(.defaultAction)
                .controlSize(.large)
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(40)
        .onAppear {
            coordinator.refreshNotificationStatus()
        }
    }

    @ViewBuilder
    private func permissionRow(
        icon: String,
        title: String,
        subtitle: String,
        badge: String,
        badgeTint: Color,
        status: OnboardingCoordinator.PermissionStatus,
        action: @escaping () -> Void
    ) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundStyle(.tint)
                .frame(width: 32, height: 32)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(title)
                        .font(.system(size: 13, weight: .semibold))
                    Text(badge)
                        .font(.system(size: 10, weight: .medium))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(badgeTint.opacity(0.18), in: Capsule())
                        .foregroundStyle(badgeTint)
                }
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()

            actionControl(status: status, action: action)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.secondary.opacity(0.08))
        )
    }

    @ViewBuilder
    private func actionControl(
        status: OnboardingCoordinator.PermissionStatus,
        action: @escaping () -> Void
    ) -> some View {
        switch status {
        case .granted:
            HStack(spacing: 4) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text(lang.t("onboarding.permissions.granted"))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        case .pending:
            ProgressView()
                .controlSize(.small)
        case .denied:
            Button(lang.t("onboarding.permissions.openSettings")) { action() }
                .controlSize(.small)
        case .unknown:
            Button(lang.t("onboarding.permissions.grant")) { action() }
                .controlSize(.small)
                .buttonStyle(.bordered)
        }
    }
}
