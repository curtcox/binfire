import Foundation

/// A minimal, non-normalizing URL splitter.
///
/// Platform URL types normalize escapes differently across ports, so binfire
/// splits URL strings itself (`spec/links.md` "raw query / raw fragment") and
/// never rebuilds a target from parsed components.
public struct URLParts: Equatable, Sendable {
    /// Lowercased scheme without `:`.
    public var scheme: String
    /// True when the URL has an authority (`scheme://...`).
    public var hasAuthority: Bool
    /// Userinfo before `@`, or nil.
    public var userinfo: String?
    /// Host exactly as written (not lowercased).
    public var host: String
    /// Port digits as written, or nil.
    public var port: String?
    /// Path exactly as written (may be empty).
    public var path: String
    /// Raw query: after the first `?` and before the first `#`, or nil.
    public var query: String?
    /// Raw fragment: after the first `#`, or nil.
    public var fragment: String?

    static let specialSchemes: Set<String> = ["http", "https", "ws", "wss", "ftp", "file"]

    /// Splits `text`. Returns nil when it has no valid scheme, or when it is
    /// not an absolute URL by a conservative reading of the WHATWG URL rules
    /// (a special scheme needs a non-empty host, ports are numeric, and the
    /// scheme and authority contain no spaces or control characters).
    public init?(_ text: String) {
        let chars = Array(text.unicodeScalars)
        guard let colon = chars.firstIndex(of: ":"), colon > 0 else { return nil }
        let schemeScalars = chars[..<colon]
        guard URLParts.isAlpha(schemeScalars.first!),
              schemeScalars.allSatisfy({ URLParts.isAlpha($0) || ("0"..."9").contains($0) || $0 == "+" || $0 == "-" || $0 == "." })
        else { return nil }
        scheme = String(String.UnicodeScalarView(schemeScalars)).lowercased()
        var rest = String(String.UnicodeScalarView(chars[(colon + 1)...]))
        // Tabs and newlines would be silently removed by WHATWG parsers; refuse them.
        if rest.unicodeScalars.contains(where: { $0 == "\t" || $0 == "\n" || $0 == "\r" }) { return nil }

        let split = URLParts.splitQueryAndFragment(rest)
        rest = split.beforeQuery
        query = split.query
        fragment = split.fragment

        let special = URLParts.specialSchemes.contains(scheme)
        if special { rest = rest.replacingOccurrences(of: "\\", with: "/") }
        if rest.hasPrefix("//") {
            hasAuthority = true
            let afterSlashes = rest.dropFirst(2)
            let authorityEnd = afterSlashes.firstIndex(of: "/") ?? afterSlashes.endIndex
            var authority = String(afterSlashes[..<authorityEnd])
            path = String(afterSlashes[authorityEnd...])
            if let at = authority.lastIndex(of: "@") {
                userinfo = String(authority[..<at])
                authority = String(authority[authority.index(after: at)...])
            } else {
                userinfo = nil
            }
            if authority.hasPrefix("["), let close = authority.firstIndex(of: "]") {
                host = String(authority[...close])
                let after = authority[authority.index(after: close)...]
                if after.isEmpty { port = nil }
                else if after.hasPrefix(":") { port = String(after.dropFirst()) }
                else { return nil }
            } else if let c = authority.lastIndex(of: ":") {
                host = String(authority[..<c])
                port = String(authority[authority.index(after: c)...])
            } else {
                host = authority
                port = nil
            }
            if let p = port {
                if p.isEmpty { port = nil }
                else if !p.allSatisfy({ $0.isASCII && $0.isNumber }) || p.count > 5 || Int(p)! > 65535 { return nil }
            }
            let forbidden: Set<Unicode.Scalar> = [" ", "#", "/", ":", "<", ">", "?", "@", "\\", "^", "|", "%", "[", "]"]
            if !host.hasPrefix("[") {
                for s in host.unicodeScalars where s.value < 0x21 || s.value == 0x7F || forbidden.contains(s) { return nil }
            }
            if special && scheme != "file" && host.isEmpty { return nil }
        } else {
            if special && scheme != "file" { return nil }
            hasAuthority = false
            userinfo = nil
            host = ""
            port = nil
            path = rest
        }
    }

    private static func isAlpha(_ s: Unicode.Scalar) -> Bool {
        ("a"..."z").contains(s) || ("A"..."Z").contains(s)
    }

