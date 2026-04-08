import SwiftUI
import WatchKit
import UserNotifications

@main
struct OpenIslandWatchApp: App {
    @WKApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(WatchSessionManager.shared)
        }
    }
}

final class AppDelegate: NSObject, WKApplicationDelegate {
    func applicationDidFinishLaunching() {
        WatchSessionManager.shared.activate()
        registerNotifications()
    }

    private func registerNotifications() {
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if let error {
                print("Watch notification auth error: \(error)")
            }
        }

        // Permission request category: Allow + Deny
        let allowAction = UNNotificationAction(identifier: "ALLOW", title: "Allow", options: [.foreground])
        let denyAction = UNNotificationAction(identifier: "DENY", title: "Deny", options: [.destructive])
        let permissionCategory = UNNotificationCategory(
            identifier: "PERMISSION_REQUEST",
            actions: [allowAction, denyAction],
            intentIdentifiers: []
        )

        // Question category: handled dynamically, just register a base
        let questionCategory = UNNotificationCategory(
            identifier: "QUESTION",
            actions: [],
            intentIdentifiers: []
        )

        // Completion: no actions
        let completionCategory = UNNotificationCategory(
            identifier: "SESSION_COMPLETED",
            actions: [],
            intentIdentifiers: []
        )

        center.setNotificationCategories([permissionCategory, questionCategory, completionCategory])
        center.delegate = WatchSessionManager.shared
    }
}
