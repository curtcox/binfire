import Foundation

/// Data-over-sound payload rules (`spec/audio.md`).
public enum Audio {
    /// ggwave's payload limit in UTF-8 bytes.
    public static let maxPayloadBytes = 140

    /// True when `text` is at most 140 UTF-8 bytes and routes to `load-cid`,
    /// `open-site`, or `open-app` via an `https://D/a/` link.
    public static func audioPayloadOK(_ text: String, links: Links) -> Bool {
        guard text.utf8.count <= maxPayloadBytes else { return false }
        let (route, source) = links.routeWithSource(text)
        switch route {
        case .loadCID, .openSite: return true
        case .openApp: return source == .httpsAppLink
        default: return false
        }
    }
}
