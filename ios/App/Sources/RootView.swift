import SwiftUI
import BinfireCore

struct RootView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        Group {
            if let slug = model.currentApp, let browser = model.browsers[slug] {
                BrowserView(controller: browser)
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
        .onOpenURL { url in model.open(url.absoluteString) }
    }
}
