import Foundation

/// The three transfer payload kinds.
public enum TransferKind: String, Sendable, CaseIterable {
    case url
    case cid
    case site
}

/// One bundle entry: content bytes and their CID.
public struct BundleEntry: Equatable, Sendable {
    public var cid: String
    public var bytes: Data

    /// An entry whose CID is computed from `bytes`.
    public init(bytes: Data) {
        self.cid = CID.computeCID(bytes)
        self.bytes = bytes
    }

    public init(cid: String, bytes: Data) {
        self.cid = cid
        self.bytes = bytes
    }
}

/// A decoded (verified) bundle: the payload of a `.binfire` file or of a
/// chunked transfer (`spec/transfer.md`).
public struct TransferBundle: Equatable, Sendable {
    public var kind: TransferKind
    /// The state URL (`url` kind).
    public var url: String?
    /// The document CID (`cid` kind) or manifest CID (`site` kind).
    public var cid: String?
    /// Slug hint (`cid` kind).
    public var app: String?
    /// Display name, at most 200 code points.
    public var name: String?
    public var entries: [BundleEntry]
    /// The validated manifest (`site` kind, after decoding).
    public var manifest: SiteManifest?

    public init(kind: TransferKind, url: String? = nil, cid: String? = nil, app: String? = nil,
                name: String? = nil, entries: [BundleEntry] = [], manifest: SiteManifest? = nil) {
        self.kind = kind
        self.url = url
        self.cid = cid
        self.app = app
        self.name = name
        self.entries = entries
        self.manifest = manifest
    }

    /// A `url` bundle.
    public static func url(_ url: String, name: String? = nil) -> TransferBundle {
        TransferBundle(kind: .url, url: url, name: name)
    }

    /// A `cid` bundle carrying one document.
    public static func document(_ bytes: Data, app: String? = nil, name: String? = nil) -> TransferBundle {
        let e = BundleEntry(bytes: bytes)
        return TransferBundle(kind: .cid, cid: e.cid, app: app, name: name, entries: [e])
    }

    /// A `site` bundle: the manifest bytes first, then each distinct file.
    public static func site(manifest: Data, files: [Data], name: String? = nil) -> TransferBundle {
        let m = BundleEntry(bytes: manifest)
        var seen: Set<String> = [m.cid]
        var entries = [m]
        for f in files {
            let e = BundleEntry(bytes: f)
            if seen.insert(e.cid).inserted { entries.append(e) }
        }
        return TransferBundle(kind: .site, cid: m.cid, name: name, entries: entries)
    }
}

/// One decoded chunk frame.
public struct TransferFrame: Equatable, Sendable {
    /// 8-byte transfer id.
    public var id: Data
    public var index: Int
    public var count: Int
    public var offset: Int
    public var total: Int
    /// The payload CID.
    public var cid: String
    public var data: Data

    public init(id: Data, index: Int, count: Int, offset: Int, total: Int, cid: String, data: Data) {
        self.id = id
        self.index = index
        self.count = count
        self.offset = offset
        self.total = total
        self.cid = cid
        self.data = data
    }

    /// The frame's wire bytes.
    public var encoded: Data {
        var out = Data([0x42, 0x46, 1, 0])
        var idBytes = [UInt8](id.prefix(8))
        while idBytes.count < 8 { idBytes.append(0) }
        out.append(contentsOf: idBytes)
        for v in [index, count, offset, total] { out.append(contentsOf: Transfer.uint32BE(v)) }
        let cidBytes = Array(cid.utf8)
        out.append(UInt8(truncatingIfNeeded: cidBytes.count))
        out.append(contentsOf: cidBytes)
        out.append(data)
        return out
    }
}

/// Bundles, chunk frames and QR text frames (`spec/transfer.md`).
public enum Transfer {
    public static let bundleMagic = Data("BFB1".utf8)
    public static let maxHeaderLength = 1_048_576
    public static let maxNameLength = 200
    /// QR text frame prefix.
    public static let qrPrefix = "BF1:"
    /// The chunk size multi-frame QR uses.
    public static let qrChunkSize = 512
    /// MIME type of `.binfire` files.
    public static let mimeType = "application/vnd.binfire.bundle"
    /// UTI of `.binfire` files.
    public static let uti = "app.binfire.bundle"

    // MARK: bundles

    /// Serializes a bundle container. Header keys are written in the order
    /// `kind`, `url`, `cid`, `app`, `name`, `entries`.
    public static func encodeBundle(_ bundle: TransferBundle) -> Data {
        var h = JSONObject()
        h["kind"] = .string(bundle.kind.rawValue)
        if let v = bundle.url { h["url"] = .string(v) }
        if let v = bundle.cid { h["cid"] = .string(v) }
        if let v = bundle.app { h["app"] = .string(v) }
        if let v = bundle.name { h["name"] = .string(v) }
        h["entries"] = .array(bundle.entries.map { .object(JSONObject([("cid", .string($0.cid))])) })
        let header = Data(JSONValue.object(h).serialized().utf8)
        var out = bundleMagic
        out.append(contentsOf: uint32BE(header.count))
        out.append(header)
        for e in bundle.entries { out.append(e.bytes) }
        return out
    }

