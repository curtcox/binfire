import UIKit
import UniformTypeIdentifiers

/// Share Extension: collects the shared text or URL and hands it to binfire
/// as `<scheme>://share#t=<text>` (spec/links.md), which the app routes with
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

  /// `<scheme>://share#t=<text>`, using the host app's first URL scheme
  /// (written by tools/configure.mjs into the app's Info.plist).
  private func shareLink(for text: String) -> URL? {
    let hostURL = Bundle.main.bundleURL.deletingLastPathComponent().deletingLastPathComponent()
    guard
      let types = Bundle(url: hostURL)?.object(forInfoDictionaryKey: "CFBundleURLTypes") as? [[String: Any]],
      let scheme = (types.first?["CFBundleURLSchemes"] as? [String])?.first
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
