import SwiftUI

struct EventCardView: View {
    let event: PendingWatchEvent
    @EnvironmentObject var sessionManager: WatchSessionManager

    var body: some View {
        switch event.message {
        case .permissionRequest(let payload):
            permissionCard(payload)
        case .question(let payload):
            questionCard(payload)
        case .sessionCompleted(let payload):
            completionCard(payload)
        case .resolved:
            EmptyView()
        }
    }

    // MARK: - Permission Request Card

    private func permissionCard(_ payload: WatchMessage.PermissionPayload) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(payload.agentTool, systemImage: "lock.shield")
                .font(.caption2)
                .foregroundStyle(.orange)

            Text(payload.title)
                .font(.headline)

            Text(payload.summary)
                .font(.caption)
                .foregroundStyle(.secondary)

            if let dir = payload.workingDirectory {
                Text(dir)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.head)
            }

            HStack {
                Button("Allow") {
                    sessionManager.resolve(requestID: payload.requestID, action: "allow")
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)

                Button(role: .destructive) {
                    sessionManager.resolve(requestID: payload.requestID, action: "deny")
                } label: {
                    Text("Deny")
                }
                .buttonStyle(.bordered)
            }

            Text(event.receivedAt, style: .relative)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    // MARK: - Question Card

    private func questionCard(_ payload: WatchMessage.QuestionPayload) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(payload.agentTool, systemImage: "questionmark.bubble")
                .font(.caption2)
                .foregroundStyle(.blue)

            Text(payload.title)
                .font(.headline)

            ForEach(payload.options, id: \.self) { option in
                Button(option) {
                    sessionManager.resolve(requestID: payload.requestID, action: option)
                }
                .buttonStyle(.bordered)
            }

            Text(event.receivedAt, style: .relative)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    // MARK: - Session Completed Card

    private func completionCard(_ payload: WatchMessage.CompletionPayload) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(payload.agentTool, systemImage: "checkmark.circle.fill")
                .font(.caption2)
                .foregroundStyle(.green)

            Text(payload.summary)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(3)

            Text(event.receivedAt, style: .relative)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }
}
