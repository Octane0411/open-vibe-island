import XCTest
@testable import OpenIslandCore

final class ClaudeCompatibleCLIProfileTests: XCTestCase {
    func testValidatesHookSource() {
        XCTAssertTrue(ClaudeCompatibleCLIProfile.isValidHookSource("ducc"))
        XCTAssertTrue(ClaudeCompatibleCLIProfile.isValidHookSource("company-cc_1.0"))
        XCTAssertFalse(ClaudeCompatibleCLIProfile.isValidHookSource(""))
        XCTAssertFalse(ClaudeCompatibleCLIProfile.isValidHookSource("company cc"))
        XCTAssertFalse(ClaudeCompatibleCLIProfile.isValidHookSource("company;cc"))
    }

    func testMatchesWrapperCommandByExecutablePath() {
        let profile = ClaudeCompatibleCLIProfile(
            displayName: "Company Claude",
            hookSource: "company-cc",
            executablePath: "/opt/company-ai/bin/acme-claude"
        )

        XCTAssertTrue(profile.matches(command: "/bin/sh /opt/company-ai/bin/acme-claude"))
    }

    func testMatchesWrapperCommandByExecutableBasename() {
        let profile = ClaudeCompatibleCLIProfile(
            displayName: "Company Claude",
            hookSource: "company-cc",
            executablePath: "/opt/company-ai/bin/acme-claude"
        )

        XCTAssertTrue(profile.matches(command: "/usr/bin/env acme-claude"))
    }

    func testDoesNotMatchInvalidProfile() {
        let profile = ClaudeCompatibleCLIProfile(
            displayName: "Invalid",
            hookSource: "company cc",
            executablePath: "/opt/company-ai/bin/acme-claude"
        )

        XCTAssertFalse(profile.matches(command: "/bin/sh /opt/company-ai/bin/acme-claude"))
    }
}
