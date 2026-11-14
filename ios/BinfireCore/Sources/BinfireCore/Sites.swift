import CryptoKit
import Foundation

/// One file of a packaged site manifest.
public struct SiteFile: Equatable, Sendable {
    public var cid: String
    /// Served as `Content-Type`.
    public var type: String
    public var size: Int
}

/// A validated packaged-site manifest (`spec/site-manifest.md`).
public struct SiteManifest: Equatable, Sendable {
    public var name: String
    /// A key of `files`.
    public var entry: String
    /// Paths in manifest order.
    public var paths: [String]
    public var files: [String: SiteFile]
    /// Optional, display-only.
    public var source: JSONObject?

    /// The sum of all file sizes.
    public var totalSize: Int { files.values.reduce(0) { $0 + $1.size } }
}

/// Packaged static sites: manifest validation, paths and site IDs.
public enum Sites {
    /// Manifests larger than this are rejected before parsing.
    public static let maxManifestBytes = 1 << 20

    /// Validates manifest bytes in the order `spec/site-manifest.md` lists,
    /// throwing the first failing check's code.
    public static func validateManifest(_ bytes: Data, limits: BinfireLimits) throws -> SiteManifest {
        // 1.
        guard bytes.count <= maxManifestBytes, let text = decodeUTF8Strict(bytes),
              let root = try? JSONValue.parse(Data(text.utf8)), case .object(let o) = root
        else { throw BinfireError.badManifest }
        // 2.
        guard o["format"] == .string("binfire-site"), o["version"] == .number(1) else { throw BinfireError.badManifest }
        // 3.
        guard case .string(let name)? = o["name"], !name.isEmpty, name.unicodeScalars.count <= 200 else { throw BinfireError.badManifest }
        // 4.
        guard case .object(let filesObject)? = o["files"], filesObject.count > 0,
              filesObject.count <= limits.maxSiteFiles else { throw BinfireError.tooManyFiles }
        let paths = filesObject.keys
        // 5.
        for p in paths where !isValidPath(p) { throw BinfireError.badPath }
        var lowered = Set<String>()
        for p in paths where !lowered.insert(asciiLowercased(p)).inserted { throw BinfireError.duplicatePath }
        // 6.
        var files: [String: SiteFile] = [:]
        var total = 0
        for p in paths {
            guard case .object(let f)? = filesObject[p], case .string(let cid)? = f["cid"], CID.isCID(cid),
                  let declared = CID.cidLength(cid) else { throw BinfireError.invalidCID }
            guard case .string(let type)? = f["type"], isValidType(type) else { throw BinfireError.badManifest }
            guard let size = f["size"]?.integerValue, size == declared else { throw BinfireError.sizeMismatch }
            guard size <= limits.maxSiteFileBytes else { throw BinfireError.tooLarge }
            files[p] = SiteFile(cid: cid, type: type, size: size)
            total += size
        }
        // 7.
        guard total <= limits.maxSiteTotalBytes else { throw BinfireError.tooLarge }
        // 8.
        guard case .string(let entry)? = o["entry"], files[entry] != nil else { throw BinfireError.missingEntry }
        // 9.
        var source: JSONObject? = nil
        if let s = o["source"] {
            guard case .object(let so) = s else { throw BinfireError.badManifest }
            source = so
        }
        return SiteManifest(name: name, entry: entry, paths: paths, files: files, source: source)
    }

    /// A valid site path: 1-1024 UTF-8 bytes, no leading or trailing `/`,
    /// segments of 1-255 bytes that are not `.` or `..` and contain no `\`,
    /// `:`, `?`, `#` or control characters (U+0000-U+001F, U+007F).
    public static func isValidPath(_ path: String) -> Bool {
        let u = Array(path.utf8)
        guard (1...1024).contains(u.count), u.first != UInt8(ascii: "/"), u.last != UInt8(ascii: "/") else { return false }
        for seg in u.split(separator: UInt8(ascii: "/"), omittingEmptySubsequences: false) {
            guard (1...255).contains(seg.count) else { return false }
            if seg.elementsEqual([0x2E]) || seg.elementsEqual([0x2E, 0x2E]) { return false }
            for c in seg {
                if c < 0x20 || c == 0x7F || c == UInt8(ascii: "\\") || c == UInt8(ascii: ":")
                    || c == UInt8(ascii: "?") || c == UInt8(ascii: "#") { return false }
            }
        }
        return true
    }

    /// `lowercase(base32(SHA-256(ascii(manifestCID))))`, RFC 4648 base32
    /// without padding: always 52 characters.
    public static func siteId(_ manifestCID: String) -> String {
        base32Lower(Array(SHA256.hash(data: Data(manifestCID.utf8))))
    }

    static func base32Lower(_ bytes: [UInt8]) -> String {
        let alphabet = Array("abcdefghijklmnopqrstuvwxyz234567".utf8)
        var out: [UInt8] = []
        var value: UInt32 = 0
        var bits = 0
        for b in bytes {
            value = (value << 8) | UInt32(b)
            bits += 8
            while bits >= 5 {
                out.append(alphabet[Int((value >> UInt32(bits - 5)) & 31)])
                bits -= 5
            }
            value &= (1 << UInt32(bits)) - 1
        }
        if bits > 0 { out.append(alphabet[Int((value << UInt32(5 - bits)) & 31)]) }
        return String(decoding: out, as: UTF8.self)
    }

    private static func isValidType(_ type: String) -> Bool {
        guard !type.isEmpty, type.unicodeScalars.count <= 100 else { return false }
        return !type.unicodeScalars.contains { $0.value <= 0x20 || $0.value == 0x7F }
    }

    private static func asciiLowercased(_ s: String) -> String {
        String(decoding: s.utf8.map { (0x41...0x5A).contains($0) ? $0 + 32 : $0 }, as: UTF8.self)
    }
}
