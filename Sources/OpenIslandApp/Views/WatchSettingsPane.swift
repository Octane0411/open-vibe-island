import AppKit
import SwiftUI

struct WatchSettingsPane: View {
    var model: AppModel
    @State private var pairingCode = ""
    @State private var connectedDevices = 0
    private var lang: LanguageManager { model.lang }
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        Form {
            Section {
                Toggle(lang.t("watch.enabled"), isOn: Binding(
                    get: { model.watchNotificationEnabled },
                    set: { model.watchNotificationEnabled = $0 }
                ))
                Text(lang.t("watch.networkDescription"))
                    .font(.caption).foregroundStyle(.secondary)
            }
            if model.watchNotificationEnabled {
                pairingSection
                devicesSection
            }
        }
        .formStyle(.grouped)
        .navigationTitle(lang.t("watch.title"))
        .onAppear(perform: refresh)
        .onReceive(timer) { _ in refresh() }
    }

    private var pairingSection: some View {
        Section(lang.t("watch.pairing")) {
            Button(lang.t("watch.pairNewDevice")) {
                model.watchRelay?.endpoint.regeneratePairingCode()
                refresh()
            }
            if !pairingCode.isEmpty {
                Text(pairingCode)
                    .font(.system(size: 11, design: .monospaced))
                    .textSelection(.enabled)
                Button(lang.t("watch.copyKey")) {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(pairingCode, forType: .string)
                }
                Text(lang.t("watch.pairingInstructions"))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var devicesSection: some View {
        Section(lang.t("watch.devices")) {
            Label(lang.t(connectedDevices > 0 ? "watch.connected" : "watch.disconnected"),
                  systemImage: connectedDevices > 0 ? "iphone" : "iphone.slash")
            Button(lang.t("watch.revoke"), role: .destructive) {
                model.watchRelay?.endpoint.revokeAllTokens()
                refresh()
            }
        }
    }

    private func refresh() {
        pairingCode = model.watchPairingCode
        connectedDevices = model.watchConnectedDevices
    }
}
