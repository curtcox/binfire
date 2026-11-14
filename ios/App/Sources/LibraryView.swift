import SwiftUI
import UIKit
import BinfireCore

/// Home: open field, and the Apps / Saved / Recent sections.
struct LibraryView: View {
    @EnvironmentObject var model: AppModel
    @State private var input = ""
    @State private var tab: Tab = .apps
    @FocusState private var inputFocused: Bool

    enum Tab: String, CaseIterable {
        case apps, saved, recent
        var title: String {
            switch self {
            case .apps: return "Apps"
            case .saved: return "Saved"
            case .recent: return "Recent"
            }
        }
    }

    var body: some View {
        VStack(spacing: 12) {
            Text("binfire").font(.largeTitle.bold()).frame(maxWidth: .infinity, alignment: .leading)
            openBar
            tabBar
            content
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    private var openBar: some View {
        HStack(spacing: 8) {
            TextField("Paste a link or CID", text: $input)
                .textFieldStyle(.roundedBorder)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.URL)
                .submitLabel(.go)
                .focused($inputFocused)
                .onSubmit(go)
                .accessibilityIdentifier("open.input")
            Button("Open", action: go)
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("open.go")
            // Paste puts the clipboard into the field and opens it; empty does nothing.
            PasteButton(payloadType: String.self) { strings in
                guard let text = Links.pasteInput(strings.first) else { return }
                Task { @MainActor in
                    input = text
                    go()
                }
            }
            .labelStyle(.iconOnly)
            .accessibilityIdentifier("open.paste")
        }
    }

    private var tabBar: some View {
        HStack(spacing: 0) {
            ForEach(Tab.allCases, id: \.self) { t in
                Button { tab = t } label: {
                    Text(t.title)
                        .font(.subheadline.weight(tab == t ? .semibold : .regular))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(tab == t ? Color.accentColor.opacity(0.15) : Color.clear)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .accessibilityIdentifier("tab.\(t.rawValue)")
                .accessibilityAddTraits(tab == t ? .isSelected : [])
            }
        }
    }

    @ViewBuilder private var content: some View {
        switch tab {
        case .apps: appsGrid
        case .saved: savedList
        case .recent: recentList
        }
    }

    private var appsGrid: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 12)], spacing: 12) {
                ForEach(model.registry.apps, id: \.slug) { app in
                    Button { model.open(app.canonicalOrigin) } label: {
                        VStack(spacing: 4) {
                            Text(app.name).font(.headline)
                            Text(app.slug).font(.caption).foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, minHeight: 72)
                        .background(Color(.secondarySystemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(app.name), \(app.slug)")
                    .accessibilityAddTraits(.isButton)
                    .accessibilityIdentifier("app.\(app.slug)")
                }
            }
            .padding(.bottom, 16)
        }
    }

    private var savedList: some View {
        List {
            ForEach(Array(model.library.saved.enumerated()), id: \.element.id) { index, item in
                let subtitle = model.label(app: item.app, url: item.url) + " · " + item.savedAt.formatted(date: .abbreviated, time: .shortened)
                Button { model.open(item.url) } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.name).font(.headline)
                        Text(subtitle).font(.caption).foregroundStyle(.secondary)
                        Text(preview(item.url)).font(.caption2).foregroundStyle(.tertiary).lineLimit(1)
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(item.name), \(subtitle)")
                .accessibilityAddTraits(.isButton)
                .accessibilityIdentifier("saved.row.\(index)")
                .swipeActions {
                    Button(role: .destructive) { model.deleteSaved(id: item.id) } label: { Label("Delete", systemImage: "trash") }
                }
                .contextMenu {
                    Button(role: .destructive) { model.deleteSaved(id: item.id) } label: { Label("Delete", systemImage: "trash") }
                }
            }
        }
        .listStyle(.plain)
        .overlay { if model.library.saved.isEmpty { emptyNote("No saved states yet.") } }
    }

    private var recentList: some View {
        List {
            ForEach(Array(model.library.recent.enumerated()), id: \.element.url) { index, item in
                let title = model.label(app: item.app, url: item.url) + " · " + item.visitedAt.formatted(date: .omitted, time: .shortened)
                let subtitle = preview(item.url, limit: 80)
                Button { model.open(item.url) } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title).font(.subheadline)
                        Text(preview(item.url)).font(.caption2).foregroundStyle(.tertiary).lineLimit(1)
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(title), \(subtitle)")
                .accessibilityAddTraits(.isButton)
                .accessibilityIdentifier("recent.row.\(index)")
            }
        }
        .listStyle(.plain)
        .overlay { if model.library.recent.isEmpty { emptyNote("Nothing opened yet.") } }
    }

    private func emptyNote(_ text: String) -> some View {
        Text(text).foregroundStyle(.secondary)
    }

    private func preview(_ url: String, limit: Int = 160) -> String {
        url.count > limit ? String(url.prefix(limit)) + "…" : url
    }

    private func go() {
        let text = input
        inputFocused = false
        model.open(text)
    }
}
