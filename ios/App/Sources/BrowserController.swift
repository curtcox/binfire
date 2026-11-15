import SwiftUI
import UIKit
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
        load(Links.withoutRun(currentURL.isEmpty ? loadedURL : currentURL))
    }

    func reload() {
        if webView.url == nil, let u = URL(string: loadedURL) { webView.load(URLRequest(url: u)) } else { webView.reload() }
    }

    /// The current state URL: the tracked main-frame URL, else the loaded one.
    var stateURL: String { currentURL.isEmpty ? loadedURL : currentURL }

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
        // `<a download>` (HashBin's >512 KiB file fallback): hand the file to the share sheet.
        if navigationAction.shouldPerformDownload { return .download }
        // Sub-frames are the app's own business; new windows go to createWebViewWith.
        guard let frame = navigationAction.targetFrame, frame.isMainFrame else { return .allow }
        guard let url = navigationAction.request.url?.absoluteString, let model else { return .cancel }
        if belongsToApp(url) || BrowserController.isPopupAllowed(url, config: model.config) { return .allow }
        if let other = model.registry.appForURL(url) {
            // Another registered app: open it in that app's own browser.
            model.openApp(slug: other.slug, url: url)
        } else {
            model.present(.text(url))
        }
        return .cancel
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse) async -> WKNavigationResponsePolicy {
        DownloadHandler.policy(for: navigationResponse)
    }

    func webView(_ webView: WKWebView, navigationAction: WKNavigationAction, didBecome download: WKDownload) {
        download.delegate = DownloadHandler.shared
    }

    func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) {
        download.delegate = DownloadHandler.shared
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
        if navigationAction.shouldPerformDownload { return .download }
        guard let frame = navigationAction.targetFrame, frame.isMainFrame else { return .allow }
        let url = navigationAction.request.url?.absoluteString ?? ""
        if BrowserController.isPopupAllowed(url, config: config) { return .allow }
        opener?.closePopup(showing: url)
        return .cancel
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse) async -> WKNavigationResponsePolicy {
        DownloadHandler.policy(for: navigationResponse)
    }

    func webView(_ webView: WKWebView, navigationAction: WKNavigationAction, didBecome download: WKDownload) {
        download.delegate = DownloadHandler.shared
    }

    func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) {
        download.delegate = DownloadHandler.shared
    }

    func webViewDidClose(_ webView: WKWebView) {
        opener?.closePopup()
    }
}

/// WebView downloads (HashBin Publish's file fallback, or any app's export):
/// saved to a temporary file, then offered in the share sheet (Save to Files, …).
@MainActor
final class DownloadHandler: NSObject, WKDownloadDelegate {
    static let shared = DownloadHandler()
    private var destinations: [ObjectIdentifier: URL] = [:]

    /// Download responses the web view can't show or that ask to be saved.
    static func policy(for response: WKNavigationResponse) -> WKNavigationResponsePolicy {
        if !response.canShowMIMEType { return .download }
        if let http = response.response as? HTTPURLResponse,
           (http.value(forHTTPHeaderField: "Content-Disposition") ?? "").lowercased().hasPrefix("attachment") {
            return .download
        }
        return .allow
    }

    func download(_ download: WKDownload, decideDestinationUsing response: URLResponse,
                  suggestedFilename: String) async -> URL? {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("downloads", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        guard (try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)) != nil else { return nil }
        var name = (suggestedFilename as NSString).lastPathComponent
        if name.isEmpty || name == "." || name == ".." { name = "download" }
        let url = dir.appendingPathComponent(name)
        destinations[ObjectIdentifier(download)] = url
        return url
    }

    func downloadDidFinish(_ download: WKDownload) {
        guard let url = destinations.removeValue(forKey: ObjectIdentifier(download)) else { return }
        UIApplication.shared.presentShareSheet([url])
    }

    func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) {
        destinations.removeValue(forKey: ObjectIdentifier(download))
    }
}
