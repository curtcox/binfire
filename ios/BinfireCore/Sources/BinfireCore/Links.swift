import Foundation

/// Where `route` sends a piece of text (`spec/links.md` "route").
public enum Route: Equatable, Sendable {
    /// Load `url` in the app's WebView. `state`, `run`, `view` come from `classifyState(url)`.
    case openApp(app: String, url: String, state: StateKind, run: Bool, view: String?)
    /// Fetch and verify `cid`; `app` is a slug hint or nil.
    case loadCID(cid: String, app: String?)
    /// Load a site manifest by CID.
    case openSite(cid: String)
    /// Not something binfire opens: show it with Open in browser / Copy. Never auto-navigate.
    case showText(String)
    /// A malformed binfire link.
    case error(BinfireError)

    /// The spec's `action` string: `open-app`, `load-cid`, `open-site`, `show-text` or `error`.
    public var action: String {
        switch self {
        case .openApp: return "open-app"
        case .loadCID: return "load-cid"
        case .openSite: return "open-site"
        case .showText: return "show-text"
        case .error: return "error"
        }
    }
}

/// Link building and routing for one configuration and registry.
public struct Links: Sendable {
    public let config: BinfireConfig
    public let registry: Registry

    public init(config: BinfireConfig, registry: Registry) {
        self.config = config
        self.registry = registry
    }

    /// How `route` recognised its input; used by `Audio.audioPayloadOK`.
    enum Source: Equatable {
        case bareCID
        case httpsAppLink // https://D/a/...
        case httpsLink    // other https://D/... links
        case schemeLink  // S://...
        case contentHost
        case appURL
        case other
    }

    // MARK: route

    /// Routes any input text (paste, share, scan, audio, transfer `url`).
    public func route(_ text: String) -> Route { routeWithSource(text).route }

    /// `route` for shared or pasted text: if plain routing only gives
    /// `show-text`, look for the first link or CID token inside the text.
    public func routeShared(_ text: String) -> Route { routeShared(text, allowShare: true) }

    private func routeShared(_ text: String, allowShare: Bool) -> Route {
        let whole = routeWithSource(text, allowShare: allowShare).route
        guard case .showText = whole else { return whole }
        let scheme = config.scheme.lowercased() + "://"
        let ws: Set<Character> = [" ", "\t", "\n", "\r", "\u{0C}", "\r\n"]
        for raw in text.split(whereSeparator: { ws.contains($0) }) {
            let token = Links.stripSharedToken(String(raw))
            let lower = token.lowercased()
            let bare = token.hasPrefix("#") ? String(token.dropFirst()) : token
            guard lower.hasPrefix("https://") || lower.hasPrefix("http://") || lower.hasPrefix(scheme)
                    || CID.isCID(bare) else { continue }
            let r = routeWithSource(token, allowShare: allowShare).route
            if case .showText = r { continue }
            return r
        }
        return .showText(Links.trimASCIIWhitespace(text))
    }

    /// Strips wrapping punctuation from a shared-text token (`spec/links.md`
    /// "routeShared" step 2), keeping balanced closing brackets.
    static func stripSharedToken(_ token: String) -> String {
        let leading: Set<Character> = ["<", "(", "[", "{", "\"", "'"]
        let trailing: Set<Character> = [">", ".", ",", ";", ":", "!", "?", "\"", "'"]
        let pairs: [Character: Character] = [")": "(", "]": "[", "}": "{"]
        var t = Substring(token)
        while let f = t.first, leading.contains(f) { t = t.dropFirst() }
        var changed = true
        while changed {
            changed = false
            while let l = t.last, trailing.contains(l) { t = t.dropLast(); changed = true }
            if let l = t.last, let open = pairs[l] {
                let closes = t.filter { $0 == l }.count
                let opens = t.filter { $0 == open }.count
                if closes > opens { t = t.dropLast(); changed = true }
            }
        }
        return String(t)
    }

