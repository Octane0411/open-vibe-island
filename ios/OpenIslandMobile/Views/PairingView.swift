import SwiftUI

struct PairingView: View {
    @EnvironmentObject var connectionManager: ConnectionManager
    @Environment(\.dismiss) private var dismiss
    @State private var selectedMac: DiscoveredMac?
    @State private var pairingCode = ""
    @State private var isPairing = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Group {
                if selectedMac == nil {
                    macListView
                } else {
                    codeInputView
                }
            }
            .navigationTitle("配对 Mac")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        connectionManager.discovery.stopBrowsing()
                        dismiss()
                    }
                }
            }
        }
        .onAppear {
            connectionManager.discovery.startBrowsing()
        }
    }

    // MARK: - Mac List

    @ViewBuilder
    private var macListView: some View {
        List {
            if connectionManager.discovery.isSearching {
                Section {
                    HStack {
                        ProgressView()
                            .padding(.trailing, 8)
                        Text("正在搜索局域网中的 Mac...")
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if !connectionManager.discovery.discoveredMacs.isEmpty {
                Section("发现的 Mac") {
                    ForEach(connectionManager.discovery.discoveredMacs) { mac in
                        Button {
                            selectedMac = mac
                        } label: {
                            HStack {
                                Image(systemName: "desktopcomputer")
                                    .foregroundStyle(.blue)
                                    .frame(width: 32)

                                VStack(alignment: .leading) {
                                    Text(mac.name)
                                        .font(.body)
                                        .foregroundStyle(.primary)
                                }

                                Spacer()

                                Image(systemName: "chevron.right")
                                    .foregroundStyle(.tertiary)
                            }
                        }
                    }
                }
            }

            if !connectionManager.discovery.isSearching && connectionManager.discovery.discoveredMacs.isEmpty {
                Section {
                    VStack(spacing: 12) {
                        Image(systemName: "wifi.slash")
                            .font(.largeTitle)
                            .foregroundStyle(.secondary)

                        Text("未发现 Mac")
                            .font(.headline)

                        Text("请确保 Mac 上的 Open Island 正在运行，且 Mac 和 iPhone 在同一 WiFi 网络下。")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)

                        Button("重新搜索") {
                            connectionManager.discovery.startBrowsing()
                        }
                        .buttonStyle(.bordered)
                    }
                    .padding(.vertical, 20)
                    .frame(maxWidth: .infinity)
                }
            }
        }
    }

    // MARK: - Code Input

    @ViewBuilder
    private var codeInputView: some View {
        VStack(spacing: 32) {
            VStack(spacing: 8) {
                Image(systemName: "desktopcomputer")
                    .font(.system(size: 40))
                    .foregroundStyle(.blue)

                Text(selectedMac?.name ?? "Mac")
                    .font(.title3)
                    .fontWeight(.medium)
            }

            VStack(spacing: 12) {
                Text("请输入 Mac 上显示的 4 位配对码")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                TextField("0000", text: $pairingCode)
                    .keyboardType(.numberPad)
                    .font(.system(size: 36, weight: .bold, design: .monospaced))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 200)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: pairingCode) { _, newValue in
                        // Limit to 4 digits
                        let filtered = String(newValue.filter(\.isNumber).prefix(4))
                        if filtered != newValue {
                            pairingCode = filtered
                        }
                    }
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.subheadline)
                    .foregroundStyle(.red)
            }

            Button {
                performPairing()
            } label: {
                if isPairing {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                } else {
                    Text("配对")
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(pairingCode.count != 4 || isPairing)
            .padding(.horizontal, 40)

            Button("选择其他 Mac") {
                selectedMac = nil
                pairingCode = ""
                errorMessage = nil
            }
            .foregroundStyle(.secondary)

            Spacer()
        }
        .padding(.top, 40)
    }

    // MARK: - Pairing

    private func performPairing() {
        guard let mac = selectedMac else { return }
        isPairing = true
        errorMessage = nil

        Task {
            do {
                try await connectionManager.pair(mac: mac, code: pairingCode)
            } catch {
                errorMessage = error.localizedDescription
                pairingCode = ""
            }
            isPairing = false
        }
    }
}
