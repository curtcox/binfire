import SwiftUI
import BinfireCore

struct RootView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        Group {
            if let slug = model.currentApp, let browser = model.browsers[slug] {
                BrowserView(controller: browser)
                    .id(slug) // a fresh view per app, so state never leaks across apps
            } else {
                LibraryView()
            }
        }
        .sheet(item: $model.sheet) { item in
            switch item {
            case .text(let text): TextSheet(text: text)
            case .error(let message): ErrorSheet(message: message)
            case .save(let request): SaveSheet(request: request)
            }
        }
        // Custom scheme links, files (Open in…) and, on some paths, Universal Links.
        .onOpenURL { url in model.openIncoming(url) }
        // Universal Links (https://<linkDomain>/…).
        .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { activity in
            if let url = activity.webpageURL { model.openIncoming(url) }
        }
    }
}
