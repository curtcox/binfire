import XCTest
@testable import BinfireCore

final class LinksTests: XCTestCase {
    var fixture: [String: Any]!
    var links: Links!

    override func setUpWithError() throws {
        fixture = try Fixtures.load("links.json")
        let cfg = try XCTUnwrap(fixture["config"] as? [String: String])
        let config = BinfireConfig(linkDomain: cfg["linkDomain"]!, scheme: cfg["scheme"]!,
                                   ownScheme: cfg["ownScheme"] ?? "", contentHost: cfg["content"]!)
        links = Links(config: config, registry: try Fixtures.registry())
    }

    /// The spec's JSON shape of a Route (`nil` stands for JSON null).
    static func fields(_ r: Route) -> [String: Any?] {
        var f: [String: Any?] = ["action": r.action]
        switch r {
        case let .openApp(app, url, state, run, view):
            f["app"] = app; f["url"] = url; f["state"] = state.rawValue; f["run"] = run; f["view"] = .some(view)
        case let .loadCID(cid, app, run):
            f["cid"] = cid; f["app"] = .some(app); f["run"] = run
        case let .openSite(cid):
            f["cid"] = cid
        case let .showText(text):
            f["text"] = text
        case let .error(e):
            f["error"] = e.code
        }
        return f
    }

    func testRoute() throws { try checkRoutes("route") { links.route($0) } }

    func testRouteShared() throws { try checkRoutes("routeShared") { links.routeShared($0) } }

    func testRouteReceived() throws { try checkRoutes("routeReceived") { links.routeReceived($0) } }

    func testWithoutRun() throws {
        let cases = try Fixtures.list(fixture, "withoutRun")
        XCTAssertFalse(cases.isEmpty)
        for c in cases { XCTAssertEqual(Links.withoutRun(c["url"] as! String), c["result"] as? String) }
    }

    func testStripSharedToken() {
        XCTAssertEqual(Links.stripSharedToken("(https://x/#print(1))."), "https://x/#print(1)")
        XCTAssertEqual(Links.stripSharedToken("<a>"), "a")
        XCTAssertEqual(Links.stripSharedToken("x)]"), "x")
    }

    func checkRoutes(_ key: String, _ routeFn: (String) -> Route) throws {
        let cases = try Fixtures.list(fixture, key)
        XCTAssertFalse(cases.isEmpty)
        for c in cases {
            let input = c["input"] as! String
            LinksTests.assertRoute(routeFn(input), c["expect"] as! [String: Any], input)
        }
    }

    /// Compares only the fields present in `expect` (a fixture route).
    static func assertRoute(_ route: Route, _ expect: [String: Any], _ label: String,
                            file: StaticString = #filePath, line: UInt = #line) {
        let got = fields(route)
        for (key, want) in expect {
            guard let entry = got[key] else { XCTFail("\(label): missing \(key)", file: file, line: line); continue }
            let have = entry ?? NSNull()
            if let h = have as? Bool {
                XCTAssertEqual(h, want as? Bool, "\(label): \(key)", file: file, line: line)
            } else {
                XCTAssertEqual("\(have)", "\(want)", "\(label): \(key)", file: file, line: line)
                XCTAssertEqual(have is NSNull, want is NSNull, "\(label): \(key) null-ness", file: file, line: line)
            }
        }
    }

    func testRouteTooLarge() {
        let big = String(repeating: "a", count: links.config.limits.maxStateBytes + 4097)
        XCTAssertEqual(links.route(big), .error(.tooLarge))
    }

    func testMakeLink() throws {
        for c in try Fixtures.list(fixture, "makeLink") {
            let url = c["url"] as! String
            if c["link"] is NSNull { XCTAssertNil(links.makeLink(url), url) }
            else { XCTAssertEqual(links.makeLink(url), c["link"] as? String, url) }
        }
        XCTAssertNil(links.makeLink("https://example.com/"))
    }

    func testMakeCIDLink() throws {
        for c in try Fixtures.list(fixture, "makeCIDLink") {
            XCTAssertEqual(links.makeCIDLink(c["cid"] as! String, app: c["app"] as? String), c["link"] as? String)
        }
    }

    func testMakeSiteLink() throws {
        for c in try Fixtures.list(fixture, "makeSiteLink") {
            XCTAssertEqual(links.makeSiteLink(c["cid"] as! String), c["link"] as? String)
        }
    }

    func testEncodeURIComponent() throws {
        for c in try Fixtures.list(fixture, "encodeURIComponent") {
            XCTAssertEqual(Links.encodeURIComponent(c["text"] as! String), c["encoded"] as? String)
        }
    }

    func testWithRunZero() throws {
        let cases = try Fixtures.list(fixture, "withRunZero")
        XCTAssertFalse(cases.isEmpty)
        for c in cases {
            XCTAssertEqual(Links.withRunZero(c["url"] as! String), c["result"] as? String)
        }
    }

    func testPasteInput() {
        XCTAssertNil(Links.pasteInput(nil))
        XCTAssertNil(Links.pasteInput(""))
        XCTAssertNil(Links.pasteInput(" \n\t"))
        XCTAssertEqual(Links.pasteInput(" https://x/ "), " https://x/ ")
    }

    func testMadeLinksRouteBack() throws {
        for c in try Fixtures.list(fixture, "makeLink") where !(c["link"] is NSNull) {
            let url = c["url"] as! String
            guard case let .openApp(_, target, _, _, _) = links.route(links.makeLink(url)!) else {
                return XCTFail("did not route back: \(url)")
            }
            XCTAssertEqual(target, url)
        }
    }
}
