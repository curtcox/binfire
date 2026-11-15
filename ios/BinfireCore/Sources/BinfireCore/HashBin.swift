import CryptoKit
import Foundation

// HashBin integration (`spec/hashbin.md`, `spec/cid.md` "Loading"): verified
// CID loading, what Native Save uploads for a state, PKCE, and the OAuth +
// upload client. Everything here is UI-free; the network and token storage
// are injected so the unit tests can drive them.

// MARK: - Loading (cid.md)

/// The response to a content fetch: the HTTP status and the body as a
/// stream of chunks. `loadCID` enforces the byte cap while reading.
public struct ContentResponse: Sendable {
    public var status: Int
    public var body: AsyncThrowingStream<Data, Error>

    public init(status: Int, body: AsyncThrowingStream<Data, Error>) {
        self.status = status
        self.body = body
    }

    /// A response whose whole body is already in memory (tests, small bodies).
    public init(status: Int, data: Data, chunkSize: Int = 4096) {
        self.status = status
        self.body = AsyncThrowingStream { continuation in
            var i = 0
            while i < data.count {
                let end = min(i + chunkSize, data.count)
                continuation.yield(data.subdata(in: i..<end))
                i = end
            }
            continuation.finish()
        }
    }
}

/// Fetches a content URL (no cookies, no credentials, no referrer). Any
/// thrown error other than a `BinfireError` counts as `network`.
public typealias ContentFetch = @Sendable (URL) async throws -> ContentResponse

public enum HashBin {
    /// `longLinkBytes` (hashbin.md "Long-link offer"): links longer than this
    /// many UTF-8 bytes also get the "Save to HashBin for a short link" notice.
    public static let longLinkBytes = 2000

    /// True when a `makeLink` result is long enough for the long-link notice.
    public static func isLongLink(_ link: String) -> Bool { link.utf8.count > longLinkBytes }

    /// The content URL of a CID: `{content}/{cid}`.
    public static func contentURL(_ cid: String, contentBase: String) -> URL? {
        var base = contentBase
        while base.hasSuffix("/") { base.removeLast() }
        return URL(string: base + "/" + cid)
    }

    /// `loadCID(cid, limit, fetch)` from `spec/cid.md` "Loading": validates,
    /// bounds before any request, streams with a cap of `cidLength(cid)`
    /// bytes and verifies. Throws a `BinfireError` with the spec's code.
    public static func loadCID(_ cid: String, limit: Int, contentBase: String,
                               fetch: ContentFetch) async throws -> Data {
        guard CID.isCID(cid), let declared = CID.cidLength(cid) else { throw BinfireError.invalidCID }
        if declared > limit { throw BinfireError.tooLarge }
        if declared <= 64 {
            guard let inline = CID.inlineContent(cid) else { throw BinfireError.invalidCID }
            return inline
        }
        guard let url = contentURL(cid, contentBase: contentBase) else { throw BinfireError.network }
        let response: ContentResponse
        do { response = try await fetch(url) } catch let e as BinfireError { throw e } catch { throw BinfireError.network }
        switch response.status {
        case 200..<300: break
        case 404: throw BinfireError.notFound
        case 451: throw BinfireError.unavailable
        case 429: throw BinfireError.rateLimited
        default: throw BinfireError.httpError
        }
        var bytes = Data()
        bytes.reserveCapacity(declared)
        do {
            for try await chunk in response.body {
                if bytes.count + chunk.count > declared { throw BinfireError.tooLarge }
                bytes.append(chunk)
            }
        } catch let e as BinfireError { throw e } catch { throw BinfireError.network }
        guard CID.verify(cid, bytes) else { throw BinfireError.mismatch }
        return bytes
    }

    // MARK: - What Native Save uploads (hashbin.md "What is saved for a state")

    /// What Native Save does for a state URL.
    public enum SaveBytes: Equatable, Sendable {
        /// The state already is a CID: link to it, upload nothing.
        case cid(String)
        /// Upload these bytes with this `Content-Type`.
        /// `kind` is `"text"` (a JSON string payload) or `"json"`.
        case upload(kind: String, bytes: Data, contentType: String)
        /// binfire can't extract the document; offer the app's own Publish.
        /// `error` is the lz error code when a `v1` payload failed to decode.
        case none(error: BinfireError?)

        /// The fixture's `kind` string.
        public var kind: String {
            switch self {
            case .cid: return "cid"
            case .upload(let kind, _, _): return kind
            case .none: return "none"
            }
        }
    }

