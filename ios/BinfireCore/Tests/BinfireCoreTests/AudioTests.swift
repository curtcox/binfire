import XCTest
@testable import BinfireCore

final class AudioTests: XCTestCase {
    func testPayloads() throws {
        let links = Links(config: .default, registry: try Fixtures.registry())
        let cases = try Fixtures.list(Fixtures.load("audio.json"), "payloads")
        XCTAssertFalse(cases.isEmpty)
        for c in cases {
            let text = c["text"] as! String
            XCTAssertEqual(Audio.audioPayloadOK(text, links: links), c["ok"] as! Bool, text)
        }
        // waveforms are added in M7.
    }
}
