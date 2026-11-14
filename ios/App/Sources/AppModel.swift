import SwiftUI
import UIKit
import BinfireCore

/// A request to name and save the current state of a browser.
struct SaveRequest: Equatable {
    let app: String
    let url: String
}

/// The root-level sheets.
enum SheetItem: Identifiable, Equatable {
    case text(String)
    case error(String)
    case save(SaveRequest)

    var id: String {
        switch self {
        case .text(let t): return "text:\(t.hashValue)"
        case .error(let m): return "error:\(m)"
        case .save(let r): return "save:\(r.app):\(r.url.hashValue)"
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

    init() {
        let config = (AppModel.resource("binfire.config", "json").flatMap { try? BinfireConfig.load(contentsOf: $0) })
            ?? .default
        let registry = (AppModel.resource("apps", "json").flatMap { try? Registry.load(contentsOf: $0) })
            ?? (try! Registry(apps: []))
        self.config = config
        self.registry = registry
        self.links = Links(config: config, registry: registry)
        self.store = try? LibraryStore.applicationSupport()
        self.library = store?.load() ?? Library()
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
        case .loadCID:
            present(.error("Opening HashBin documents by CID is coming in M3."))
        case .openSite:
            present(.error("Packaged sites are coming in M6."))
        }
    }

    /// Shows a sheet, waiting for any sheet being dismissed first.
    func present(_ item: SheetItem) {
        if sheet == nil {
            sheet = item
        } else {
            sheet = nil
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in self?.sheet = item }
        }
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
        sheet = nil
        if let current = currentApp, current != slug { browsers[current]?.popup = nil }
        b.load(url)
        currentApp = slug
    }

    func showLibrary() {
        currentApp = nil
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
