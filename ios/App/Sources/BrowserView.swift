import SwiftUI
import UIKit
import BinfireCore

/// One app's browser: toolbar, run banner and the live web view.
struct BrowserView: View {
    @EnvironmentObject var model: AppModel
    @ObservedObject var controller: BrowserController

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            if controller.showRunBanner { runBanner }
            WebViewHost(webView: controller.webView)
                .ignoresSafeArea(edges: .bottom)
        }
        .sheet(item: $controller.popup) { popup in
            PopupSheet(popup: popup) { controller.closePopup() }
        }
    }

    private var toolbar: some View {
        HStack(spacing: 14) {
            Button { model.showLibrary() } label: { Label("Library", systemImage: "chevron.left") }
                .labelStyle(.iconOnly)
                .accessibilityIdentifier("web.library")
            Text(controller.title)
                .font(.headline)
                .lineLimit(1)
                .accessibilityIdentifier("web.title")
            Spacer()
            Button { controller.reload() } label: { Label("Reload", systemImage: "arrow.clockwise") }
                .labelStyle(.iconOnly)
                .accessibilityIdentifier("web.reload")
            Menu {
                Button {
                    if let link = controller.shareLink { UIPasteboard.general.string = link }
                } label: { Label("Copy link", systemImage: "link") }
                .disabled(controller.shareLink == nil)
            } label: { Label("Send", systemImage: "square.and.arrow.up") }
                .labelStyle(.iconOnly)
                .accessibilityIdentifier("web.send")
            Button {
                let url = controller.currentURL.isEmpty ? controller.loadedURL : controller.currentURL
                model.present(.save(SaveRequest(app: controller.app.slug, url: url)))
            } label: { Label("Save", systemImage: "bookmark") }
                .labelStyle(.iconOnly)
                .accessibilityIdentifier("web.save")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private var runBanner: some View {
        HStack {
            Image(systemName: "pause.circle")
            Text("Opened without running (run=0).").font(.subheadline)
            Spacer()
            Button("Run") { controller.run() }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("run.go")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color.yellow.opacity(0.25))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("run.banner")
    }
}

/// A popup window from the app (FK Publish), shown as a sheet.
struct PopupSheet: View {
    let popup: PopupController
    let close: () -> Void

    var body: some View {
        NavigationStack {
            WebViewHost(webView: popup.webView)
                .ignoresSafeArea(edges: .bottom)
                .navigationTitle("HashBin")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Close", action: close) }
                }
        }
    }
}
