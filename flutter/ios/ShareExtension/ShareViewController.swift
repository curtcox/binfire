import UIKit
import UniformTypeIdentifiers

/// Share Extension: collects the shared text or URL and hands it to binfire
/// as `<ownScheme>://share#t=<text>` (spec/links.md), which the app routes with
/// `routeShared`. No UI, no App Group: the text travels in the link.
class ShareViewController: UIViewController {
  override func viewDidAppear(_ animated: Bool) {
    super.viewDidAppear(animated)
    Task { @MainActor in
      let text = await sharedText()
      if !text.isEmpty, let url = shareLink(for: text) {
        openHostApp(url)
      }
      extensionContext?.completeRequest(returningItems: [], completionHandler: nil)
    }
  }

  /// Text and web URLs from all attachments, joined by spaces.
  private func sharedText() async -> String {
    var parts: [String] = []
    let items = extensionContext?.inputItems as? [NSExtensionItem] ?? []
    for item in items {
      for provider in item.attachments ?? [] {
        if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier),
          let url = try? await provider.loadItem(forTypeIdentifier: UTType.url.identifier) as? URL,
          !url.isFileURL
        {
          parts.append(url.absoluteString)
        } else if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier),
          let text = try? await provider.loadItem(forTypeIdentifier: UTType.plainText.identifier) as? String
        {
          parts.append(text)
        }
      }
      if parts.isEmpty, let text = item.attributedContentText?.string, !text.isEmpty {
        parts.append(text)
      }
    }
    return parts.joined(separator: " ")
  }

  /// `<ownScheme>://share#t=<text>`. The private scheme is the host app's
  /// bundle ID, registered by tools/configure.mjs in the app's Info.plist, so
  /// the text reaches this app even when other binfire ports claim `binfire`.
  private func shareLink(for text: String) -> URL? {
    let hostURL = Bundle.main.bundleURL.deletingLastPathComponent().deletingLastPathComponent()
    guard
      let host = Bundle(url: hostURL),
      let hostID = host.bundleIdentifier,
      let types = host.object(forInfoDictionaryKey: "CFBundleURLTypes") as? [[String: Any]],
      let scheme = types.flatMap({ $0["CFBundleURLSchemes"] as? [String] ?? [] })
        .first(where: { $0.caseInsensitiveCompare(hostID) == .orderedSame })
    else { return nil }
    var allowed = CharacterSet.alphanumerics
    allowed.insert(charactersIn: "-_.!~*'()")
    guard let encoded = text.addingPercentEncoding(withAllowedCharacters: allowed) else { return nil }
    return URL(string: "\(scheme)://share#t=\(encoded)")
  }

  /// Extensions can't call `UIApplication.shared` or `open(_:)` directly;
  /// the responder chain reaches the host application object, and the
  /// method is called through the Objective-C runtime.
  private func openHostApp(_ url: URL) {
    let selector = NSSelectorFromString("openURL:options:completionHandler:")
    typealias OpenURL = @convention(c) (
      AnyObject, Selector, NSURL, NSDictionary, (@convention(block) (Bool) -> Void)?
    ) -> Void
    var responder: UIResponder? = self
    while let current = responder {
      if current is UIApplication, current.responds(to: selector) {
        let open = unsafeBitCast(current.method(for: selector), to: OpenURL.self)
        open(current, selector, url as NSURL, NSDictionary(), nil)
        return
      }
      responder = current.next
    }
  }
}
