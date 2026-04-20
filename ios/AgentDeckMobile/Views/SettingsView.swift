import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var connectionManager: ConnectionManager

    var body: some View {
        Form {
            notificationSettingsSection
            deviceSection
            dangerSection
        }
        .navigationTitle("设置")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Notification Settings

    @ViewBuilder
    private var notificationSettingsSection: some View {
        Section("通知类型") {
            Toggle(isOn: $connectionManager.notifyPermissions) {
                Label("权限请求", systemImage: "lock.shield")
            }
            Toggle(isOn: $connectionManager.notifyQuestions) {
                Label("问题", systemImage: "questionmark.bubble")
            }
            Toggle(isOn: $connectionManager.notifyCompletions) {
                Label("完成通知", systemImage: "checkmark.circle")
            }
        }

        Section {
            Toggle(isOn: $connectionManager.silentCompletions) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("静默模式")
                    Text("完成通知不发出声音")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .disabled(!connectionManager.notifyCompletions)
        } header: {
            Text("声音")
        }
    }

    // MARK: - Device Info

    @ViewBuilder
    private var deviceSection: some View {
        Section("已配对设备") {
            if let macName = connectionManager.connectedMacName {
                HStack {
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(macName)
                                .font(.body)
                            if let pairedAt = connectionManager.pairedAt {
                                Text("配对时间: \(pairedAt, style: .date)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    } icon: {
                        Image(systemName: "desktopcomputer")
                            .foregroundStyle(.blue)
                    }

                    Spacer()

                    connectionStatusBadge
                }
            } else {
                HStack {
                    Image(systemName: "desktopcomputer")
                        .foregroundStyle(.secondary)
                    Text("未配对")
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    @ViewBuilder
    private var connectionStatusBadge: some View {
        switch connectionManager.state {
        case .connected:
            HStack(spacing: 4) {
                Circle()
                    .fill(.green)
                    .frame(width: 7, height: 7)
                Text("已连接")
                    .font(.caption)
                    .foregroundStyle(.green)
            }
        case .paired:
            HStack(spacing: 4) {
                ProgressView()
                    .controlSize(.mini)
                Text("连接中")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        case .discovering:
            HStack(spacing: 4) {
                ProgressView()
                    .controlSize(.mini)
                Text("搜索中")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        case .disconnected:
            HStack(spacing: 4) {
                Circle()
                    .fill(.red)
                    .frame(width: 7, height: 7)
                Text("离线")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
    }

    // MARK: - Danger Zone

    @ViewBuilder
    private var dangerSection: some View {
        Section {
            if connectionManager.connectedMacName != nil {
                Button(role: .destructive) {
                    connectionManager.disconnect()
                } label: {
                    Label("断开连接并取消配对", systemImage: "xmark.circle")
                }
            }

            Button {
                connectionManager.startDiscovery()
            } label: {
                Label("重新搜索 Mac", systemImage: "arrow.clockwise")
            }
        }
    }
}
