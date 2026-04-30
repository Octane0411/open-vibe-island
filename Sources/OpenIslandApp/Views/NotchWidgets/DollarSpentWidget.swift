// Sources/OpenIslandApp/Views/NotchWidgets/DollarSpentWidget.swift
import SwiftUI
import AppKit
import OpenIslandCore

struct DollarSpentWidget: View {
    let state: CodeburnState

    var body: some View {
        switch state {
        case .ok(let snap):
            Text(format(snap.todayCost, currency: snap.currency))
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(.white.opacity(0.9))
                .lineLimit(1)

        case .notInstalled, .notProbed:
            Button(action: openInstallURL) {
                Image(systemName: "info.circle")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.5))
            }
            .buttonStyle(.plain)
            .help("Install codeburn to enable $ tracking")

        case .unavailable:
            Text("$—")
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(.white.opacity(0.4))
        }
    }

    private func format(_ cost: Double, currency: String) -> String {
        let symbol = (currency == "USD") ? "$" : ""
        if cost < 10 {
            return String(format: "\(symbol)%.2f", cost)
        }
        return String(format: "\(symbol)%.1f", cost)
    }

    private func openInstallURL() {
        if let url = URL(string: "https://github.com/getagentseal/codeburn#install") {
            NSWorkspace.shared.open(url)
        }
    }
}
