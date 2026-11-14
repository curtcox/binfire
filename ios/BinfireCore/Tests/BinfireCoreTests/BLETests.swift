import XCTest
@testable import BinfireCore

final class BLETests: XCTestCase {
    func testCodes() throws {
        let cases = try Fixtures.list(Fixtures.load("ble.json"), "codes")
        XCTAssertFalse(cases.isEmpty)
        for c in cases {
            let s = try XCTUnwrap(Data(hex: c["senderNonceHex"] as! String))
            let r = try XCTUnwrap(Data(hex: c["receiverNonceHex"] as! String))
            XCTAssertEqual(BLE.confirmationCode(senderNonce: s, receiverNonce: r), c["code"] as? String)
        }
    }
}
