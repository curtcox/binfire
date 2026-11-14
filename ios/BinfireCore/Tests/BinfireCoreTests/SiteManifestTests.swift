import XCTest
@testable import BinfireCore

final class SiteManifestTests: XCTestCase {
    var fixture: [String: Any]!
    var limits = BinfireLimits()

    override func setUpWithError() throws {
        fixture = try Fixtures.load("site-manifest.json")
        let l = try XCTUnwrap(fixture["limits"] as? [String: Int])
        limits.maxSiteFiles = try XCTUnwrap(l["maxSiteFiles"])
        limits.maxSiteFileBytes = try XCTUnwrap(l["maxSiteFileBytes"])
        limits.maxSiteTotalBytes = try XCTUnwrap(l["maxSiteTotalBytes"])
    }

    func testValid() throws {
        let cases = try Fixtures.list(fixture, "valid")
        XCTAssertFalse(cases.isEmpty)
        for c in cases {
            let name = c["name"] as! String
            let bytes = Data((c["text"] as! String).utf8)
            let m = try Sites.validateManifest(bytes, limits: limits)
            let cid = CID.computeCID(bytes)
            XCTAssertEqual(cid, c["cid"] as? String, name)
            XCTAssertEqual(Sites.siteId(cid), c["siteId"] as? String, name)
            XCTAssertEqual(m.entry, c["entry"] as? String, name)
            XCTAssertEqual(m.files.count, c["files"] as? Int, name)
        }
    }

    func testInvalid() throws {
        for c in try Fixtures.list(fixture, "invalid") {
            let bytes = Data((c["text"] as! String).utf8)
            XCTAssertEqual(Fixtures.errorCode { try Sites.validateManifest(bytes, limits: limits) }, c["error"] as? String,
                           c["name"] as! String)
        }
    }

    func testPaths() throws {
        for c in try Fixtures.list(fixture, "paths") {
            let path = c["path"] as! String
            XCTAssertEqual(Sites.isValidPath(path), c["ok"] as! Bool, path)
        }
    }

    func testSiteIds() throws {
        for c in try Fixtures.list(fixture, "siteIds") {
            let id = Sites.siteId(c["cid"] as! String)
            XCTAssertEqual(id, c["siteId"] as? String)
            XCTAssertEqual(id.count, 52)
        }
    }
}
