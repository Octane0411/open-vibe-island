import XCTest
@testable import OpenIslandCore

final class ClaudeCompatibleCLIProfileStoreTests: XCTestCase {
    private var defaults: UserDefaults!
    private let suiteName = "ClaudeCompatibleCLIProfileStoreTests"

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        super.tearDown()
    }

    func testSaveAndLoadProfiles() throws {
        let store = ClaudeCompatibleCLIProfileStore(userDefaults: defaults, key: "profiles")
        let profile = ClaudeCompatibleCLIProfile(
            displayName: "Company Claude",
            hookSource: "company-cc",
            executablePath: "/opt/company-ai/bin/acme-claude"
        )

        try store.save([profile])

        XCTAssertEqual(store.load(), [profile])
    }

    func testLoadFiltersInvalidProfiles() throws {
        let store = ClaudeCompatibleCLIProfileStore(userDefaults: defaults, key: "profiles")
        let valid = ClaudeCompatibleCLIProfile(
            displayName: "Company Claude",
            hookSource: "company-cc",
            executablePath: "/opt/company-ai/bin/acme-claude"
        )
        let invalid = ClaudeCompatibleCLIProfile(
            displayName: "Invalid",
            hookSource: "company cc",
            executablePath: "/opt/company-ai/bin/acme-claude"
        )

        try store.save([valid, invalid])

        XCTAssertEqual(store.load(), [valid])
    }
}