    func routeWithSource(_ text: String, allowShare: Bool = true) -> (route: Route, source: Source) {
        // Bound before anything else (before trimming or scanning).
        if text.utf8.count > config.limits.maxStateBytes + 4096 { return (.error(.tooLarge), .other) }
        let input = Links.trimASCIIWhitespace(text)
        // Control characters (C0 or DEL) anywhere after trimming: never a link.
        if input.utf8.contains(where: { $0 < 0x20 || $0 == 0x7F }) { return (.showText(input), .other) }

        // 1. A bare CID, optionally after a leading '#'.
        let bare = input.hasPrefix("#") ? String(input.dropFirst()) : input
        if CID.isCID(bare) { return (.loadCID(cid: bare, app: nil), .bareCID) }

        // 2. Not an absolute URL.
        guard let url = URLParts(input) else { return (.showText(input), .other) }

        // 3. binfire links.
        let scheme = config.scheme.lowercased()
        if url.scheme == scheme {
            let path = url.hasAuthority ? url.host + url.path : url.path
            return (binfireLink(input, path: path, isScheme: true, allowShare: allowShare), .schemeLink)
        }
        if url.scheme == "https", url.hasAuthority, url.userinfo == nil, url.normalizedPort == nil,
           url.normalizedHost == config.linkDomain.lowercased() {
            let route = binfireLink(input, path: url.normalizedPath, isScheme: false, allowShare: false)
            let isAppLink = url.normalizedPath.split(separator: "/").first == "a"
            return (route, isAppLink ? .httpsAppLink : .httpsLink)
        }

        // 4. https://<content host>/<CID>
        if let content = URLParts(config.contentHost), url.scheme == content.scheme, url.hasAuthority,
           url.userinfo == nil, url.normalizedHost == content.normalizedHost, url.normalizedPort == content.normalizedPort,
           url.path.hasPrefix("/") {
            let segment = String(url.path.dropFirst())
            if !segment.contains("/"), CID.isCID(segment) { return (.loadCID(cid: segment, app: nil), .contentHost) }
        }

        // 5. A registered app URL, unchanged.
        if let app = registry.appForURL(input) { return (openApp(app.slug, input), .appURL) }

        // 6. Anything else.
        return (.showText(input), .other)
    }

    private func openApp(_ slug: String, _ url: String) -> Route {
        let s = URLState.classifyState(url)
        return .openApp(app: slug, url: url, state: s.state, run: s.run, view: s.view)
    }

    private func binfireLink(_ input: String, path rawPath: String, isScheme: Bool, allowShare: Bool) -> Route {
        var path = Substring(rawPath)
        while path.hasPrefix("/") { path = path.dropFirst() }
        while path.hasSuffix("/") { path = path.dropLast() }
        let segments = path.split(separator: "/", omittingEmptySubsequences: false)
        let split = URLParts.splitQueryAndFragment(input)
        switch segments.first {
        case "a" where segments.count == 2:
            guard let app = registry.app(slug: String(segments[1])) else { return .error(.unknownApp) }
            var target = app.canonicalOrigin
            if let q = split.query { target += "?" + q }
            if let f = split.fragment { target += "#" + f }
            return openApp(app.slug, target)
        case "open" where segments.count == 1:
            guard let u = QueryParams(split.fragment).get("u"), URLParts(u) != nil else { return .error(.badLink) }
            if let app = registry.appForURL(u) { return openApp(app.slug, u) }
            return .showText(u)
        case "c" where segments.count == 1:
            guard let cid = split.fragment, CID.isCID(cid) else { return .error(.invalidCID) }
            let hint = QueryParams(split.query).get("app").flatMap { registry.app(slug: $0)?.slug }
            return .loadCID(cid: cid, app: hint)
        case "s" where segments.count == 1:
            guard let cid = split.fragment, CID.isCID(cid) else { return .error(.invalidCID) }
            return .openSite(cid: cid)
        case "share" where segments.count == 1 && isScheme && allowShare:
            // S://share#t=<text>: share extensions hand text to the app. Not recursive.
            guard let t = QueryParams(split.fragment).get("t") else { return .error(.badLink) }
            return routeShared(t, allowShare: false)
        default:
            return .error(.unknownLink)
        }
    }

    // MARK: building links

    /// The https link for a registered app URL: `https://D/a/<slug>?query#fragment`
    /// when the URL is on the canonical origin at exactly the base path, else
    /// `https://D/open#u=<encodeURIComponent(url)>`. Nil if no app matches.
    ///
    /// The short form is used only when the raw query and raw fragment hold
    /// only RFC 3986 query/fragment characters (`isRFC3986QueryOrFragment`).
    public func makeLink(_ url: String) -> String? {
        guard let m = registry.match(url) else { return nil }
        let split = URLParts.splitQueryAndFragment(url)
        if m.isCanonical && m.exactPath && Links.isRFC3986QueryOrFragment(split.query ?? "") && Links.isRFC3986QueryOrFragment(split.fragment ?? "") {
            var link = "https://\(config.linkDomain)/a/\(m.slug)"
            if let q = split.query { link += "?" + q }
            if let f = split.fragment { link += "#" + f }
            return link
        }
        return "https://\(config.linkDomain)/open#u=" + Links.encodeURIComponent(url)
    }

