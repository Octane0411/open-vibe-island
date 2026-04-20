import Foundation
import UserNotifications
import os

/// Manages local notification permissions, categories, and delivery.
/// Notifications are automatically mirrored to Apple Watch by the system.
@MainActor
final class NotificationManager: NSObject, ObservableObject {
    private static let logger = Logger(subsystem: "app.agentdeck.mobile", category: "NotificationManager")

    @Published private(set) var isAuthorized = false

    private let center = UNUserNotificationCenter.current()

    // MARK: - Category Identifiers

    static let permissionCategoryID = "PERMISSION_REQUEST"
    static let sessionCompletedCategoryID = "SESSION_COMPLETED"
    /// Question categories are dynamically generated: "QUESTION_<requestID>"
    static let questionCategoryPrefix = "QUESTION_"

    // MARK: - Action Identifiers

    static let allowActionID = "ALLOW"
    static let denyActionID = "DENY"

    // MARK: - Setup

    func requestAuthorization() async {
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
            isAuthorized = granted
            if granted {
                Self.logger.info("Notification authorization granted")
                registerStaticCategories()
            } else {
                Self.logger.info("Notification authorization denied")
            }
        } catch {
            Self.logger.error("Failed to request notification authorization: \(error.localizedDescription)")
        }
    }

    /// Registers the static notification categories (permission request and session completed).
    /// Question categories are registered dynamically per event.
    private func registerStaticCategories() {
        let allowAction = UNNotificationAction(
            identifier: Self.allowActionID,
            title: "Allow",
            options: []
        )
        let denyAction = UNNotificationAction(
            identifier: Self.denyActionID,
            title: "Deny",
            options: [.destructive]
        )

        let permissionCategory = UNNotificationCategory(
            identifier: Self.permissionCategoryID,
            actions: [allowAction, denyAction],
            intentIdentifiers: []
        )

        let completedCategory = UNNotificationCategory(
            identifier: Self.sessionCompletedCategoryID,
            actions: [],
            intentIdentifiers: []
        )

        center.setNotificationCategories([permissionCategory, completedCategory])
        Self.logger.info("Registered static notification categories")
    }

    // MARK: - Send Notifications

    func sendPermissionNotification(_ event: WatchPermissionEvent) {
        guard isAuthorized else { return }

        let content = UNMutableNotificationContent()
        content.title = event.agentTool
        content.subtitle = event.workingDirectory ?? ""
        content.body = "\(event.title): \(event.summary)"
        content.sound = .default
        content.categoryIdentifier = Self.permissionCategoryID
        content.userInfo = [
            "requestID": event.requestID,
            "sessionID": event.sessionID,
            "eventType": "permissionRequested",
        ]

        let request = UNNotificationRequest(
            identifier: "permission-\(event.requestID)",
            content: content,
            trigger: nil // Deliver immediately
        )

        center.add(request) { error in
            if let error {
                Self.logger.error("Failed to send permission notification: \(error.localizedDescription)")
            } else {
                Self.logger.info("Permission notification sent for \(event.requestID)")
            }
        }
    }

    func sendQuestionNotification(_ event: WatchQuestionEvent) {
        guard isAuthorized else { return }

        // Dynamically create a category with options as actions (max 4)
        let actions: [UNNotificationAction] = event.options.prefix(4).enumerated().map { index, option in
            UNNotificationAction(
                identifier: "OPTION_\(index)",
                title: option,
                options: []
            )
        }

        let categoryID = "\(Self.questionCategoryPrefix)\(event.requestID)"
        let questionCategory = UNNotificationCategory(
            identifier: categoryID,
            actions: actions,
            intentIdentifiers: []
        )

        // Merge with existing categories to preserve static ones
        center.getNotificationCategories { [weak self] existing in
            guard let self else { return }
            var categories = existing
            categories.insert(questionCategory)
            self.center.setNotificationCategories(categories)
        }

        let content = UNMutableNotificationContent()
        content.title = event.agentTool
        content.body = event.title
        content.sound = .default
        content.categoryIdentifier = categoryID
        content.userInfo = [
            "requestID": event.requestID,
            "sessionID": event.sessionID,
            "eventType": "questionAsked",
            "options": event.options,
        ]

        let request = UNNotificationRequest(
            identifier: "question-\(event.requestID)",
            content: content,
            trigger: nil
        )

        center.add(request) { error in
            if let error {
                Self.logger.error("Failed to send question notification: \(error.localizedDescription)")
            } else {
                Self.logger.info("Question notification sent for \(event.requestID)")
            }
        }
    }

    // MARK: - Notification Cleanup

    /// Remove a delivered notification after the user acted on it or it was resolved remotely.
    func removeNotification(forRequestID requestID: String) {
        let identifiers = [
            "permission-\(requestID)",
            "question-\(requestID)",
        ]
        center.removeDeliveredNotifications(withIdentifiers: identifiers)
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
        Self.logger.info("Removed notifications for requestID \(requestID)")
    }

    /// Remove the dynamically registered question category after it's been resolved.
    func removeQuestionCategory(forRequestID requestID: String) {
        let categoryID = "\(Self.questionCategoryPrefix)\(requestID)"
        center.getNotificationCategories { [weak self] existing in
            guard let self else { return }
            let filtered = existing.filter { $0.identifier != categoryID }
            if filtered.count < existing.count {
                self.center.setNotificationCategories(filtered)
                Self.logger.info("Removed dynamic category \(categoryID)")
            }
        }
    }

    func sendCompletionNotification(_ event: WatchCompletionEvent, silent: Bool = false) {
        guard isAuthorized else { return }

        let content = UNMutableNotificationContent()
        content.title = "\(event.agentTool) - Task completed"
        content.body = event.summary
        content.sound = silent ? nil : .default
        content.categoryIdentifier = Self.sessionCompletedCategoryID
        content.userInfo = [
            "sessionID": event.sessionID,
            "eventType": "sessionCompleted",
        ]

        let request = UNNotificationRequest(
            identifier: "completed-\(event.sessionID)-\(UUID().uuidString.prefix(8))",
            content: content,
            trigger: nil
        )

        center.add(request) { error in
            if let error {
                Self.logger.error("Failed to send completion notification: \(error.localizedDescription)")
            } else {
                Self.logger.info("Completion notification sent for session \(event.sessionID)")
            }
        }
    }
}