    public static let textContentType = "text/plain; charset=utf-8"
    public static let jsonContentType = "application/json"

    /// `saveBytes(url)`: classifies the state and, for `v1`, decompresses the
    /// payload (bounded by `limit`).
    public static func saveBytes(_ url: String, limit: Int = BinfireLimits.default.maxStateBytes) -> SaveBytes {
        let state = URLState.classifyState(url)
        switch state.state {
        case .cid:
            guard let cid = state.cid else { return .none(error: nil) }
            return .cid(cid)
        case .v1:
            let hash = URLParts.splitQueryAndFragment(url).fragment ?? ""
            let payload = Array(hash.utf16.dropFirst(3))
            let units: [UInt16]
            do { units = try LZ.decompress(payload, limitBytes: limit) } catch let e as BinfireError {
                return .none(error: e)
            } catch { return .none(error: .invalid) }
            let text = String(decoding: units, as: UTF16.self)
            let bytes = Data(text.utf8)
            if case .string(let s)? = try? JSONValue.parse(bytes) {
                return .upload(kind: "text", bytes: Data(s.utf8), contentType: textContentType)
            }
            return .upload(kind: "json", bytes: bytes, contentType: jsonContentType)
        default:
            return .none(error: nil)
        }
    }

    // MARK: - Cost

    /// HashBin's estimated cost for `bytes`, from `GET {api}/api/config`'s
    /// `price_cents_per_mb_month` (one month, at least 1 cent), or nil when
    /// HashBin publishes no price (then the UI shows "up to" the configured
    /// `maxCostCents`; binfire never invents a price).
    public static func estimateCents(bytes: Int, config: HashBinServerConfig?) -> Int? {
        guard let price = config?.priceCentsPerMBMonth else { return nil }
        let mb = Double(bytes) / 1_000_000
        return max(1, Int((mb * price).rounded(.up)))
    }
}

/// The parts of `GET {api}/api/config` binfire uses. Every field is optional.
public struct HashBinServerConfig: Equatable, Sendable {
    public var maxUploadBytes: Int?
    public var priceCentsPerMBMonth: Double?

    public init(maxUploadBytes: Int? = nil, priceCentsPerMBMonth: Double? = nil) {
        self.maxUploadBytes = maxUploadBytes
        self.priceCentsPerMBMonth = priceCentsPerMBMonth
    }

    public init?(json data: Data) {
        guard case .object(let o)? = try? JSONValue.parse(data) else { return nil }
        maxUploadBytes = o["max_upload_bytes"]?.integerValue
        if case .number(let n)? = o["price_cents_per_mb_month"] { priceCentsPerMBMonth = n }
    }
}

// MARK: - PKCE

public enum PKCE {
    /// `base64url(SHA-256(ascii(verifier)))`.
    public static func challenge(_ verifier: String) -> String {
        Base64URL.encode(SHA256.hash(data: Data(verifier.utf8)))
    }

    /// 32 random bytes in base64url (used for both the verifier and `state`).
    public static func randomToken() -> String {
        var rng = SystemRandomNumberGenerator()
        return Base64URL.encode((0..<32).map { _ in UInt8.random(in: 0...255, using: &rng) })
    }
}

// MARK: - HTTP and token storage abstractions

public struct HTTPRequest: Equatable, Sendable {
    public var method: String
    public var url: URL
    public var headers: [String: String]
    public var body: Data?

    public init(method: String, url: URL, headers: [String: String] = [:], body: Data? = nil) {
        self.method = method
        self.url = url
        self.headers = headers
        self.body = body
    }
}

public struct HTTPResponse: Equatable, Sendable {
    public var status: Int
    public var body: Data

    public init(status: Int, body: Data = Data()) {
        self.status = status
        self.body = body
    }

    /// The body's top-level JSON object, or an empty object.
    var json: JSONObject {
        if case .object(let o)? = try? JSONValue.parse(body) { return o }
        return JSONObject()
    }
}

/// Sends HTTP requests. Errors it throws count as `network`.
public protocol HTTPTransport: Sendable {
    func send(_ request: HTTPRequest) async throws -> HTTPResponse
}

/// The stored OAuth tokens (`hashbin.tokens`).
public struct HashBinTokens: Codable, Equatable, Sendable {
    public var accessToken: String
    public var refreshToken: String
    public var expiresAt: Date

    public init(accessToken: String, refreshToken: String, expiresAt: Date) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.expiresAt = expiresAt
    }
}

