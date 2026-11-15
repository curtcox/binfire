import SwiftUI
import UIKit
import BinfireCore

/// A request to name and save the current state of a browser.
struct SaveRequest: Equatable {
    let app: String
    let url: String
}

/// A CID that loaded and verified but matched no single app.
struct ChooserRequest: Equatable {
    let cid: String
    /// The matching apps, or every app when none matched.
    let slugs: [String]
}

/// A pending Native Save of `bytes` (the confirm sheet observes the estimate).
@MainActor
final class HashBinSave: ObservableObject, Identifiable, Equatable {
    let id = UUID()
    let app: String
    let bytes: Data
    let contentType: String
    /// Copy the `/c#` link when done (the long-link offer).
    let copyLink: Bool
    @Published var configLoaded = false
    @Published var estimateCents: Int?
    var serverConfig: HashBinServerConfig?

    init(app: String, bytes: Data, contentType: String, copyLink: Bool) {
        self.app = app
        self.bytes = bytes
        self.contentType = contentType
        self.copyLink = copyLink
    }

    nonisolated static func == (a: HashBinSave, b: HashBinSave) -> Bool { a.id == b.id }
}

/// The root-level sheets.
enum SheetItem: Identifiable, Equatable {
    case text(String)
    case error(String)
    case save(SaveRequest)
    case loading(String)
    case chooser(ChooserRequest)
    /// The Send menu for a browser's current state.
    case send(SaveRequest)
    /// Copy link produced a long link: offer a short HashBin link.
    case longNotice(SaveRequest)
    case hashbinConfirm(HashBinSave)
    case hashbinResult(String)
    /// binfire can't extract this state: use the app's own Publish.
    case publishNote(String)

    var id: String {
        switch self {
        case .text(let t): return "text:\(t.hashValue)"
        case .error(let m): return "error:\(m)"
        case .save(let r): return "save:\(r.app):\(r.url.hashValue)"
        case .loading(let m): return "loading:\(m)"
        case .chooser(let c): return "chooser:\(c.cid)"
        case .send(let r): return "send:\(r.app):\(r.url.hashValue)"
        case .longNotice(let r): return "long:\(r.app):\(r.url.hashValue)"
        case .hashbinConfirm(let s): return "confirm:\(s.id)"
        case .hashbinResult(let l): return "result:\(l)"
        case .publishNote(let a): return "publishNote:\(a)"
        }
    }
}

/// App-wide state: configuration, registry, library, browsers and sheets.
/// Every input goes through `route()`.
@MainActor
final class AppModel: ObservableObject {
    let config: BinfireConfig
    let registry: Registry
    let links: Links
    private let store: LibraryStore?

    @Published private(set) var library: Library
    /// The slug of the visible browser, or nil for the library.
    @Published var currentApp: String?
    @Published var sheet: SheetItem?
    /// One live browser per registered app, kept across switches.
    @Published private(set) var browsers: [String: BrowserController] = [:]

    /// Native Save, or nil when no client ID is configured (then only the
    /// apps' own Publish is offered).
    let hashbin: HashBinClient?
    @Published private(set) var hashbinSignedIn = false
    private let webAuth = WebAuth()
    private var loadTask: Task<Void, Never>?
    private var loadGeneration = 0
    private var presentGeneration = 0

    init() {
        var config = (AppModel.resource("binfire.config", "json").flatMap { try? BinfireConfig.load(contentsOf: $0) })
            ?? .default
        DebugOverrides.apply(to: &config)
        let registry = (AppModel.resource("apps", "json").flatMap { try? Registry.load(contentsOf: $0) })
            ?? (try! Registry(apps: []))
        self.config = config
        self.registry = registry
        self.links = Links(config: config, registry: registry)
        self.store = try? LibraryStore.applicationSupport()
        self.library = store?.load() ?? Library()
        if config.hashbinClientId.isEmpty {
            self.hashbin = nil
        } else {
            let redirect = (config.ownScheme.isEmpty ? config.scheme : config.ownScheme) + "://oauth"
            self.hashbin = HashBinClient(api: config.hashbinAPI, clientId: config.hashbinClientId, redirectURI: redirect,
                                         transport: URLSessionTransport(), store: KeychainTokenStore())
        }
        refreshSignedIn()
    }

    /// Finds a bundled resource (the Resources folder is copied as a folder reference).
    static func resource(_ name: String, _ ext: String) -> URL? {
        Bundle.main.url(forResource: name, withExtension: ext, subdirectory: "Resources")
            ?? Bundle.main.url(forResource: name, withExtension: ext)
    }

    // MARK: routing

    /// Routes any text (typed, pasted, opened link) and acts on the result.
    func open(_ text: String) {
        handle(links.route(text))
    }

