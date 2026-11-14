import SwiftUI
import WebKit
import BinfireCore

/// One registered app's live WKWebView, its URL tracking and navigation policy.
@MainActor
final class BrowserController: NSObject, ObservableObject, WKNavigationDelegate, WKUIDelegate {
    let app: RegistryApp
    let webView: WKWebView
    private weak var model: AppModel?
    private var urlObservation: NSKeyValueObservation?

    /// The latest main-frame URL that belongs to this app.
    @Published private(set) var currentURL: String = ""
    /// The URL binfire last loaded (used until the web view reports a URL).
    @Published private(set) var loadedURL: String = ""
    /// An open popup (FK Publish), shown as a sheet.
    @Published var popup: PopupController?

    init(app: RegistryApp, model: AppModel) {
        self.app = app
        self.model = model
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = true
        webView = WKWebView(frame: .zero, configuration: configuration)
        webView.accessibilityIdentifier = "web.view"
        webView.allowsBackForwardNavigationGestures = true
        super.init()
        webView.navigationDelegate = self
        webView.uiDelegate = self
        // KVO on url also fires on history.replaceState.
        urlObservation = webView.observe(\.url, options: [.new]) { [weak self] webView, _ in
            let url = webView.url?.absoluteString
            Task { @MainActor in self?.urlChanged(url) }
        }
    }

    var title: String {
        "\(app.name) · \(URLState.classifyState(currentURL.isEmpty ? loadedURL : currentURL).state.rawValue)"
    }

    /// Shown while the current main-frame URL (tracked by KVO) has `run=0`.
    var showRunBanner: Bool {
        let url = currentURL.isEmpty ? loadedURL : currentURL
        return !url.isEmpty && !URLState.classifyState(url).run
    }

    /// Loads a URL of this app.
    func load(_ url: String) {
        loadedURL = url
        currentURL = url
        guard let u = URL(string: url) else { return }
        webView.load(URLRequest(url: u))
    }

    /// Run: reload the same URL without the `run` parameter.
    func run() {
        load(Links.removingRun(currentURL.isEmpty ? loadedURL : currentURL))
    }

    func reload() {
        if webView.url == nil, let u = URL(string: loadedURL) { webView.load(URLRequest(url: u)) } else { webView.reload() }
    }

    /// The https link for the current state (`makeLink`).
    var shareLink: String? {
        model?.links.makeLink(currentURL.isEmpty ? loadedURL : currentURL)
    }

    private func belongsToApp(_ url: String) -> Bool {
        model?.registry.appForURL(url)?.slug == app.slug
    }

    private func urlChanged(_ url: String?) {
        guard let url, belongsToApp(url) else { return }
        currentURL = url
        model?.recordVisit(url: url, app: app.slug)
    }

    /// True for `about:blank` and URLs under the HashBin API origin.
    static func isPopupAllowed(_ url: String, config: BinfireConfig) -> Bool {
        if url == "about:blank" || url.hasPrefix("about:blank") { return true }
        guard let u = URLParts(url), let api = URLParts(config.hashbinAPI) else { return false }
        return u.scheme == api.scheme && u.hasAuthority && u.userinfo == nil
            && u.normalizedHost == api.normalizedHost && u.normalizedPort == api.normalizedPort
    }

    // MARK: WKNavigationDelegate

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
        // Sub-frames are the app's own business; new windows go to createWebViewWith.
        guard let frame = navigationAction.targetFrame, frame.isMainFrame else { return .allow }
        guard let url = navigationAction.request.url?.absoluteString, let model else { return .cancel }
        if belongsToApp(url) || BrowserController.isPopupAllowed(url, config: model.config) { return .allow }
        model.present(.text(url))
        return .cancel
    }

    // MARK: WKUIDelegate

    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        guard let model else { return nil }
        let target = navigationAction.request.url?.absoluteString ?? "about:blank"
        guard target.isEmpty || BrowserController.isPopupAllowed(target, config: model.config) else {
            model.present(.text(target))
            return nil
        }
        let p = PopupController(configuration: configuration, opener: self, config: model.config)
        popup = p
        return p.webView
    }

    func closePopup(showing text: String? = nil) {
        popup = nil
        guard let text else { return }
        // Let the popup sheet finish dismissing before the text sheet appears.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in self?.model?.present(.text(text)) }
    }
}

/// A popup window (FK's Publish flow) sharing the opener's process and storage.
@MainActor
final class PopupController: NSObject, Identifiable, WKNavigationDelegate, WKUIDelegate {
    let id = UUID()
    let webView: WKWebView
    private weak var opener: BrowserController?
    private let config: BinfireConfig

    init(configuration: WKWebViewConfiguration, opener: BrowserController, config: BinfireConfig) {
        webView = WKWebView(frame: .zero, configuration: configuration)
        webView.accessibilityIdentifier = "popup.view"
        self.opener = opener
        self.config = config
        super.init()
        webView.navigationDelegate = self
        webView.uiDelegate = self
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
        guard let frame = navigationAction.targetFrame, frame.isMainFrame else { return .allow }
        let url = navigationAction.request.url?.absoluteString ?? ""
        if BrowserController.isPopupAllowed(url, config: config) { return .allow }
        opener?.closePopup(showing: url)
        return .cancel
    }

    func webViewDidClose(_ webView: WKWebView) {
        opener?.closePopup()
    }
}