/// Where tokens live: the Keychain in the app, memory in tests.
public protocol TokenStore: Sendable {
    func load() -> HashBinTokens?
    func save(_ tokens: HashBinTokens?)
}

/// A token store for tests and previews.
public final class MemoryTokenStore: TokenStore, @unchecked Sendable {
    private let lock = NSLock()
    private var tokens: HashBinTokens?
    public init(_ tokens: HashBinTokens? = nil) { self.tokens = tokens }
    public func load() -> HashBinTokens? { lock.lock(); defer { lock.unlock() }; return tokens }
    public func save(_ tokens: HashBinTokens?) { lock.lock(); self.tokens = tokens; lock.unlock() }
}

// MARK: - Client

/// One sign-in attempt: open `url` in the system auth session, then pass
/// the callback URL to `HashBinClient.completeSignIn`.
public struct AuthorizationRequest: Equatable, Sendable {
    public var url: URL
    public var state: String
    public var verifier: String
    public var redirectURI: String
    /// The callback scheme for the auth session (the redirect URI's scheme).
    public var callbackScheme: String
}

/// The result of `POST /api/content`.
public struct UploadResult: Equatable, Sendable {
    public var cid: String
    public var sizeBytes: Int?
    public var costCents: Int?
    public var expiresAt: String?
}

