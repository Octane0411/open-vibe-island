import SwiftUI
import UserNotifications

@main
struct OpenIslandMobileApp: App {
    @StateObject private var connectionManager = ConnectionManager()
    @StateObject private var notificationManager = NotificationManager()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(connectionManager)
                .environmentObject(notificationManager)
                .task {
                    // Request notification permission on first launch
                    await notificationManager.requestAuthorization()

                    // Set the notification center delegate for foreground display and action handling
                    UNUserNotificationCenter.current().delegate = notificationManager

                    // Wire notification manager into connection manager
                    connectionManager.notificationManager = notificationManager

                    // Activate WatchConnectivity session
                    WatchConnectivityManager.shared.activate()
                }
        }
    }
}
