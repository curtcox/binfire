import XCTest
@testable import BinfireCore

final class QRTests: XCTestCase {
    func testPlans() throws {
        let fixture = try Fixtures.load("qr.json")
        let t = try XCTUnwrap(fixture["thresholds"] as? [String: Int])
        XCTAssertEqual(t["okMax"], QR.okMax)
        XCTAssertEqual(t["denseMax"], QR.denseMax)
        let cases = try Fixtures.list(fixture, "plans")
        XCTAssertFalse(cases.isEmpty)
        for c in cases {
            XCTAssertEqual(QR.qrPlan(bytes: c["bytes"] as! Int).rawValue, c["plan"] as? String)
        }
    }
}
