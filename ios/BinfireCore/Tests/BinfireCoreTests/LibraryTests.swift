import XCTest
@testable import BinfireCore

final class LibraryTests: XCTestCase {
    let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    func testRecentDedupesAndOrdersNewestFirst() {
        var lib = Library()
        lib.addRecent(url: "https://a/#1", app: "a", at: t0)
        lib.addRecent(url: "https://a/#2", app: "a", at: t0 + 1)
        lib.addRecent(url: "https://a/#1", app: "a", at: t0 + 2)
        XCTAssertEqual(lib.recent.map(\.url), ["https://a/#1", "https://a/#2"])
        XCTAssertEqual(lib.recent[0].visitedAt, t0 + 2)
    }

    func testRecentCappedAt100() {
        var lib = Library()
        for i in 0..<150 { lib.addRecent(url: "https://a/#\(i)", app: "a", at: t0 + Double(i)) }
        XCTAssertEqual(lib.recent.count, 100)
        XCTAssertEqual(lib.recent.first?.url, "https://a/#149")
        XCTAssertEqual(lib.recent.last?.url, "https://a/#50")
    }

    func testSavedNewestFirstAllowsDuplicatesAndDeletes() {
        var lib = Library()
        let a = lib.save(name: "A", url: "https://a/#1", app: "a", at: t0)
        lib.save(name: "B", url: "https://a/#1", app: "a", at: t0 + 1)
        XCTAssertEqual(lib.saved.map(\.name), ["B", "A"])
        lib.deleteSaved(id: a.id)
        XCTAssertEqual(lib.saved.map(\.name), ["B"])
    }

    func testJSONModelRoundTrip() throws {
        var lib = Library()
        lib.save(name: "S", url: "https://python.hashbin.page/#x", app: "python", at: t0, id: "id-1")
        lib.addRecent(url: "https://python.hashbin.page/#y", app: "python", at: t0)
        let data = try lib.encoded()
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(json["version"] as? Int, 1)
        let saved = try XCTUnwrap(json["saved"] as? [[String: Any]])
        XCTAssertEqual(saved[0]["savedAt"] as? String, "2027-01-15T08:00:00Z")
        XCTAssertEqual(saved[0]["id"] as? String, "id-1")
        XCTAssertEqual((json["sites"] as? [Any])?.count, 0)
        XCTAssertEqual(try Library(data: data), lib)
    }

    func testDecodesSpecExample() throws {
        let text = """
        { "version": 1,
          "saved":  [{ "id": "u", "name": "n", "url": "https://x/", "app": "python", "savedAt": "2026-11-14T15:00:00Z" }],
          "recent": [{ "url": "https://x/", "app": "python", "visitedAt": "2026-11-14T15:00:00Z" }],
          "sites":  [] }
        """
        let lib = try Library(data: Data(text.utf8))
        XCTAssertEqual(lib.saved.first?.name, "n")
        XCTAssertEqual(lib.recent.count, 1)
    }

    func testStorePersists() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("lib-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let store = LibraryStore(fileURL: url)
        XCTAssertEqual(store.load(), Library())
        var lib = Library()
        lib.save(name: "S", url: "https://x/", app: "python", at: t0)
        try store.saveNow(lib)
        XCTAssertEqual(LibraryStore(fileURL: url).load(), lib)
    }

    func testRemovingRun() {
        let cases: [(String, String)] = [
            ("https://x/?run=0#a", "https://x/#a"),
            ("https://x/?view=code&run=0", "https://x/?view=code"),
            ("https://x/?run=0&view=a+b#c?run=0", "https://x/?view=a+b#c?run=0"),
            ("https://x/?run=0&run=1", "https://x/"),
            ("https://x/?r%75n=0&x=1", "https://x/?x=1"),
            ("https://x/?xrun=1", "https://x/?xrun=1"),
            ("https://x/#a?run=0", "https://x/#a?run=0"),
            ("https://x/?&run=0#y", "https://x/#y"),
            ("https://x/", "https://x/"),
        ]
        for (input, want) in cases { XCTAssertEqual(Links.removingRun(input), want, input) }
        // Round trip with withRunZero.
        XCTAssertEqual(Links.removingRun(Links.withRunZero("https://x/?v=1#f")), "https://x/?v=1#f")
    }
}
