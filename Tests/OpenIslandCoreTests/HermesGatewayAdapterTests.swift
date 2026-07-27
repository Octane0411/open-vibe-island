import Foundation
import Testing
@testable import OpenIslandCore

@Suite
struct HermesGatewayAdapterTests {
    @Test
    func decodesMetadataOnlySessionList() throws {
        let data = Data(#"{"object":"list","data":[{"id":"session-1","title":"Orbit work","model":"gpt-5.6-sol","source":"desktop","status":"active","message_count":4,"updated_at":"2026-07-26T20:00:00Z","unexpected_prompt":"must not survive"}]}"#.utf8)

        let sessions = try HermesGatewayAdapter.decodeSessions(data)

        #expect(sessions == [
            HermesGatewaySession(
                id: "session-1",
                title: "Orbit work",
                model: "gpt-5.6-sol",
                source: "desktop",
                status: "active",
                messageCount: 4,
                updatedAt: "2026-07-26T20:00:00Z"
            ),
        ])
    }

    @Test
    func onlyAllowsLoopbackGatewayURLs() {
        #expect(HermesGatewayAdapter.isLoopback(URL(string: "http://127.0.0.1:8642")!))
        #expect(HermesGatewayAdapter.isLoopback(URL(string: "http://localhost:8642")!))
        #expect(HermesGatewayAdapter.isLoopback(URL(string: "http://[::1]:8642")!))
        #expect(!HermesGatewayAdapter.isLoopback(URL(string: "https://example.com")!))
    }

    @Test
    func unsupportedEventClaimsRemainUnavailable() {
        #expect(!HermesGatewayAdapter.supportsApprovalEvents)
        #expect(!HermesGatewayAdapter.supportsCompletionEvents)

        let snapshot = HermesGatewaySnapshot(
            gateway: .live,
            sessions: .live,
            sessionItems: [],
            detail: "fixture"
        )
        #expect(snapshot.approvals == .unavailable)
        #expect(snapshot.completions == .unavailable)
    }
}
