import Foundation

/// A named saved state (`spec/ui.md` "Library data").
public struct SavedState: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var name: String
    public var url: String
    public var app: String
    public var savedAt: Date

    public init(id: String = UUID().uuidString.lowercased(), name: String, url: String, app: String, savedAt: Date) {
        self.id = id
        self.name = name
        self.url = url
        self.app = app
        self.savedAt = savedAt
    }
}

/// One recently visited state URL.
public struct RecentEntry: Codable, Equatable, Sendable {
    public var url: String
    public var app: String
    public var visitedAt: Date

    public init(url: String, app: String, visitedAt: Date) {
        self.url = url
        self.app = app
        self.visitedAt = visitedAt
    }
}

/// One packaged site in the library (M6).
public struct SiteEntry: Codable, Equatable, Sendable {
    public var cid: String
    public var name: String
    public var addedAt: Date

    public init(cid: String, name: String, addedAt: Date) {
        self.cid = cid
        self.name = name
        self.addedAt = addedAt
    }
}

/// The library: saved states, recents and sites, with the shared JSON model
/// `{ "version": 1, "saved": [...], "recent": [...], "sites": [...] }`.
/// Dates are ISO 8601 strings such as `2026-11-14T15:00:00Z`.
public struct Library: Codable, Equatable, Sendable {
    /// Recent entries are capped at this many.
    public static let recentCap = 100
    /// Recent entries are also capped at this many total URL bytes (UTF-8).
    public static let recentMaxTotalBytes = 16 * 1024 * 1024
    /// A URL longer than this (UTF-8 bytes) is never added to Recent.
    public static let recentMaxURLBytes = 1024 * 1024

    public var version: Int = 1
    /// Newest first, no cap, duplicate URLs allowed.
    public private(set) var saved: [SavedState] = []
    /// Newest first, deduplicated by URL, at most `recentCap` entries and
    /// `recentMaxTotalBytes` of URLs.
    public private(set) var recent: [RecentEntry] = []
    public private(set) var sites: [SiteEntry] = []

    public init() {}

    /// Records a visit: moves (or inserts) `url` to the front, then drops the
    /// oldest entries beyond the count and byte caps. A URL over
    /// `recentMaxURLBytes` is ignored (save it by name instead).
    /// Returns false when the URL was too large to add.
    @discardableResult
    public mutating func addRecent(url: String, app: String, at date: Date = Date()) -> Bool {
        guard url.utf8.count <= Library.recentMaxURLBytes else { return false }
        recent.removeAll { $0.url == url }
        recent.insert(RecentEntry(url: url, app: app, visitedAt: date), at: 0)
        trimRecent()
        return true
    }

    private mutating func trimRecent() {
        recent.removeAll { $0.url.utf8.count > Library.recentMaxURLBytes }
        if recent.count > Library.recentCap { recent.removeLast(recent.count - Library.recentCap) }
        var total = recent.reduce(0) { $0 + $1.url.utf8.count }
        while total > Library.recentMaxTotalBytes, let last = recent.popLast() {
            total -= last.url.utf8.count
        }
    }

    /// Saves a named state at the front and returns it.
    @discardableResult
    public mutating func save(name: String, url: String, app: String, at date: Date = Date(),
                              id: String = UUID().uuidString.lowercased()) -> SavedState {
        let s = SavedState(id: id, name: name, url: url, app: app, savedAt: date)
        saved.insert(s, at: 0)
        return s
    }

    /// Deletes the saved state with `id`.
    public mutating func deleteSaved(id: String) {
        saved.removeAll { $0.id == id }
    }

    /// Removes every recent entry.
    public mutating func clearRecent() { recent.removeAll() }

    /// Adds (or moves to the front) a site by manifest CID.
    public mutating func addSite(cid: String, name: String, at date: Date = Date()) {
        sites.removeAll { $0.cid == cid }
        sites.insert(SiteEntry(cid: cid, name: name, addedAt: date), at: 0)
    }

    // MARK: JSON

    private enum CodingKeys: String, CodingKey { case version, saved, recent, sites }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try c.decodeIfPresent(Int.self, forKey: .version) ?? 1
        saved = try c.decodeIfPresent([SavedState].self, forKey: .saved) ?? []
        recent = try c.decodeIfPresent([RecentEntry].self, forKey: .recent) ?? []
        trimRecent()
        sites = try c.decodeIfPresent([SiteEntry].self, forKey: .sites) ?? []
    }

    /// Encodes the library model as JSON.
    public func encoded() throws -> Data {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try e.encode(self)
    }

    /// Decodes the library model from JSON.
    public init(data: Data) throws {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        self = try d.decode(Library.self, from: data)
    }
}

/// Persists a `Library` as a JSON file (in Application Support on device).
public final class LibraryStore: @unchecked Sendable {
    public let fileURL: URL
    private let queue = DispatchQueue(label: "binfire.library.store")

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    /// `Application Support/binfire/library.json`.
    public static func applicationSupport() throws -> LibraryStore {
        let dir = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                              appropriateFor: nil, create: true)
            .appendingPathComponent("binfire", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return LibraryStore(fileURL: dir.appendingPathComponent("library.json"))
    }

    /// Loads the library; a missing or unreadable file gives an empty library.
    public func load() -> Library {
        guard let data = try? Data(contentsOf: fileURL), let lib = try? Library(data: data) else { return Library() }
        return lib
    }

    /// Writes the library atomically on a background queue.
    public func save(_ library: Library) {
        guard let data = try? library.encoded() else { return }
        let url = fileURL
        queue.async { try? data.write(to: url, options: .atomic) }
    }

    /// Writes synchronously (tests, app shutdown).
    public func saveNow(_ library: Library) throws {
        let data = try library.encoded()
        try queue.sync { try data.write(to: fileURL, options: .atomic) }
    }
}
