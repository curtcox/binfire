import SwiftUI
import UIKit
import BinfireCore

/// Shows text binfire won't open itself: Open in browser (http/https only) and Copy.
struct TextSheet: View {
    @Environment(\.dismiss) private var dismiss
    let text: String

    private var isWebURL: Bool {
        guard let u = URLParts(text) else { return false }
        return (u.scheme == "https" || u.scheme == "http") && u.hasAuthority
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Not a binfire link").font(.headline)
            Text("binfire only opens registered apps. You can open this in your browser or copy it.")
                .font(.subheadline).foregroundStyle(.secondary)
            ScrollView {
                Text(text.count > 4000 ? String(text.prefix(4000)) + "…" : text)
                    .font(.body.monospaced())
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityIdentifier("text.value")
            }
            .frame(maxHeight: 240)
            HStack {
                if isWebURL {
                    Button("Open in browser") {
                        if let u = URL(string: text) { UIApplication.shared.open(u) }
                        dismiss()
                    }
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("text.openBrowser")
                }
                Button("Copy") {
                    UIPasteboard.general.string = text
                    dismiss()
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("text.copy")
                Spacer()
                Button("Close") { dismiss() }
            }
            Spacer()
        }
        .padding(20)
        .presentationDetents([.medium, .large])
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("text.sheet")
    }
}

/// An error message with OK.
struct ErrorSheet: View {
    @Environment(\.dismiss) private var dismiss
    let message: String

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle").font(.largeTitle).foregroundStyle(.orange)
            Text(message)
                .multilineTextAlignment(.center)
                .accessibilityIdentifier("error.message")
            Button("OK") { dismiss() }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("error.ok")
        }
        .padding(24)
        .presentationDetents([.medium])
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("error.sheet")
    }
}

/// Names and saves the current state.
struct SaveSheet: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let request: SaveRequest
    @State private var name = ""
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            Form {
                TextField("Name", text: $name)
                    .focused($focused)
                    .submitLabel(.done)
                    .onSubmit(confirm)
                    .accessibilityIdentifier("save.name")
                Text(model.label(app: request.app, url: request.url))
                    .font(.caption).foregroundStyle(.secondary)
            }
            .navigationTitle("Save state")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.accessibilityIdentifier("save.cancel")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: confirm).accessibilityIdentifier("save.confirm")
                }
            }
        }
        .presentationDetents([.medium])
    }

    private func confirm() {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalName = trimmed.isEmpty ? model.label(app: request.app, url: request.url) : trimmed
        model.save(name: finalName, request: request)
        dismiss()
    }
}