    /// Decodes and fully verifies a bundle container, applying the checks of
    /// `spec/transfer.md` in order.
    public static func decodeBundle(_ data: Data, limits: BinfireLimits) throws -> TransferBundle {
        let d = Data(data) // re-base indices at 0
        // 1.
        guard d.count >= 4, d.prefix(4) == bundleMagic else { throw BinfireError.badMagic }
        guard d.count >= 8 else { throw BinfireError.badBundle }
        let hlen = Int(readUInt32BE(d, 4))
        guard hlen >= 2, hlen <= maxHeaderLength, d.count >= 8 + hlen else { throw BinfireError.badBundle }
        // 2.
        guard let headerText = decodeUTF8Strict(d.subdata(in: 8..<(8 + hlen))),
              let headerValue = try? JSONValue.parse(Data(headerText.utf8)),
              case .object(let h) = headerValue,
              case .string(let kindText)? = h["kind"], let kind = TransferKind(rawValue: kindText),
              case .array(let entryValues)? = h["entries"] else { throw BinfireError.badBundle }
        func optionalString(_ key: String) throws -> String? {
            switch h[key] {
            case nil: return nil
            case .string(let s)?: return s
            default: throw BinfireError.badBundle
            }
        }
        let url = try optionalString("url")
        let cid = try optionalString("cid")
        let app = try optionalString("app")
        let name = try optionalString("name")
        if let name, name.unicodeScalars.count > maxNameLength { throw BinfireError.badBundle }
        switch kind {
        case .url: guard url != nil else { throw BinfireError.badBundle }
        case .cid, .site: guard cid != nil else { throw BinfireError.badBundle }
        }
        var entryCIDs: [String] = []
        for v in entryValues {
            guard case .object(let e) = v, case .string(let c)? = e["cid"] else { throw BinfireError.badBundle }
            entryCIDs.append(c)
        }
        // 3.
        for c in entryCIDs where !CID.isCID(c) { throw BinfireError.invalidCID }
        let sizes = entryCIDs.map { CID.cidLength($0)! }
        var sum = 0
        for s in sizes {
            sum += s
            if sum > limits.maxTransferBytes { throw BinfireError.tooLarge }
        }
        guard d.count == 8 + hlen + sum else { throw BinfireError.badBundle }
        // 4.
        var entries: [BundleEntry] = []
        var offset = 8 + hlen
        for (c, size) in zip(entryCIDs, sizes) {
            let bytes = d.subdata(in: offset..<(offset + size))
            guard CID.verify(c, bytes) else { throw BinfireError.mismatch }
            entries.append(BundleEntry(cid: c, bytes: bytes))
            offset += size
        }
        // 5.
        var manifest: SiteManifest? = nil
        switch kind {
        case .url:
            guard entries.isEmpty else { throw BinfireError.badBundle }
        case .cid:
            guard entryCIDs == [cid!] else { throw BinfireError.badBundle }
        case .site:
            guard let first = entries.first, first.cid == cid else { throw BinfireError.badBundle }
            let m = try Sites.validateManifest(first.bytes, limits: limits)
            guard Set(entryCIDs).count == entryCIDs.count else { throw BinfireError.badBundle }
            let required = Set(m.files.values.map(\.cid)).union([first.cid])
            guard Set(entryCIDs) == required else { throw BinfireError.badBundle }
            manifest = m
        }
        return TransferBundle(kind: kind, url: url, cid: cid, app: app, name: name, entries: entries, manifest: manifest)
    }

    // MARK: frames

    /// Splits `payload` into frames deterministically. `id` is the 8-byte
    /// transfer id; `chunkSize` must be at least 1.
    public static func encodeFrames(_ payload: Data, id: Data, chunkSize: Int) -> [Data] {
        precondition(chunkSize >= 1, "chunkSize must be >= 1")
        precondition(id.count == 8, "transfer id must be 8 bytes")
        let p = Data(payload)
        let cid = CID.computeCID(p)
        let total = p.count
        let count = max(1, (total + chunkSize - 1) / chunkSize)
        return (0..<count).map { i in
            let offset = i * chunkSize
            let end = min(offset + chunkSize, total)
            return TransferFrame(id: id, index: i, count: count, offset: offset, total: total, cid: cid,
                                 data: p.subdata(in: min(offset, total)..<end)).encoded
        }
    }

    /// A random 8-byte transfer id.
    public static func randomTransferID() -> Data {
        var g = SystemRandomNumberGenerator()
        return Data((0..<8).map { _ in UInt8.random(in: 0...255, using: &g) })
    }

