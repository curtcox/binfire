import Foundation

/// The state kinds of `spec/state.md` "Classification".
public enum StateKind: String, Sendable, CaseIterable {
    case publish
    case cid
    case v1
    case unsupportedVersion = "unsupported-version"
    case src
    case h1
    case fragment
    case doc
    case compressed
    case example
    case none
}

/// The result of `URLState.classifyState`.
public struct StateClassification: Equatable, Sendable {
    public var state: StateKind
    /// False only when the query has `run=0`.
    public var run: Bool
    /// The `view` query value, or nil.
    public var view: String?
    /// The CID when `state == .cid`.
    public var cid: String?
    /// UTF-8 length of the whole URL string.
    public var bytes: Int
}

/// Classifying an app URL's state for routing and labelling. binfire never
/// rewrites state; this only reads it. (Named `URLState` so it does not clash
/// with SwiftUI's `State`.)
public enum URLState {
    /// Classifies `url` (an absolute URL that matched a registry app), first
    /// matching rule wins, following FK `createUrlState().parse`.
    public static func classifyState(_ url: String) -> StateClassification {
        let split = URLParts.splitQueryAndFragment(url)
        let hash = split.fragment ?? ""
        let params = QueryParams(split.query)
        var state: StateKind
        var cid: String? = nil
        if QueryParams(hash).has("hashbin_publish") { state = .publish }
        else if CID.isCID(hash) { state = .cid; cid = hash }
        else if hash.hasPrefix("v1.") { state = .v1 }
        else if isVersioned(hash) { state = .unsupportedVersion }
        else if hash.hasPrefix("src=") { state = .src }
        else if hash.hasPrefix("h1=") { state = .h1 }
        else if !hash.isEmpty { state = .fragment }
        else if params.has("doc") { state = .doc }
        else if params.has("compressed") { state = .compressed }
        else if params.has("example") { state = .example }
        else { state = .none }
        return StateClassification(state: state, run: params.get("run") != "0", view: params.get("view"),
                                   cid: cid, bytes: url.utf8.count)
    }

    /// `^v[0-9]+\.`
    private static func isVersioned(_ hash: String) -> Bool {
        let u = Array(hash.utf8)
        guard u.first == UInt8(ascii: "v") else { return false }
        var i = 1
        while i < u.count, (0x30...0x39).contains(u[i]) { i += 1 }
        return i > 1 && i < u.count && u[i] == UInt8(ascii: ".")
    }
}
