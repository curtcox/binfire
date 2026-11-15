import XCTest
@testable import BinfireCore

final class ConfigTests: XCTestCase {
    func testLoadsRuntimeConfig() throws {
        let c = try BinfireConfig.load(contentsOf: Fixtures.repoRoot.appendingPathComponent("ios/App/Resources/binfire.config.json"))
        XCTAssertEqual(c.ownScheme, "app.binfire.ios")
        XCTAssertEqual(c.oauthRedirect, "app.binfire.ios://oauth")
        var expected = BinfireConfig.default
        expected.ownScheme = c.ownScheme
        expected.oauthRedirect = c.oauthRedirect
        XCTAssertEqual(c, expected)
    }

    func testLoadsRepoConfig() throws {
        let c = try BinfireConfig.load(contentsOf: Fixtures.repoRoot.appendingPathComponent("config/binfire.config.json"))
        XCTAssertEqual(c.linkDomain, "binfire.app")
        XCTAssertEqual(c.limits, .default)
        XCTAssertEqual(c.hashbinMaxCostCents, 25)
    }

    func testHashBinMaxCostCents() throws {
        let c = try BinfireConfig(data: Data(#"{"hashbin":{"maxCostCents":7}}"#.utf8))
        XCTAssertEqual(c.hashbinMaxCostCents, 7)
        XCTAssertEqual(c.hashbinAPI, "https://hashbin.org")
        XCTAssertThrowsError(try BinfireConfig(data: Data(#"{"hashbin":{"maxCostCents":"7"}}"#.utf8)))
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
