import XCTest
@testable import OpenIslandCore

final class HookSourceClassificationTests: XCTestCase {
    func testMissingSourceDefaultsToCodex() {
        XCTAssertEqual(HookSourceClassification.classify(nil), .codex)
        XCTAssertEqual(HookSourceClassification.classify(""), .codex)
    }

    func testKnownNonClaudeSourcesKeepTheirProtocol() {
        XCTAssertEqual(HookSourceClassification.classify("codex"), .codex)
        XCTAssertEqual(HookSourceClassification.classify("cursor"), .cursor)
        XCTAssertEqual(HookSourceClassification.classify("gemini"), .gemini)
    }

    func testKnownClaudeSourcesUseClaudeFormat() {
        XCTAssertEqual(HookSourceClassification.classify("claude"), .claudeFormat("claude"))
        XCTAssertEqual(HookSourceClassification.classify("qoder"), .claudeFormat("qoder"))
        XCTAssertEqual(HookSourceClassification.classify("kimi"), .claudeFormat("kimi"))
    }

    func testUnknownNonEmptySourceUsesClaudeFormat() {
        XCTAssertEqual(HookSourceClassification.classify("acme-cc"), .claudeFormat("acme-cc"))
        XCTAssertTrue(HookSourceClassification.classify("company-cc").isClaudeFormat)
    }
}
