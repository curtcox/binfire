import SwiftUI
import UIKit
import BinfireCore

/// A spinner while a CID loads or an upload runs.
struct LoadingSheet: View {
    @EnvironmentObject var model: AppModel
    let message: String

    var body: some View {
        VStack(spacing: 16) {
            ProgressView()
            Text(message)
            Button("Cancel") { model.cancelLoading() }
        }
        .padding(24)
        .presentationDetents([.fraction(0.3)])
        .interactiveDismissDisabled()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("loading.sheet")
    }
}

/// A verified CID that no single app claims: pick an app, copy, or open raw.
struct ChooserSheet: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let request: ChooserRequest

    var body: some View {
        NavigationStack {
            List {
                Section("Open with") {
                    ForEach(request.slugs, id: \.self) { slug in
                        let name = model.registry.app(slug: slug)?.name ?? slug
                        Button(name) {
                            if let app = model.registry.app(slug: slug) {
                                model.openApp(slug: slug, url: app.canonicalOrigin + "#" + request.cid)
                            }
                        }
                        .accessibilityIdentifier("chooser.app.\(slug)")
                    }
                }
                Section {
                    Button("Copy link") {
                        UIPasteboard.general.string = model.links.makeCIDLink(request.cid)
                        dismiss()
                    }
                    .accessibilityIdentifier("chooser.copy")
                    Button("Open raw") {
                        if let url = HashBin.contentURL(request.cid, contentBase: model.config.contentHost) {
                            UIApplication.shared.open(url)
                        }
                        dismiss()
                    }
                    .accessibilityIdentifier("chooser.raw")
                }
            }
            .navigationTitle("Open document")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
            }
        }
        .presentationDetents([.medium, .large])
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("chooser.sheet")
    }
}

/// The Send menu: Copy link, and Save to HashBin when a client ID is configured.
struct SendSheet: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let request: SaveRequest

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Send").font(.headline)
            Button {
                model.copyLink(request)
            } label: { Label("Copy link", systemImage: "link").frame(maxWidth: .infinity, alignment: .leading) }
            .buttonStyle(.bordered)
            .disabled(model.links.makeLink(request.url) == nil)
            .accessibilityIdentifier("send.copy")
            if model.hashbin != nil {
                Button {
                    model.startHashBinSave(app: request.app, url: request.url, copyLink: false)
                } label: { Label("Save to HashBin", systemImage: "icloud.and.arrow.up").frame(maxWidth: .infinity, alignment: .leading) }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("send.hashbin")
            }
            Spacer()
        }
        .padding(20)
        .presentationDetents([.fraction(0.3)])
    }
}

/// Copy link made a link long enough to be truncated by messengers.
struct LongNoticeSheet: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let request: SaveRequest

    var body: some View {
        VStack(spacing: 16) {
            Text("Link copied, but it's long").font(.headline)
            Text("Some messengers and mail apps cut off links this long. Save to HashBin for a short link.")
                .multilineTextAlignment(.center)
            // Without a client ID this shows hashbin.publishNote (use the app's own Publish).
            Button("Save to HashBin for a short link") {
                model.startHashBinSave(app: request.app, url: request.url, copyLink: true)
            }
            .buttonStyle(.borderedProminent)
            .accessibilityIdentifier("long.save")
            Button("OK") { dismiss() }
        }
        .padding(24)
        .presentationDetents([.medium])
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("long.notice")
    }
}

/// Size and estimated cost before a paid upload.
struct HashBinConfirmSheet: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var save: HashBinSave

    private var size: String { ByteCountFormatter.string(fromByteCount: Int64(save.bytes.count), countStyle: .file) }

    private var estimate: String {
        if !save.configLoaded { return "Estimating cost…" }
        if let cents = save.estimateCents { return "Estimated cost: \(dollars(cents))" }
        return "Cost: up to \(dollars(model.config.hashbinMaxCostCents))"
    }

    private func dollars(_ cents: Int) -> String {
        String(format: "$%d.%02d", cents / 100, cents % 100)
    }

    var body: some View {
        VStack(spacing: 16) {
            Text("Save to HashBin?").font(.headline)
            Text("Size: \(size)").accessibilityIdentifier("hashbin.size")
            Text(estimate).foregroundStyle(.secondary)
            Text("HashBin is pay to publish. The cost comes from your HashBin balance.")
                .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
            HStack {
                Button("Cancel") { dismiss() }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("hashbin.cancel")
                Button("Save") { model.confirmHashBinSave(save) }
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("hashbin.ok")
            }
        }
        .padding(24)
        .presentationDetents([.medium])
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("hashbin.confirm")
    }
}

/// The `/c#` link for a saved document.
struct HashBinResultSheet: View {
    @Environment(\.dismiss) private var dismiss
    let link: String

    var body: some View {
        VStack(spacing: 16) {
            Text("Saved to HashBin").font(.headline)
            Text(link)
                .font(.callout.monospaced())
                .textSelection(.enabled)
                .multilineTextAlignment(.center)
                .accessibilityIdentifier("hashbin.link")
            HStack {
                Button("Copy") {
                    UIPasteboard.general.string = link
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("hashbin.copy")
                Button("Done") { dismiss() }.buttonStyle(.bordered)
            }
        }
        .padding(24)
        .presentationDetents([.medium])
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("hashbin.result")
    }
}

/// For states binfire can't extract: point at the app's own Publish.
struct PublishNoteSheet: View {
    @Environment(\.dismiss) private var dismiss
    let appName: String

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "info.circle").font(.largeTitle)
            Text("binfire can't read this document's contents directly. Use \(appName)'s own Publish (Save to HashBin) button to make a short link.")
                .multilineTextAlignment(.center)
            Button("OK") { dismiss() }.buttonStyle(.borderedProminent)
        }
        .padding(24)
        .presentationDetents([.medium])
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("hashbin.publishNote")
    }
}
