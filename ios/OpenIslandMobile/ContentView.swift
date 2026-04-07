import SwiftUI

struct ContentView: View {
    @EnvironmentObject var connectionManager: ConnectionManager

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                connectionStatusSection
                recentEventsSection
                Spacer()
            }
            .padding()
            .navigationTitle("Open Island")
            .sheet(isPresented: $connectionManager.showPairing) {
                PairingView()
                    .environmentObject(connectionManager)
            }
        }
    }

    // MARK: - Connection Status

    @ViewBuilder
    private var connectionStatusSection: some View {
        VStack(spacing: 12) {
            Image(systemName: connectionManager.state.iconName)
                .font(.system(size: 48))
                .foregroundStyle(connectionManager.state.iconColor)

            Text(connectionManager.state.displayText)
                .font(.headline)

            if let macName = connectionManager.connectedMacName {
                Text(macName)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            switch connectionManager.state {
            case .disconnected:
                Button("搜索 Mac") {
                    connectionManager.startDiscovery()
                }
                .buttonStyle(.borderedProminent)

            case .discovering:
                ProgressView()
                    .padding(.top, 4)

            case .paired:
                Button("断开连接") {
                    connectionManager.disconnect()
                }
                .buttonStyle(.bordered)
                .foregroundStyle(.red)

            case .connected:
                Button("断开连接") {
                    connectionManager.disconnect()
                }
                .buttonStyle(.bordered)
                .foregroundStyle(.red)
            }
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Recent Events

    @ViewBuilder
    private var recentEventsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("最近事件")
                .font(.headline)

            if connectionManager.recentEvents.isEmpty {
                Text("暂无事件")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 20)
            } else {
                ForEach(connectionManager.recentEvents) { event in
                    eventRow(event)
                }
            }
        }
    }

    @ViewBuilder
    private func eventRow(_ event: WatchEvent) -> some View {
        HStack(spacing: 12) {
            Image(systemName: event.iconName)
                .foregroundStyle(event.iconColor)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(event.title)
                    .font(.subheadline)
                    .fontWeight(.medium)

                if let subtitle = event.subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            Text(event.timestamp, style: .relative)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 6)
    }
}
