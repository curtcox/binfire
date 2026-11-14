import XCTest
@testable import BinfireCore

final class TransferTests: XCTestCase {
    var fixture: [String: Any]!
    var limits = BinfireLimits()

    override func setUpWithError() throws {
        fixture = try Fixtures.load("transfer.json")
        let l = try XCTUnwrap(fixture["limits"] as? [String: Int])
        limits.maxTransferBytes = try XCTUnwrap(l["maxTransferBytes"])
    }

    func testBundles() throws {
        let cases = try Fixtures.list(fixture, "bundles")
        XCTAssertFalse(cases.isEmpty)
        for c in cases {
            let name = c["name"] as! String
            let bytes = try Fixtures.b64(c["b64"])
            let expect = c["expect"] as! [String: Any]
            let b = try Transfer.decodeBundle(bytes, limits: limits)
            XCTAssertEqual(b.kind.rawValue, expect["kind"] as? String, name)
            XCTAssertEqual(b.url, expect["url"] as? String, name)
            XCTAssertEqual(b.cid, expect["cid"] as? String, name)
            XCTAssertEqual(b.app, expect["app"] as? String, name)
            XCTAssertEqual(b.name, expect["name"] as? String, name)
            XCTAssertEqual(b.entries.map(\.cid), expect["entries"] as? [String], name)
            XCTAssertEqual(b.manifest != nil, b.kind == .site, name)
            // Re-encoding a decoded bundle reproduces it (except ignored fields).
            if !["unknown header fields ignored", "header with leading BOM"].contains(name) {
                XCTAssertEqual(Transfer.encodeBundle(b), bytes, name)
            }
            XCTAssertEqual(try Transfer.decodeBundle(Transfer.encodeBundle(b), limits: limits).entries, b.entries)
        }
    }

    func testBundleErrors() throws {
        for c in try Fixtures.list(fixture, "bundleErrors") {
            let bytes = try Fixtures.b64(c["b64"])
            XCTAssertEqual(Fixtures.errorCode { try Transfer.decodeBundle(bytes, limits: limits) }, c["error"] as? String,
                           c["name"] as! String)
        }
    }

    func testFrames() throws {
        let cases = try Fixtures.list(fixture, "frames")
        XCTAssertFalse(cases.isEmpty)
        for c in cases {
            let name = c["name"] as! String
            let payload = try Fixtures.b64(c["payloadB64"])
            let id = try XCTUnwrap(Data(hex: c["idHex"] as! String))
            let expected = try (c["frames"] as! [String]).map { try Fixtures.b64($0) }
            XCTAssertEqual(CID.computeCID(payload), c["cid"] as? String, name)
            let frames = Transfer.encodeFrames(payload, id: id, chunkSize: c["chunkSize"] as! Int)
            XCTAssertEqual(frames, expected, name)

            var r = Reassembler(limits: limits)
            var result: Data?
            for (i, f) in expected.reversed().enumerated() {
                let decoded = try Transfer.decodeFrame(f)
                XCTAssertEqual(decoded.encoded, f, name)
                XCTAssertEqual(decoded.cid, c["cid"] as? String)
                result = try r.add(f)
                XCTAssertEqual(r.missing().count, expected.count - i - 1, name)
                if i < expected.count - 1 { XCTAssertNil(result, name) }
            }
            XCTAssertEqual(result, payload, name)
            XCTAssertTrue(r.isComplete)
            // Identical duplicates are ignored.
            XCTAssertNil(try r.add(expected[0]))
        }
    }

    func testMissingListsGaps() throws {
        let c = try Fixtures.list(fixture, "frames").first { $0["name"] as? String == "ten bytes in chunks of four" }!
        let frames = try (c["frames"] as! [String]).map { try Fixtures.b64($0) }
        var r = Reassembler(limits: limits)
        XCTAssertEqual(r.missing(), [])
        try r.add(frames[1])
        XCTAssertEqual(r.missing(), [0, 2])
        XCTAssertEqual(r.missing(limit: 1), [0])
    }

    func testFrameErrors() throws {
        for c in try Fixtures.list(fixture, "frameErrors") {
            let bytes = try Fixtures.b64(c["b64"])
            XCTAssertEqual(Fixtures.errorCode { try Transfer.decodeFrame(bytes) }, c["error"] as? String, c["name"] as! String)
        }
    }

    func testReassemblyErrors() throws {
        for c in try Fixtures.list(fixture, "reassemblyErrors") {
            let frames = try (c["frames"] as! [String]).map { try Fixtures.b64($0) }
            var r = Reassembler(limits: limits)
            let code = Fixtures.errorCode { for f in frames { try r.add(f) } }
            XCTAssertEqual(code, c["error"] as? String, c["name"] as! String)
        }
    }

    func testBuildersAndSlices() throws {
        let doc = Data(#"{"format":"hashbin-diagram","type":"python","src":""}"#.utf8)
        var container = Data([9, 9, 9])
        container.append(Transfer.encodeBundle(.document(doc, app: "python", name: "Doc")))
        let slice = container.dropFirst(3) // non-zero startIndex
        let b = try Transfer.decodeBundle(slice, limits: limits)
        XCTAssertEqual(b.entries.first?.bytes, doc)
        XCTAssertEqual(b.app, "python")
        let frames = Transfer.encodeFrames(slice, id: Transfer.randomTransferID(), chunkSize: 7)
        var r = Reassembler(limits: limits)
        var out: Data?
        for f in frames { out = try r.add((Data([0]) + f).dropFirst()) }
        XCTAssertEqual(out, Data(slice))
    }

    func testQR() throws {
        let qr = try XCTUnwrap(fixture["qr"] as? [String: String])
        XCTAssertEqual(qr["prefix"], Transfer.qrPrefix)
        let set = try Fixtures.list(fixture, "frames")[1]
        let frame = try Fixtures.b64((set["frames"] as! [String])[0])
        XCTAssertEqual(Transfer.qrText(frame), qr["example"])
        XCTAssertEqual(Transfer.frameFromQRText(qr["example"]!), frame)
        XCTAssertNil(Transfer.frameFromQRText("https://binfire.app/"))
    }
}
