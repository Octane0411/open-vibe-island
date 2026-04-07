import Foundation
import SwiftUI

// MARK: - SSE Event Models (aligned with macOS WatchHTTPEndpoint.swift)

struct WatchPermissionEvent: Codable, Sendable {
    var sessionID: String
    var agentTool: String
    var title: String
    var summary: String
    var workingDirectory: String?
    var primaryAction: String
    var secondaryAction: String
    var requestID: String
}

struct WatchQuestionEvent: Codable, Sendable {
    var sessionID: String
    var agentTool: String
    var title: String
    var options: [String]
    var requestID: String
}

struct WatchCompletionEvent: Codable, Sendable {
    var sessionID: String
    var agentTool: String
    var summary: String
}

// MARK: - Pairing

struct WatchPairRequest: Codable, Sendable {
    var code: String
}

struct WatchPairResponse: Codable, Sendable {
    var token: String
}

// MARK: - Resolution

struct WatchResolutionRequest: Codable, Sendable {
    var requestID: String
    var action: String
}

// MARK: - Status

struct WatchStatusResponse: Codable, Sendable {
    var connected: Bool
    var activeSessionCount: Int
}

// MARK: - Unified Event for UI display

struct WatchEvent: Identifiable {
    let id = UUID()
    let timestamp: Date
    let kind: Kind
    let agentTool: String
    let sessionID: String

    enum Kind {
        case permissionRequested(title: String, summary: String, requestID: String,
                                 primaryAction: String, secondaryAction: String)
        case questionAsked(title: String, options: [String], requestID: String)
        case sessionCompleted(summary: String)
    }

    var title: String {
        switch kind {
        case let .permissionRequested(title, _, _, _, _):
            return title
        case let .questionAsked(title, _, _):
            return title
        case let .sessionCompleted(summary):
            return summary
        }
    }

    var subtitle: String? {
        switch kind {
        case let .permissionRequested(_, summary, _, _, _):
            return summary
        case let .questionAsked(_, options, _):
            return options.joined(separator: " / ")
        case .sessionCompleted:
            return nil
        }
    }

    var iconName: String {
        switch kind {
        case .permissionRequested: return "lock.shield"
        case .questionAsked: return "questionmark.bubble"
        case .sessionCompleted: return "checkmark.circle"
        }
    }

    var iconColor: Color {
        switch kind {
        case .permissionRequested: return .orange
        case .questionAsked: return .blue
        case .sessionCompleted: return .green
        }
    }

    // MARK: - Factory methods from SSE events

    static func from(_ event: WatchPermissionEvent) -> WatchEvent {
        WatchEvent(
            timestamp: Date(),
            kind: .permissionRequested(
                title: event.title,
                summary: event.summary,
                requestID: event.requestID,
                primaryAction: event.primaryAction,
                secondaryAction: event.secondaryAction
            ),
            agentTool: event.agentTool,
            sessionID: event.sessionID
        )
    }

    static func from(_ event: WatchQuestionEvent) -> WatchEvent {
        WatchEvent(
            timestamp: Date(),
            kind: .questionAsked(
                title: event.title,
                options: event.options,
                requestID: event.requestID
            ),
            agentTool: event.agentTool,
            sessionID: event.sessionID
        )
    }

    static func from(_ event: WatchCompletionEvent) -> WatchEvent {
        WatchEvent(
            timestamp: Date(),
            kind: .sessionCompleted(summary: event.summary),
            agentTool: event.agentTool,
            sessionID: event.sessionID
        )
    }
}
