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
            case .loading(let message): LoadingSheet(message: message)
            case .chooser(let request): ChooserSheet(request: request)
            case .send(let request): SendSheet(request: request)
            case .longNotice(let request): LongNoticeSheet(request: request)
            case .hashbinConfirm(let save): HashBinConfirmSheet(save: save)
            case .hashbinResult(let link): HashBinResultSheet(link: link)
            case .publishNote(let appName): PublishNoteSheet(appName: appName)
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
