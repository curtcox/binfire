import Foundation

/// What one scanned text did (`spec/qr.md` "Scan session").
public enum ScanResult: Equatable, Sendable {
    /// A frame of an incomplete transfer: `received` distinct indexes of `count`.
    case progress(received: Int, count: Int)
    /// A bad frame (`bad-frame`, `bad-magic`, `bad-version`, `too-large`,
    /// `inconsistent`, `mismatch`).
    case frameError(BinfireError)
    /// The last frame of a transfer: the verified payload bytes.
    case bundle(Data)
    /// Not a frame: `routeReceived(text)`.
    case route(Route)

    /// The spec's `kind` string.
    public var kind: String {
        switch self {
        case .progress: return "progress"
        case .frameError: return "frame-error"
        case .bundle: return "bundle"
        case .route: return "route"
        }
    }
}

/// Collects every decoded text of one scan sheet, live or from images, and
/// reassembles `BF1:` multi-frame transfers (`spec/qr.md`).
public struct ScanSession: Sendable {
    /// The longest base64url text after `BF1:` that is decoded.
    public static let maxFrameText = 2048

    public let links: Links
    private var current: Reassembler?

    public init(links: Links) {
        self.links = links
    }

    /// The transfer in progress, if any.
    public var inProgress: Bool { current != nil }

    public mutating func accept(_ text: String) -> ScanResult {
        let trimmed = Links.trimASCIIWhitespace(text)
        guard trimmed.hasPrefix(Transfer.qrPrefix) else { return .route(links.routeReceived(text)) }
        let rest = trimmed.dropFirst(Transfer.qrPrefix.count)
        guard rest.utf8.count <= ScanSession.maxFrameText, let bytes = Base64URL.decode(rest) else {
            return .frameError(.badFrame)
        }
        let frame: TransferFrame
        do {
            frame = try Transfer.decodeFrame(bytes)
        } catch {
            // A bad frame keeps the current transfer.
            return .frameError(error as? BinfireError ?? .badFrame)
        }
        var r = current.flatMap { $0.id == frame.id ? $0 : nil } ?? Reassembler(limits: links.config.limits)
        do {
            if let payload = try r.add(frame: frame) {
                current = nil
                return .bundle(payload)
            }
            current = r
            return .progress(received: r.receivedCount, count: r.count)
        } catch {
            current = nil
            return .frameError(error as? BinfireError ?? .badFrame)
        }
    }
}

/// What to do with a received bundle's payload (`spec/qr.md` "Received bundles").
public enum ReceivedAction: Equatable, Sendable {
    /// Handle this route (from a `url` bundle: `routeReceived(header.url)`).
    case route(Route)
    /// A verified document: cache it by CID, then continue as a `load-cid`
    /// route with `app` as the hint and `run: false`.
    case document(cid: String, bytes: Data, app: String?)
    /// Show the error sheet. `error` is the decode error, or nil for a
    /// packaged site (not supported until M6).
    case error(BinfireError?)

    /// The error-sheet text for a packaged site, until M6.
    public static let siteMessage = "Packaged sites arrive in a later version."

    public static func from(payload: Data, links: Links) -> ReceivedAction {
        let bundle: TransferBundle
        do {
            bundle = try Transfer.decodeBundle(payload, limits: links.config.limits)
        } catch {
            return .error(error as? BinfireError ?? .badBundle)
        }
        switch bundle.kind {
        case .url:
            return .route(links.routeReceived(bundle.url ?? ""))
        case .cid:
            guard let cid = bundle.cid, let entry = bundle.entries.first(where: { $0.cid == cid }) else {
                return .error(.badBundle)
            }
            return .document(cid: cid, bytes: entry.bytes, app: bundle.app)
        case .site:
            return .error(nil)
        }
    }
}

extension QR {
    /// The `BF1:` texts of a multi-frame QR for an app state URL
    /// (`spec/qr.md` "Multi-frame QR"): a `url` bundle of the raw URL, split
    /// into 512-byte chunks with transfer id `id` (8 random bytes).
    public static func multiFrameTexts(url: String, id: Data = Transfer.randomTransferID()) -> [String] {
        let payload = Transfer.encodeBundle(.url(url))
        return Transfer.encodeFrames(payload, id: id, chunkSize: Transfer.qrChunkSize).map(Transfer.qrText)
    }
}
