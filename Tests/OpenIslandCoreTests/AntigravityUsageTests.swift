import Foundation
import Testing
@testable import OpenIslandCore

struct AntigravityUsageTests {
    @Test
    func credentialStoreParsesLinesAndKeepsFreshestPerAddress() throws {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("agy-credentials-\(UUID().uuidString)")

        defer {
            try? FileManager.default.removeItem(at: fileURL)
        }

        let payload = """
        localhost:58033 stale-token 1795577000
        not-a-credential-line
        localhost:58033 fresh-token 1795578000
        localhost:49446 other-token 1795579000
        """
        try payload.write(to: fileURL, atomically: true, encoding: .utf8)

        let credentials = AntigravityCredentialStore.load(from: fileURL)

        #expect(credentials.count == 2)
        #expect(credentials[0] == AntigravityCredential(
            address: "localhost:58033",
            token: "fresh-token",
            capturedAt: Date(timeIntervalSince1970: 1_795_578_000)
        ))
        #expect(credentials[1].address == "localhost:49446")
    }

    @Test
    func credentialStoreReturnsEmptyForMissingFile() {
        let missingURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("agy-credentials-missing-\(UUID().uuidString)")

        #expect(AntigravityCredentialStore.load(from: missingURL).isEmpty)
    }

    @Test
    func quotaParsingReadsPlanCredits() throws {
        let payload = """
        {
          "userStatus": {
            "planStatus": {
              "planInfo": {
                "planName": "Pro",
                "monthlyPromptCredits": 50000,
                "monthlyFlowCredits": 150000
              },
              "availablePromptCredits": 500,
              "availableFlowCredits": 100
            }
          }
        }
        """

        let snapshot = try AntigravityUsageLoader.parseQuota(
            from: Data(payload.utf8)
        )

        #expect(snapshot.planName == "Pro")
        #expect(snapshot.monthlyPromptCredits == 50_000)
        #expect(snapshot.availablePromptCredits == 500)
        #expect(snapshot.monthlyFlowCredits == 150_000)
        #expect(snapshot.availableFlowCredits == 100)
        #expect(snapshot.isEmpty == false)
    }

    @Test
    func quotaParsingAcceptsStringNumbersAndMissingPlanInfo() throws {
        let payload = """
        {
          "userStatus": {
            "planStatus": {
              "planInfo": {
                "monthlyPromptCredits": "800",
                "monthlyFlowCredits": 2400
              },
              "availablePromptCredits": "200",
              "availableFlowCredits": 600
            }
          }
        }
        """

        let snapshot = try AntigravityUsageLoader.parseQuota(
            from: Data(payload.utf8)
        )

        #expect(snapshot.monthlyPromptCredits == 800)
        #expect(snapshot.availablePromptCredits == 200)
        #expect(snapshot.monthlyFlowCredits == 2_400)
        #expect(snapshot.availableFlowCredits == 600)
    }

    @Test
    func quotaParsingRejectsPayloadsWithoutPlanStatus() {
        #expect(throws: AntigravityUsageError.invalidResponse) {
            _ = try AntigravityUsageLoader.parseQuota(from: Data("{\"userStatus\": {}}".utf8))
        }
    }

    @Test
    func usedPercentagesClampAndReport() {
        let snapshot = AntigravityQuotaSnapshot(
            planName: nil,
            monthlyPromptCredits: 50_000,
            availablePromptCredits: 500,
            monthlyFlowCredits: 150_000,
            availableFlowCredits: 0
        )

        #expect(abs(snapshot.promptUsedPercentage - 99) < 0.0001)
        #expect(snapshot.flowUsedPercentage == 100)

        let exhausted = AntigravityQuotaSnapshot(
            planName: nil,
            monthlyPromptCredits: 0,
            availablePromptCredits: 0,
            monthlyFlowCredits: 0,
            availableFlowCredits: 0
        )
        #expect(exhausted.isEmpty)
        #expect(exhausted.promptUsedPercentage == 0)
    }

    @Test
    func requestCarriesConnectHeadersAndToken() throws {
        let credential = AntigravityCredential(
            address: "localhost:58033",
            token: "975a0492-a78a-4df8-9fe0-998c7bb7193b"
        )

        let request = try #require(AntigravityUsageLoader.makeRequest(credential: credential))

        #expect(request.url?.absoluteString == "http://localhost:58033/exa.language_server_pb.LanguageServerService/GetUserStatus")
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
        #expect(request.value(forHTTPHeaderField: "Connect-Protocol-Version") == "1")
        #expect(request.value(forHTTPHeaderField: "x-antigravity-csrf-token") == credential.token)
    }
}
