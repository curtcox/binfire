import XCTest
@testable import BinfireCore

final class ConfigTests: XCTestCase {
    func testLoadsRuntimeConfig() throws {
        let c = try BinfireConfig.load(contentsOf: Fixtures.repoRoot.appendingPathComponent("ios/App/Resources/binfire.config.json"))
        XCTAssertEqual(c, BinfireConfig.default)
    }

    func testLoadsRepoConfig() throws {
        let c = try BinfireConfig.load(contentsOf: Fixtures.repoRoot.appendingPathComponent("config/binfire.config.json"))
        XCTAssertEqual(c.linkDomain, "binfire.app")
        XCTAssertEqual(c.limits, .default)
    }

    func testRejectsWrongTypes() {
        XCTAssertThrowsError(try BinfireConfig(data: Data(#"{"linkDomain": 5}"#.utf8)))
        XCTAssertThrowsError(try BinfireConfig(data: Data("[]".utf8)))
    }

    func testPartialConfigKeepsDefaults() throws {
        let c = try BinfireConfig(data: Data(#"{"linkDomain":"example.org","limits":{"maxSiteFiles":3}}"#.utf8))
        XCTAssertEqual(c.linkDomain, "example.org")
        XCTAssertEqual(c.limits.maxSiteFiles, 3)
        XCTAssertEqual(c.limits.maxTransferBytes, BinfireLimits.default.maxTransferBytes)
    }
}
