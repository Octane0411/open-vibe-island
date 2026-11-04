import SwiftUI

struct PairingView: View {
    @EnvironmentObject var connectionManager: ConnectionManager
    @Environment(\.dismiss) private var dismiss
    @State private var selectedMac: DiscoveredMac?
    @State private var pairingCode = ""
    @State private var isPairing = false
    @State private var errorMessage: String?
    @State private var showManualEntry = false
    @State private var manualHost = ""
    @State private var manualPort = "7890"
    @State private var manualCode = ""
    @State private var manualError: String?
    @State private var isManualPairing = false

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

            Section {
                Button {
                    showManualEntry = true
                } label: {
                    HStack {
                        Image(systemName: "keyboard")
                            .foregroundStyle(.orange)
                            .frame(width: 32)
                        Text("手动输入 IP 地址")
                    }
                }
            }
        }
        .sheet(isPresented: $showManualEntry) {
            manualEntrySheet
        }
    }

    // MARK: - Manual Entry Sheet

    private var manualEntrySheet: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("IP 地址", text: $manualHost)
                        .keyboardType(.decimalPad)
                    TextField("端口", text: $manualPort)
                        .keyboardType(.numberPad)
                    SecureField("粘贴配对密钥", text: $manualCode)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } footer: {
                    Text("Bonjour 无法发现时（如热点、AP 隔离），可手动输入 Mac 的 IP 和端口。")
                }

                if let manualError = formatError(for: manualCode) ?? manualError {
                    Section {
                        Text(manualError)
                            .foregroundStyle(.red)
                            .font(.subheadline)
                    }
                }

                Section {
                    Button {
                        performManualPairing()
                    } label: {
                        if isManualPairing {
                            HStack {
                                Spacer()
                                ProgressView()
                                Spacer()
                            }
                        } else {
                            Text("连接并配对")
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .disabled(manualHost.isEmpty || (try? WatchPairingCode(manualCode)) == nil || isManualPairing)
                }
            }
            .navigationTitle("手动连接")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        showManualEntry = false
                    }
                }
            }
        }
    }

    // MARK: - Manual Pairing

    private func performManualPairing() {
        guard let port = UInt16(manualPort) else {
            manualError = "端口格式无效"
            return
        }
        isManualPairing = true
        manualError = nil

        Task {
            do {
                try await connectionManager.pairManual(host: manualHost, port: port, code: manualCode)
                showManualEntry = false
            } catch {
                manualError = error.localizedDescription
                manualCode = ""
            }
            isManualPairing = false
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
                Text("在 Mac 上点击“配对新设备”，复制密钥后粘贴到这里。密钥仅有效两分钟。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                SecureField("粘贴配对密钥", text: $pairingCode)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .textFieldStyle(.roundedBorder)
                    .padding(.horizontal)

            }

            if let errorMessage = formatError(for: pairingCode) ?? errorMessage {
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
            .disabled((try? WatchPairingCode(pairingCode)) == nil || isPairing)
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

    private func formatError(for code: String) -> String? {
        guard !code.isEmpty, (try? WatchPairingCode(code)) == nil else { return nil }
        return "配对密钥格式不完整或无效，请从 Mac 复制完整密钥。"
    }

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