// MARK: - UNUserNotificationCenterDelegate

extension NotificationManager: UNUserNotificationCenterDelegate {
    /// Show notifications as banners even when app is in foreground.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        // Show banner + sound in foreground for permission requests and questions;
        // for completed events, show only the list (no intrusive banner).
        let categoryID = notification.request.content.categoryIdentifier
        if categoryID == Self.sessionCompletedCategoryID {
            return [.list, .sound]
        }
        return [.banner, .list, .sound]
    }

    /// Handle notification action responses (Allow/Deny/option selection).
    /// This is the entry point for Step 4 bidirectional interaction.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let userInfo = response.notification.request.content.userInfo
        let actionID = response.actionIdentifier

        // Ignore default tap and dismiss actions for now
        guard actionID != UNNotificationDefaultActionIdentifier,
              actionID != UNNotificationDismissActionIdentifier else {
            return
        }

        guard let requestID = userInfo["requestID"] as? String else { return }

        let action: String
        switch actionID {
        case Self.allowActionID:
            action = "allow"
        case Self.denyActionID:
            action = "deny"
        default:
            // Question option: "OPTION_0", "OPTION_1", etc.
            if actionID.hasPrefix("OPTION_"),
               let index = Int(actionID.dropFirst("OPTION_".count)),
               let options = userInfo["options"] as? [String],
               index < options.count {
                action = options[index]
            } else {
                return
            }
        }

        NotificationManager.logger.info("Notification action: \(actionID) → \(action) for request \(requestID)")

        // Clean up the notification and dynamic category after user acted
        await MainActor.run {
            removeNotification(forRequestID: requestID)
            removeQuestionCategory(forRequestID: requestID)
        }

        // Notify ConnectionManager to post resolution and mark event as resolved
        await MainActor.run {
            NotificationActionRelay.shared.pendingResolution = (requestID: requestID, action: action)
        }
    }
}

// MARK: - Action Relay

/// Simple relay to bridge notification actions back to ConnectionManager.
/// Uses @Published so ConnectionManager can observe and post the resolution.
@MainActor
final class NotificationActionRelay: ObservableObject {
    static let shared = NotificationActionRelay()

    @Published var pendingResolution: (requestID: String, action: String)?

    private init() {}
}
