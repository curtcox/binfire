import Foundation
import XCTest
@testable import BinfireCore

/// Reads `shared/fixtures/*.json` straight from the repo (never copied).
enum Fixtures {
    /// The repository root, found from this file's path:
    /// <root>/ios/BinfireCore/Tests/BinfireCoreTests/Fixtures.swift
    static let repoRoot: URL = {
        var u = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { u.deleteLastPathComponent() }
        return u
    }()

    static func load(_ name: String) throws -> [String: Any] {
        let url = repoRoot.appendingPathComponent("shared/fixtures/\(name)")
        let data = try Data(contentsOf: url)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    /// The fixture parsed with BinfireCore's own JSON parser, which (unlike
    /// Foundation bridging) keeps a leading U+FEFF inside string values.
    static func loadValue(_ name: String) throws -> JSONValue {
        try JSONValue.parse(Data(contentsOf: repoRoot.appendingPathComponent("shared/fixtures/\(name)")))
    }

    static func list(_ fixture: [String: Any], _ key: String) throws -> [[String: Any]] {
        try XCTUnwrap(fixture[key] as? [[String: Any]], "missing list \(key)")
    }

    /// Bytes given as `"text"` (UTF-8) or `"b64"` (base64url).
    static func bytes(_ c: [String: Any], text: String = "text", b64: String = "b64") throws -> Data {
        if let t = c[text] as? String { return Data(t.utf8) }
        let b = try XCTUnwrap(c[b64] as? String)
        return try XCTUnwrap(Base64URL.decode(b), "bad base64url \(b)")
    }

    static func b64(_ s: Any?) throws -> Data {
        try XCTUnwrap(Base64URL.decode(try XCTUnwrap(s as? String)))
    }

    static func registry() throws -> Registry {
        try Registry.load(contentsOf: repoRoot.appendingPathComponent("shared/registry/apps.json"))
    }

    /// Runs `body` and returns the thrown BinfireError code, or nil.
    static func errorCode<T>(_ body: () throws -> T) -> String? {
        do { _ = try body(); return nil } catch let e as BinfireError { return e.code } catch { return "unexpected \(error)" }
    }
}
