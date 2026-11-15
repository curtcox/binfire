import Foundation
import XCTest
@testable import BinfireCore

/// A fake HTTP transport: answers from a handler and records every request.
final class FakeTransport: HTTPTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var _requests: [HTTPRequest] = []
    var delay: UInt64 = 0
    let handler: @Sendable (HTTPRequest) throws -> HTTPResponse

    init(_ handler: @escaping @Sendable (HTTPRequest) throws -> HTTPResponse) { self.handler = handler }

    var requests: [HTTPRequest] { lock.lock(); defer { lock.unlock() }; return _requests }
    private func record(_ r: HTTPRequest) { lock.lock(); _requests.append(r); lock.unlock() }

    func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        record(request)
        if delay > 0 { try await Task.sleep(nanoseconds: delay) }
        return try handler(request)
    }
}

private func json(_ status: Int, _ text: String) -> HTTPResponse { HTTPResponse(status: status, body: Data(text.utf8)) }

private func bodyObject(_ r: HTTPRequest) -> [String: String] {
    (try? JSONSerialization.jsonObject(with: r.body ?? Data())) as? [String: String] ?? [:]
}

final class HashBinTests: XCTestCase {
    var fixture: [String: Any]!
    override func setUpWithError() throws { fixture = try Fixtures.load("hashbin.json") }

    // MARK: fixtures

    func testLongLinkBytes() throws {
        XCTAssertEqual(fixture["longLinkBytes"] as? Int, HashBin.longLinkBytes)
        XCTAssertFalse(HashBin.isLongLink(String(repeating: "a", count: 2000)))
        XCTAssertTrue(HashBin.isLongLink(String(repeating: "a", count: 2001)))
        XCTAssertTrue(HashBin.isLongLink(String(repeating: "é", count: 1001))) // 2002 UTF-8 bytes
    }

    func testPKCE() throws {
        let cases = try Fixtures.list(fixture, "pkce")
        XCTAssertFalse(cases.isEmpty)
        for c in cases { XCTAssertEqual(PKCE.challenge(c["verifier"] as! String), c["challenge"] as? String) }
        let t = PKCE.randomToken()
        XCTAssertEqual(t.utf8.count, 43)
        XCTAssertEqual(Base64URL.decode(t)?.count, 32)
        XCTAssertNotEqual(t, PKCE.randomToken())
    }

    func testSaveBytes() throws {
        let cases = try Fixtures.list(fixture, "saveBytes")
        XCTAssertFalse(cases.isEmpty)
        for c in cases {
            let url = c["url"] as! String
            let result = HashBin.saveBytes(url)
            XCTAssertEqual(result.kind, c["kind"] as? String, url)
            switch result {
            case .cid(let cid): XCTAssertEqual(cid, c["cid"] as? String)
            case let .upload(kind, bytes, type):
                XCTAssertEqual(String(decoding: bytes, as: UTF8.self), c["text"] as? String, url)
                XCTAssertEqual(type, kind == "text" ? "text/plain; charset=utf-8" : "application/json")
            case .none(let error): XCTAssertEqual(error?.code, c["error"] as? String, url)
            }
        }
    }

    func testSaveBytesBounded() {
        let big = String(repeating: "x", count: 5000)
        let url = "https://python.hashbin.page/#v1." + LZ.compress("\"\(big)\"")
        XCTAssertEqual(HashBin.saveBytes(url, limit: 100), .none(error: .tooLarge))
        XCTAssertEqual(HashBin.saveBytes(url).kind, "text")
    }

    func testLoadCIDFixtures() async throws {
        let cases = try Fixtures.list(fixture, "fetch")
        XCTAssertGreaterThanOrEqual(cases.count, 10)
        for c in cases {
            let name = c["name"] as! String
            let cid = c["cid"] as! String
            let status = c["status"] as? Int ?? 200
            let body = try Fixtures.b64(c["bodyB64"] ?? "")
            let calls = Counter()
            let fetch: ContentFetch = { url in
                calls.add(url)
                return ContentResponse(status: status, data: body, chunkSize: 7)
            }
            var got: Data?
            var code: String?
            do { got = try await HashBin.loadCID(cid, limit: c["limit"] as! Int, contentBase: "https://256t.us/", fetch: fetch) }
            catch let e as BinfireError { code = e.code }
            XCTAssertEqual(calls.count, (c["request"] as! Bool) ? 1 : 0, name)
            if calls.count == 1 { XCTAssertEqual(calls.urls.first?.absoluteString, "https://256t.us/\(cid)", name) }
            if c["ok"] as? Bool == true {
                XCTAssertNil(code, name)
                XCTAssertEqual(got, body, name)
            } else {
                XCTAssertEqual(code, c["error"] as? String, name)
            }
        }
    }

