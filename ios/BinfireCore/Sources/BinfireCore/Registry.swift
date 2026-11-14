import Foundation

/// One app from `shared/registry/apps.json` (`spec/registry.md`).
public struct RegistryApp: Equatable, Sendable {
    public var slug: String
    public var name: String
    /// Base used to build new links.
    public var canonicalOrigin: String
    public var recoveryOrigin: String
    /// More bases that match the app; never used to build links.
    public var otherOrigins: [String]
    /// Envelope keys (`"<format>:<type>"` or `"<format>"`).
    public var documentTypes: [String]
    public var offlineManifest: String?
    public var icon: String?
    /// Open capability object; known keys are `fragmentKit` and `publish`.
    public var capabilities: JSONObject

    /// All bases in matching order: canonical, recovery, then others.
    public var bases: [String] { [canonicalOrigin, recoveryOrigin] + otherOrigins }

    public init(slug: String, name: String, canonicalOrigin: String, recoveryOrigin: String,
                otherOrigins: [String] = [], documentTypes: [String] = [], offlineManifest: String? = nil,
                icon: String? = nil, capabilities: JSONObject = JSONObject()) {
        self.slug = slug
        self.name = name
        self.canonicalOrigin = canonicalOrigin
        self.recoveryOrigin = recoveryOrigin
        self.otherOrigins = otherOrigins
        self.documentTypes = documentTypes
        self.offlineManifest = offlineManifest
        self.icon = icon
        self.capabilities = capabilities
    }

    /// True when `capabilities[key] == true`.
    public func hasCapability(_ key: String) -> Bool { capabilities[key] == .bool(true) }
}

/// The app registry: loading and URL matching (`appForURL`).
public struct Registry: Equatable, Sendable {
    public private(set) var apps: [RegistryApp]
    private var parsedBases: [(slug: String, base: URLParts, isCanonical: Bool)]

    public static func == (a: Registry, b: Registry) -> Bool { a.apps == b.apps }

    /// Builds a registry from apps. Throws `bad-registry` when a slug or base
    /// is malformed or a slug repeats.
    public init(apps: [RegistryApp]) throws {
        self.apps = apps
        parsedBases = []
        var slugs = Set<String>()
        for app in apps {
            guard Registry.isValidSlug(app.slug), slugs.insert(app.slug).inserted else { throw BinfireError.badRegistry }
            for (i, base) in app.bases.enumerated() {
                guard let parts = URLParts(base), parts.scheme == "https" || parts.scheme == "http",
                      parts.userinfo == nil, parts.port == nil, parts.query == nil, parts.fragment == nil,
                      !parts.host.isEmpty else { throw BinfireError.badRegistry }
                parsedBases.append((app.slug, parts, i == 0))
            }
        }
    }

    /// Parses `apps.json` (`format: "binfire-registry"`, `version: 1`).
    public init(data: Data) throws {
        guard let root = try? JSONValue.parse(data), case .object(let o) = root,
              o["format"] == .string("binfire-registry"), o["version"]?.integerValue == 1,
              case .array(let list)? = o["apps"] else { throw BinfireError.badRegistry }
        var apps: [RegistryApp] = []
        for item in list {
            guard case .object(let a) = item,
                  let slug = a["slug"]?.stringValue, let name = a["name"]?.stringValue,
                  let canonical = a["canonicalOrigin"]?.stringValue,
                  let recovery = a["recoveryOrigin"]?.stringValue else { throw BinfireError.badRegistry }
            func strings(_ key: String) throws -> [String] {
                guard let v = a[key] else { return [] }
                guard case .array(let arr) = v else { throw BinfireError.badRegistry }
                return try arr.map { guard let s = $0.stringValue else { throw BinfireError.badRegistry }; return s }
            }
            func optionalString(_ key: String) throws -> String? {
                switch a[key] {
                case nil, .null?: return nil
                case .string(let s)?: return s
                default: throw BinfireError.badRegistry
                }
            }
            var caps = JSONObject()
            if case .object(let c)? = a["capabilities"] { caps = c }
            apps.append(RegistryApp(slug: slug, name: name, canonicalOrigin: canonical, recoveryOrigin: recovery,
                                    otherOrigins: try strings("otherOrigins"), documentTypes: try strings("documentTypes"),
                                    offlineManifest: try optionalString("offlineManifest"),
                                    icon: try optionalString("icon"), capabilities: caps))
        }
        try self.init(apps: apps)
    }

    /// Loads `apps.json` from a file URL.
    public static func load(contentsOf url: URL) throws -> Registry {
        guard let data = try? Data(contentsOf: url) else { throw BinfireError.badRegistry }
        return try Registry(data: data)
    }

    /// `^[a-z0-9][a-z0-9-]*$`
    public static func isValidSlug(_ slug: String) -> Bool {
        let u = Array(slug.utf8)
        guard let first = u.first else { return false }
        func ok(_ c: UInt8, dash: Bool) -> Bool {
            (0x61...0x7A).contains(c) || (0x30...0x39).contains(c) || (dash && c == UInt8(ascii: "-"))
        }
        return ok(first, dash: false) && u.dropFirst().allSatisfy { ok($0, dash: true) }
    }

    /// The app with this slug, or nil.
    public func app(slug: String) -> RegistryApp? { apps.first { $0.slug == slug } }

    /// The first app (in file order) whose base matches the absolute URL
    /// `url`, per `spec/registry.md` "Matching".
    public func appForURL(_ url: String) -> RegistryApp? {
        guard let m = match(url) else { return nil }
        return app(slug: m.slug)
    }

    /// Like `appForURL`, also telling whether the matching base is the app's
    /// canonical origin and whether the path is exactly the base path.
    func match(_ url: String) -> (slug: String, isCanonical: Bool, exactPath: Bool)? {
        guard let u = URLParts(url), u.userinfo == nil, u.hasAuthority,
              u.scheme == "https" || u.scheme == "http" else { return nil }
        let host = u.normalizedHost, port = u.normalizedPort, path = u.normalizedPath
        for b in parsedBases {
            guard u.scheme == b.base.scheme, host == b.base.normalizedHost, port == b.base.normalizedPort else { continue }
            let basePath = b.base.normalizedPath
            if path == basePath { return (b.slug, b.isCanonical, true) }
            if basePath.hasSuffix("/") && path == basePath + "index.html" { return (b.slug, b.isCanonical, false) }
        }
        return nil
    }

    /// Every app that lists `key` in `documentTypes`, in file order.
    public func appsForDocumentType(_ key: String) -> [RegistryApp] {
        apps.filter { $0.documentTypes.contains(key) }
    }
}