/// HashBin OAuth 2.0 + PKCE and upload client (`spec/hashbin.md` "Native Save").
public actor HashBinClient {
    public let api: String
    public let clientId: String
    public let redirectURI: String
    public static let scope = "content:write balance:read"
    /// Refresh this long before the access token expires.
    public static let refreshMargin: TimeInterval = 60

    private let transport: HTTPTransport
    private let store: TokenStore
    private let now: @Sendable () -> Date
    private var refreshTask: Task<HashBinTokens, Error>?

    public init(api: String, clientId: String, redirectURI: String, transport: HTTPTransport,
                store: TokenStore, now: @escaping @Sendable () -> Date = { Date() }) {
        var base = api
        while base.hasSuffix("/") { base.removeLast() }
        self.api = base
        self.clientId = clientId
        self.redirectURI = redirectURI
        self.transport = transport
        self.store = store
        self.now = now
    }

    public var isSignedIn: Bool { store.load() != nil }

    // MARK: sign in

    /// Builds the authorize URL with fresh `state` and PKCE verifier.
    public nonisolated func authorizationRequest(state: String = PKCE.randomToken(),
                                                 verifier: String = PKCE.randomToken()) -> AuthorizationRequest? {
        guard var c = URLComponents(string: api + "/oauth/authorize") else { return nil }
        c.queryItems = [
            URLQueryItem(name: "client_id", value: clientId),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: HashBinClient.scope),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "code_challenge", value: PKCE.challenge(verifier)),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
        ]
        // URLComponents leaves `+`, `:` and `/` alone in query values; encode
        // them so the server's form decoding reads exactly what was sent.
        c.percentEncodedQuery = c.queryItems?.map {
            "\($0.name)=\(Links.encodeURIComponent($0.value ?? ""))"
        }.joined(separator: "&")
        guard let url = c.url else { return nil }
        let scheme = redirectURI.split(separator: ":", maxSplits: 1).first.map(String.init) ?? ""
        return AuthorizationRequest(url: url, state: state, verifier: verifier, redirectURI: redirectURI,
                                    callbackScheme: scheme)
    }

    /// Checks the callback (`state`, `error`, `code`) and exchanges the code
    /// for tokens. Throws `cancelled`, `failed` or `network`.
    public func completeSignIn(callback: URL, request: AuthorizationRequest) async throws {
        let items = URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func param(_ name: String) -> String? { items.first { $0.name == name }?.value }
        guard param("state") == request.state else { throw BinfireError.failed }
        if param("error") == "access_denied" { throw BinfireError.cancelled }
        guard param("error") == nil, let code = param("code"), !code.isEmpty else { throw BinfireError.failed }
        let response = try await postJSON("/oauth/token", [
            ("grant_type", "authorization_code"), ("client_id", clientId), ("code", code),
            ("redirect_uri", request.redirectURI), ("code_verifier", request.verifier),
        ])
        guard response.status == 200, let tokens = parseTokens(response) else { throw BinfireError.failed }
        store.save(tokens)
    }

    // MARK: tokens

    /// A non-expired access token, refreshing first when it expires within
    /// `refreshMargin`. Throws `signedOut` when there are no usable tokens.
    public func accessToken() async throws -> String {
        guard let tokens = store.load() else { throw BinfireError.signedOut }
        if tokens.expiresAt.timeIntervalSince(now()) > HashBinClient.refreshMargin { return tokens.accessToken }
        return try await refresh().accessToken
    }

    /// Refreshes the tokens. Concurrent callers share one request, because
    /// refresh tokens rotate and work only once.
    public func refresh() async throws -> HashBinTokens {
        if let task = refreshTask { return try await task.value }
        guard let current = store.load() else { throw BinfireError.signedOut }
        let task = Task { try await self.performRefresh(current) }
        refreshTask = task
        defer { refreshTask = nil }
        return try await task.value
    }

    private func performRefresh(_ current: HashBinTokens) async throws -> HashBinTokens {
        let response = try await postJSON("/oauth/token", [
            ("grant_type", "refresh_token"), ("client_id", clientId), ("refresh_token", current.refreshToken),
        ])
        if response.status == 401 || response.json["error"]?.stringValue == "invalid_grant" {
            store.save(nil)
            throw BinfireError.signedOut
        }
        guard response.status == 200, let tokens = parseTokens(response) else { throw BinfireError.httpError }
        store.save(tokens)
        return tokens
    }

    /// Sign out: revoke the refresh token (best effort), then clear the tokens.
    public func signOut() async {
        guard let tokens = store.load() else { return }
        store.save(nil)
        _ = try? await postJSON("/oauth/revoke", [("token", tokens.refreshToken), ("token_type_hint", "refresh_token")])
    }

    // MARK: API

    /// `GET {api}/api/config`, or nil when it isn't available.
    public func serverConfig() async -> HashBinServerConfig? {
        guard let url = URL(string: api + "/api/config"),
              let response = try? await transport.send(HTTPRequest(method: "GET", url: url)),
              response.status == 200 else { return nil }
        return HashBinServerConfig(json: response.body)
    }

    /// `POST {api}/api/content?max_cost_cents=<n>` with the raw bytes, then
    /// recomputes the CID. Throws `signedOut` (tokens cleared), `insufficient-balance`,
    /// `cost-exceeded`, `too-large`, `http-error`, `mismatch` or `network`.
    public func upload(_ bytes: Data, contentType: String, maxCostCents: Int) async throws -> UploadResult {
        let token = try await accessToken()
        guard let url = URL(string: api + "/api/content?max_cost_cents=\(max(0, maxCostCents))") else {
            throw BinfireError.httpError
        }
        let response = try await send(HTTPRequest(method: "POST", url: url, headers: [
            "Authorization": "Bearer \(token)", "Content-Type": contentType,
        ], body: bytes))
        let body = response.json
        let error = body["error"]?.stringValue
        switch response.status {
        case 200..<300: break
        case 401:
            store.save(nil)
            throw BinfireError.signedOut
        case 402: throw BinfireError.insufficientBalance
        case 409 where error == "max_cost_exceeded": throw BinfireError.costExceeded
        case 413: throw BinfireError.tooLarge
        default:
            if error == "insufficient_balance" { throw BinfireError.insufficientBalance }
            throw BinfireError.httpError
        }
        guard let cid = body["cid"]?.stringValue else { throw BinfireError.httpError }
        guard cid == CID.computeCID(bytes) else { throw BinfireError.mismatch }
        return UploadResult(cid: cid, sizeBytes: body["size_bytes"]?.integerValue,
                            costCents: body["cost_cents"]?.integerValue, expiresAt: body["expires_at"]?.stringValue)
    }

    // MARK: helpers

    private func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        do { return try await transport.send(request) } catch let e as BinfireError { throw e } catch {
            throw BinfireError.network
        }
    }

    private func postJSON(_ path: String, _ fields: [(String, String)]) async throws -> HTTPResponse {
        guard let url = URL(string: api + path) else { throw BinfireError.httpError }
        let body = JSONValue.object(JSONObject(fields.map { ($0.0, JSONValue.string($0.1)) })).serialized()
        return try await send(HTTPRequest(method: "POST", url: url, headers: ["Content-Type": "application/json"],
                                          body: Data(body.utf8)))
    }

    private func parseTokens(_ response: HTTPResponse) -> HashBinTokens? {
        let o = response.json
        guard let access = o["access_token"]?.stringValue, let refresh = o["refresh_token"]?.stringValue else { return nil }
        let expiresIn: Double
        if case .number(let n)? = o["expires_in"] { expiresIn = n } else { expiresIn = 900 }
        return HashBinTokens(accessToken: access, refreshToken: refresh, expiresAt: now().addingTimeInterval(expiresIn))
    }
}
