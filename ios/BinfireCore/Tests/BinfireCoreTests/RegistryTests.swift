import XCTest
@testable import BinfireCore

final class RegistryTests: XCTestCase {
    func testCases() throws {
        let registry = try Fixtures.registry()
        let cases = try Fixtures.list(Fixtures.load("registry.json"), "cases")
        XCTAssertFalse(cases.isEmpty)
        for c in cases {
            let url = c["url"] as! String
            XCTAssertEqual(registry.appForURL(url)?.slug, c["app"] as? String, url)
        }
    }

    func testBundledCopyMatchesShared() throws {
        let shared = try Fixtures.registry()
        let bundled = try Registry.load(contentsOf: Fixtures.repoRoot.appendingPathComponent("ios/App/Resources/apps.json"))
        XCTAssertEqual(shared, bundled)
    }

    func testRejectsBadSlug() {
        let app = RegistryApp(slug: "Bad", name: "x", canonicalOrigin: "https://a.example/", recoveryOrigin: "https://b.example/")
        XCTAssertThrowsError(try Registry(apps: [app]))
    }
}
