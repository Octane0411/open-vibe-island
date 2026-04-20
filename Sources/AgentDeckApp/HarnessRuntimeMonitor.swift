import Foundation

struct HarnessRuntimeEvent: Codable, Equatable {
    let category: String
    let name: String
    let message: String?
    let offsetSeconds: Double
}

struct HarnessRuntimeArtifacts: Codable, Equatable {
    struct Milestone: Codable, Equatable {
        let name: String
        let offsetSeconds: Double
    }

    struct TimingSummary: Codable, Equatable {
        let bootstrapSeconds: Double?
        let scenarioLoadSeconds: Double?
        let controlCenterConfiguredSeconds: Double?
        let overlayPresentedSeconds: Double?
        let bridgeReadySeconds: Double?
        let captureScheduledSeconds: Double?
        let captureStartedSeconds: Double?
        let launchToCaptureSeconds: Double
    }

    let logPath: String
    let timelinePath: String
    let eventCount: Int
    let latestMessage: String?
    let launchCompleted: Bool
    let milestones: [Milestone]
    let timings: TimingSummary

    static func make(
        events: [HarnessRuntimeEvent],
        logPath: String,
        timelinePath: String,
        launchToCaptureSeconds: Double
    ) -> HarnessRuntimeArtifacts {
        let milestones = events
            .filter { $0.category == "milestone" }
            .map { event in
                Milestone(name: event.name, offsetSeconds: event.offsetSeconds)
            }

        func offset(for milestoneName: String) -> Double? {
            milestones.first { $0.name == milestoneName }?.offsetSeconds
        }

        return HarnessRuntimeArtifacts(
            logPath: logPath,
            timelinePath: timelinePath,
            eventCount: events.count,
            latestMessage: events.last { $0.category == "log" }?.message,
            launchCompleted: offset(for: "bootstrapCompleted") != nil,
            milestones: milestones,
            timings: TimingSummary(
                bootstrapSeconds: offset(for: "bootstrapCompleted"),
                scenarioLoadSeconds: offset(for: "scenarioLoaded"),
                controlCenterConfiguredSeconds: offset(for: "controlCenterConfigured"),
                overlayPresentedSeconds: offset(for: "overlayPresented"),
                bridgeReadySeconds: offset(for: "bridgeReady"),
                captureScheduledSeconds: offset(for: "captureScheduled"),
                captureStartedSeconds: offset(for: "captureStarted"),
                launchToCaptureSeconds: launchToCaptureSeconds
            )
        )
    }
}

@MainActor
final class HarnessRuntimeMonitor {
    private let launchedAt: Date
    private var events: [HarnessRuntimeEvent] = []

    init(launchedAt: Date = .now) {
        self.launchedAt = launchedAt
    }

    func recordMilestone(_ name: String, message: String? = nil) {
        append(category: "milestone", name: name, message: message)
    }

    func recordLog(_ message: String) {
        append(category: "log", name: "lastActionMessage", message: message)
    }

    func writeArtifacts(
        to directoryURL: URL,
        launchToCaptureSeconds: Double,
        fileManager: FileManager = .default
    ) throws -> HarnessRuntimeArtifacts {
        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)

        let timelinePath = "timeline.json"
        let timelineURL = directoryURL.appendingPathComponent(timelinePath)
        let timelineEncoder = JSONEncoder()
        timelineEncoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try timelineEncoder.encode(events).write(to: timelineURL)

        let logPath = "runtime.log"
        let logURL = directoryURL.appendingPathComponent(logPath)
        let logLines = events.map { event in
            let detail = event.message.map { " - \($0)" } ?? ""
            return String(format: "%7.3fs [%@] %@%@", event.offsetSeconds, event.category, event.name, detail)
        }
        try (logLines.joined(separator: "\n") + "\n").write(to: logURL, atomically: true, encoding: .utf8)

        return HarnessRuntimeArtifacts.make(
            events: events,
            logPath: logPath,
            timelinePath: timelinePath,
            launchToCaptureSeconds: launchToCaptureSeconds
        )
    }

    private func append(category: String, name: String, message: String?) {
        let event = HarnessRuntimeEvent(
            category: category,
            name: name,
            message: message,
            offsetSeconds: Date().timeIntervalSince(launchedAt)
        )
        events.append(event)
    }
}
