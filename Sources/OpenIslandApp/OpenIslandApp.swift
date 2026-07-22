import AppKit
import SwiftUI

@MainActor
final class OpenIslandAppDelegate: NSObject, NSApplicationDelegate {
    let model = AppModel()
    let graphWorkspaceService: any GraphWorkspaceServicing = {
        do {
            return try GraphWorkspaceService.live()
        } catch {
            return UnavailableGraphWorkspaceService(
                message: error.localizedDescription
            )
        }
    }()
    private let harnessLaunchConfiguration = HarnessLaunchConfiguration()
    private let launchedAt = Date()
    private lazy var harnessRuntimeMonitor = HarnessRuntimeMonitor(launchedAt: launchedAt)

    func applicationDidFinishLaunching(_ notification: Notification) {
        ProcessInfo.processInfo.disableAutomaticTermination(
            "Open Island should remain active while monitoring local agent sessions."
        )
        ProcessInfo.processInfo.disableSuddenTermination()
        NSApp.setActivationPolicy(model.showDockIcon ? .regular : .accessory)
        harnessRuntimeMonitor.recordMilestone("applicationDidFinishLaunching")

        DispatchQueue.main.async { [self] in
            harnessRuntimeMonitor.recordMilestone("bootstrapStarted")
            model.harnessRuntimeMonitor = harnessRuntimeMonitor
            harnessRuntimeMonitor.recordLog(model.lastActionMessage)

            model.ignoresPointerExitDuringHarness = harnessLaunchConfiguration.scenario != nil
            model.disablesOverlayEventMonitoringDuringHarness = harnessLaunchConfiguration.scenario != nil
            model.startIfNeeded(
                startBridge: harnessLaunchConfiguration.shouldStartBridge,
                shouldPerformBootAnimation: harnessLaunchConfiguration.shouldPerformBootAnimation,
                loadRuntimeState: harnessLaunchConfiguration.scenario == nil
            )
            harnessRuntimeMonitor.recordMilestone("modelStarted")

            if let scenario = harnessLaunchConfiguration.scenario {
                model.loadDebugSnapshot(
                    scenario.snapshot(),
                    presentOverlay: harnessLaunchConfiguration.presentOverlay
                )
            }

            // Hide all windows on launch — settings opens on demand only.
            OpenIslandAppDelegate.hideAllAppWindows()

            harnessRuntimeMonitor.recordMilestone("bootstrapCompleted")

            if let captureDelay = harnessLaunchConfiguration.captureDelay,
               harnessLaunchConfiguration.artifactDirectoryURL != nil {
                harnessRuntimeMonitor.recordMilestone(
                    "captureScheduled",
                    message: String(format: "%.3fs", captureDelay)
                )
                DispatchQueue.main.asyncAfter(deadline: .now() + captureDelay) { [self] in
                    harnessRuntimeMonitor.recordMilestone("captureStarted")
                    try? HarnessArtifactRecorder.record(
                        configuration: harnessLaunchConfiguration,
                        model: model,
                        launchedAt: launchedAt,
                        runtimeMonitor: harnessRuntimeMonitor
                    )
                }
            }

            if let autoExitAfter = harnessLaunchConfiguration.autoExitAfter {
                harnessRuntimeMonitor.recordMilestone(
                    "autoExitScheduled",
                    message: String(format: "%.3fs", autoExitAfter)
                )
                DispatchQueue.main.asyncAfter(deadline: .now() + autoExitAfter) {
                    NSApp.terminate(nil)
                }
            }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    private static func hideAllAppWindows() {
        for window in NSApp.windows {
            window.orderOut(nil)
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        model.showSettings()
        return false
    }
}

@main
struct OpenIslandApp: App {
    @NSApplicationDelegateAdaptor(OpenIslandAppDelegate.self)
    private var appDelegate

    @Environment(\.openWindow) private var openWindow

    var body: some Scene {
        Window("Open Island Settings", id: "settings") {
            SettingsWindowContent(model: appDelegate.model)
        }
        .windowResizability(.contentMinSize)

        Window(
            GraphWorkspaceEntryPoint.label,
            id: GraphWorkspaceEntryPoint.windowID
        ) {
            GraphWorkspaceRegistrar(
                model: appDelegate.model,
                service: appDelegate.graphWorkspaceService
            )
        }
        .defaultSize(width: 1_240, height: 780)
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button("Settings…") {
                    openWindow(id: "settings")
                    appDelegate.model.showSettings()
                }
                .keyboardShortcut(",", modifiers: .command)
            }
            CommandGroup(after: .newItem) {
                Button("New Graph") {
                    openWindow(id: GraphWorkspaceEntryPoint.windowID)
                    DispatchQueue.main.async {
                        appDelegate.model.newGraphDefinitionAction?()
                        appDelegate.model.showGraphWorkspace()
                    }
                }
                .keyboardShortcut("n", modifiers: [.command, .shift])

                Button("Open Graph Definition…") {
                    openWindow(id: GraphWorkspaceEntryPoint.windowID)
                    DispatchQueue.main.async {
                        appDelegate.model.openGraphDefinitionAction?()
                        appDelegate.model.showGraphWorkspace()
                    }
                }
                .keyboardShortcut("o", modifiers: [.command, .shift])
            }
            CommandGroup(after: .windowArrangement) {
                Button(GraphWorkspaceEntryPoint.label) {
                    openWindow(id: GraphWorkspaceEntryPoint.windowID)
                    appDelegate.model.showGraphWorkspace()
                }
                .keyboardShortcut(
                    GraphWorkspaceEntryPoint.shortcutKey,
                    modifiers: [.command, .shift]
                )
            }
        }
    }
}

private struct GraphWorkspaceRegistrar: View {
    var model: AppModel
    let service: any GraphWorkspaceServicing
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        GraphWorkspaceWindowContent(model: model, service: service)
            .onAppear {
                model.openGraphWorkspaceWindow = { [openWindow] in
                    openWindow(id: GraphWorkspaceEntryPoint.windowID)
                }
            }
    }
}

/// Refreshes the `openWindow` registration each time the settings
/// window opens, keeping the closure current after window recreation.
private struct SettingsWindowContent: View {
    var model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        SettingsView(model: model)
            .onAppear {
                model.openSettingsWindow = { [openWindow] in
                    openWindow(id: "settings")
                }
            }
    }
}
