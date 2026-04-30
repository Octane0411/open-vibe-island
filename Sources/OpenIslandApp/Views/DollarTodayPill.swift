import SwiftUI
import OpenIslandCore

struct DollarTodayPill: View {
    let state: CodeburnState

    var body: some View {
        if case .ok(let snap) = state {
            Text(format(snap.todayCost, currency: snap.currency))
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundStyle(tint(for: snap.todayCost))
                .accessibilityLabel("\(snap.currency) \(snap.todayCost) spent today")
        } else {
            EmptyView()
        }
    }

    private func format(_ cost: Double, currency: String) -> String {
        let symbol = (currency == "USD") ? "$" : ""
        if cost < 10 { return String(format: "\(symbol)%.2f", cost) }
        return String(format: "\(symbol)%.1f", cost)
    }

    private func tint(for cost: Double) -> Color {
        if cost < 5 { return .green }
        if cost < 20 { return .yellow }
        return .orange
    }
}
