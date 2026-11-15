import AuthenticationServices
import Foundation
import Security
import UIKit
import BinfireCore

// Platform pieces of the HashBin integration: Keychain token storage, the
// URLSession transports, the system auth session, the share sheet for
// WebView downloads, and the DEBUG-only HashBin overrides.

/// Stores `hashbin.tokens` in the Keychain, readable after first unlock on
/// this device only. Tokens never go anywhere else.
///
/// The last value is also kept in memory for this process, so a session
/// still works when the Keychain refuses access (an unsigned simulator build
/// has no keychain entitlement: errSecMissingEntitlement). Nothing else
/// persists the tokens.
final class KeychainTokenStore: TokenStore, @unchecked Sendable {
    static let account = "hashbin.tokens"
    private let service: String
    private let lock = NSLock()
    private var cached: HashBinTokens??

    init(service: String = Bundle.main.bundleIdentifier ?? "binfire") {
        self.service = service
    }

    private var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: KeychainTokenStore.account]
    }

    func load() -> HashBinTokens? {
        lock.lock(); defer { lock.unlock() }
        if let cached { return cached }
        let tokens = keychainLoad()
        cached = .some(tokens)
        return tokens
    }

    func save(_ tokens: HashBinTokens?) {
        lock.lock(); defer { lock.unlock() }
        cached = .some(tokens)
        keychainSave(tokens)
    }

    private func keychainLoad() -> HashBinTokens? {
        var q = query
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &item) == errSecSuccess, let data = item as? Data else { return nil }
        return try? JSONDecoder().decode(HashBinTokens.self, from: data)
    }

    private func keychainSave(_ tokens: HashBinTokens?) {
        SecItemDelete(query as CFDictionary)
        guard let tokens, let data = try? JSONEncoder().encode(tokens) else { return }
        var q = query
        q[kSecValueData as String] = data
        q[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let status = SecItemAdd(q as CFDictionary, nil)
        #if DEBUG
        if status != errSecSuccess { NSLog("binfire: Keychain write failed (OSStatus %d); tokens kept for this run only", status) }
        #endif
    }
}

/// A cookie-less, cache-less session with a 30 s timeout (cid.md "Loading").
enum HashBinSession {
    static let shared: URLSession = {
        let c = URLSessionConfiguration.ephemeral
        c.httpCookieAcceptPolicy = .never
        c.httpShouldSetCookies = false
        c.httpCookieStorage = nil
        c.urlCache = nil
        c.urlCredentialStorage = nil
        c.requestCachePolicy = .reloadIgnoringLocalCacheData
        c.timeoutIntervalForRequest = 30
        return URLSession(configuration: c)
    }()
}

/// `HTTPTransport` over URLSession.
struct URLSessionTransport: HTTPTransport {
    var session: URLSession = HashBinSession.shared

    func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        var r = URLRequest(url: request.url, timeoutInterval: 30)
        r.httpMethod = request.method
        r.httpShouldHandleCookies = false
        for (k, v) in request.headers { r.setValue(v, forHTTPHeaderField: k) }
        r.httpBody = request.body
        let (data, response) = try await session.data(for: r)
        return HTTPResponse(status: (response as? HTTPURLResponse)?.statusCode ?? 0, body: data)
    }
}

/// Pulls a URLSession byte stream in 64 KiB chunks, only as fast as
/// `loadCID` reads them, so its byte cap stops the download.
private final class ByteChunker: @unchecked Sendable {
    private var iterator: URLSession.AsyncBytes.Iterator
    init(_ bytes: URLSession.AsyncBytes) { iterator = bytes.makeAsyncIterator() }

    func next() async throws -> Data? {
        var buffer = Data()
        while buffer.count < 65_536, let b = try await iterator.next() { buffer.append(b) }
        return buffer.isEmpty ? nil : buffer
    }
}

enum ContentFetcher {
    /// The production `ContentFetch`: GET with no cookies, credentials or referrer.
    static let urlSession: ContentFetch = { url in
        var r = URLRequest(url: url, timeoutInterval: 30)
        r.httpShouldHandleCookies = false
        let (bytes, response) = try await HashBinSession.shared.bytes(for: r)
        let chunker = ByteChunker(bytes)
        return ContentResponse(status: (response as? HTTPURLResponse)?.statusCode ?? 0,
                               body: AsyncThrowingStream(unfolding: { try await chunker.next() }))
    }
}

/// Runs `ASWebAuthenticationSession` (shared Safari cookies, so a signed-in
/// hashbin.org session is reused) and returns the callback URL.
@MainActor
final class WebAuth: NSObject, ASWebAuthenticationPresentationContextProviding {
    private var session: ASWebAuthenticationSession?

    func authenticate(url: URL, callbackScheme: String) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            let s = ASWebAuthenticationSession(url: url, callbackURLScheme: callbackScheme) { [weak self] callback, error in
                self?.session = nil
                if let callback {
                    continuation.resume(returning: callback)
                } else if let e = error as? ASWebAuthenticationSessionError, e.code == .canceledLogin {
                    continuation.resume(throwing: BinfireError.cancelled)
                } else {
                    continuation.resume(throwing: BinfireError.failed)
                }
            }
            s.prefersEphemeralWebBrowserSession = false
            s.presentationContextProvider = self
            session = s
            if !s.start() {
                session = nil
                continuation.resume(throwing: BinfireError.failed)
            }
        }
    }

    nonisolated func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        MainActor.assumeIsolated { UIApplication.shared.keyWindowForPresentation ?? ASPresentationAnchor() }
    }
}

extension UIApplication {
    var keyWindowForPresentation: UIWindow? {
        connectedScenes.compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first { $0.isKeyWindow }
    }

    /// The top-most presented view controller, for UIKit presentations.
    var topViewController: UIViewController? {
        var top = keyWindowForPresentation?.rootViewController
        while let next = top?.presentedViewController, !next.isBeingDismissed { top = next }
        return top
    }

    /// Shows the share sheet (Save to Files, AirDrop, …) for local files.
    func presentShareSheet(_ items: [Any]) {
        guard let top = topViewController else { return }
        let vc = UIActivityViewController(activityItems: items, applicationActivities: nil)
        vc.popoverPresentationController?.sourceView = top.view
        vc.popoverPresentationController?.sourceRect = CGRect(x: top.view.bounds.midX, y: top.view.bounds.midY, width: 0, height: 0)
        top.present(vc, animated: true)
    }
}

/// DEBUG builds only: `-hashbinApi URL -hashbinContent URL -hashbinClientId ID`
/// launch arguments (UserDefaults argument domain) override the bundled
/// HashBin settings, so the app can run against tools/mock-hashbin.mjs.
/// Release builds compile this to a no-op.
enum DebugOverrides {
    static func apply(to config: inout BinfireConfig, arguments: [String] = ProcessInfo.processInfo.arguments,
                      defaults: UserDefaults = .standard) {
        #if DEBUG
        func value(_ key: String) -> String? {
            if let v = defaults.string(forKey: key), !v.isEmpty { return v }
            // Also accept `--key value` and `key=value`, whatever the launcher sends.
            for (i, arg) in arguments.enumerated() {
                if (arg == "-" + key || arg == "--" + key), i + 1 < arguments.count { return arguments[i + 1] }
                if arg.hasPrefix(key + "=") { return String(arg.dropFirst(key.count + 1)) }
            }
            return nil
        }
        if let v = value("hashbinApi") { config.hashbinAPI = v }
        if let v = value("hashbinContent") { config.contentHost = v }
        if let v = value("hashbinClientId") { config.hashbinClientId = v }
        #endif
    }
}
