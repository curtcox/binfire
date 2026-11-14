import Foundation

/// RFC 4648 section 5 base64url without padding, with the strict decoder from
/// `spec/README.md`.
public enum Base64URL {
    private static let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_".utf8)
    private static let lookup: [Int8] = {
        var t = [Int8](repeating: -1, count: 256)
        for (i, c) in alphabet.enumerated() { t[Int(c)] = Int8(i) }
        return t
    }()

    /// Encodes bytes without padding.
    public static func encode<B: Sequence>(_ bytes: B) -> String where B.Element == UInt8 {
        let b = Array(bytes)
        var out = [UInt8]()
        out.reserveCapacity((b.count * 4 + 2) / 3)
        var i = 0
        while i + 3 <= b.count {
            let n = UInt32(b[i]) << 16 | UInt32(b[i + 1]) << 8 | UInt32(b[i + 2])
            out.append(alphabet[Int(n >> 18 & 63)])
            out.append(alphabet[Int(n >> 12 & 63)])
            out.append(alphabet[Int(n >> 6 & 63)])
            out.append(alphabet[Int(n & 63)])
            i += 3
        }
        let rest = b.count - i
        if rest == 1 {
            let n = UInt32(b[i]) << 16
            out.append(alphabet[Int(n >> 18 & 63)])
            out.append(alphabet[Int(n >> 12 & 63)])
        } else if rest == 2 {
            let n = UInt32(b[i]) << 16 | UInt32(b[i + 1]) << 8
            out.append(alphabet[Int(n >> 18 & 63)])
            out.append(alphabet[Int(n >> 12 & 63)])
            out.append(alphabet[Int(n >> 6 & 63)])
        }
        return String(decoding: out, as: UTF8.self)
    }

    /// Strictly decodes base64url: rejects padding, characters outside the
    /// alphabet, `len % 4 == 1`, and non-canonical trailing bits. Returns nil
    /// when the text is not canonical base64url.
    public static func decode<S: StringProtocol>(_ text: S) -> Data? {
        let chars = Array(text.utf8)
        if chars.count % 4 == 1 { return nil }
        var out = Data()
        out.reserveCapacity(chars.count * 3 / 4)
        var acc: UInt32 = 0
        var bits = 0
        for c in chars {
            let v = lookup[Int(c)]
            if v < 0 { return nil }
            acc = acc << 6 | UInt32(v)
            bits += 6
            if bits >= 8 {
                bits -= 8
                out.append(UInt8(acc >> UInt32(bits) & 0xFF))
                acc &= (1 << UInt32(bits)) - 1
            }
        }
        // Leftover bits must be zero (canonical encoding).
        if bits > 0 && acc != 0 { return nil }
        return out
    }
}

extension Data {
    /// Lowercase hex string.
    var hexString: String { map { String(format: "%02x", $0) }.joined() }

    /// Parses a hex string (even length, 0-9a-fA-F). Returns nil if invalid.
    init?(hex: String) {
        let chars = Array(hex.utf8)
        guard chars.count % 2 == 0 else { return nil }
        var out = Data(capacity: chars.count / 2)
        func nibble(_ c: UInt8) -> UInt8? {
            switch c {
            case 0x30...0x39: return c - 0x30
            case 0x41...0x46: return c - 0x41 + 10
            case 0x61...0x66: return c - 0x61 + 10
            default: return nil
            }
        }
        var i = 0
        while i < chars.count {
            guard let h = nibble(chars[i]), let l = nibble(chars[i + 1]) else { return nil }
            out.append(h << 4 | l)
            i += 2
        }
        self = out
    }
}