    /// Splits the raw query and raw fragment out of `text` (`spec/links.md`).
    static func splitQueryAndFragment(_ text: String) -> (beforeQuery: String, query: String?, fragment: String?) {
        var head = Substring(text)
        var fragment: String? = nil
        if let hash = head.firstIndex(of: "#") {
            fragment = String(head[head.index(after: hash)...])
            head = head[..<hash]
        }
        var query: String? = nil
        if let q = head.firstIndex(of: "?") {
            query = String(head[head.index(after: q)...])
            head = head[..<q]
        }
        return (String(head), query, fragment)
    }

    /// The raw query of any string: after the first `?`, before the first `#`.
    public static func rawQuery(_ text: String) -> String? { splitQueryAndFragment(text).query }

    /// The raw fragment of any string: after the first `#`.
    public static func rawFragment(_ text: String) -> String? { splitQueryAndFragment(text).fragment }

    /// Lowercased host (ASCII), for case-insensitive comparison.
    public var normalizedHost: String { host.lowercased() }

    /// The port with the scheme's default port removed (nil means default).
    public var normalizedPort: String? {
        guard let p = port, let n = Int(p) else { return nil }
        switch (scheme, n) {
        case ("https", 443), ("http", 80), ("wss", 443), ("ws", 80), ("ftp", 21): return nil
        default: return String(n)
        }
    }

    /// The path as a WHATWG parser would see it for comparison: empty becomes
    /// `/` for special schemes, and `.`/`..` segments are resolved.
    public var normalizedPath: String {
        let special = URLParts.specialSchemes.contains(scheme)
        if path.isEmpty { return special && hasAuthority ? "/" : "" }
        guard path.hasPrefix("/") else { return path }
        let segments = path.dropFirst().split(separator: "/", omittingEmptySubsequences: false)
        var out: [Substring] = []
        for (i, seg) in segments.enumerated() {
            let last = i == segments.count - 1
            let lower = seg.lowercased()
            if lower == ".." || lower == ".%2e" || lower == "%2e." || lower == "%2e%2e" {
                if !out.isEmpty { out.removeLast() }
                if last { out.append("") }
            } else if lower == "." || lower == "%2e" {
                if last { out.append("") }
            } else {
                out.append(seg)
            }
        }
        return "/" + out.joined(separator: "/")
    }
}

/// `URLSearchParams`-style parsing of a raw query string: split on `&`, split
/// each pair on the first `=`, turn `+` into a space, then percent-decode as
/// UTF-8 (invalid escapes are kept, invalid UTF-8 becomes U+FFFD).
public struct QueryParams: Sendable {
    public private(set) var pairs: [(name: String, value: String)] = []

    /// Parses `query`. A single leading `?` is dropped, as the
    /// `URLSearchParams` constructor does.
    public init(_ query: String?) {
        guard var q = query else { return }
        if q.hasPrefix("?") { q.removeFirst() }
        for part in q.split(separator: "&", omittingEmptySubsequences: true) {
            if let eq = part.firstIndex(of: "=") {
                pairs.append((QueryParams.decode(part[..<eq]), QueryParams.decode(part[part.index(after: eq)...])))
            } else {
                pairs.append((QueryParams.decode(part), ""))
            }
        }
    }

    /// The first value for `name`, like `URLSearchParams.get`.
    public func get(_ name: String) -> String? { pairs.first { $0.name == name }?.value }

    /// True when `name` is present, like `URLSearchParams.has`.
    public func has(_ name: String) -> Bool { pairs.contains { $0.name == name } }

    /// `+` → space, then percent-decode as UTF-8.
    public static func decode<S: StringProtocol>(_ text: S) -> String {
        let bytes = Array(text.utf8)
        var out: [UInt8] = []
        out.reserveCapacity(bytes.count)
        var i = 0
        func hex(_ c: UInt8) -> UInt8? {
            switch c {
            case 0x30...0x39: return c - 0x30
            case 0x41...0x46: return c - 0x41 + 10
            case 0x61...0x66: return c - 0x61 + 10
            default: return nil
            }
        }
        while i < bytes.count {
            let b = bytes[i]
            if b == UInt8(ascii: "+") {
                out.append(0x20)
            } else if b == UInt8(ascii: "%"), i + 2 < bytes.count, let h = hex(bytes[i + 1]), let l = hex(bytes[i + 2]) {
                out.append(h << 4 | l)
                i += 2
            } else {
                out.append(b)
            }
            i += 1
        }
        return String(decoding: out, as: UTF8.self)
    }
}
