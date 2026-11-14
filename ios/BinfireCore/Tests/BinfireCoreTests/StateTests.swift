import XCTest
@testable import BinfireCore

final class StateTests: XCTestCase {
    func testCases() throws {
        let registry = try Fixtures.registry()
        let cases = try Fixtures.list(Fixtures.load("state.json"), "cases")
        XCTAssertFalse(cases.isEmpty)
        for c in cases {
            let url = c["url"] as! String
            XCTAssertEqual(registry.appForURL(url)?.slug, c["app"] as? String, url)
            let s = URLState.classifyState(url)
            XCTAssertEqual(s.state.rawValue, c["state"] as? String, url)
            XCTAssertEqual(s.run, c["run"] as? Bool, url)
            XCTAssertEqual(s.view, c["view"] as? String, url)
            XCTAssertEqual(s.cid, c["cid"] as? String, url)
            XCTAssertEqual(s.bytes, c["bytes"] as? Int, url)
        }
    }
}
