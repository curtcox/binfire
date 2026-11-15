import XCTest
@testable import BinfireCore
#if canImport(Vision)
import Vision
import CoreGraphics
import ImageIO
#endif

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

    /// The links.json configuration (the fixtures' routes assume it).
    private func fixtureLinks() throws -> Links {
        let links = try Fixtures.load("links.json")
        let cfg = try XCTUnwrap(links["config"] as? [String: String])
        let config = BinfireConfig(linkDomain: cfg["linkDomain"]!, scheme: cfg["scheme"]!,
                                   ownScheme: cfg["ownScheme"] ?? "", contentHost: cfg["content"]!)
        return Links(config: config, registry: try Fixtures.registry())
    }

    func testScans() throws {
        let fixture = try Fixtures.load("qr.json")
        let links = try fixtureLinks()
        let cases = try Fixtures.list(fixture, "scans")
        XCTAssertFalse(cases.isEmpty)
        for c in cases {
            let name = c["name"] as! String
            let texts = c["texts"] as! [String]
            let results = c["results"] as! [[String: Any]]
            XCTAssertEqual(texts.count, results.count, name)
            var session = ScanSession(links: links)
            for (i, (text, want)) in zip(texts, results).enumerated() {
                let label = "\(name) #\(i)"
                let got = session.accept(text)
                XCTAssertEqual(got.kind, want["kind"] as? String, label)
                switch got {
                case let .progress(received, count):
                    if let r = want["received"] as? Int { XCTAssertEqual(received, r, label) }
                    if let n = want["count"] as? Int { XCTAssertEqual(count, n, label) }
                case let .frameError(e):
                    if let w = want["error"] as? String { XCTAssertEqual(e.code, w, label) }
                case let .bundle(payload):
                    if want["payloadB64"] != nil { XCTAssertEqual(payload, try Fixtures.b64(want["payloadB64"]), label) }
                case let .route(route):
                    if let r = want["route"] as? [String: Any] { LinksTests.assertRoute(route, r, label) }
                }
            }
        }
    }

    func testMaxFrameText() throws {
        let fixture = try Fixtures.load("qr.json")
        let max = try XCTUnwrap(fixture["maxFrameText"] as? Int)
        XCTAssertEqual(max, 4 + ((29 + 94 + 512) * 4 + 2) / 3) // 4 + ceil(635 * 4 / 3)
        XCTAssertEqual(QR.qrPlan(bytes: max), .ok)
    }

    func testMultiFrameSendRoundTrip() throws {
        let links = try fixtureLinks()
        let url = "https://python.hashbin.page/#v1." + String(repeating: "x", count: 4000)
        let id = Data([1, 2, 3, 4, 5, 6, 7, 8])
        let texts = QR.multiFrameTexts(url: url, id: id)
        XCTAssertGreaterThan(texts.count, 1)
        let payload = Transfer.encodeBundle(.url(url))
        XCTAssertEqual(texts, Transfer.encodeFrames(payload, id: id, chunkSize: 512).map { "BF1:" + Base64URL.encode($0) })
        for t in texts {
            XCTAssertTrue(t.hasPrefix("BF1:"))
            XCTAssertLessThanOrEqual(t.utf8.count, 851)
            XCTAssertEqual(QR.qrPlan(t), .ok)
        }
        // Received in reverse order, with a repeat.
        var session = ScanSession(links: links)
        var last: ScanResult?
        for (i, t) in ([texts[texts.count - 1]] + texts.reversed()).enumerated() {
            last = session.accept(t)
            if i < texts.count { XCTAssertEqual(last?.kind, "progress") }
        }
        guard case let .bundle(got)? = last else { return XCTFail("no bundle: \(String(describing: last))") }
        XCTAssertEqual(got, payload)
        guard case let .route(route) = ReceivedAction.from(payload: got, links: links),
              case let .openApp(app, opened, _, run, _) = route else { return XCTFail("not open-app") }
        XCTAssertEqual(app, "python")
        XCTAssertEqual(opened, Links.withRunZero(url))
        XCTAssertFalse(run)
        // Two sends of one URL use different random ids.
        XCTAssertNotEqual(QR.multiFrameTexts(url: url), QR.multiFrameTexts(url: url))
    }

    func testReceivedBundles() throws {
        let links = try fixtureLinks()
        let doc = Data("hello document".utf8)
        let cidBundle = Transfer.encodeBundle(.document(doc, app: "python"))
        XCTAssertEqual(ReceivedAction.from(payload: cidBundle, links: links),
                       .document(cid: CID.computeCID(doc), bytes: doc, app: "python"))
        XCTAssertEqual(ReceivedAction.from(payload: Data("nope".utf8), links: links), .error(.badMagic))
        // transfer.json bundles: every kind acts per spec/qr.md.
        for c in try Fixtures.list(try Fixtures.load("transfer.json"), "bundles") {
            let name = c["name"] as! String
            let expect = c["expect"] as! [String: Any]
            let action = ReceivedAction.from(payload: try Fixtures.b64(c["b64"]), links: links)
            switch expect["kind"] as! String {
            case "url":
                XCTAssertEqual(action, .route(links.routeReceived(expect["url"] as! String)), name)
            case "cid":
                guard case let .document(cid, bytes, app) = action else { XCTFail(name); continue }
                XCTAssertEqual(cid, expect["cid"] as? String, name)
                XCTAssertTrue(CID.verify(cid, bytes), name)
                XCTAssertEqual(app, expect["app"] as? String, name)
            default:
                XCTAssertEqual(action, .error(nil), name)
            }
        }
        let text = Transfer.encodeBundle(.url("hello world"))
        XCTAssertEqual(ReceivedAction.from(payload: text, links: links), .route(.showText("hello world")))
    }

    func testRouteReceivedRunZero() throws {
        let links = try fixtureLinks()
        let cid = "AAAAAABBuDCGzYSU5VcIrX7Ngt-0vKG9ph7Lt8rwxolnkC5wk0Xl2DBet6wNWIr8bLt1FhqpyMfg6phr2DPa_l4czTc0Wg"
        XCTAssertEqual(links.routeReceived(cid), .loadCID(cid: cid, app: nil, run: false))
        XCTAssertEqual(links.route(cid), .loadCID(cid: cid, app: nil, run: true))
    }

    /// Decodes `shared/fixtures/qr/*.png` with Vision, as scan-from-image does.
    func testFixtureImagesDecodeWithVision() throws {
        #if canImport(Vision)
        let fixture = try Fixtures.load("qr.json")
        let images = try Fixtures.list(fixture, "images")
        XCTAssertFalse(images.isEmpty)
        for img in images {
            let file = img["file"] as! String
            let url = Fixtures.repoRoot.appendingPathComponent("shared/fixtures/qr/\(file)")
            guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
                  let cg = CGImageSourceCreateImageAtIndex(src, 0, nil) else { return XCTFail("can't read \(file)") }
            let request = VNDetectBarcodesRequest()
            request.symbologies = [.qr]
            do {
                try VNImageRequestHandler(cgImage: cg, options: [:]).perform([request])
            } catch {
                throw XCTSkip("Vision unavailable here: \(error)")
            }
            let texts = (request.results ?? []).compactMap(\.payloadStringValue)
            XCTAssertEqual(texts.first, img["text"] as? String, file)
        }
        #else
        throw XCTSkip("Vision is not available on this platform")
        #endif
    }
}