    func testLoadCIDNetworkErrors() async throws {
        let cid = try XCTUnwrap(try Fixtures.list(fixture, "fetch").first { $0["name"] as? String == "verified body" }?["cid"] as? String)
        struct Offline: Error {}
        let failing: ContentFetch = { _ in throw Offline() }
        await assertCode("network") { _ = try await HashBin.loadCID(cid, limit: 1 << 20, contentBase: "https://x", fetch: failing) }
        let midStream: ContentFetch = { _ in
            ContentResponse(status: 200, body: AsyncThrowingStream { c in c.yield(Data("ab".utf8)); c.finish(throwing: Offline()) })
        }
        await assertCode("network") { _ = try await HashBin.loadCID(cid, limit: 1 << 20, contentBase: "https://x", fetch: midStream) }
    }

    // MARK: client

    private let api = "https://hashbin.test"
    private let redirect = "app.binfire.ios://oauth"

    private func client(_ transport: FakeTransport, _ store: TokenStore, now: Date = Date(timeIntervalSince1970: 1_000_000)) -> HashBinClient {
        HashBinClient(api: api + "/", clientId: "app_test", redirectURI: redirect, transport: transport, store: store, now: { now })
    }

    func testAuthorizeURL() throws {
        let c = client(FakeTransport { _ in json(500, "") }, MemoryTokenStore())
        let verifier = "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk"
        let r = try XCTUnwrap(c.authorizationRequest(state: "st", verifier: verifier))
        XCTAssertEqual(r.callbackScheme, "app.binfire.ios")
        let comps = try XCTUnwrap(URLComponents(url: r.url, resolvingAgainstBaseURL: false))
        XCTAssertEqual(comps.host, "hashbin.test")
        XCTAssertEqual(comps.path, "/oauth/authorize")
        let q = Dictionary(uniqueKeysWithValues: (comps.queryItems ?? []).map { ($0.name, $0.value ?? "") })
        XCTAssertEqual(q, ["client_id": "app_test", "redirect_uri": redirect, "response_type": "code",
                           "scope": "content:write balance:read", "state": "st",
                           "code_challenge": "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM", "code_challenge_method": "S256"])
        XCTAssertTrue(r.url.absoluteString.contains("scope=content%3Awrite%20balance%3Aread"))
        XCTAssertTrue(r.url.absoluteString.contains("redirect_uri=app.binfire.ios%3A%2F%2Foauth"))
    }

