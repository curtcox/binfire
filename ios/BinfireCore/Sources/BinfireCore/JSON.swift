import Foundation

/// A JSON object that keeps key order (first occurrence) like a JavaScript
/// object. Duplicate keys keep the last value, as `JSON.parse` does.
public struct JSONObject: Equatable, Sendable {
    public private(set) var keys: [String] = []
    private var values: [String: JSONValue] = [:]

    public init() {}

    public init(_ pairs: [(String, JSONValue)]) {
        for (k, v) in pairs { self[k] = v }
    }

    public var count: Int { keys.count }

    public subscript(key: String) -> JSONValue? {
        get { values[key] }
        set {
            if let newValue {
                if values.updateValue(newValue, forKey: key) == nil { keys.append(key) }
            } else if values.removeValue(forKey: key) != nil {
                keys.removeAll { $0 == key }
            }
        }
    }
}

/// A parsed JSON value with JavaScript `JSON.parse` semantics (numbers are
/// doubles, booleans are distinct from numbers).
public indirect enum JSONValue: Equatable, Sendable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSONValue])
    case object(JSONObject)

    /// The string payload, or nil.
    public var stringValue: String? {
        if case .string(let s) = self { return s }
        return nil
    }

    /// The value as an integer when it is a JSON number that `Number.isInteger` accepts.
    public var integerValue: Int? {
        guard case .number(let d) = self, d.isFinite, d.rounded(.towardZero) == d,
              abs(d) <= 9_007_199_254_740_992 else { return nil }
        return Int(d)
    }

    /// Parses UTF-8 JSON text. A leading byte-order mark is skipped (as
    /// `TextDecoder` does). Invalid UTF-8 or invalid JSON throws.
    public static func parse(_ data: Data, maxDepth: Int = 256) throws -> JSONValue {
        var bytes = [UInt8](data)
        guard String(decoding: bytes, as: UTF8.self).utf8.elementsEqual(bytes) else { throw JSONParseError() }
        if bytes.starts(with: [0xEF, 0xBB, 0xBF]) { bytes.removeFirst(3) }
        var parser = JSONParser(bytes: bytes, maxDepth: maxDepth)
        return try parser.parseDocument()
    }

    /// Serializes like `JSON.stringify` (no whitespace, keys in order).
    public func serialized() -> String {
        var out = ""
        write(into: &out)
        return out
    }

    private func write(into out: inout String) {
        switch self {
        case .null: out += "null"
        case .bool(let b): out += b ? "true" : "false"
        case .number(let d):
            if !d.isFinite { out += "null" }
            else if d.rounded(.towardZero) == d, abs(d) < 1e21 { out += String(Int64(d)) }
            else { out += String(d) }
        case .string(let s): JSONValue.writeString(s, into: &out)
        case .array(let a):
            out += "["
            for (i, v) in a.enumerated() {
                if i > 0 { out += "," }
                v.write(into: &out)
            }
            out += "]"
        case .object(let o):
            out += "{"
            for (i, k) in o.keys.enumerated() {
                if i > 0 { out += "," }
                JSONValue.writeString(k, into: &out)
                out += ":"
                o[k]!.write(into: &out)
            }
            out += "}"
        }
    }

    private static func writeString(_ s: String, into out: inout String) {
        out += "\""
        for u in s.unicodeScalars {
            switch u {
            case "\"": out += "\\\""
            case "\\": out += "\\\\"
            case "\u{08}": out += "\\b"
            case "\u{0C}": out += "\\f"
            case "\n": out += "\\n"
            case "\r": out += "\\r"
            case "\t": out += "\\t"
            default:
                if u.value < 0x20 {
                    out += "\\u00" + (u.value < 0x10 ? "0" : "") + String(u.value, radix: 16)
                } else {
                    out.unicodeScalars.append(u)
                }
            }
        }
        out += "\""
    }
}

struct JSONParseError: Error {}

private struct JSONParser {
    let bytes: [UInt8]
    let maxDepth: Int
    var i = 0

    init(bytes: [UInt8], maxDepth: Int) {
        self.bytes = bytes
        self.maxDepth = maxDepth
    }

    mutating func parseDocument() throws -> JSONValue {
        skipWhitespace()
        let v = try parseValue(depth: 0)
        skipWhitespace()
        guard i == bytes.count else { throw JSONParseError() }
        return v
    }

    mutating func skipWhitespace() {
        while i < bytes.count, [0x20, 0x09, 0x0A, 0x0D].contains(bytes[i]) { i += 1 }
    }

    mutating func expect(_ literal: String) throws {
        for b in literal.utf8 {
            guard i < bytes.count, bytes[i] == b else { throw JSONParseError() }
            i += 1
        }
    }