    /// Parses one frame, failing with `bad-magic`, `bad-version` or `bad-frame`.
    public static func decodeFrame(_ bytes: Data) throws -> TransferFrame {
        let b = Data(bytes)
        guard b.count >= 2, b[0] == 0x42, b[1] == 0x46 else { throw BinfireError.badMagic }
        guard b.count >= 4 else { throw BinfireError.badFrame }
        guard b[2] == 1, b[3] == 0 else { throw BinfireError.badVersion }
        guard b.count >= 29 else { throw BinfireError.badFrame }
        let cidLen = Int(b[28])
        guard (8...94).contains(cidLen), b.count >= 29 + cidLen else { throw BinfireError.badFrame }
        let index = Int(readUInt32BE(b, 12))
        let count = Int(readUInt32BE(b, 16))
        let offset = Int(readUInt32BE(b, 20))
        let total = Int(readUInt32BE(b, 24))
        let cidBytes = b.subdata(in: 29..<(29 + cidLen))
        guard cidBytes.allSatisfy({ $0 < 0x80 }), case let cid = String(decoding: cidBytes, as: UTF8.self),
              CID.isCID(cid), CID.cidLength(cid) == total else { throw BinfireError.badFrame }
        let data = b.subdata(in: (29 + cidLen)..<b.count)
        guard index < count, offset + data.count <= total else { throw BinfireError.badFrame }
        return TransferFrame(id: b.subdata(in: 4..<12), index: index, count: count, offset: offset,
                             total: total, cid: cid, data: data)
    }

    /// `BF1:` + base64url(frame).
    public static func qrText(_ frame: Data) -> String { qrPrefix + Base64URL.encode(frame) }

    /// The frame bytes of a `BF1:` QR text, or nil if it is not one.
    public static func frameFromQRText(_ text: String) -> Data? {
        guard text.hasPrefix(qrPrefix) else { return nil }
        return Base64URL.decode(text.dropFirst(qrPrefix.count))
    }

    // MARK: byte helpers

    static func uint32BE(_ v: Int) -> [UInt8] {
        let u = UInt32(truncatingIfNeeded: v)
        return [UInt8(u >> 24 & 0xFF), UInt8(u >> 16 & 0xFF), UInt8(u >> 8 & 0xFF), UInt8(u & 0xFF)]
    }

    static func readUInt32BE(_ d: Data, _ at: Int) -> UInt32 {
        UInt32(d[at]) << 24 | UInt32(d[at + 1]) << 16 | UInt32(d[at + 2]) << 8 | UInt32(d[at + 3])
    }
}

/// Reassembles chunk frames received in any order (`spec/transfer.md`
/// "Reassembly").
public struct Reassembler: Sendable {
    public let limits: BinfireLimits
    /// The first frame's `id`, `count`, `total` and `cid`, once known.
    public private(set) var id: Data?
    public private(set) var count = 0
    public private(set) var total = 0
    public private(set) var cid: String?
    private var chunks: [Int: (offset: Int, data: Data)] = [:]
    /// The verified payload once complete.
    public private(set) var payload: Data?

    public init(limits: BinfireLimits) {
        self.limits = limits
    }

    /// True when every index has arrived and the payload verified.
    public var isComplete: Bool { payload != nil }

    /// Number of distinct indexes received.
    public var receivedCount: Int { chunks.count }

    /// Adds one frame's bytes. Returns the verified payload when this frame
    /// completes the transfer, else nil. Throws the frame's decode error,
    /// `too-large`, `inconsistent`, `bad-frame` or `mismatch`.
    @discardableResult
    public mutating func add(_ bytes: Data) throws -> Data? {
        try add(frame: Transfer.decodeFrame(bytes))
    }

    /// Adds one decoded frame. See `add(_:)`.
    @discardableResult
    public mutating func add(frame f: TransferFrame) throws -> Data? {
        if let id {
            guard f.id == id, f.count == count, f.total == total, f.cid == cid else { throw BinfireError.inconsistent }
        } else {
            guard f.total <= limits.maxTransferBytes else { throw BinfireError.tooLarge }
            // Every chunk but an empty payload's single frame carries data, so a
            // count above max(1, total) can never tile; refuse it before tracking indexes.
            guard f.count <= max(1, f.total) else { throw BinfireError.badFrame }
            id = f.id
            count = f.count
            total = f.total
            cid = f.cid
        }
        if let existing = chunks[f.index] {
            guard existing.offset == f.offset, existing.data == f.data else { throw BinfireError.inconsistent }
            return nil
        }
        if payload != nil { return nil }
        chunks[f.index] = (f.offset, f.data)
        guard chunks.count == count else { return nil }

        var assembled = Data(capacity: total)
        for chunk in chunks.values.sorted(by: { $0.offset < $1.offset }) {
            guard chunk.offset == assembled.count else { throw BinfireError.badFrame }
            assembled.append(chunk.data)
        }
        guard assembled.count == total else { throw BinfireError.badFrame }
        guard CID.verify(cid!, assembled) else { throw BinfireError.mismatch }
        payload = assembled
        return assembled
    }

    /// Indexes that have not arrived yet, ascending (at most `limit`).
    public func missing(limit: Int = Int.max) -> [Int] {
        guard id != nil else { return [] }
        var out: [Int] = []
        var i = 0
        while i < count && out.count < limit {
            if chunks[i] == nil { out.append(i) }
            i += 1
        }
        return out
    }
}
