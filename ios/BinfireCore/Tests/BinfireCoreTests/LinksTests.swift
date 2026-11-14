import XCTest
@testable import BinfireCore

final class LinksTests: XCTestCase {
    var fixture: [String: Any]!
    var links: Links!

    override func setUpWithError() throws {
        fixture = try Fixtures.load("links.json")
        let cfg = try XCTUnwrap(fixture["config"] as? [String: String])
        let config = BinfireConfig(linkDomain: cfg["linkDomain"]!, scheme: cfg["scheme"]!, contentHost: cfg["content"]!)
        links = Links(config: config, registry: try Fixtures.registry())
    }

    /// The spec's JSON shape of a Route (`nil` stands for JSON null).
    static func fields(_ r: Route) -> [String: Any?] {
        var f: [String: Any?] = ["action": r.action]
        switch r {
        case let .openApp(app, url, state, run, view):
            f["app"] = app; f["url"] = url; f["state"] = state.rawValue; f["run"] = run; f["view"] = .some(view)
        case let .loadCID(cid, app):
            f["cid"] = cid; f["app"] = .some(app)
        case let .openSite(cid):
            f["cid"] = cid
        case let .showText(text):
            f["text"] = text
        case let .error(e):
            f["error"] = e.code
        }
        return f
    }

    func testRoute() throws {
        let cases = try Fixtures.list(fixture, "route")
        XCTAssertFalse(cases.isEmpty)
        for c in cases {
            let input = c["input"] as! String
            let expect = c["expect"] as! [String: Any]
            let got = LinksTests.fields(links.route(input))
            for (key, want) in expect {
                guard let entry = got[key] else { XCTFail("\(input): missing \(key)"); continue }
                let have = entry ?? NSNull()
                if let h = have as? Bool {
                    XCTAssertEqual(h, want as? Bool, "\(input): \(key)")
                } else {
                    XCTAssertEqual("\(have)", "\(want)", "\(input): \(key)")
                    XCTAssertEqual(have is NSNull, want is NSNull, "\(input): \(key) null-ness")
                }
            }
        }
    }

    func testRouteTooLarge() {
        let big = String(repeating: "a", count: links.config.limits.maxStateBytes + 4097)
        XCTAssertEqual(links.route(big), .error(.tooLarge))
    }

    func testMakeLink() throws {
        for c in try Fixtures.list(fixture, "makeLink") {
            XCTAssertEqual(links.makeLink(c["url"] as! String), c["link"] as? String)
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

    func testMadeLinksRouteBack() throws {
        for c in try Fixtures.list(fixture, "makeLink") {
            let url = c["url"] as! String
            guard case let .openApp(_, target, _, _, _) = links.route(links.makeLink(url)!) else {
                return XCTFail("did not route back: \(url)")
            }
            XCTAssertEqual(target, url)
        }
    }
}