    mutating func parseValue(depth: Int) throws -> JSONValue {
        guard depth <= maxDepth, i < bytes.count else { throw JSONParseError() }
        switch bytes[i] {
        case UInt8(ascii: "{"):
            i += 1
            var obj = JSONObject()
            skipWhitespace()
            if i < bytes.count, bytes[i] == UInt8(ascii: "}") { i += 1; return .object(obj) }
            while true {
                skipWhitespace()
                guard i < bytes.count, bytes[i] == UInt8(ascii: "\"") else { throw JSONParseError() }
                let key = try parseString()
                skipWhitespace()
                try expect(":")
                skipWhitespace()
                obj[key] = try parseValue(depth: depth + 1)
                skipWhitespace()
                guard i < bytes.count else { throw JSONParseError() }
                if bytes[i] == UInt8(ascii: ",") { i += 1; continue }
                if bytes[i] == UInt8(ascii: "}") { i += 1; return .object(obj) }
                throw JSONParseError()
            }
        case UInt8(ascii: "["):
            i += 1
            var arr: [JSONValue] = []
            skipWhitespace()
            if i < bytes.count, bytes[i] == UInt8(ascii: "]") { i += 1; return .array(arr) }
            while true {
                skipWhitespace()
                arr.append(try parseValue(depth: depth + 1))
                skipWhitespace()
                guard i < bytes.count else { throw JSONParseError() }
                if bytes[i] == UInt8(ascii: ",") { i += 1; continue }
                if bytes[i] == UInt8(ascii: "]") { i += 1; return .array(arr) }
                throw JSONParseError()
            }
        case UInt8(ascii: "\""):
            return .string(try parseString())
        case UInt8(ascii: "t"): try expect("true"); return .bool(true)
        case UInt8(ascii: "f"): try expect("false"); return .bool(false)
        case UInt8(ascii: "n"): try expect("null"); return .null
        default:
            return .number(try parseNumber())
        }
    }

    mutating func parseNumber() throws -> Double {
        let start = i
        func digits() -> Int {
            let s = i
            while i < bytes.count, bytes[i] >= 0x30, bytes[i] <= 0x39 { i += 1 }
            return i - s
        }
        if i < bytes.count, bytes[i] == UInt8(ascii: "-") { i += 1 }
        guard i < bytes.count else { throw JSONParseError() }
        if bytes[i] == UInt8(ascii: "0") { i += 1 } else if digits() == 0 { throw JSONParseError() }
        if i < bytes.count, bytes[i] == UInt8(ascii: ".") {
            i += 1
            guard digits() > 0 else { throw JSONParseError() }
        }
        if i < bytes.count, bytes[i] == UInt8(ascii: "e") || bytes[i] == UInt8(ascii: "E") {
            i += 1
            if i < bytes.count, bytes[i] == UInt8(ascii: "+") || bytes[i] == UInt8(ascii: "-") { i += 1 }
            guard digits() > 0 else { throw JSONParseError() }
        }
        guard let d = Double(String(decoding: bytes[start..<i], as: UTF8.self)) else { throw JSONParseError() }
        return d
    }

    mutating func parseHex4() throws -> UInt32 {
        guard i + 4 <= bytes.count else { throw JSONParseError() }
        var v: UInt32 = 0
        for _ in 0..<4 {
            let b = bytes[i]
            let d: UInt32
            switch b {
            case 0x30...0x39: d = UInt32(b - 0x30)
            case 0x41...0x46: d = UInt32(b - 0x41 + 10)
            case 0x61...0x66: d = UInt32(b - 0x61 + 10)
            default: throw JSONParseError()
            }
            v = v << 4 | d
            i += 1
        }
        return v
    }

    mutating func parseString() throws -> String {
        i += 1 // opening quote
        var out: [UInt8] = []
        var scalars = ""
        func flush() {
            if !out.isEmpty { scalars += String(decoding: out, as: UTF8.self); out.removeAll() }
        }
        while true {
            guard i < bytes.count else { throw JSONParseError() }
            let b = bytes[i]
            if b == UInt8(ascii: "\"") { i += 1; break }
            if b < 0x20 { throw JSONParseError() }
            if b != UInt8(ascii: "\\") { out.append(b); i += 1; continue }
            i += 1
            guard i < bytes.count else { throw JSONParseError() }
            let e = bytes[i]
            i += 1
            switch e {
            case UInt8(ascii: "\""): out.append(0x22)
            case UInt8(ascii: "\\"): out.append(0x5C)
            case UInt8(ascii: "/"): out.append(0x2F)
            case UInt8(ascii: "b"): out.append(0x08)
            case UInt8(ascii: "f"): out.append(0x0C)
            case UInt8(ascii: "n"): out.append(0x0A)
            case UInt8(ascii: "r"): out.append(0x0D)
            case UInt8(ascii: "t"): out.append(0x09)
            case UInt8(ascii: "u"):
                var v = try parseHex4()
                if (0xD800...0xDBFF).contains(v), i + 6 <= bytes.count,
                   bytes[i] == UInt8(ascii: "\\"), bytes[i + 1] == UInt8(ascii: "u") {
                    let save = i
                    i += 2
                    let lo = try parseHex4()
                    if (0xDC00...0xDFFF).contains(lo) {
                        v = 0x10000 + ((v - 0xD800) << 10) + (lo - 0xDC00)
                    } else {
                        i = save
                    }
                }
                // Lone surrogates cannot live in a Swift String; they become U+FFFD.
                let scalar = Unicode.Scalar(v) ?? "\u{FFFD}"
                out.append(contentsOf: Array(String(Character(scalar)).utf8))
            default:
                throw JSONParseError()
            }
        }
        flush()
        return scalars
    }
}

/// Decodes bytes as strict UTF-8 (no replacement), dropping one leading BOM
/// like `new TextDecoder('utf-8', { fatal: true })`. Returns nil if invalid.
func decodeUTF8Strict(_ data: Data) -> String? {
    let s = String(decoding: data, as: UTF8.self)
    guard s.utf8.elementsEqual(data) else { return nil }
    if s.unicodeScalars.first == "\u{FEFF}" { return String(s.unicodeScalars.dropFirst()) }
    return s
}
