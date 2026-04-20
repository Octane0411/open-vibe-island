import SwiftUI

struct EventDetailView: View {
    let event: WatchEvent
    @EnvironmentObject var connectionManager: ConnectionManager

    var body: some View {
        List {
            headerSection
            detailSection

            if !event.isResolved, event.requestID != nil {
                actionSection
            }

            if event.isResolved {
                resolutionSection
            }

            metadataSection
        }
        .listStyle(.insetGrouped)
        .navigationTitle("事件详情")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Header

    @ViewBuilder
    private var headerSection: some View {
        Section {
            VStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(event.isResolved ? Color.green.opacity(0.15) : event.iconColor.opacity(0.15))
                        .frame(width: 56, height: 56)
                    Image(systemName: event.isResolved ? "checkmark.circle.fill" : event.iconName)
                        .font(.system(size: 26))
                        .foregroundStyle(event.isResolved ? .green : event.iconColor)
                }

                Text(event.title)
                    .font(.headline)
                    .multilineTextAlignment(.center)

                HStack(spacing: 8) {
                    Text(event.agentTool)
                        .font(.caption)
                        .foregroundStyle(.blue)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(.blue.opacity(0.1), in: Capsule())

                    Text(eventTypeLabel)
                        .font(.caption)
                        .foregroundStyle(event.iconColor)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(event.iconColor.opacity(0.1), in: Capsule())

                    if event.isResolved {
                        Text("已处理")
                            .font(.caption)
                            .foregroundStyle(.green)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(.green.opacity(0.1), in: Capsule())
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
        }
    }

    // MARK: - Detail Content

    @ViewBuilder
    private var detailSection: some View {
        switch event.kind {
        case let .permissionRequested(title, summary, _, primaryAction, secondaryAction):
            Section("权限请求") {
                LabeledContent("操作", value: title)
                LabeledContent("摘要", value: summary)
                if let dir = event.workingDirectory {
                    LabeledContent("工作目录", value: dir)
                }
                HStack {
                    Text("可选操作")
                    Spacer()
                    Text(primaryAction)
                        .foregroundStyle(.green)
                    Text("/")
                        .foregroundStyle(.secondary)
                    Text(secondaryAction)
                        .foregroundStyle(.red)
                }
            }

        case let .questionAsked(title, options, _):
            Section("问题") {
                Text(title)
                    .font(.body)
            }
            if !options.isEmpty {
                Section("选项") {
                    ForEach(Array(options.enumerated()), id: \.offset) { _, option in
                        Text(option)
                    }
                }
            }

        case let .sessionCompleted(summary):
            Section("完成摘要") {
                Text(summary)
                    .font(.body)
            }
        }
    }

    // MARK: - Actions (for unresolved actionable events)

    @ViewBuilder
    private var actionSection: some View {
        Section {
            switch event.kind {
            case let .permissionRequested(_, _, requestID, primaryAction, secondaryAction):
                Button {
                    postResolution(requestID: requestID, action: primaryAction.lowercased())
                } label: {
                    Label(primaryAction, systemImage: "checkmark.circle")
                }

                Button(role: .destructive) {
                    postResolution(requestID: requestID, action: secondaryAction.lowercased())
                } label: {
                    Label(secondaryAction, systemImage: "xmark.circle")
                }

            case let .questionAsked(_, options, requestID):
                ForEach(Array(options.enumerated()), id: \.offset) { _, option in
                    Button {
                        postResolution(requestID: requestID, action: option)
                    } label: {
                        Label(option, systemImage: "arrow.right.circle")
                    }
                }

            case .sessionCompleted:
                EmptyView()
            }
        } header: {
            Text("操作")
        }
    }

    // MARK: - Resolution Info

    @ViewBuilder
    private var resolutionSection: some View {
        Section("处理结果") {
            if let action = event.resolvedAction {
                LabeledContent("操作", value: action)
            }
            if let resolvedAt = event.resolvedAt {
                LabeledContent("处理时间") {
                    Text(resolvedAt, style: .relative)
                        .foregroundStyle(.secondary)
                    + Text(" 前")
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - Metadata

    @ViewBuilder
    private var metadataSection: some View {
        Section("详细信息") {
            LabeledContent("Session ID") {
                Text(event.sessionID)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            LabeledContent("时间") {
                Text(event.timestamp, format: .dateTime)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Helpers

    private var eventTypeLabel: String {
        switch event.kind {
        case .permissionRequested: return "权限请求"
        case .questionAsked: return "问题"
        case .sessionCompleted: return "任务完成"
        }
    }

    private func postResolution(requestID: String, action: String) {
        Task {
            do {
                try await connectionManager.postResolution(requestID: requestID, action: action)
                connectionManager.markEventResolved(requestID: requestID, action: action)
            } catch {
                // Error is handled via connectionError
            }
        }
    }
}
