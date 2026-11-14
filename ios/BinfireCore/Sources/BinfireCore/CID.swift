import CryptoKit
import Foundation

/// 256t content identifiers (`spec/cid.md`).
public enum CID {
    /// The largest length a CID can declare: 2^48 - 1.
    public static let maxLength: Int = (1 << 48) - 1

    /// Computes the CID of `bytes`: base64url(uint48 length) + inline bytes
    /// (when length <= 64) or base64url(SHA-512(bytes)).
    public static func computeCID(_ bytes: Data) -> String {
        let n = UInt64(bytes.count)
        var prefix = [UInt8](repeating: 0, count: 6)
        for i in 0..<6 { prefix[i] = UInt8(truncatingIfNeeded: n >> UInt64(8 * (5 - i))) }
        let suffix: [UInt8] = bytes.count <= 64 ? Array(bytes) : Array(SHA512.hash(data: bytes))
        return Base64URL.encode(prefix) + Base64URL.encode(suffix)
    }

    /// The content length a CID declares in its 8-character prefix, or nil if
    /// the prefix is missing or not base64url.
    public static func cidLength(_ cid: String) -> Int? {
        let utf8 = Array(cid.utf8)
        guard utf8.count >= 8, let prefix = Base64URL.decode(String(decoding: utf8[0..<8], as: UTF8.self)),
              prefix.count == 6 else { return nil }
        return prefix.reduce(0) { $0 << 8 | Int($1) }
    }

    /// True when the CID carries its content inline (declared length <= 64).
    public static func isInline(_ cid: String) -> Bool {
        guard let n = cidLength(cid) else { return false }
        return n <= 64
    }

    /// Validates a CID exactly as `spec/cid.md` "Validation" describes.
    /// A leading `#` is not stripped.
    public static func isCID(_ cid: String) -> Bool {
        let utf8 = Array(cid.utf8)
        guard (8...94).contains(utf8.count) else { return false }
        for c in utf8 {
            switch c {
            case UInt8(ascii: "A")...UInt8(ascii: "Z"), UInt8(ascii: "a")...UInt8(ascii: "z"),
                 UInt8(ascii: "0")...UInt8(ascii: "9"), UInt8(ascii: "-"), UInt8(ascii: "_"): continue
            default: return false
            }
        }
        guard let n = cidLength(cid), n <= maxLength,
              let suffix = Base64URL.decode(String(decoding: utf8[8...], as: UTF8.self)) else { return false }
        if n <= 64 {
            return utf8.count == 8 + (4 * n + 2) / 3 && suffix.count == n
        }
        return utf8.count == 94 && suffix.count == 64
    }

    /// The inline content of an inline CID, or nil for hashed or invalid CIDs.
    public static func inlineContent(_ cid: String) -> Data? {
        guard isCID(cid), let n = cidLength(cid), n <= 64 else { return nil }
        return Base64URL.decode(String(cid.utf8.dropFirst(8))!)
    }

    /// True when `computeCID(bytes) == cid`. Returns false early when the byte
    /// count differs from the declared length, so nothing large is hashed.
    public static func verify(_ cid: String, _ bytes: Data) -> Bool {
        guard let n = cidLength(cid), n == bytes.count else { return false }
        return computeCID(bytes) == cid
    }
}
