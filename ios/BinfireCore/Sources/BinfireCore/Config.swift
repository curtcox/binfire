import Foundation

/// Size bounds for untrusted input (`config/binfire.config.json` `limits`).
public struct BinfireLimits: Equatable, Sendable {
    public var maxStateBytes: Int
    public var maxSiteFileBytes: Int
    public var maxSiteTotalBytes: Int
    public var maxSiteFiles: Int
    public var maxTransferBytes: Int

    public init(maxStateBytes: Int = 5_242_880,
                maxSiteFileBytes: Int = 26_214_400,
                maxSiteTotalBytes: Int = 104_857_600,
                maxSiteFiles: Int = 2000,
                maxTransferBytes: Int = 104_857_600) {
        self.maxStateBytes = maxStateBytes
        self.maxSiteFileBytes = maxSiteFileBytes
        self.maxSiteTotalBytes = maxSiteTotalBytes
        self.maxSiteFiles = maxSiteFiles
        self.maxTransferBytes = maxTransferBytes
    }

    /// The default limits from `config/binfire.config.json`.
    public static let `default` = BinfireLimits()
}

/// Runtime configuration: the shape of the bundled `binfire.config.json`.
///
/// Every value is injectable so that core logic never hard-codes a domain,
/// scheme, host or limit. Missing keys in a loaded file keep their defaults.
public struct BinfireConfig: Equatable, Sendable {
    public var appName: String
    /// `D` in links.md: the https host of binfire links (`binfire.app`).
    public var linkDomain: String
    /// `S` in links.md: the public custom URL scheme (`binfire`).
    public var scheme: String
    /// `O` in links.md: this port's private reverse-DNS scheme (its app ID,
    /// e.g. `app.binfire.ios`). Empty when not configured. Used for the
    /// OAuth redirect, share-extension hand-off and UI tests.
    public var ownScheme: String
    /// HashBin API base URL.
    public var hashbinAPI: String
    /// HashBin content base URL (`https://256t.us`), used for `/<CID>` links and loading.
    public var contentHost: String
    /// HashBin OAuth client ID (may be empty).
    public var hashbinClientId: String
    /// `max_cost_cents` sent with every Native Save upload (`hashbin.maxCostCents`).
    public var hashbinMaxCostCents: Int
    public var bleServiceUUID: String
    public var bleControlCharacteristicUUID: String
    public var bleDataCharacteristicUUID: String
    public var limits: BinfireLimits
    public var oauthRedirect: String

    public init(appName: String = "binfire",
                linkDomain: String = "binfire.app",
                scheme: String = "binfire",
                ownScheme: String = "",
                hashbinAPI: String = "https://hashbin.org",
                contentHost: String = "https://256t.us",
                hashbinClientId: String = "",
                hashbinMaxCostCents: Int = 25,
                bleServiceUUID: String = "6b1f0001-5b6e-4d1a-9f2e-62696e666972",
                bleControlCharacteristicUUID: String = "6b1f0002-5b6e-4d1a-9f2e-62696e666972",
                bleDataCharacteristicUUID: String = "6b1f0003-5b6e-4d1a-9f2e-62696e666972",
                limits: BinfireLimits = .default,
                oauthRedirect: String = "binfire://oauth") {
        self.appName = appName
        self.linkDomain = linkDomain
        self.scheme = scheme
        self.ownScheme = ownScheme
        self.hashbinAPI = hashbinAPI
        self.contentHost = contentHost
        self.hashbinClientId = hashbinClientId
        self.hashbinMaxCostCents = hashbinMaxCostCents
        self.bleServiceUUID = bleServiceUUID
        self.bleControlCharacteristicUUID = bleControlCharacteristicUUID
        self.bleDataCharacteristicUUID = bleDataCharacteristicUUID
        self.limits = limits
        self.oauthRedirect = oauthRedirect
    }

    /// The defaults from `config/binfire.config.json`.
    public static let `default` = BinfireConfig()

    /// Parses a runtime `binfire.config.json`. Throws `BinfireError.badConfig`.
    public init(data: Data) throws {
        guard let root = try? JSONValue.parse(data), case .object(let o) = root else {
            throw BinfireError.badConfig
        }
        var c = BinfireConfig()
        func str(_ obj: JSONObject, _ key: String, _ into: inout String) throws {
            guard let v = obj[key] else { return }
            guard case .string(let s) = v else { throw BinfireError.badConfig }
            into = s
        }
        func int(_ obj: JSONObject, _ key: String, _ into: inout Int) throws {
            guard let v = obj[key] else { return }
            guard let n = v.integerValue, n >= 0 else { throw BinfireError.badConfig }
            into = n
        }
        func object(_ key: String) throws -> JSONObject? {
            guard let v = o[key] else { return nil }
            guard case .object(let sub) = v else { throw BinfireError.badConfig }
            return sub
        }
        try str(o, "appName", &c.appName)
        try str(o, "linkDomain", &c.linkDomain)
        try str(o, "scheme", &c.scheme)
        try str(o, "ownScheme", &c.ownScheme)
        try str(o, "oauthRedirect", &c.oauthRedirect)
        if let h = try object("hashbin") {
            try str(h, "api", &c.hashbinAPI)
            try str(h, "content", &c.contentHost)
            try str(h, "clientId", &c.hashbinClientId)
            try int(h, "maxCostCents", &c.hashbinMaxCostCents)
        }
        if let b = try object("ble") {
            try str(b, "serviceUuid", &c.bleServiceUUID)
            try str(b, "controlCharacteristicUuid", &c.bleControlCharacteristicUUID)
            try str(b, "dataCharacteristicUuid", &c.bleDataCharacteristicUUID)
        }
        if let l = try object("limits") {
            try int(l, "maxStateBytes", &c.limits.maxStateBytes)
            try int(l, "maxSiteFileBytes", &c.limits.maxSiteFileBytes)
            try int(l, "maxSiteTotalBytes", &c.limits.maxSiteTotalBytes)
            try int(l, "maxSiteFiles", &c.limits.maxSiteFiles)
            try int(l, "maxTransferBytes", &c.limits.maxTransferBytes)
        }
        c.scheme = c.scheme.lowercased()
        c.ownScheme = c.ownScheme.lowercased()
        self = c
    }

    /// Loads a runtime `binfire.config.json` from a file URL.
    public static func load(contentsOf url: URL) throws -> BinfireConfig {
        guard let data = try? Data(contentsOf: url) else { throw BinfireError.badConfig }
        return try BinfireConfig(data: data)
    }
}
