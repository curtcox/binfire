import XCTest
@testable import BinfireCore

final class CIDTests: XCTestCase {
    var fixture: [String: Any]!
    override func setUpWithError() throws { fixture = try Fixtures.load("cid.json") }

    func testCompute() throws {
        let cases = try Fixtures.list(fixture, "compute") + Fixtures.list(fixture, "reference")
        XCTAssertGreaterThan(cases.count, 10)
        for c in cases {
            let cid = c["cid"] as! String
            let bytes = try Fixtures.bytes(c)
            XCTAssertEqual(CID.computeCID(bytes), cid)
            XCTAssertEqual(CID.cidLength(cid), bytes.count)
            XCTAssertTrue(CID.verify(cid, bytes))
            XCTAssertEqual(CID.isInline(cid), bytes.count <= 64)
            if bytes.count <= 64 { XCTAssertEqual(CID.inlineContent(cid), bytes) }
        }
    }

    func testValid() throws {
        let valid = try XCTUnwrap(fixture["valid"] as? [String])
        XCTAssertFalse(valid.isEmpty)
        for cid in valid { XCTAssertTrue(CID.isCID(cid), cid) }
    }

    func testInvalid() throws {
        for c in try Fixtures.list(fixture, "invalid") {
            XCTAssertFalse(CID.isCID(c["cid"] as! String), c["why"] as! String)
        }
    }

    func testVerify() throws {
        for c in try Fixtures.list(fixture, "verify") {
            XCTAssertEqual(CID.verify(c["cid"] as! String, try Fixtures.bytes(c)), c["ok"] as! Bool, "\(c)")
        }
    }

    func testLengths() throws {
        for c in try Fixtures.list(fixture, "lengths") {
            XCTAssertEqual(CID.cidLength(c["cid"] as! String), c["length"] as? Int)
        }
    }

    func testBase64URLStrict() {
        XCTAssertNil(Base64URL.decode("QQ=="))
        XCTAssertNil(Base64URL.decode("QR"))   // non-canonical trailing bits
        XCTAssertNil(Base64URL.decode("Q"))    // len % 4 == 1
        XCTAssertNil(Base64URL.decode("a+b/"))
        XCTAssertEqual(Base64URL.decode("QQ"), Data("A".utf8))
        XCTAssertEqual(Base64URL.encode(Data([0xFB, 0xFF])), "-_8")
    }
}
