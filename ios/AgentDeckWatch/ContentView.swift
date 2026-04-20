import SwiftUI

struct ContentView: View {
    @EnvironmentObject var sessionManager: WatchSessionManager

    var body: some View {
        NavigationStack {
            Group {
                if sessionManager.pendingEvents.isEmpty {
                    emptyState
                } else {
                    eventList
                }
            }
            .navigationTitle("Agent Deck")
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "applewatch.radiowaves.left.and.right")
                .font(.system(size: 40))
                .foregroundStyle(.blue)
                .symbolEffect(.pulse, isActive: !sessionManager.isPhoneReachable)

            Text("一切就绪")
                .font(.headline)

            Text(sessionManager.isPhoneReachable ? "iPhone 已连接" : "iPhone 未连接")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var eventList: some View {
        List(sessionManager.pendingEvents.sorted(by: { $0.receivedAt > $1.receivedAt })) { event in
            EventCardView(event: event)
        }
        .safeAreaInset(edge: .bottom) {
            if let error = sessionManager.lastError {
                Text(error)
                    .font(.caption2)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.red.opacity(0.85), in: RoundedRectangle(cornerRadius: 6))
                    .padding(.bottom, 4)
            }
        }
    }
}
