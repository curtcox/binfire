import UIKit
import UniformTypeIdentifiers
import BinfireCore

/// Share Extension: takes one shared URL or text and hands it to the app as
/// `<ownScheme>://share#t=<encodeURIComponent(text)>`. The app routes it with
/// `routeShared` (spec/links.md, `share`).
final class ShareViewController: UIViewController {
    private var sharedText: String?
    private let preview = UILabel()
    private let openButton = UIButton(configuration: .filled())

    private lazy var config: BinfireConfig = {
        guard let url = Bundle.main.url(forResource: "binfire.config", withExtension: "json"),
              let c = try? BinfireConfig.load(contentsOf: url) else { return .default }
        return c
    }()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground

        let title = UILabel()
        title.text = "Open in binfire"
        title.font = .preferredFont(forTextStyle: .headline)

        preview.numberOfLines = 4
        preview.font = .preferredFont(forTextStyle: .footnote)
        preview.textColor = .secondaryLabel
        preview.text = "Loading…"

        openButton.configuration?.title = "Open"
        openButton.isEnabled = false
        openButton.addTarget(self, action: #selector(openTapped), for: .touchUpInside)
        openButton.accessibilityIdentifier = "share.open"

        let cancel = UIButton(configuration: .bordered())
        cancel.configuration?.title = "Cancel"
        cancel.addTarget(self, action: #selector(cancelTapped), for: .touchUpInside)
        cancel.accessibilityIdentifier = "share.cancel"

        let buttons = UIStackView(arrangedSubviews: [cancel, openButton])
        buttons.spacing = 12
        buttons.distribution = .fillEqually
        let stack = UIStackView(arrangedSubviews: [title, preview, buttons])
        stack.axis = .vertical
        stack.spacing = 16
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.layoutMarginsGuide.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: view.layoutMarginsGuide.trailingAnchor),
            stack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 24),
        ])
        loadSharedItem()
    }

    private func loadSharedItem() {
        let providers = (extensionContext?.inputItems as? [NSExtensionItem] ?? []).flatMap { $0.attachments ?? [] }
        if let p = providers.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.url.identifier) }) {
            p.loadItem(forTypeIdentifier: UTType.url.identifier) { [weak self] item, _ in
                let text = (item as? URL)?.absoluteString ?? (item as? String)
                DispatchQueue.main.async { self?.received(text) }
            }
        } else if let p = providers.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) }) {
            p.loadItem(forTypeIdentifier: UTType.plainText.identifier) { [weak self] item, _ in
                let text = (item as? String) ?? (item as? Data).flatMap { String(data: $0, encoding: .utf8) }
                DispatchQueue.main.async { self?.received(text) }
            }
        } else {
            received(nil)
        }
    }

    private func received(_ text: String?) {
        guard let text, !text.isEmpty else {
            preview.text = "Nothing to open."
            return
        }
        sharedText = text
        preview.text = text.count > 300 ? String(text.prefix(300)) + "…" : text
        openButton.isEnabled = true
    }

    @objc private func openTapped() {
        // Hand off via this port's own scheme: several binfire builds on one
        // device may all claim the public scheme (spec/links.md "Schemes").
        let scheme = config.ownScheme.isEmpty ? config.scheme : config.ownScheme
        guard let text = sharedText,
              let url = URL(string: "\(scheme)://share#t=" + Links.encodeURIComponent(text)) else { return }
        _ = openViaResponderChain(url)
        extensionContext?.completeRequest(returningItems: nil)
    }

    @objc private func cancelTapped() {
        extensionContext?.cancelRequest(withError: NSError(domain: NSCocoaErrorDomain, code: NSUserCancelledError))
    }

    /// Extensions can't call `UIApplication.shared.open`; walk the responder
    /// chain to the host UIApplication and call `open(_:options:completionHandler:)`
    /// dynamically (the old `openURL:` is a no-op since iOS 18).
    private func openViaResponderChain(_ url: URL) -> Bool {
        var responder: UIResponder? = self
        let selector = sel_registerName("openURL:options:completionHandler:")
        while let r = responder {
            if let app = r as? UIApplication, app.responds(to: selector) {
                typealias OpenFn = @convention(c) (AnyObject, Selector, NSURL, NSDictionary, AnyObject?) -> Void
                let fn = unsafeBitCast(app.method(for: selector), to: OpenFn.self)
                fn(app, selector, url as NSURL, NSDictionary(), nil)
                return true
            }
            responder = r.next
        }
        return false
    }
}