    /// `https://D/c#<cid>` or `https://D/c?app=<slug>#<cid>`.
    public func makeCIDLink(_ cid: String, app slug: String? = nil) -> String {
        if let slug { return "https://\(config.linkDomain)/c?app=\(Links.encodeURIComponent(slug))#\(cid)" }
        return "https://\(config.linkDomain)/c#\(cid)"
    }

    /// `https://D/s#<cid>`.
    public func makeSiteLink(_ cid: String) -> String {
        "https://\(config.linkDomain)/s#\(cid)"
    }

    // MARK: helpers

    /// JavaScript's `encodeURIComponent`: everything except
    /// `A-Z a-z 0-9 - _ . ! ~ * ' ( )` is percent-encoded as UTF-8, uppercase hex.
    public static func encodeURIComponent(_ text: String) -> String {
        let hex = Array("0123456789ABCDEF".utf8)
        var out: [UInt8] = []
        out.reserveCapacity(text.utf8.count)
        for b in text.utf8 {
            switch b {
            case 0x41...0x5A, 0x61...0x7A, 0x30...0x39,
                 UInt8(ascii: "-"), UInt8(ascii: "_"), UInt8(ascii: "."), UInt8(ascii: "!"),
                 UInt8(ascii: "~"), UInt8(ascii: "*"), UInt8(ascii: "'"), UInt8(ascii: "("), UInt8(ascii: ")"):
                out.append(b)
            default:
                out.append(UInt8(ascii: "%"))
                out.append(hex[Int(b >> 4)])
                out.append(hex[Int(b & 15)])
            }
        }
        return String(decoding: out, as: UTF8.self)
    }

    /// True when `text` holds only RFC 3986 query/fragment characters:
    /// `A-Z a-z 0-9 - . _ ~ ! $ & ' ( ) * + , ; = : @ / ?` and `%` followed by
    /// two hex digits.
    public static func isRFC3986QueryOrFragment(_ text: String) -> Bool {
        let u = Array(text.utf8)
        let allowed = Set("-._~!$&'()*+,;=:@/?".utf8)
        func isHex(_ c: UInt8) -> Bool { (0x30...0x39).contains(c) || (0x41...0x46).contains(c) || (0x61...0x66).contains(c) }
        var i = 0
        while i < u.count {
            let c = u[i]
            if (0x41...0x5A).contains(c) || (0x61...0x7A).contains(c) || (0x30...0x39).contains(c) || allowed.contains(c) {
                i += 1
            } else if c == UInt8(ascii: "%"), i + 2 < u.count, isHex(u[i + 1]), isHex(u[i + 2]) {
                i += 3
            } else {
                return false
            }
        }
        return true
    }

    /// Adds `run=0` to a received URL's raw query unless the query already has
    /// a `run` key (`spec/links.md` "withRunZero"). Nothing else changes.
    public static func withRunZero(_ url: String) -> String {
        let split = URLParts.splitQueryAndFragment(url)
        if QueryParams(split.query).has("run") { return url }
        var out = split.beforeQuery
        out += split.query.map { "?" + $0 + "&run=0" } ?? "?run=0"
        if let f = split.fragment { out += "#" + f }
        return out
    }

    /// Removes every `run` parameter from the raw query (names decoded as
    /// `URLSearchParams` does), keeping everything else byte for byte. The `?`
    /// is dropped when nothing remains. Used by the Run button.
    public static func withoutRun(_ url: String) -> String {
        let split = URLParts.splitQueryAndFragment(url)
        guard let query = split.query else { return url }
        let kept = query.split(separator: "&", omittingEmptySubsequences: false).filter { part in
            let name = part.firstIndex(of: "=").map { part[..<$0] } ?? part
            return QueryParams.decode(name) != "run"
        }
        var out = split.beforeQuery
        let joined = kept.joined(separator: "&")
        if !joined.isEmpty { out += "?" + joined }
        if let f = split.fragment { out += "#" + f }
        return out
    }

    /// What the Paste button puts into the open field and opens: the
    /// clipboard text, or nil (do nothing) when it is missing or only ASCII
    /// whitespace.
    public static func pasteInput(_ clipboard: String?) -> String? {
        guard let clipboard, !trimASCIIWhitespace(clipboard).isEmpty else { return nil }
        return clipboard
    }

    /// Trims ASCII whitespace (tab, LF, FF, CR, space) from both ends.
    public static func trimASCIIWhitespace(_ text: String) -> String {
        let ws: Set<UInt8> = [0x09, 0x0A, 0x0C, 0x0D, 0x20]
        let u = Array(text.utf8)
        var s = 0, e = u.count
        while s < e, ws.contains(u[s]) { s += 1 }
        while e > s, ws.contains(u[e - 1]) { e -= 1 }
        return String(decoding: u[s..<e], as: UTF8.self)
    }
}