    /// A URL handed to the app by the system: a tapped custom-scheme or
    /// Universal Link (plain `route`), or a `.binfire` file.
    func openIncoming(_ url: URL) {
        if url.isFileURL {
            present(.error("Opening .binfire files is coming in M5."))
            return
        }
        // OAuth callbacks belong to the auth session, never to route().
        if let scheme = url.scheme?.lowercased(), scheme == config.ownScheme, url.host == "oauth" { return }
        open(url.absoluteString)
    }

    /// Routes shared or pasted text, finding a link inside it (`routeShared`).
    func openShared(_ text: String) {
        handle(links.routeShared(text))
    }

    func handle(_ route: Route) {
        switch route {
        case let .openApp(app, url, _, _, _):
            openApp(slug: app, url: url)
        case let .showText(text):
            present(.text(text))
        case let .error(e):
            present(.error(AppModel.message(for: e)))
        case let .loadCID(cid, app):
            loadCID(cid, hint: app)
        case .openSite:
            present(.error("Packaged sites are coming in M6."))
        }
    }

    /// Shows a sheet, waiting for any sheet being dismissed first. A later
    /// `present` or `dismissSheet` wins over a pending one.
    func present(_ item: SheetItem) {
        presentGeneration += 1
        let generation = presentGeneration
        if sheet == nil {
            sheet = item
        } else {
            sheet = nil
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
                guard let self, self.presentGeneration == generation else { return }
                self.sheet = item
            }
        }
    }

    func dismissSheet() {
        presentGeneration += 1
        sheet = nil
    }

    static func message(for error: BinfireError) -> String {
        switch error {
        case .unknownApp: return "This binfire link names an app that isn't in the registry."
        case .badLink: return "This binfire link is malformed: it has no valid URL to open."
        case .unknownLink: return "This binfire link isn't one binfire understands."
        case .invalidCID: return "This binfire link doesn't contain a valid content ID."
        case .tooLarge: return "This text is too large to open."
        default: return "This link can't be opened (\(error.code))."
        }
    }

    // MARK: browsers

    func browser(for slug: String) -> BrowserController? {
        if let b = browsers[slug] { return b }
        guard let app = registry.app(slug: slug) else { return nil }
        let b = BrowserController(app: app, model: self)
        browsers[slug] = b
        return b
    }

    func openApp(slug: String, url: String) {
        guard let b = browser(for: slug) else { return }
        // Any open sheet or popup gives way to the browser.
        dismissSheet()
        if let current = currentApp, current != slug { browsers[current]?.popup = nil }
        b.load(url)
        currentApp = slug
    }

    func showLibrary() {
        currentApp = nil
    }

    // MARK: CID loading (cid.md "Opening a loaded document")

    func loadCID(_ cid: String, hint: String?) {
        loadTask?.cancel()
        loadGeneration += 1
        let generation = loadGeneration
        let config = config
        present(.loading("Loading document…"))
        loadTask = Task { [weak self] in
            do {
                let bytes = try await HashBin.loadCID(cid, limit: config.limits.maxStateBytes,
                                                      contentBase: config.contentHost, fetch: ContentFetcher.urlSession)
                guard let self, generation == self.loadGeneration else { return }
                self.openLoaded(cid: cid, bytes: bytes, hint: hint)
            } catch {
                guard let self, generation == self.loadGeneration, !Task.isCancelled else { return }
                self.present(.error(AppModel.loadMessage(for: error as? BinfireError ?? .network)))
            }
        }
    }

    /// Cancel from the loading sheet.
    func cancelLoading() {
        loadGeneration += 1
        loadTask?.cancel()
        loadTask = nil
        dismissSheet()
    }

    private func openLoaded(cid: String, bytes: Data, hint: String?) {
        let apps: [RegistryApp]
        if let hint, let app = registry.app(slug: hint) {
            apps = [app]
        } else {
            apps = Envelope.documentType(bytes).map { registry.appsForDocumentType($0) } ?? []
        }
        if apps.count == 1 {
            openApp(slug: apps[0].slug, url: apps[0].canonicalOrigin + "#" + cid)
        } else {
            present(.chooser(ChooserRequest(cid: cid, slugs: (apps.isEmpty ? registry.apps : apps).map(\.slug))))
        }
    }

    static func loadMessage(for error: BinfireError) -> String {
        switch error {
        case .network: return "Couldn't reach HashBin. Check your connection and try again."
        case .notFound: return "This document wasn't found. It may have expired or been deleted."
        case .unavailable: return "This document is unavailable for legal reasons."
        case .rateLimited: return "HashBin is busy (rate limited). Try again in a minute."
        case .tooLarge: return "This document is too large to open."
        case .mismatch: return "This document failed verification: its content doesn't match its ID."
        case .invalidCID: return "This isn't a valid content ID."
        case .httpError: return "HashBin returned an error. Try again later."
        default: return "This document can't be opened (\(error.code))."
        }
    }

    // MARK: Native Save (hashbin.md)

    /// Save to HashBin for a browser's current state.
    func startHashBinSave(app slug: String, url: String, copyLink: Bool) {
        let appName = registry.app(slug: slug)?.name ?? slug
        guard let hashbin else {
            present(.publishNote(appName))
            return
        }
        switch HashBin.saveBytes(url, limit: config.limits.maxStateBytes) {
        case .cid(let cid):
            finishSave(cid: cid, app: slug, copyLink: copyLink)
        case .none:
            present(.publishNote(appName))
        case let .upload(_, bytes, contentType):
            let save = HashBinSave(app: slug, bytes: bytes, contentType: contentType, copyLink: copyLink)
            present(.hashbinConfirm(save))
            Task {
                let server = await hashbin.serverConfig()
                save.serverConfig = server
                save.estimateCents = HashBin.estimateCents(bytes: bytes.count, config: server)
                save.configLoaded = true
            }
        }
    }

    /// Save on the confirm sheet: sign in if needed, upload, show the link.
    func confirmHashBinSave(_ save: HashBinSave) {
        guard let hashbin else { return }
        dismissSheet()
        Task {
            do {
                if let max = save.serverConfig?.maxUploadBytes, save.bytes.count > max { throw BinfireError.tooLarge }
                let maxCost = save.estimateCents ?? HashBin.fallbackMaxCostCents
                if !(await hashbin.isSignedIn) { try await signIn(hashbin) }
                present(.loading("Saving to HashBin…"))
                var result: UploadResult
                do {
                    result = try await hashbin.upload(save.bytes, contentType: save.contentType, maxCostCents: maxCost)
                } catch BinfireError.signedOut {
                    // Expired or revoked: sign in again once, then retry.
                    dismissSheet()
                    try await signIn(hashbin)
                    present(.loading("Saving to HashBin…"))
                    result = try await hashbin.upload(save.bytes, contentType: save.contentType, maxCostCents: maxCost)
                }
                finishSave(cid: result.cid, app: save.app, copyLink: save.copyLink)
            } catch BinfireError.cancelled {
                dismissSheet()
            } catch {
                present(.error(AppModel.saveMessage(for: error as? BinfireError ?? .network)))
            }
            refreshSignedIn()
        }
    }

    private func signIn(_ hashbin: HashBinClient) async throws {
        guard let request = hashbin.authorizationRequest() else { throw BinfireError.failed }
        let callback = try await webAuth.authenticate(url: request.url, callbackScheme: request.callbackScheme)
        try await hashbin.completeSignIn(callback: callback, request: request)
        refreshSignedIn()
    }

    private func finishSave(cid: String, app: String, copyLink: Bool) {
        let link = links.makeCIDLink(cid, app: app)
        if copyLink { UIPasteboard.general.string = link }
        present(.hashbinResult(link))
    }

    func signOutHashBin() {
        guard let hashbin else { return }
        Task {
            await hashbin.signOut()
            refreshSignedIn()
        }
    }

    func refreshSignedIn() {
        guard let hashbin else { return }
        Task { hashbinSignedIn = await hashbin.isSignedIn }
    }

    static func saveMessage(for error: BinfireError) -> String {
        switch error {
        case .insufficientBalance: return "Your HashBin balance is too low. Add funds on hashbin.org, then try again."
        case .costExceeded: return "Saving would cost more than the estimate, so nothing was charged or saved."
        case .tooLarge: return "This document is too large for HashBin."
        case .failed: return "Signing in to HashBin failed. Try again."
        case .signedOut: return "You're signed out of HashBin. Try again to sign in."
        case .network: return "Couldn't reach HashBin. Check your connection and try again."
        case .mismatch: return "HashBin returned a content ID that doesn't match the document, so no link was made."
        default: return "Saving to HashBin failed (\(error.code))."
        }
    }

    // MARK: Send

    /// Send → Copy link: copies `makeLink`; a long link also gets the
    /// "Save to HashBin for a short link" notice.
    func copyLink(_ request: SaveRequest) {
        guard let link = links.makeLink(request.url) else { dismissSheet(); return }
        UIPasteboard.general.string = link
        if HashBin.isLongLink(link) { present(.longNotice(request)) } else { dismissSheet() }
    }

    // MARK: library

    func recordVisit(url: String, app: String) {
        library.addRecent(url: url, app: app)
        store?.save(library)
    }

    func save(name: String, request: SaveRequest) {
        library.save(name: name, url: request.url, app: request.app)
        store?.save(library)
    }

    func deleteSaved(id: String) {
        library.deleteSaved(id: id)
        store?.save(library)
    }

    /// "Python · cid" style label for a state URL.
    func label(app slug: String, url: String) -> String {
        let name = registry.app(slug: slug)?.name ?? slug
        return "\(name) · \(URLState.classifyState(url).state.rawValue)"
    }
}
