import XCTest
@testable import BinfireCore

final class LZTests: XCTestCase {
    var fixture: [String: Any]!
    override func setUpWithError() throws { fixture = try Fixtures.load("lz.json") }

    func testRoundtrip() throws {
        let cases = try Fixtures.list(fixture, "roundtrip")
        XCTAssertFalse(cases.isEmpty)
        for c in cases {
            let text = Array((c["text"] as! String).utf16)
            let compressed = Array((c["compressed"] as! String).utf16)
            XCTAssertEqual(LZ.compress(text), compressed, "compress \(c["text"]!)")
            XCTAssertEqual(try LZ.decompress(compressed, limitBytes: 5 * 1024 * 1024), text)
        }
    }

    func testInvalid() throws {
        for c in try Fixtures.list(fixture, "invalid") {
            let input = Array((c["compressed"] as! String).utf16)
            let limit = c["limit"] as! Int
            XCTAssertEqual(Fixtures.errorCode { try LZ.decompress(input, limitBytes: limit) }, c["error"] as? String,
                           c["name"] as! String)
        }
    }

    func testSpaces() throws {
        for c in try Fixtures.list(fixture, "spaces") {
            XCTAssertEqual(try LZ.decompress(c["compressed"] as! String, limitBytes: 1000), c["text"] as? String)
        }
    }

    func testLoneSurrogatesSurvive() throws {
        let text: [UInt16] = [0x61, 0xD800, 0x62, 0xDC00, 0xD83D, 0xDE00]
        let c = LZ.compress(text)
        XCTAssertEqual(try LZ.decompress(c, limitBytes: 100), text)
    }
}
