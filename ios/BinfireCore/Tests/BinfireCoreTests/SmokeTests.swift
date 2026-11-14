import XCTest
@testable import BinfireCore

final class SmokeTests: XCTestCase {
    func testVersion() { XCTAssertEqual(BinfireCore.version, "0.1.0") }
}
