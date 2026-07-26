import Foundation
import Testing
@testable import OpenIslandCore

struct OrbitReceiptTests {
    @Test
    func ledgerKeepsAppendOnlyStatusTransitionsWithinBound() {
        let receiptID = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!
        var ledger = OrbitReceiptLedger(maxEntries: 2)
        let queued = OrbitReceipt(
            id: receiptID,
            createdAt: Date(timeIntervalSince1970: 1_000),
            sessionID: "session-1",
            requestID: receiptID,
            adapter: "codex",
            action: .permissionAllowedOnce,
            scope: "SettingsView.swift",
            status: .queued,
            summary: "permission decision queued"
        )

        ledger.append(queued)
        ledger.append(queued.with(status: .sent))
        ledger.append(
            OrbitReceipt(
                sessionID: "session-2",
                adapter: "claudeCode",
                action: .questionAnswered,
                scope: "question",
                status: .failed,
                summary: "question answer failed"
            )
        )

        #expect(ledger.entries.count == 2)
        #expect(ledger.entries[0] == queued.with(status: .sent))
        #expect(ledger.entries[1].status == .failed)
        #expect(ledger.entry(id: receiptID)?.status == .sent)
    }

    @Test
    func receiptRoundTripsWithoutChangingIdentityOrStatus() throws {
        let receipt = OrbitReceipt(
            id: UUID(uuidString: "11111111-2222-3333-4444-555555555555")!,
            createdAt: Date(timeIntervalSince1970: 2_000),
            sessionID: "session-1",
            requestID: nil,
            adapter: "codex",
            action: .permissionDenied,
            scope: "SettingsView.swift",
            status: .failed,
            summary: "permission decision failed"
        )

        let data = try JSONEncoder().encode(receipt)
        let decoded = try JSONDecoder().decode(OrbitReceipt.self, from: data)

        #expect(decoded == receipt)
        #expect(decoded.id == receipt.id)
        #expect(decoded.status == .failed)
    }
}