    func testSignInExchangesCode() async throws {
        let transport = FakeTransport { r in
            XCTAssertEqual(r.url.absoluteString, "https://hashbin.test/oauth/token")
            return json(200, #"{"access_token":"A1","refresh_token":"R1","expires_in":900}"#)
        }
        let store = MemoryTokenStore()
        let c = client(transport, store)
        let req = try XCTUnwrap(c.authorizationRequest(state: "st", verifier: "ver"))
        try await c.completeSignIn(callback: URL(string: "app.binfire.ios://oauth?code=C1&state=st")!, request: req)
        XCTAssertEqual(store.load(), HashBinTokens(accessToken: "A1", refreshToken: "R1", expiresAt: Date(timeIntervalSince1970: 1_000_900)))
        let sent = bodyObject(transport.requests[0])
        XCTAssertEqual(sent, ["grant_type": "authorization_code", "client_id": "app_test", "code": "C1",
                              "redirect_uri": redirect, "code_verifier": "ver"])
        XCTAssertEqual(transport.requests[0].headers["Content-Type"], "application/json")
    }

    func testSignInCallbackErrors() async throws {
        let transport = FakeTransport { _ in json(400, #"{"error":"invalid_grant"}"#) }
        let store = MemoryTokenStore()
        let c = client(transport, store)
        let req = try XCTUnwrap(c.authorizationRequest(state: "st", verifier: "ver"))
        await assertCode("failed") { try await c.completeSignIn(callback: URL(string: "x://oauth?code=C&state=other")!, request: req) }
        await assertCode("cancelled") { try await c.completeSignIn(callback: URL(string: "x://oauth?error=access_denied&state=st")!, request: req) }
        await assertCode("failed") { try await c.completeSignIn(callback: URL(string: "x://oauth?error=server_error&state=st")!, request: req) }
        await assertCode("failed") { try await c.completeSignIn(callback: URL(string: "x://oauth?state=st")!, request: req) }
        XCTAssertEqual(transport.requests.count, 0)
        await assertCode("failed") { try await c.completeSignIn(callback: URL(string: "x://oauth?code=C&state=st")!, request: req) }
        XCTAssertNil(store.load())
    }

    func testAccessTokenFreshAndSignedOut() async throws {
        let transport = FakeTransport { _ in json(500, "") }
        let now = Date(timeIntervalSince1970: 1_000_000)
        await assertCode("signed-out") { _ = try await self.client(transport, MemoryTokenStore(), now: now).accessToken() }
        let store = MemoryTokenStore(HashBinTokens(accessToken: "A", refreshToken: "R", expiresAt: now.addingTimeInterval(61)))
        let token = try await client(transport, store, now: now).accessToken()
        XCTAssertEqual(token, "A")
        XCTAssertEqual(transport.requests.count, 0)
    }

    func testRefreshSingleFlightAndRotation() async throws {
        let transport = FakeTransport { r in
            XCTAssertEqual(bodyObject(r), ["grant_type": "refresh_token", "client_id": "app_test", "refresh_token": "R0"])
            return json(200, #"{"access_token":"A1","refresh_token":"R1","expires_in":900}"#)
        }
        transport.delay = 50_000_000
        let now = Date(timeIntervalSince1970: 1_000_000)
        // Expires within the 60 s margin: must refresh.
        let store = MemoryTokenStore(HashBinTokens(accessToken: "A0", refreshToken: "R0", expiresAt: now.addingTimeInterval(59)))
        let c = client(transport, store, now: now)
        async let t1 = c.accessToken()
        async let t2 = c.accessToken()
        async let t3 = c.accessToken()
        let tokens = try await [t1, t2, t3]
        XCTAssertEqual(tokens, ["A1", "A1", "A1"])
        XCTAssertEqual(transport.requests.count, 1, "concurrent callers share one refresh")
        XCTAssertEqual(store.load()?.refreshToken, "R1", "the rotated refresh token is stored")
    }

    func testRefreshInvalidGrantClearsTokens() async throws {
        for response in [json(400, #"{"error":"invalid_grant"}"#), json(401, "")] {
            let transport = FakeTransport { _ in response }
            let now = Date(timeIntervalSince1970: 1_000_000)
            let store = MemoryTokenStore(HashBinTokens(accessToken: "A0", refreshToken: "R0", expiresAt: now))
            await assertCode("signed-out") { _ = try await self.client(transport, store, now: now).accessToken() }
            XCTAssertNil(store.load())
        }
    }

    func testSignOutRevokes() async throws {
        let transport = FakeTransport { _ in json(200, "{}") }
        let store = MemoryTokenStore(HashBinTokens(accessToken: "A", refreshToken: "R", expiresAt: Date()))
        await client(transport, store).signOut()
        XCTAssertNil(store.load())
        XCTAssertEqual(transport.requests.map(\.url.absoluteString), ["https://hashbin.test/oauth/revoke"])
        XCTAssertEqual(bodyObject(transport.requests[0]), ["token": "R", "token_type_hint": "refresh_token"])
        // Offline sign-out still clears the tokens.
        struct Offline: Error {}
        let offline = FakeTransport { _ in throw Offline() }
        let store2 = MemoryTokenStore(HashBinTokens(accessToken: "A", refreshToken: "R", expiresAt: Date()))
        await client(offline, store2).signOut()
        XCTAssertNil(store2.load())
    }

    private func validStore() -> MemoryTokenStore {
        MemoryTokenStore(HashBinTokens(accessToken: "A", refreshToken: "R", expiresAt: Date(timeIntervalSince1970: 2_000_000)))
    }

    func testUploadSuccess() async throws {
        let bytes = Data(#"print("hi")"#.utf8)
        let cid = CID.computeCID(bytes)
        let transport = FakeTransport { _ in json(200, #"{"cid":"\#(cid)","size_bytes":11,"cost_cents":1,"expires_at":"2026-12-14T00:00:00Z"}"#) }
        let result = try await client(transport, validStore()).upload(bytes, contentType: HashBin.textContentType, maxCostCents: 3)
        XCTAssertEqual(result, UploadResult(cid: cid, sizeBytes: 11, costCents: 1, expiresAt: "2026-12-14T00:00:00Z"))
        let r = transport.requests[0]
        XCTAssertEqual(r.method, "POST")
        XCTAssertEqual(r.url.absoluteString, "https://hashbin.test/api/content?max_cost_cents=3")
        XCTAssertEqual(r.headers["Authorization"], "Bearer A")
        XCTAssertEqual(r.headers["Content-Type"], "text/plain; charset=utf-8")
        XCTAssertEqual(r.body, bytes)
    }

    func testUploadMismatch() async throws {
        let other = CID.computeCID(Data("other".utf8))
        let transport = FakeTransport { _ in json(200, #"{"cid":"\#(other)"}"#) }
        await assertCode("mismatch") { _ = try await self.client(transport, self.validStore()).upload(Data("x".utf8), contentType: "text/plain", maxCostCents: 1) }
    }

    func testUploadErrors() async throws {
        let cases: [(HTTPResponse, String)] = [
            (json(402, #"{"error":"insufficient_balance"}"#), "insufficient-balance"),
            (json(402, ""), "insufficient-balance"),
            (json(400, #"{"error":"insufficient_balance"}"#), "insufficient-balance"),
            (json(409, #"{"error":"max_cost_exceeded","cost_cents":5}"#), "cost-exceeded"),
            (json(409, #"{"error":"conflict"}"#), "http-error"),
            (json(413, #"{"max_upload_bytes":90000000}"#), "too-large"),
            (json(500, ""), "http-error"),
            (json(200, "{}"), "http-error"),
        ]
        for (response, code) in cases {
            let transport = FakeTransport { _ in response }
            await assertCode(code) { _ = try await self.client(transport, self.validStore()).upload(Data("x".utf8), contentType: "text/plain", maxCostCents: 1) }
        }
        // 401 clears the tokens so the next save signs in again.
        let store = validStore()
        await assertCode("signed-out") { _ = try await self.client(FakeTransport { _ in json(401, "") }, store).upload(Data("x".utf8), contentType: "text/plain", maxCostCents: 1) }
        XCTAssertNil(store.load())
        // Not signed in: no request at all.
        let none = FakeTransport { _ in json(200, "{}") }
        await assertCode("signed-out") { _ = try await self.client(none, MemoryTokenStore()).upload(Data("x".utf8), contentType: "text/plain", maxCostCents: 1) }
        XCTAssertEqual(none.requests.count, 0)
        // Transport failure.
        struct Offline: Error {}
        await assertCode("network") { _ = try await self.client(FakeTransport { _ in throw Offline() }, self.validStore()).upload(Data("x".utf8), contentType: "text/plain", maxCostCents: 1) }
    }

    func testServerConfigAndEstimate() async throws {
        let transport = FakeTransport { r in
            XCTAssertEqual(r.url.absoluteString, "https://hashbin.test/api/config")
            return json(200, #"{"max_upload_bytes":94371840,"price_cents_per_mb_month":1,"mock":true}"#)
        }
        let config = await client(transport, MemoryTokenStore()).serverConfig()
        XCTAssertEqual(config, HashBinServerConfig(maxUploadBytes: 94_371_840, priceCentsPerMBMonth: 1))
        XCTAssertEqual(HashBin.estimateCents(bytes: 11, config: config), 1)
        XCTAssertEqual(HashBin.estimateCents(bytes: 2_500_000, config: config), 3)
        XCTAssertNil(HashBin.estimateCents(bytes: 11, config: HashBinServerConfig(maxUploadBytes: 1)))
        let failing = await client(FakeTransport { _ in json(500, "") }, MemoryTokenStore()).serverConfig()
        XCTAssertNil(failing)
    }

    // MARK: helpers

    private func assertCode(_ code: String, file: StaticString = #filePath, line: UInt = #line,
                            _ body: () async throws -> Void) async {
        do {
            try await body()
            XCTFail("expected \(code)", file: file, line: line)
        } catch let e as BinfireError {
            XCTAssertEqual(e.code, code, file: file, line: line)
        } catch {
            XCTFail("unexpected \(error)", file: file, line: line)
        }
    }
}

final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var _urls: [URL] = []
    func add(_ url: URL) { lock.lock(); _urls.append(url); lock.unlock() }
    var urls: [URL] { lock.lock(); defer { lock.unlock() }; return _urls }
    var count: Int { urls.count }
}
