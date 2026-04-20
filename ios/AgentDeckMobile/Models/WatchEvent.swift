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

/// Sent by macOS when an actionable request has been resolved (e.g. user acted on Mac).
struct WatchResolvedEvent: Codable, Sendable {
    var requestID: String
    var sessionID: String
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
    let workingDirectory: String?
    /// Whether this event has been resolved (user acted on it or Mac resolved it).
    var isResolved: Bool = false
    /// When the event was resolved (set alongside isResolved).
    var resolvedAt: Date?
    /// The action that was taken to resolve (e.g. "allow", "deny", option text).
    var resolvedAction: String?

    enum Kind {
        case permissionRequested(title: String, summary: String, requestID: String,
                                 primaryAction: String, secondaryAction: String)
        case questionAsked(title: String, options: [String], requestID: String)
        case sessionCompleted(summary: String)
    }

    /// The requestID associated with actionable events (permission/question), nil for completion.
    var requestID: String? {
        switch kind {
        case let .permissionRequested(_, _, requestID, _, _):
            return requestID
        case let .questionAsked(_, _, requestID):
            return requestID
        case .sessionCompleted:
            return nil
        }
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
            sessionID: event.sessionID,
            workingDirectory: event.workingDirectory
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
            sessionID: event.sessionID,
            workingDirectory: nil
        )
    }

    static func from(_ event: WatchCompletionEvent) -> WatchEvent {
        WatchEvent(
            timestamp: Date(),
            kind: .sessionCompleted(summary: event.summary),
            agentTool: event.agentTool,
            sessionID: event.sessionID,
            workingDirectory: nil
        )
    }
}
