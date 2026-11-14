import XCTest
@testable import BinfireCore

final class EnvelopeTests: XCTestCase {
    func testCases() throws {
        let registry = try Fixtures.registry()
        let cases = try Fixtures.list(Fixtures.load("envelope.json"), "cases")
        XCTAssertFalse(cases.isEmpty)
        for c in cases {
            let type = Envelope.documentType(try Fixtures.bytes(c))
            XCTAssertEqual(type, c["documentType"] as? String, "\(c)")
            let apps = type.map { Envelope.appsForDocumentType($0, in: registry).map(\.slug) } ?? []
            XCTAssertEqual(apps, c["apps"] as? [String], "\(c)")
        }
    }
}
